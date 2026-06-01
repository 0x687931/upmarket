import Foundation
import OSLog

struct ConversionRunner {
    typealias ProgressHandler = (ConversionStage) -> Void

    let pythonWorker: PythonWorker

    nonisolated init(pythonWorker: PythonWorker = PythonWorker()) {
        self.pythonWorker = pythonWorker
    }

    func analyse(fileURL: URL) async -> ComplexityAdvice? {
        guard let workspace = try? AppWorkspace.create(prefix: "analyse"),
              let tempURL = try? AppWorkspace.copy(fileURL, into: workspace) else { return nil }
        defer { AppWorkspace.remove(workspace) }
        return try? await pythonWorker.analyse(fileURL: tempURL, workspaceURL: workspace)
    }

    func run(_ job: ConversionJob, progress: ProgressHandler? = nil) async -> ConversionResult {
        AppLog.conversion.info("Starting conversion correlationID=\(job.correlationID, privacy: .public) ext=\(job.ext, privacy: .public)")
        guard !Task.isCancelled else { return .failure(ConversionError.cancelled.errorDescription ?? "Conversion cancelled.") }

        progress?(.copying)
        let workspace: URL
        let tempURL: URL
        do {
            workspace = try AppWorkspace.create(prefix: "conversion")
            tempURL = try AppWorkspace.copy(job.sourceURL, into: workspace)
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
        let raw = await extract(job: job, tempURL: tempURL, workspaceURL: workspace)
        guard !Task.isCancelled else { return .failure(ConversionError.cancelled.errorDescription ?? "Conversion cancelled.") }
        guard case .success(let output) = raw else {
            AppLog.conversion.error("Conversion failed correlationID=\(job.correlationID, privacy: .public)")
            return raw
        }

        progress?(.postProcessing)
        let refined = await postProcess(output)
        progress?(.complete)
        AppLog.conversion.info("Conversion completed correlationID=\(job.correlationID, privacy: .public)")
        return .success(refined)
    }

    private func extract(job: ConversionJob, tempURL: URL, workspaceURL: URL) async -> ConversionResult {
        let ext = job.sourceURL.pathExtension.lowercased()
        let title = job.sourceURL.deletingPathExtension().lastPathComponent

        switch ext {
        case "pdf":
            if job.useAI {
                return await pythonWorker.convert(fileURL: tempURL, title: title, useAI: true, password: job.password, workspaceURL: workspaceURL)
            }
            if let classification = try? await NativeDocumentClassifier.classify(pdfURL: tempURL, password: job.password) {
                AppLog.conversion.info(
                    "Document classifier recommendation=\(classification.recommendedPathway.diagnosticLabel, privacy: .public) confidence=\(classification.confidence, privacy: .public)"
                )
                switch classification.recommendedPathway {
                case .visionOCR:
                    return await runVisionExtraction(fileURL: tempURL, title: title, password: job.password, workspaceURL: workspaceURL)
                case .enhanced:
                    return await runEnhancedPDFConversion(fileURL: tempURL, title: title, password: job.password, workspaceURL: workspaceURL)
                case .pdfKit:
                    return await runPDFKitConversion(fileURL: tempURL, title: title, password: job.password, workspaceURL: workspaceURL)
                }
            }
            return await runPDFKitConversion(fileURL: tempURL, title: title, password: job.password, workspaceURL: workspaceURL)
        case "mp3", "m4a", "wav", "aiff", "opus":
            return await runSpeechTranscription(fileURL: tempURL, title: title)
        case _ where NativeMetadataExtractor.handlesImage(ext):
            return NativeMetadataExtractor.imageMetadata(url: tempURL, title: title)
        case _ where NativeMetadataExtractor.handlesMedia(ext):
            return await NativeMetadataExtractor.mediaMetadata(url: tempURL, title: title)
        default:
            return await pythonWorker.convert(fileURL: tempURL, title: title, useAI: job.useAI, password: job.password, workspaceURL: workspaceURL)
        }
    }

    private func runVisionExtraction(fileURL: URL, title: String, password: String?, workspaceURL: URL) async -> ConversionResult {
        do {
            let result = try await VisionDocumentExtractor.extract(pdfURL: fileURL, password: password)
            return .success(ConversionOutput(
                markdown: result.markdown,
                pages: result.pageCount,
                format: "PDF",
                title: title,
                pipeline: .fast
            ))
        } catch VisionDocumentExtractor.ExtractionError.passwordRequired {
            return .failure(ConversionError.passwordRequired.errorDescription ?? "This PDF is password-protected.")
        } catch {
            return await runPDFKitConversion(fileURL: fileURL, title: title, password: password, workspaceURL: workspaceURL)
        }
    }

    private func runSpeechTranscription(fileURL: URL, title: String) async -> ConversionResult {
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
                pipeline: .fast
            ))
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func runPDFKitConversion(fileURL: URL, title: String, password: String?, workspaceURL: URL) async -> ConversionResult {
        do {
            let result = try PDFConverter.convert(url: fileURL, password: password)
            return .success(ConversionOutput(
                markdown: result.markdown,
                pages: result.pageCount,
                format: "PDF",
                title: title,
                pipeline: .fast
            ))
        } catch PDFConverter.ConversionError.passwordRequired {
            return .failure(ConversionError.passwordRequired.errorDescription ?? "This PDF is password-protected.")
        } catch {
            return await pythonWorker.convert(fileURL: fileURL, title: title, useAI: false, password: password, workspaceURL: workspaceURL)
        }
    }

    private func runEnhancedPDFConversion(fileURL: URL, title: String, password: String?, workspaceURL: URL) async -> ConversionResult {
        let result = await pythonWorker.convert(fileURL: fileURL, title: title, useAI: false, password: password, workspaceURL: workspaceURL)
        if case .success = result {
            return result
        }
        AppLog.conversion.error("Advanced document extraction failed; using basic extraction")
        return await runPDFKitConversion(fileURL: fileURL, title: title, password: password, workspaceURL: workspaceURL)
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
            pipeline: output.pipeline
        )
    }
}
