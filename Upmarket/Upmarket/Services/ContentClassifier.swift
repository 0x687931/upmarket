import Foundation
import ImageIO
import OSLog

#if canImport(Vision)
import Vision
#endif

/// Classifies any supported file by its *content*, not its extension.
///
/// For PDFs, delegates to NativeDocumentClassifier (text density + Vision sampling).
/// For images, uses VNClassifyImageRequest (scene type) and VNRecognizeTextRequest
/// (text density probe) to distinguish photo/artwork from scanned documents.
/// Multi-page TIFFs are always treated as scanned documents regardless of content.
///
/// The result drives routing in ConversionRunner: which pipeline to use, and
/// whether the user needs to upgrade before conversion can proceed.
enum ContentClassifier {

    // MARK: - Public types

    enum ContentKind: Equatable {
        /// Digital text document — embedded text, no OCR needed.
        case digitalDocument
        /// Scanned or image-based document — needs OCR/AI to extract text.
        case scannedDocument
        /// Photo, artwork, or diagram — metadata only, no text extraction possible.
        case photoOrArtwork
        /// Structured document format (DOCX, PPTX, etc.) — single Enhanced pathway.
        case structuredDocument
        /// Audio/video — speech or media metadata pathway.
        case audioVideo
    }

    /// Minimum pipeline tier required to convert this content.
    enum RequiredTier: Equatable {
        /// PDFKit or metadata — always available.
        case basic
        /// Enhanced Docling layout model — requires Advanced Runtime (Apple Silicon).
        case enhanced
        /// AI VLM (Granite) — requires Pro entitlement + AI model downloaded.
        case ai
    }

    struct Classification: Equatable {
        let kind: ContentKind
        let requiredTier: RequiredTier
        /// True when Vision detected substantial text in an image/TIFF.
        let hasExtractableText: Bool
        /// Page/frame count from ImageIO or PDFKit.
        let frameCount: Int
        /// Forwarded from NativeDocumentClassifier for PDFs.
        let pdfEvidence: NativeDocumentClassifier.Evidence?
        /// Recommended conversion pathway after accounting for kind + tier.
        let recommendedPathway: ConversionPathway

        /// True when the content needs OCR or VLM and cannot be served by fast/native paths.
        var needsAdvancedProcessing: Bool {
            requiredTier == .enhanced || requiredTier == .ai
        }

        /// Complexity advice for the pre-conversion analysis prompt.
        var complexityAdvice: ComplexityAdvice? {
            switch kind {
            case .scannedDocument:
                return ComplexityAdvice(
                    recommendation: .aiRequired,
                    score: 90,
                    reasons: ["scanned or image-based content"],
                    detectedLanguage: nil
                )
            case .digitalDocument where requiredTier == .enhanced:
                return ComplexityAdvice(
                    recommendation: .aiRecommended,
                    score: 60,
                    reasons: ["complex layout or table-heavy content"],
                    detectedLanguage: pdfEvidence?.detectedLanguage
                )
            default:
                return nil
            }
        }

        var diagnosticLabel: String { kind.diagnosticLabel }
    }

    // MARK: - Classification entry point

    /// Classify a file by its content. Always runs on a background thread.
    /// Returns nil only when the file cannot be opened at all.
    static func classify(
        fileURL: URL,
        password: String? = nil,
        supportsAdvancedRuntime: Bool = DeviceCapability.currentSupportsAdvancedRuntime,
        supportsAI: Bool = DeviceCapability.shared.supportsUpmarketAI
    ) async -> Classification? {
        let ext = fileURL.pathExtension.lowercased()
        let format = ConversionFormat(fileExtension: ext)

        // Audio/video — always basic, single pathway
        if let format, ToolFormatCapabilityMatrix.supports(.avFoundation, format)
            || ToolFormatCapabilityMatrix.supports(.speech, format) {
            return Classification(
                kind: .audioVideo,
                requiredTier: .basic,
                hasExtractableText: false,
                frameCount: 1,
                pdfEvidence: nil,
                recommendedPathway: .metadata
            )
        }

        // Structured documents (DOCX, PPTX, XLSX, HTML, etc.) — Enhanced only
        let structuredFormats: Set<ConversionFormat> = [
            .docx, .pptx, .xlsx, .html, .md, .txt, .asciidoc, .epub,
            .csv, .json, .xml, .zip, .webvtt
        ]
        if let format, structuredFormats.contains(format) {
            return Classification(
                kind: .structuredDocument,
                requiredTier: supportsAdvancedRuntime ? .enhanced : .basic,
                hasExtractableText: true,
                frameCount: 1,
                pdfEvidence: nil,
                recommendedPathway: .enhanced
            )
        }

        // PDF — delegate to NativeDocumentClassifier
        if ext == "pdf" {
            return await classifyPDF(fileURL: fileURL, password: password,
                                     supportsAdvancedRuntime: supportsAdvancedRuntime,
                                     supportsAI: supportsAI)
        }

        // Images (PNG, JPG, TIFF, HEIC, WebP, BMP, GIF)
        let imageFormats: Set<ConversionFormat> = [
            .png, .jpg, .jpeg, .tiff, .tif, .heic, .heif, .webp, .bmp, .gif
        ]
        if let format, imageFormats.contains(format) {
            return await classifyImage(fileURL: fileURL,
                                       supportsAdvancedRuntime: supportsAdvancedRuntime,
                                       supportsAI: supportsAI)
        }

        // Unknown format
        return nil
    }

    // MARK: - PDF classification

    private static func classifyPDF(
        fileURL: URL,
        password: String?,
        supportsAdvancedRuntime: Bool,
        supportsAI: Bool
    ) async -> Classification? {
        guard let pdfClass = try? await NativeDocumentClassifier.classify(
            pdfURL: fileURL, password: password
        ) else {
            // Can't open PDF — caller handles
            return nil
        }

        let kind: ContentKind
        let tier: RequiredTier
        let pathway: ConversionPathway

        switch pdfClass.recommendedPathway {
        case .pdfKit:
            kind = .digitalDocument
            tier = .basic
            pathway = .pdfKit
        case .enhanced:
            kind = .digitalDocument
            tier = supportsAdvancedRuntime ? .enhanced : .basic
            pathway = supportsAdvancedRuntime ? .enhanced : .pdfKit
        case .visionOCR:
            kind = .scannedDocument
            tier = supportsAI ? .ai : .basic
            pathway = supportsAI ? .ai : .visionOCR
        }

        AppLog.conversion.info(
            "ContentClassifier PDF kind=\(kind.diagnosticLabel, privacy: .public) tier=\(tier.diagnosticLabel, privacy: .public) pathway=\(pathway.rawValue, privacy: .public)"
        )
        return Classification(
            kind: kind,
            requiredTier: tier,
            hasExtractableText: kind == .digitalDocument,
            frameCount: pdfClass.evidence.pageCount,
            pdfEvidence: pdfClass.evidence,
            recommendedPathway: pathway
        )
    }

    // MARK: - Image classification

    private static func classifyImage(
        fileURL: URL,
        supportsAdvancedRuntime: Bool,
        supportsAI: Bool
    ) async -> Classification? {
        // Step 1: frame count via ImageIO — multi-page = always a scanned document
        let frameCount = imageFrameCount(fileURL: fileURL)

        if frameCount > 1 {
            AppLog.conversion.info(
                "ContentClassifier image multi-page frameCount=\(frameCount, privacy: .public) → scanned document"
            )
            return Classification(
                kind: .scannedDocument,
                requiredTier: supportsAI ? .ai : .basic,
                hasExtractableText: true,
                frameCount: frameCount,
                pdfEvidence: nil,
                recommendedPathway: supportsAI ? .ai : .visionOCR
            )
        }

        // Step 2: Vision scene classification — document vs photo/artwork
        let sceneKind = await classifyImageScene(fileURL: fileURL)

        switch sceneKind {
        case .photoOrArtwork:
            AppLog.conversion.info("ContentClassifier image scene=photo/artwork → metadata only")
            return Classification(
                kind: .photoOrArtwork,
                requiredTier: .basic,
                hasExtractableText: false,
                frameCount: 1,
                pdfEvidence: nil,
                recommendedPathway: .metadata
            )

        case .document, .unknown:
            // Step 3: VNRecognizeTextRequest (fast) to measure text density
            let textDensity = await probeImageTextDensity(fileURL: fileURL)
            let hasText = textDensity > 0.05  // >5% of image area has detected text

            if hasText {
                AppLog.conversion.info(
                    "ContentClassifier image scene=document textDensity=\(textDensity, privacy: .public) → scanned document"
                )
                return Classification(
                    kind: .scannedDocument,
                    requiredTier: supportsAI ? .ai : .basic,
                    hasExtractableText: true,
                    frameCount: 1,
                    pdfEvidence: nil,
                    recommendedPathway: supportsAI ? .ai : .visionOCR
                )
            } else {
                // Scene looks like a document but no text found — diagram/infographic
                AppLog.conversion.info(
                    "ContentClassifier image scene=document textDensity=\(textDensity, privacy: .public) → diagram/no text → metadata"
                )
                return Classification(
                    kind: .photoOrArtwork,
                    requiredTier: .basic,
                    hasExtractableText: false,
                    frameCount: 1,
                    pdfEvidence: nil,
                    recommendedPathway: .metadata
                )
            }
        }
    }

    // MARK: - Vision helpers

    private enum SceneKind { case document, photoOrArtwork, unknown }

    private static func classifyImageScene(fileURL: URL) async -> SceneKind {
        #if canImport(Vision)
        if #available(macOS 11.0, *) {
            return await withCheckedContinuation { continuation in
                let request = VNClassifyImageRequest { request, error in
                    guard error == nil,
                          let observations = request.results as? [VNClassificationObservation]
                    else {
                        continuation.resume(returning: .unknown)
                        return
                    }
                    // Document-like identifiers verified from VNClassifyImageRequest
                    // taxonomy (1,303 labels, Revision1/Revision2).
                    // "text" and "printed_text" do NOT exist in the taxonomy.
                    let documentLabels: Set<String> = [
                        "document", "printed_page", "receipt", "book", "newspaper",
                        "chart", "diagram", "flipchart", "checkbook"
                    ]
                    let topObservations = observations.filter { $0.confidence > 0.1 }
                    let isDocument = topObservations.contains { documentLabels.contains($0.identifier) }
                    continuation.resume(returning: isDocument ? .document : .photoOrArtwork)
                }
                let handler = VNImageRequestHandler(url: fileURL, options: [:])
                try? handler.perform([request])
            }
        }
        #endif
        return .unknown
    }

    private static func probeImageTextDensity(fileURL: URL) async -> Double {
        #if canImport(Vision)
        if #available(macOS 10.15, *) {
            return await withCheckedContinuation { continuation in
                let request = VNRecognizeTextRequest { request, error in
                    guard error == nil,
                          let observations = request.results as? [VNRecognizedTextObservation],
                          !observations.isEmpty
                    else {
                        continuation.resume(returning: 0)
                        return
                    }
                    // Measure total bounding-box area of detected text blocks
                    let totalArea = observations.reduce(0.0) { sum, obs in
                        let bb = obs.boundingBox
                        return sum + Double(bb.width * bb.height)
                    }
                    continuation.resume(returning: min(1.0, totalArea))
                }
                request.recognitionLevel = .fast  // ANE-accelerated, ~50ms
                request.usesLanguageCorrection = false
                let handler = VNImageRequestHandler(url: fileURL, options: [:])
                try? handler.perform([request])
            }
        }
        #endif
        return 0
    }

    // MARK: - ImageIO helpers

    private static func imageFrameCount(fileURL: URL) -> Int {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return 1 }
        return CGImageSourceGetCount(source)
    }
}

// MARK: - Diagnostic labels

extension ContentClassifier.ContentKind {
    var diagnosticLabel: String {
        switch self {
        case .digitalDocument:  return "digital-document"
        case .scannedDocument:  return "scanned-document"
        case .photoOrArtwork:   return "photo-artwork"
        case .structuredDocument: return "structured-document"
        case .audioVideo:       return "audio-video"
        }
    }
}

extension ContentClassifier.RequiredTier {
    var diagnosticLabel: String {
        switch self {
        case .basic:    return "basic"
        case .enhanced: return "enhanced"
        case .ai:       return "ai"
        }
    }
}
