import Foundation
import ImageIO
import OSLog
import PDFKit
import SwiftOfficeMarkdown
import UpmarketVLM
import UniformTypeIdentifiers

struct ConversionRunner {
    typealias ProgressHandler = (ConversionProgress) -> Void

    private let supportsAdvancedRuntime: Bool
    private let supportsAI: Bool
    private let tier: @Sendable () -> AppTier
    private let modelsReady: @Sendable () -> Bool
    private let usesInjectedModelReadiness: Bool
    private let classifyOverride: (@Sendable (URL, String?, Bool, Bool) async -> ContentClassifier.Classification?)?
    private let pdfCandidateBudget: PDFCandidateBudget

    @MainActor
    init(
        supportsAdvancedRuntime: Bool = DeviceCapability.currentSupportsAdvancedRuntime,
        supportsAI: Bool = DeviceCapability.shared.supportsUpmarketAI,
        tier: (@Sendable () -> AppTier)? = nil,
        modelsReady: (@Sendable () -> Bool)? = nil,
        classifyOverride: (@Sendable (URL, String?, Bool, Bool) async -> ContentClassifier.Classification?)? = nil,
        pdfCandidateBudget: PDFCandidateBudget = .default
    ) {
        self.supportsAdvancedRuntime = supportsAdvancedRuntime
        self.supportsAI = supportsAI

        if let tier {
            self.tier = tier
        } else {
            let tierValue = StoreManager.shared.tier
            self.tier = { tierValue }
        }

        if let modelsReady {
            self.modelsReady = modelsReady
            self.usesInjectedModelReadiness = true
        } else {
            let modelsReadyValue = ModelManager.shared.assetsReady(for: .ai)
            self.modelsReady = { modelsReadyValue }
            self.usesInjectedModelReadiness = false
        }

        self.classifyOverride = classifyOverride
        self.pdfCandidateBudget = pdfCandidateBudget
    }

    func analyse(fileURL: URL) async -> ComplexityAdvice? {
        let signpost = AppSignpost.conversion.beginInterval("analyse")
        defer { AppSignpost.conversion.endInterval("analyse", signpost) }

        let workspace: URL
        let tempURL: URL
        do {
            workspace = try AppWorkspace.create(prefix: "analyse")
            do {
                tempURL = try AppWorkspace.copy(fileURL, into: workspace)
            } catch {
                AppWorkspace.remove(workspace)
                return nil
            }
        } catch {
            return nil
        }
        defer { AppWorkspace.remove(workspace) }

        let classification: ContentClassifier.Classification?
        if let override = classifyOverride {
            classification = await override(tempURL, nil, supportsAdvancedRuntime, supportsAI)
        } else {
            classification = await ContentClassifier.classify(fileURL: tempURL, supportsAdvancedRuntime: supportsAdvancedRuntime, supportsAI: supportsAI)
        }
        guard let classification else { return nil }

        AppLog.conversion.info(
            "Document analysis kind=\(classification.kind.diagnosticLabel, privacy: .public) tier=\(classification.requiredTier.diagnosticLabel, privacy: .public)"
        )
        return classification.complexityAdvice
    }

    func run(_ job: ConversionJob, progress: ProgressHandler? = nil) async -> ConversionResult {
        let fileSizeBytes = await FileSystemMetrics.shared.readFileSize(job.sourceURL)
        AppLog.conversion.info("Starting conversion correlationID=\(job.correlationID, privacy: .public) ext=\(job.ext, privacy: .public) bytes=\(fileSizeBytes, privacy: .public)")
        guard !Task.isCancelled else { return .failure(ConversionError.cancelled.errorDescription ?? "Conversion cancelled.") }

        progress?(.copying)
        let workspace: URL
        let tempURL: URL
        let copySignpost = AppSignpost.conversion.beginInterval("copyToTemp")
        defer { AppSignpost.conversion.endInterval("copyToTemp", copySignpost) }
        do {
            workspace = try AppWorkspace.create(prefix: "conversion")
            do {
                tempURL = try AppWorkspace.copy(job.sourceURL, into: workspace)
            } catch {
                AppWorkspace.remove(workspace)
                throw error
            }
        } catch ConversionError.fileTooLarge {
            AppLog.conversion.error("Conversion rejected oversized file correlationID=\(job.correlationID, privacy: .public) bytes=\(fileSizeBytes, privacy: .public)")
            return .failure(ConversionError.fileTooLarge.errorDescription ?? "This document is too large to convert safely.")
        } catch ConversionError.sourceUnavailable {
            AppLog.conversion.error("Conversion source unavailable correlationID=\(job.correlationID, privacy: .public)")
            return .failure(ConversionError.sourceUnavailable.errorDescription ?? "This document is not available on this Mac.")
        } catch {
            AppLog.conversion.error("Conversion input copy failed correlationID=\(job.correlationID, privacy: .public) error=\(error.localizedDescription, privacy: .private)")
            return .failure(ConversionError.inaccessible.errorDescription ?? "Upmarket couldn't access this file.")
        }
        defer { AppWorkspace.remove(workspace) }

        progress?(.analysing)
        let analyseSignpost = AppSignpost.conversion.beginInterval("analyse")
        let classification: ContentClassifier.Classification?
        if let override = classifyOverride {
            classification = await override(tempURL, job.password, supportsAdvancedRuntime, supportsAI)
        } else {
            classification = await ContentClassifier.classify(fileURL: tempURL, password: job.password, supportsAdvancedRuntime: supportsAdvancedRuntime, supportsAI: supportsAI)
        }
        AppSignpost.conversion.endInterval("analyse", analyseSignpost)
        guard !Task.isCancelled else { return .failure(ConversionError.cancelled.errorDescription ?? "Conversion cancelled.") }

        // Entitlement gate: check if the user's tier can handle this content.
        // Basic users cannot convert scanned documents or documents requiring AI/Enhanced.
        if let classification {
            let entitlementCheck = checkCapability(for: classification, job: job)
            if let failure = entitlementCheck { return failure }
        }

        progress?(.extracting)
        let raw = await extract(job: job, tempURL: tempURL, workspaceURL: workspace, classification: classification, progress: progress)
        guard !Task.isCancelled else { return .failure(ConversionError.cancelled.errorDescription ?? "Conversion cancelled.") }
        guard case .success(let output) = raw else {
            AppLog.conversion.error("Conversion failed correlationID=\(job.correlationID, privacy: .public) ext=\(job.ext, privacy: .public) bytes=\(fileSizeBytes, privacy: .public)")
            return raw
        }

        progress?(.postProcessing)
        let postProcessSignpost = AppSignpost.conversion.beginInterval("postProcess")
        let refined = await ConversionPostProcessor.process(output)
        AppSignpost.conversion.endInterval("postProcess", postProcessSignpost)
        progress?(.complete)
        AppLog.conversion.info("Conversion completed correlationID=\(job.correlationID, privacy: .public)")
        return .success(refined)
    }

    // MARK: - Capability gate

    /// Returns a failure result if the user cannot use the required capability, nil to proceed.
    private func checkCapability(
        for classification: ContentClassifier.Classification,
        job: ConversionJob
    ) -> ConversionResult? {
        var downloadedAssets: Set<ModelAsset>
        if usesInjectedModelReadiness {
            downloadedAssets = modelsReady() ? Set(classification.requiredTier.requiredAssets) : []
        } else {
            downloadedAssets = ModelManager.shared.downloadedAssets
        }
        if classification.requiredTier == .ai {
            let engine = job.aiEngine ?? AIEngine.selected
            if engine == .lfm2 {
                if downloadedAssets.contains(engine.asset) {
                    downloadedAssets.insert(.graniteDocling)
                } else {
                    downloadedAssets.remove(.graniteDocling)
                }
            }
        }

        let gate = AppTierGate(
            tier: tier(),
            downloadedAssets: downloadedAssets,
            deviceSupportsRuntime: supportsAdvancedRuntime,
            aiFeatureEnabled: supportsAI && FeatureFlags.shared.aiAvailable,
            aiFeatureUnavailableReason: FeatureFlags.shared.aiUnavailableReason
        )
        if let reason = gate.unavailableReason(for: classification.requiredTier) {
            if classification.requiredTier == .ai {
                AppLog.conversion.info("AI capability blocked correlationID=\(job.correlationID, privacy: .public) reason=\(reason, privacy: .public)")
            }
            let error: ConversionError = classification.requiredTier == .ai
                ? (tier() < .max ? .upgradeRequired : .modelUnavailable)
                : .unsupportedOnThisMac
            return .failure(error.errorDescription ?? reason)
        }
        return nil
    }

    // MARK: - Content-driven routing

    /// Routes conversion based on ContentClassifier result rather than file extension.
    /// The classifier has already examined the actual content; we trust its recommendation.
    private func extract(
        job: ConversionJob,
        tempURL: URL,
        workspaceURL: URL,
        classification: ContentClassifier.Classification?,
        progress: ProgressHandler?
    ) async -> ConversionResult {
        let title = job.sourceURL.deletingPathExtension().lastPathComponent

        guard let classification else {
            // Classifier returned nil — file unreadable
            return .failure(ConversionError.inaccessible.errorDescription ?? "Upmarket couldn't access this file.")
        }

        // An explicit engine arrives from the CLI evaluation path. It must force that exact
        // model and fail closed: classifier routing or OCR fallback would otherwise write
        // non-model output into a file labelled as Granite or LFM2.
        let sourceExtension = job.sourceURL.pathExtension.lowercased()
        if job.useAI, let engine = job.aiEngine, sourceExtension == "pdf" {
            guard #available(macOS 26, *),
                  shouldUseVLM(engine: engine, evidence: classification.pdfEvidence, force: true) else {
                return .failure(
                    ConversionError.modelUnavailable.errorDescription
                        ?? "The selected AI model is not available."
                )
            }
            return await runVLMConversion(
                fileURL: tempURL,
                title: title,
                password: job.password,
                workspaceURL: workspaceURL,
                engine: engine,
                fallbackOnFailure: false
            )
        }

        switch classification.kind {

        case .audioVideo:
            return await runAudioConversion(
                fileURL: tempURL, title: title, useAI: job.useAI,
                password: job.password, workspaceURL: workspaceURL, progress: progress
            )

        case .photoOrArtwork:
            // No extractable text — return metadata only
            let ext = job.sourceURL.pathExtension.lowercased()
            if NativeMetadataExtractor.handlesMedia(ext) {
                return await NativeMetadataExtractor.mediaMetadata(url: tempURL, title: title)
            }
            return NativeMetadataExtractor.imageMetadata(url: tempURL, title: title)

        case .structuredDocument:
            // All structured formats convert in-process with native engines — no Python.
            // The capability gate has already cleared the tier.
            let ext = job.sourceURL.pathExtension.lowercased()
            if ext == "html" || ext == "htm" {
                return runNativeHTMLConversion(fileURL: tempURL, title: title)
            }
            if NativeTextConverter.extensions.contains(ext) {
                // Plain-text family (.txt/.md/.csv) — in-process.
                return runNativeTextConversion(fileURL: tempURL, title: title, ext: ext)
            }
            if Self.nativeOfficeExtensions.contains(ext) {
                // OOXML + legacy-binary Office via the native SwiftOfficeMarkdown engine.
                return runNativeOfficeConversion(fileURL: tempURL, title: title)
            }
            if ext == "epub" {
                // EPUB is a ZIP of XHTML — converted in-process (ZipReader + native HTML).
                return runNativeEPUBConversion(fileURL: tempURL, title: title)
            }
            // Formats with no native engine (e.g. .zip/.webvtt) are not supported
            // without the removed Python runtime.
            return .failure(ConversionError.unsupportedOnThisMac.errorDescription ?? "This conversion is not supported on this Mac.")

        case .digitalDocument:
            // Digital PDF or image with embedded/clean text
            // Route through quality-selected conversion with evidence from classifier
            let evidence = classification.pdfEvidence
            switch classification.recommendedPathway {
            case .pdfKit:
                return await runPDFKitConversion(
                    fileURL: tempURL, title: title, password: job.password, workspaceURL: workspaceURL
                )
            case .visionOCR, .enhanced:
                // Complex/digital documents: Apple Vision (PDFKit baseline + Vision OCR,
                // quality-selected) is the Pure-Apple engine. The Enhanced (Docling/Python)
                // path has been removed; native Granite is reserved for the AI pathway.
                return await runQualitySelectedPDFConversion(
                    fileURL: tempURL, title: title, password: job.password,
                    workspaceURL: workspaceURL, classifierEvidence: evidence,
                    progress: progress
                )
            case .ai:
                // AI pathway. The user-selected native VLM (mlx-swift, no Python) runs when its
                // weights are present. Granite-Docling is narrow (clean typed Latin/simplified-
                // Chinese only); LFM2.5-VL is general-purpose so it skips that eligibility gate.
                // Everything else (and any failure) falls through to Apple Vision native.
                let engine = job.aiEngine ?? AIEngine.selected
                if #available(macOS 26, *), shouldUseVLM(engine: engine, evidence: evidence) {
                    return await runVLMConversion(
                        fileURL: tempURL, title: title, password: job.password,
                        workspaceURL: workspaceURL, engine: engine
                    )
                }
                return await runVisionExtraction(
                    fileURL: tempURL, title: title, password: job.password, workspaceURL: workspaceURL
                )
            case .speech, .metadata, .nativeHTML, .nativeOffice, .nativeText, .nativeEPUB:
                // Not reachable for digital documents (native HTML/Office/text/EPUB route
                // via .structuredDocument); PDFKit is the safe native default here.
                return await runPDFKitConversion(
                    fileURL: tempURL, title: title, password: job.password, workspaceURL: workspaceURL
                )
            }

        case .scannedDocument:
            // Image/TIFF/scanned PDF requiring OCR or AI
            // Entitlement gate already passed above; route to best available
            let useAI = job.useAI && supportsAI
                && tier() >= .max
            let evidence = classification.pdfEvidence
            let ext = job.sourceURL.pathExtension.lowercased()
            let engine = job.aiEngine ?? AIEngine.selected
            // Max+AI on a PDF: the user-selected native VLM (mlx-swift) when its weights are
            // present and (for Granite) the document is eligible; otherwise Apple Vision.
            if useAI, ext == "pdf",
               #available(macOS 26, *),
               shouldUseVLM(engine: engine, evidence: evidence) {
                return await runVLMConversion(
                    fileURL: tempURL, title: title, password: job.password,
                    workspaceURL: workspaceURL, engine: engine
                )
            }
            // Scanned images carry no page structure that PDFKit/PDF-Vision can parse, so they
            // need the image-specific Vision-OCR API rather than the PDF quality path (which
            // calls VisionDocumentExtractor.extract(pdfURL:) and would fail on raw images).
            if Self.imageExtensions.contains(ext) {
                return await runVisionImageExtraction(fileURL: tempURL, title: title)
            }
            // Scanned/complex PDFs and non-eligible docs: Apple Vision OCR over the PDF path.
            return await runQualitySelectedPDFConversion(
                fileURL: tempURL, title: title, password: job.password,
                workspaceURL: workspaceURL, classifierEvidence: evidence,
                progress: progress
            )
        }
    }

    private func runAudioConversion(
        fileURL: URL,
        title: String,
        useAI: Bool,
        password: String?,
        workspaceURL: URL,
        progress: ProgressHandler?
    ) async -> ConversionResult {
        let speech = await runSpeechTranscription(fileURL: fileURL, title: title)
        if speech.output != nil {
            return speech
        }
        // Speech transcription unavailable — fall back to native media metadata.
        return await runMediaMetadataFallback(fileURL: fileURL, title: title, previous: speech)
    }

    private func runMediaMetadataFallback(fileURL: URL, title: String, previous: ConversionResult) async -> ConversionResult {
        guard let format = ConversionFormat(fileExtension: fileURL.pathExtension),
              ToolFormatCapabilityMatrix.supports(.avFoundation, format) else {
            return previous
        }
        AppLog.conversion.info("Audio transcription unavailable; trying native media metadata ext=\(fileURL.pathExtension, privacy: .public)")
        let metadata = await NativeMetadataExtractor.mediaMetadata(url: fileURL, title: title)
        return metadata.output == nil ? previous : metadata
    }

    /// Raster image formats that carry OCR-able text. Routed through the image-specific
    /// Vision API rather than the PDF path, which cannot open a bare image.
    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "tiff", "tif", "heic", "heif", "webp", "bmp", "gif",
    ]

    /// Apple Vision OCR for a single scanned image. Mirrors `runVisionExtraction` but uses
    /// the image entry point (`extract(imageURL:)`); images are never password-protected.
    private func runVisionImageExtraction(fileURL: URL, title: String) async -> ConversionResult {
        let signpost = AppSignpost.conversion.beginInterval("nativeExtract")
        defer { AppSignpost.conversion.endInterval("nativeExtract", signpost) }

        do {
            let result = try await VisionDocumentExtractor.extract(imageURL: fileURL)
            var metadata = DocumentMetadata.visionDocuments(elementType: result.documentElementType)
            metadata = DocumentMetadata(
                elementType: metadata.elementType,
                language: metadata.language,
                extractionMethod: "vision",
                extractionConfidence: 0.85,
                containsHandwriting: result.containsHandwriting,
                handwritingRatio: result.handwritingRatio
            )
            return .success(ConversionOutput(
                markdown: result.markdown,
                pages: result.pageCount,
                format: fileURL.pathExtension.uppercased(),
                title: title,
                pipeline: .fast,
                selectedPathway: .visionOCR,
                metadata: metadata,
                originalTables: result.structuredTables
            ))
        } catch VisionDocumentExtractor.ExtractionError.passwordRequired {
            // Not expected for images, but handled for parity with the PDF path.
            return .failure(ConversionError.passwordRequired.errorDescription ?? "This file is protected.")
        } catch {
            return .failure(ConversionError.inaccessible.errorDescription ?? "Upmarket couldn't read this image.")
        }
    }

    private func runVisionExtraction(fileURL: URL, title: String, password: String?, workspaceURL: URL) async -> ConversionResult {
        let signpost = AppSignpost.conversion.beginInterval("nativeExtract")
        defer { AppSignpost.conversion.endInterval("nativeExtract", signpost) }

        // Check if PDF needs chunking for structured extraction (page limit ~20-30)
        if DocumentChunker.needsChunking(fileURL) {
            AppLog.conversion.info("Large PDF detected; will process in chunks for structured extraction")
            return await runChunkedVisionExtraction(fileURL: fileURL, title: title, password: password)
        }

        do {
            let result = try await VisionDocumentExtractor.extract(pdfURL: fileURL, password: password)

            // Check if significant handwriting detected and suggest AI routing
            var metadata = DocumentMetadata.visionDocuments(
                elementType: result.documentElementType
            )
            metadata = DocumentMetadata(
                elementType: metadata.elementType,
                language: metadata.language,
                extractionMethod: "vision",
                extractionConfidence: 0.85,
                containsHandwriting: result.containsHandwriting,
                handwritingRatio: result.handwritingRatio
            )

            // If significant handwriting detected and AI available, flag for potential re-routing
            if result.containsHandwriting && supportsAI && modelsReady() {
                AppLog.conversion.info("Significant handwriting detected; AI pathway may improve quality")
            }

            return .success(ConversionOutput(
                markdown: result.markdown,
                pages: result.pageCount,
                format: "PDF",
                title: title,
                pipeline: .fast,
                selectedPathway: .visionOCR,
                metadata: metadata,
                originalTables: result.structuredTables
            ))
        } catch VisionDocumentExtractor.ExtractionError.passwordRequired {
            return .failure(ConversionError.passwordRequired.errorDescription ?? "This PDF is password-protected.")
        } catch {
            return await runPDFKitConversion(fileURL: fileURL, title: title, password: password, workspaceURL: workspaceURL)
        }
    }

    /// True when the user-selected AI engine should run for this document: its weights are on
    /// disk and — for the narrow Granite-Docling engine only — the document is eligible. The
    /// general-purpose LFM2.5-VL engine skips the eligibility gate.
    @available(macOS 26, *)
    private func shouldUseVLM(
        engine: AIEngine,
        evidence: NativeDocumentClassifier.Evidence?,
        force: Bool = false
    ) -> Bool {
        guard ModelManager.shared.downloadedAssets.contains(engine.asset) else { return false }
        return force || engine == .lfm2 || evidence?.isGraniteDoclingEligible == true
    }

    /// Native VLM (mlx-swift, no Python) PDF conversion — the no-Python replacement for the
    /// Docling-MLX AI path. Renders each page and runs the user-selected on-device engine
    /// (Granite-Docling → DocTags→Markdown, or LFM2.5-VL → plain Markdown). Falls back to
    /// Apple Vision (also Pure-Apple) on any model-load or inference failure.
    @available(macOS 26, *)
    private func runVLMConversion(
        fileURL: URL,
        title: String,
        password: String?,
        workspaceURL: URL,
        engine: AIEngine,
        fallbackOnFailure: Bool = true
    ) async -> ConversionResult {
        guard let document = PDFDocument(url: fileURL) else {
            if !fallbackOnFailure {
                return .failure("The selected AI engine could not read this PDF.")
            }
            return await runVisionExtraction(fileURL: fileURL, title: title, password: password, workspaceURL: workspaceURL)
        }
        if document.isLocked, let password { _ = document.unlock(withPassword: password) }

        // Each engine loads its own weights directory. The per-page closure hides the engine
        // difference from the page loop below. Release resolves an Apple-managed asset-pack URL
        // (process-lifetime, never persisted); Debug resolves a local directory.
        let modelDir: URL
        do {
            modelDir = try await ModelManager.shared.resolveModelDirectory(for: engine.asset)
        } catch {
            if !fallbackOnFailure {
                return .failure("The AI model isn't available. Re-download it from Settings.")
            }
            return await runVisionExtraction(fileURL: fileURL, title: title, password: password, workspaceURL: workspaceURL)
        }
        let convert: @Sendable (URL) async throws -> String
        switch engine {
        case .granite:
            let e = GraniteDoclingEngine(source: .modelDirectory(modelDir))
            convert = { try await e.convertToMarkdown(imageURL: $0) }
        case .lfm2:
            let e = LFM2VLEngine(source: .modelDirectory(modelDir))
            convert = { try await e.convertToMarkdown(imageURL: $0) }
        }

        let tmp = FileManager.default.temporaryDirectory
        var pages: [String] = []
        do {
            for i in 0..<document.pageCount {
                try Task.checkCancellation()
                guard let page = document.page(at: i), let cg = Self.renderPDFPage(page) else { continue }
                let url = tmp.appendingPathComponent("vlm-\(UUID().uuidString).png")
                try Self.writePNG(cg, to: url)
                defer { try? FileManager.default.removeItem(at: url) }
                pages.append(try await convert(url))
            }
        } catch is CancellationError {
            return .failure("Conversion cancelled.")
        } catch {
            if !fallbackOnFailure {
                AppLog.conversion.error("Explicit AI conversion failed: \(error.localizedDescription, privacy: .public)")
                return .failure("The selected AI engine could not convert this document.")
            }
            AppLog.conversion.error("Native AI conversion failed; falling back to OCR: \(error.localizedDescription, privacy: .public)")
            return await runVisionExtraction(fileURL: fileURL, title: title, password: password, workspaceURL: workspaceURL)
        }
        return .success(ConversionOutput(
            markdown: pages.joined(separator: "\n\n---\n\n"),
            pages: document.pageCount, format: "PDF", title: title,
            pipeline: .ai, selectedPathway: .ai,
            metadata: DocumentMetadata.visionDocuments(elementType: nil),
            originalTables: []))
    }

    // Granite-Docling reads scanned pages at the embedded raster's native detail; 150 dpi
    // upscales a typical scan into blur (the VLM then mis-reads it as a picture), so the AI
    // path renders at 300 dpi. The scale is clamped so an oversized page can't exceed the
    // Vision render-side budget and blow memory.
    private static func renderPDFPage(_ page: PDFPage, dpi: CGFloat = 300) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let maxSide = CGFloat(VisionProcessingLimits.maximumRenderedSide)
        let scale = min(dpi / 72.0, maxSide / max(bounds.width, bounds.height))
        let w = Int(bounds.width * scale), h = Int(bounds.height * scale)
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }

    /// Process large PDFs by chunking into Vision-safe pieces.
    private func runChunkedVisionExtraction(fileURL: URL, title: String, password: String?) async -> ConversionResult {
        do {
            let chunks = try DocumentChunker.chunk(pdfURL: fileURL, password: password)
            let metadata = DocumentChunker.analyzeChunking(pageCount: chunks.last?.endPageIndex ?? 0)

            AppLog.conversion.info("Processing large PDF in \(metadata.chunkCount, privacy: .public) chunk(s)")

            var allMarkdowns: [String] = []
            var allTables: [TableRepair.StructuredTable] = []
            var totalPages = 0

            for chunk in chunks {
                if Task.isCancelled {
                    return .failure(ConversionError.cancelled.errorDescription ?? "Conversion cancelled.")
                }

                // Extract chunk using Vision
                let chunkMarkdown = try await extractChunk(chunk, password: password)
                allMarkdowns.append(chunkMarkdown.markdown)
                allTables.append(contentsOf: chunkMarkdown.tables)
                totalPages += chunk.pageCount
            }

            let combined = allMarkdowns.joined(separator: "\n\n---\n\n")

            return .success(ConversionOutput(
                markdown: combined,
                pages: totalPages,
                format: "PDF",
                title: title,
                pipeline: .fast,
                selectedPathway: .visionOCR,
                metadata: DocumentMetadata(
                    elementType: nil,
                    language: nil,
                    extractionMethod: "vision-chunked",
                    extractionConfidence: 0.80
                ),
                originalTables: allTables
            ))
        } catch DocumentChunker.ChunkingError.passwordRequired {
            return .failure(ConversionError.passwordRequired.errorDescription ?? "This PDF is password-protected.")
        } catch {
            AppLog.conversion.error("Chunk processing failed: \(error.localizedDescription, privacy: .private)")
            // Fallback to basic extraction if chunking fails
            return .failure("Unable to process this large document safely. Please try with a smaller file or use a simpler conversion mode.")
        }
    }

    /// Extract a single chunk of a PDF.
    private func extractChunk(_ chunk: DocumentChunker.Chunk, password: String?) async throws -> (markdown: String, tables: [TableRepair.StructuredTable]) {
        // Create temporary PDF with just this chunk's pages
        let tempPDF = PDFDocument()
        for page in chunk.pages {
            tempPDF.insert(page, at: tempPDF.pageCount)
        }

        // Save to temporary file
        let tempDir = try AppWorkspace.create(prefix: "chunk")
        defer { try? AppWorkspace.remove(tempDir) }

        let tempURL = tempDir.appendingPathComponent("chunk.pdf")
        guard tempPDF.write(to: tempURL) else {
            throw ConversionError.failed("Could not save PDF chunk to temporary file")
        }

        // Extract using Vision on macOS 26+ or VisionOCR as fallback
        if #available(macOS 26, *) {
            let result = try await VisionDocumentExtractor.extract(pdfURL: tempURL, password: password)
            return (markdown: result.markdown, tables: result.structuredTables)
        } else {
            let result = try await VisionOCR.recognise(pdfURL: tempURL, password: password)
            return (markdown: result.text, tables: [])
        }
    }

    private func runSpeechTranscription(fileURL: URL, title: String) async -> ConversionResult {
        let signpost = AppSignpost.conversion.beginInterval("nativeExtract")
        defer { AppSignpost.conversion.endInterval("nativeExtract", signpost) }

        guard await SpeechTranscriber.requestAuthorisation() else {
            return .failure("Microphone access is required to transcribe audio. Enable it in System Settings -> Privacy.")
        }
        do {
            let transcriber = SpeechTranscriber()
            let result = try await transcriber.transcribe(audioURL: fileURL)
            let markdown = transcriber.toMarkdown(result)
            return .success(ConversionOutput(
                markdown: markdown,
                pages: 1,
                format: fileURL.pathExtension.uppercased(),
                title: title,
                pipeline: .fast,
                selectedPathway: .speech
            ))
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func runPDFKitConversion(fileURL: URL, title: String, password: String?, workspaceURL: URL) async -> ConversionResult {
        let signpost = AppSignpost.conversion.beginInterval("nativeExtract")
        defer { AppSignpost.conversion.endInterval("nativeExtract", signpost) }

        do {
            let result = try PDFConverter.convert(url: fileURL, password: password)
            return .success(ConversionOutput(
                markdown: result.markdown,
                pages: result.pageCount,
                format: "PDF",
                title: title,
                pipeline: .fast,
                selectedPathway: .pdfKit,
                metadata: DocumentMetadata.pdfkit()
            ))
        } catch PDFConverter.ConversionError.passwordRequired {
            return .failure(ConversionError.passwordRequired.errorDescription ?? "This PDF is password-protected.")
        } catch let error as VisionProcessingLimitError {
            switch error {
            case .tooManyPages, .imageTooLarge, .pageTooLarge:
                return .failure(ConversionError.fileTooLarge.errorDescription ?? "This document is too large to convert safely.")
            case .invalidPageBounds:
                return .failure(ConversionError.inaccessible.errorDescription ?? "Upmarket couldn't access this file.")
            }
        } catch {
            // PDFKit couldn't parse it. Vision is run separately as the secondary candidate
            // in runQualitySelectedPDFConversion, so surface a clear failure here rather than
            // recursing into Vision (whose own fallback is PDFKit).
            return .failure(ConversionError.inaccessible.errorDescription ?? "Upmarket couldn't read this document.")
        }
    }

    /// In-process HTML → Markdown conversion. No Python, no network, no download — runs in
    /// the Basic tier. Returns `.failure` on unreadable/unparseable input so the caller can
    /// fall back to the Enhanced runtime when it is available.
    private func runNativeHTMLConversion(fileURL: URL, title: String) -> ConversionResult {
        let signpost = AppSignpost.conversion.beginInterval("nativeExtract")
        defer { AppSignpost.conversion.endInterval("nativeExtract", signpost) }

        guard let data = try? Data(contentsOf: fileURL) else {
            return .failure(ConversionError.inaccessible.errorDescription ?? "Upmarket couldn't access this file.")
        }
        guard let markdown = try? NativeHTMLConverter.convert(data: data),
              !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(ConversionError.inaccessible.errorDescription ?? "Upmarket couldn't read this HTML file.")
        }
        return .success(ConversionOutput(
            markdown: markdown,
            pages: 1,
            format: "HTML",
            title: title,
            pipeline: .fast,
            selectedPathway: .nativeHTML,
            metadata: DocumentMetadata.nativeHTML()
        ))
    }

    /// Office documents (OOXML `.docx/.xlsx/.pptx` + variants, and legacy binary
    /// `.doc/.xls/.xlsb/.ppt`) converted in-process — no Python runtime needed.
    static let nativeOfficeExtensions: Set<String> = [
        "docx", "docm", "dotx", "dotm",
        "xlsx", "xlsm", "xltx", "xltm", "xlsb",
        "pptx", "pptm", "potx", "potm", "ppsx", "ppsm",
        "doc", "xls", "ppt",
    ]

    /// Plain-text family (`.txt/.md/.csv`) → Markdown, in-process. No Python, no network,
    /// no download — runs in the Basic tier. Returns `.failure` on unreadable input so the
    /// caller can fall back to the Enhanced runtime when it is available.
    private func runNativeTextConversion(fileURL: URL, title: String, ext: String) -> ConversionResult {
        let signpost = AppSignpost.conversion.beginInterval("nativeExtract")
        defer { AppSignpost.conversion.endInterval("nativeExtract", signpost) }

        guard let data = try? Data(contentsOf: fileURL) else {
            return .failure(ConversionError.inaccessible.errorDescription ?? "Upmarket couldn't access this file.")
        }
        guard let markdown = try? NativeTextConverter.convert(data: data, ext: ext),
              !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(ConversionError.inaccessible.errorDescription ?? "Upmarket couldn't read this file.")
        }
        return .success(ConversionOutput(
            markdown: markdown,
            pages: 1,
            format: ext.uppercased(),
            title: title,
            pipeline: .fast,
            selectedPathway: .nativeText
        ))
    }

    private func runNativeOfficeConversion(fileURL: URL, title: String) -> ConversionResult {
        let signpost = AppSignpost.conversion.beginInterval("nativeExtract")
        defer { AppSignpost.conversion.endInterval("nativeExtract", signpost) }

        guard let markdown = try? OfficeToMarkdown.convert(fileURL: fileURL),
              !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(ConversionError.inaccessible.errorDescription ?? "Upmarket couldn't read this document.")
        }
        return .success(ConversionOutput(
            markdown: markdown,
            pages: 0,
            format: fileURL.pathExtension.uppercased(),
            title: title,
            pipeline: .fast,
            selectedPathway: .nativeOffice
        ))
    }

    /// EPUB → Markdown in-process (ZipReader + native HTML walker). No Python, no download.
    private func runNativeEPUBConversion(fileURL: URL, title: String) -> ConversionResult {
        let signpost = AppSignpost.conversion.beginInterval("nativeExtract")
        defer { AppSignpost.conversion.endInterval("nativeExtract", signpost) }

        guard let markdown = try? NativeEPUBConverter.convert(fileURL: fileURL),
              !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(ConversionError.inaccessible.errorDescription ?? "Upmarket couldn't read this book.")
        }
        return .success(ConversionOutput(
            markdown: markdown,
            pages: 0,
            format: "EPUB",
            title: title,
            pipeline: .fast,
            selectedPathway: .nativeEPUB
        ))
    }

    /// PDFKit baseline + Apple Vision OCR, quality-selected. Both engines are native
    /// (Pure-Apple); the removed Python/Docling path is no longer a candidate.
    private func runQualitySelectedPDFConversion(
        fileURL: URL,
        title: String,
        password: String?,
        workspaceURL: URL,
        classifierEvidence: NativeDocumentClassifier.Evidence?,
        progress: ProgressHandler?
    ) async -> ConversionResult {
        var outputs: [(label: String, output: ConversionOutput)] = []
        var firstFailure: ConversionResult?

        let basic = await runPDFKitConversion(fileURL: fileURL, title: title, password: password, workspaceURL: workspaceURL)
        if case .success(let output) = basic {
            outputs.append((label: "basic", output: output))
            guard pdfCandidateBudget.shouldRunSecondary(
                afterBasic: output,
                evidence: classifierEvidence
            ) else {
                AppLog.conversion.info("PDF candidate budget accepted basic output without secondary path pages=\(output.pages, privacy: .public)")
                return .success(output)
            }
        } else {
            firstFailure = basic
        }

        let vision = await runVisionExtraction(fileURL: fileURL, title: title, password: password, workspaceURL: workspaceURL)
        if case .success(let output) = vision {
            outputs.append((label: "image-text", output: output))
        } else if firstFailure == nil {
            firstFailure = vision
        }

        let serialResults = outputs.map { (label: $0.label, result: ConversionResult.success($0.output)) }
            + (firstFailure.map { [("__failure__", $0)] } ?? [])
        return selectBest(from: serialResults, evidence: classifierEvidence)
    }

    private func selectBest(
        from results: [(label: String, result: ConversionResult)],
        evidence: NativeDocumentClassifier.Evidence?
    ) -> ConversionResult {
        var outputs: [(label: String, output: ConversionOutput)] = []
        var firstFailure: ConversionResult?
        for (label, result) in results {
            if case .success(let output) = result {
                outputs.append((label: label, output: output))
            } else if firstFailure == nil {
                firstFailure = result
            }
        }
        let imageTextReference = outputs.first { $0.label == "image-text" }?.output.markdown
        let candidates = outputs.map {
            scoredCandidate(label: $0.label, output: $0.output,
                            evidence: evidence, imageTextReference: imageTextReference)
        }
        guard let best = MarkdownQualityScorer.best(candidates) else {
            return firstFailure ?? .failure("Upmarket couldn't convert this document.")
        }
        AppLog.conversion.info(
            "Selected conversion candidate=\(best.label, privacy: .public) quality=\(best.score.overall, privacy: .public)"
        )
        return .success(best.output)
    }

    private func scoredCandidate(
        label: String,
        output: ConversionOutput,
        evidence: NativeDocumentClassifier.Evidence?,
        imageTextReference: String?
    ) -> (label: String, output: ConversionOutput, score: MarkdownQualityScorer.Score) {
        (
            label: label,
            output: output,
            score: MarkdownQualityScorer.score(
                markdown: output.markdown,
                pages: output.pages,
                classifierEvidence: evidence,
                imageText: imageTextReference
            )
        )
    }

}
