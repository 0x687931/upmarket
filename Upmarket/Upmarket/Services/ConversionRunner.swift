import Foundation
import OSLog

struct ConversionRunner {
    typealias ProgressHandler = (ConversionProgress) -> Void

    let pythonWorker: PythonWorker
    private let supportsAdvancedRuntime: Bool
    private let supportsAI: Bool
    private let tier: @Sendable () -> AppTier
    private let modelsReady: @Sendable () -> Bool
    private let usesInjectedModelReadiness: Bool
    private let classifyOverride: (@Sendable (URL, String?, Bool, Bool) async -> ContentClassifier.Classification?)?
    private let pdfCandidateBudget: PDFCandidateBudget

    @MainActor
    init(
        pythonWorker: PythonWorker = PythonWorker(),
        supportsAdvancedRuntime: Bool = DeviceCapability.currentSupportsAdvancedRuntime,
        supportsAI: Bool = DeviceCapability.shared.supportsUpmarketAI,
        tier: (@Sendable () -> AppTier)? = nil,
        modelsReady: (@Sendable () -> Bool)? = nil,
        classifyOverride: (@Sendable (URL, String?, Bool, Bool) async -> ContentClassifier.Classification?)? = nil,
        pdfCandidateBudget: PDFCandidateBudget = .default
    ) {
        self.pythonWorker = pythonWorker
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
        let fileSizeBytes = await FileSizeReader.shared.readSize(job.sourceURL)
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
        let downloadedAssets: Set<ModelAsset>
        if usesInjectedModelReadiness {
            downloadedAssets = modelsReady() ? Set(classification.requiredTier.requiredAssets) : []
        } else {
            downloadedAssets = ModelManager.shared.downloadedAssets
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
            // DOCX/PPTX/HTML etc. — Enhanced pathway, PDFKit fallback
            guard supportsAdvancedRuntime else {
                return .failure(ConversionError.unsupportedOnThisMac.errorDescription ?? "This conversion is not supported on this Mac.")
            }
            return await runPythonConversion(
                fileURL: tempURL, title: title, useAI: false,
                password: job.password, workspaceURL: workspaceURL, progress: progress
            )

        case .digitalDocument:
            // Digital PDF or image with embedded/clean text
            // Route through quality-selected conversion with evidence from classifier
            let evidence = classification.pdfEvidence
            switch classification.recommendedPathway {
            case .pdfKit:
                return await runPDFKitConversion(
                    fileURL: tempURL, title: title, password: job.password, workspaceURL: workspaceURL
                )
            case .visionOCR:
                return await runQualitySelectedPDFConversion(
                    fileURL: tempURL, title: title, password: job.password,
                    workspaceURL: workspaceURL, classifierEvidence: evidence,
                    secondary: .imageText, progress: progress
                )
            case .enhanced:
                guard supportsAdvancedRuntime else {
                    return await runPDFKitConversion(
                        fileURL: tempURL, title: title, password: job.password, workspaceURL: workspaceURL
                    )
                }
                return await runQualitySelectedPDFConversion(
                    fileURL: tempURL, title: title, password: job.password,
                    workspaceURL: workspaceURL, classifierEvidence: evidence,
                    secondary: .advanced(useAI: false), progress: progress
                )
            case .ai, .speech, .metadata:
                return await runPDFKitConversion(
                    fileURL: tempURL, title: title, password: job.password, workspaceURL: workspaceURL
                )
            }

        case .scannedDocument:
            // Image/TIFF/scanned PDF requiring OCR or AI
            // Entitlement gate already passed above; route to best available
            let useAI = job.useAI && supportsAI
                && tier() >= .max
            if useAI {
                // Pro+AI: PDFKit baseline + Vision OCR + AI (concurrent in runQualitySelectedPDFConversion)
                let evidence = classification.pdfEvidence
                let ext = job.sourceURL.pathExtension.lowercased()
                if ext == "pdf" {
                    return await runQualitySelectedPDFConversion(
                        fileURL: tempURL, title: title, password: job.password,
                        workspaceURL: workspaceURL, classifierEvidence: evidence,
                        secondary: .all(useAI: true), progress: progress
                    )
                } else {
                    // Image/TIFF — run AI directly (VLM handles images natively)
                    return await runPythonConversion(
                        fileURL: tempURL, title: title, useAI: true,
                        password: job.password, workspaceURL: workspaceURL, progress: progress
                    )
                }
            } else {
                // Basic/Enhanced: Vision OCR is the best available for scanned content
                return await runQualitySelectedPDFConversion(
                    fileURL: tempURL, title: title, password: job.password,
                    workspaceURL: workspaceURL, classifierEvidence: classification.pdfEvidence,
                    secondary: .imageText, progress: progress
                )
            }
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
        guard let format = ConversionFormat(fileExtension: fileURL.pathExtension) else {
            return await runMediaMetadataFallback(fileURL: fileURL, title: title, previous: speech)
        }
        if supportsAdvancedRuntime, ToolFormatCapabilityMatrix.supports(.markItDown, format) {
            AppLog.conversion.info("Audio native transcription unavailable; trying advanced fallback ext=\(fileURL.pathExtension, privacy: .public)")
            let advanced = await runPythonConversion(
                fileURL: fileURL,
                title: title,
                useAI: useAI,
                password: password,
                workspaceURL: workspaceURL,
                progress: progress
            )
            if advanced.output != nil {
                return advanced
            }
        }
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

    private func runVisionExtraction(fileURL: URL, title: String, password: String?, workspaceURL: URL) async -> ConversionResult {
        let signpost = AppSignpost.conversion.beginInterval("nativeExtract")
        defer { AppSignpost.conversion.endInterval("nativeExtract", signpost) }

        do {
            let result = try await VisionDocumentExtractor.extract(pdfURL: fileURL, password: password)
            return .success(ConversionOutput(
                markdown: result.markdown,
                pages: result.pageCount,
                format: "PDF",
                title: title,
                pipeline: .fast,
                selectedPathway: .visionOCR
            ))
        } catch VisionDocumentExtractor.ExtractionError.passwordRequired {
            return .failure(ConversionError.passwordRequired.errorDescription ?? "This PDF is password-protected.")
        } catch {
            return await runPDFKitConversion(fileURL: fileURL, title: title, password: password, workspaceURL: workspaceURL)
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
                selectedPathway: .pdfKit
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
            guard supportsAdvancedRuntime else {
                return .failure(ConversionError.unsupportedOnThisMac.errorDescription ?? "This conversion is not supported on this Mac.")
            }
            return await runPythonConversion(
                fileURL: fileURL,
                title: title,
                useAI: false,
                password: password,
                workspaceURL: workspaceURL,
                progress: nil
            )
        }
    }

    enum PDFSecondaryCandidate {
        case imageText
        case advanced(useAI: Bool)
        case all(useAI: Bool)
    }

    private func runQualitySelectedPDFConversion(
        fileURL: URL,
        title: String,
        password: String?,
        workspaceURL: URL,
        classifierEvidence: NativeDocumentClassifier.Evidence?,
        secondary: PDFSecondaryCandidate,
        progress: ProgressHandler?
    ) async -> ConversionResult {
        // Small Pro+AI PDFs can fan out across independent engines. Larger
        // documents use the serial budget below so one input cannot multiply
        // CPU, OCR, helper-process, and memory cost at the same time.
        if case .all(let useAI) = secondary,
           pdfCandidateBudget.allowsFullFanout(evidence: classifierEvidence) {
            async let basicResult = runPDFKitConversion(
                fileURL: fileURL, title: title, password: password, workspaceURL: workspaceURL
            )
            async let visionResult = runVisionExtraction(
                fileURL: fileURL, title: title, password: password, workspaceURL: workspaceURL
            )
            async let pythonResult = runPythonConversion(
                fileURL: fileURL, title: title, useAI: useAI,
                password: password, workspaceURL: workspaceURL, progress: progress
            )
            let (basic, vision, python) = await (basicResult, visionResult, pythonResult)
            let allResults: [(label: String, result: ConversionResult)] = [
                ("basic", basic), ("image-text", vision),
                (useAI ? "ai" : "advanced", python),
            ]
            return selectBest(from: allResults, evidence: classifierEvidence)
        }

        var outputs: [(label: String, output: ConversionOutput)] = []
        var firstFailure: ConversionResult?

        let basic = await runPDFKitConversion(fileURL: fileURL, title: title, password: password, workspaceURL: workspaceURL)
        if case .success(let output) = basic {
            outputs.append((label: "basic", output: output))
            guard pdfCandidateBudget.shouldRunSecondary(
                afterBasic: output,
                evidence: classifierEvidence,
                secondary: secondary
            ) else {
                AppLog.conversion.info("PDF candidate budget accepted basic output without secondary path pages=\(output.pages, privacy: .public)")
                return .success(output)
            }
        } else {
            firstFailure = basic
        }

        let secondaryCandidates: [(label: String, result: ConversionResult)]
        switch secondary {
        case .imageText:
            secondaryCandidates = [(
                label: "image-text",
                result: await runVisionExtraction(fileURL: fileURL, title: title, password: password, workspaceURL: workspaceURL)
            )]
        case .advanced(let useAI):
            secondaryCandidates = [(
                label: useAI ? "ai" : "advanced",
                result: await runPythonConversion(
                    fileURL: fileURL, title: title, useAI: useAI,
                    password: password, workspaceURL: workspaceURL, progress: progress
                )
            )]
        case .all(let useAI):
            secondaryCandidates = [(
                label: useAI ? "ai" : "advanced",
                result: await runPythonConversion(
                    fileURL: fileURL, title: title, useAI: useAI,
                    password: password, workspaceURL: workspaceURL, progress: progress
                )
            )]
        }

        for candidate in secondaryCandidates {
            if case .success(let output) = candidate.result {
                outputs.append((label: candidate.label, output: output))
            } else if firstFailure == nil {
                firstFailure = candidate.result
            }
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

    private func runPythonConversion(
        fileURL: URL,
        title: String,
        useAI: Bool,
        password: String?,
        workspaceURL: URL,
        progress: ProgressHandler?
    ) async -> ConversionResult {
        guard supportsAdvancedRuntime else {
            return .failure(ConversionError.unsupportedOnThisMac.errorDescription ?? "This conversion is not supported on this Mac.")
        }
        progress?(.python)
        let signpost = AppSignpost.conversion.beginInterval("pythonConvert")
        defer { AppSignpost.conversion.endInterval("pythonConvert", signpost) }
        return await pythonWorker.convert(
            fileURL: fileURL,
            title: title,
            useAI: useAI,
            password: password,
            workspaceURL: workspaceURL,
            heartbeat: {
                progress?(.python)
            },
            progress: { helperProgress in
                progress?(helperProgress)
            }
        )
    }
}
