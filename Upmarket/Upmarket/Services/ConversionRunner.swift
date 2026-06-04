import Foundation
import OSLog

struct ConversionRunner {
    typealias ProgressHandler = (ConversionProgress) -> Void

    let pythonWorker: PythonWorker
    private let supportsAdvancedRuntime: Bool

    nonisolated init(
        pythonWorker: PythonWorker = PythonWorker(),
        supportsAdvancedRuntime: Bool = DeviceCapability.currentSupportsAdvancedRuntime
    ) {
        self.pythonWorker = pythonWorker
        self.supportsAdvancedRuntime = supportsAdvancedRuntime
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
        if tempURL.pathExtension.lowercased() == "pdf",
           let classification = try? await NativeDocumentClassifier.classify(pdfURL: tempURL) {
            AppLog.conversion.info(
                "Document analysis bucket=\(classification.bucket.diagnosticLabel, privacy: .public) recommendation=\(classification.recommendedPathway.diagnosticLabel, privacy: .public) confidence=\(classification.confidence, privacy: .public)"
            )
            return classification.complexityAdvice
        }
        return nil
    }

    func run(_ job: ConversionJob, progress: ProgressHandler? = nil) async -> ConversionResult {
        AppLog.conversion.info("Starting conversion correlationID=\(job.correlationID, privacy: .public) ext=\(job.ext, privacy: .public)")
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
            AppLog.conversion.error("Conversion rejected oversized file correlationID=\(job.correlationID, privacy: .public)")
            return .failure(ConversionError.fileTooLarge.errorDescription ?? "This document is too large to convert safely.")
        } catch ConversionError.sourceUnavailable {
            AppLog.conversion.error("Conversion source unavailable correlationID=\(job.correlationID, privacy: .public)")
            return .failure(ConversionError.sourceUnavailable.errorDescription ?? "This document is not available on this Mac.")
        } catch {
            AppLog.conversion.error("Conversion input copy failed correlationID=\(job.correlationID, privacy: .public) error=\(error.localizedDescription, privacy: .private)")
            return .failure(ConversionError.inaccessible.errorDescription ?? "Upmarket couldn't access this file.")
        }
        defer { AppWorkspace.remove(workspace) }

        progress?(.extracting)
        let raw = await extract(job: job, tempURL: tempURL, workspaceURL: workspace, progress: progress)
        guard !Task.isCancelled else { return .failure(ConversionError.cancelled.errorDescription ?? "Conversion cancelled.") }
        guard case .success(let output) = raw else {
            AppLog.conversion.error("Conversion failed correlationID=\(job.correlationID, privacy: .public)")
            return raw
        }

        progress?(.postProcessing)
        let postProcessSignpost = AppSignpost.conversion.beginInterval("postProcess")
        let refined = await postProcess(output)
        AppSignpost.conversion.endInterval("postProcess", postProcessSignpost)
        progress?(.complete)
        AppLog.conversion.info("Conversion completed correlationID=\(job.correlationID, privacy: .public)")
        return .success(refined)
    }

    private func extract(
        job: ConversionJob,
        tempURL: URL,
        workspaceURL: URL,
        progress: ProgressHandler?
    ) async -> ConversionResult {
        let ext = job.sourceURL.pathExtension.lowercased()
        let title = job.sourceURL.deletingPathExtension().lastPathComponent

        let format = ConversionFormat(fileExtension: ext)

        switch ext {
        case "pdf":
            if job.useAI {
                let classification = try? await NativeDocumentClassifier.classify(pdfURL: tempURL, password: job.password)
                if let classification {
                    AppLog.conversion.info(
                        "Document classifier bucket=\(classification.bucket.diagnosticLabel, privacy: .public) recommendation=\(classification.recommendedPathway.diagnosticLabel, privacy: .public) confidence=\(classification.confidence, privacy: .public)"
                    )
                }
                return await runQualitySelectedPDFConversion(
                    fileURL: tempURL,
                    title: title,
                    password: job.password,
                    workspaceURL: workspaceURL,
                    classifierEvidence: classification?.evidence,
                    secondary: .all(useAI: true),
                    progress: progress
                )
            }
            if let classification = try? await NativeDocumentClassifier.classify(pdfURL: tempURL, password: job.password) {
                AppLog.conversion.info(
                    "Document classifier bucket=\(classification.bucket.diagnosticLabel, privacy: .public) recommendation=\(classification.recommendedPathway.diagnosticLabel, privacy: .public) confidence=\(classification.confidence, privacy: .public)"
                )
                switch classification.recommendedPathway {
                case .visionOCR:
                    return await runQualitySelectedPDFConversion(
                        fileURL: tempURL,
                        title: title,
                        password: job.password,
                        workspaceURL: workspaceURL,
                        classifierEvidence: classification.evidence,
                        secondary: .imageText,
                        progress: progress
                    )
                case .enhanced:
                    guard supportsAdvancedRuntime else {
                        return await runPDFKitConversion(fileURL: tempURL, title: title, password: job.password, workspaceURL: workspaceURL)
                    }
                    return await runQualitySelectedPDFConversion(
                        fileURL: tempURL,
                        title: title,
                        password: job.password,
                        workspaceURL: workspaceURL,
                        classifierEvidence: classification.evidence,
                        secondary: .advanced(useAI: false),
                        progress: progress
                    )
                case .pdfKit:
                    return await runPDFKitConversion(fileURL: tempURL, title: title, password: job.password, workspaceURL: workspaceURL)
                }
            }
            return await runPDFKitConversion(fileURL: tempURL, title: title, password: job.password, workspaceURL: workspaceURL)
        case _ where format.map({ ToolFormatCapabilityMatrix.supports(.speech, $0) }) == true:
            return await runAudioConversion(
                fileURL: tempURL,
                title: title,
                useAI: job.useAI,
                password: job.password,
                workspaceURL: workspaceURL,
                progress: progress
            )
        case _ where NativeMetadataExtractor.handlesImage(ext):
            return NativeMetadataExtractor.imageMetadata(url: tempURL, title: title)
        case _ where NativeMetadataExtractor.handlesMedia(ext):
            return await NativeMetadataExtractor.mediaMetadata(url: tempURL, title: title)
        default:
            guard supportsAdvancedRuntime else {
                return .failure(ConversionError.unsupportedOnThisMac.errorDescription ?? "This conversion is not supported on this Mac.")
            }
            return await runPythonConversion(
                fileURL: tempURL,
                title: title,
                useAI: job.useAI,
                password: job.password,
                workspaceURL: workspaceURL,
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

    private enum PDFSecondaryCandidate {
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
        var outputs: [(label: String, output: ConversionOutput)] = []
        var firstFailure: ConversionResult?

        let basic = await runPDFKitConversion(fileURL: fileURL, title: title, password: password, workspaceURL: workspaceURL)
        if case .success(let output) = basic {
            outputs.append((label: "basic", output: output))
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
                    fileURL: fileURL,
                    title: title,
                    useAI: useAI,
                    password: password,
                    workspaceURL: workspaceURL,
                    progress: progress
                )
            )]
        case .all(let useAI):
            secondaryCandidates = [
                (
                    label: "image-text",
                    result: await runVisionExtraction(fileURL: fileURL, title: title, password: password, workspaceURL: workspaceURL)
                ),
                (
                    label: useAI ? "ai" : "advanced",
                    result: await runPythonConversion(
                        fileURL: fileURL,
                        title: title,
                        useAI: useAI,
                        password: password,
                        workspaceURL: workspaceURL,
                        progress: progress
                    )
                )
            ]
        }

        for candidate in secondaryCandidates {
            if case .success(let output) = candidate.result {
                outputs.append((label: candidate.label, output: output))
            } else if firstFailure == nil {
                firstFailure = candidate.result
            }
        }

        let imageTextReference = outputs.first { $0.label == "image-text" }?.output.markdown
        let candidates = outputs.map {
            scoredCandidate(
                label: $0.label,
                output: $0.output,
                evidence: classifierEvidence,
                imageTextReference: imageTextReference
            )
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

    private func postProcess(_ output: ConversionOutput) async -> ConversionOutput {
        let intelligence = DocumentIntelligence.extractMetadata(from: output.markdown)
        let nlInput = TextStructurer.Input(
            rawMarkdown: output.markdown,
            detectedLanguage: intelligence.language
        )
        let nlResult = TextStructurer.refine(nlInput)

        let wtResult = await WritingToolsRefinerAdapter.refine(
            markdown: nlResult.markdown,
            language: nlResult.detectedLanguage
        )
        let fmResult = await FoundationModelEnhancer.enhance(
            markdown: wtResult.markdown,
            documentType: intelligence.documentType.rawValue
        )

        let title = fmResult.extractedTitle ?? intelligence.title ?? output.title
        return ConversionOutput(
            markdown: fmResult.refinedMarkdown,
            pages: output.pages,
            format: output.format,
            title: title,
            pipeline: output.pipeline,
            selectedPathway: output.selectedPathway
        )
    }
}
