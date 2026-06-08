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

        // Step 2: VNRecognizeTextRequest (ANE, fast recognition level, ~50-100ms).
        // This is the single source of truth for all 1,303 taxonomy categories —
        // rather than maintaining a hardcoded subset of VNClassifyImageRequest
        // identifiers, we ask Vision directly: "is there readable text here?"
        // If yes → scanned document (route to OCR/AI).
        // If no  → photo, artwork, or diagram with no text (route to metadata).
        // This handles the full taxonomy correctly without any manual label list.
        let textSignal = await probeImageTextSignal(fileURL: fileURL)
        // Require ≥20 recognised words to classify as a text document.
        // Area-based thresholds fail on two edges:
        //   - Diagrams with a few axis labels: high area ratio, low word count → not a doc
        //   - Small-text images (webp): low area ratio, meaningful word count → is a doc
        let hasText = textSignal.wordCount >= 10

        if hasText {
            AppLog.conversion.info(
                "ContentClassifier image wordCount=\(textSignal.wordCount, privacy: .public) → scanned document"
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
            AppLog.conversion.info(
                "ContentClassifier image wordCount=\(textSignal.wordCount, privacy: .public) → no extractable text → metadata"
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

    private struct TextSignal {
        let wordCount: Int
    }

    private static func probeImageTextSignal(fileURL: URL) async -> TextSignal {
        #if canImport(Vision)
        if #available(macOS 10.15, *) {
            return await withCheckedContinuation { continuation in
                let request = VNRecognizeTextRequest { request, error in
                    guard error == nil,
                          let observations = request.results as? [VNRecognizedTextObservation]
                    else {
                        continuation.resume(returning: TextSignal(wordCount: 0))
                        return
                    }
                    // Count words across all recognised text blocks.
                    // Word count is robust to image scale and bounding-box size variations:
                    //   - Diagrams with axis labels: few words (e.g. 5) → not a document
                    //   - Text documents at any resolution: many words (≥20) → document
                    let words = observations
                        .compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: " ")
                        .split(separator: " ")
                        .count
                    continuation.resume(returning: TextSignal(wordCount: words))
                }
                request.recognitionLevel = .fast  // ANE-accelerated, ~50ms
                request.usesLanguageCorrection = false
                let handler = VNImageRequestHandler(url: fileURL, options: [:])
                try? handler.perform([request])
            }
        }
        #endif
        return TextSignal(wordCount: 0)
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
