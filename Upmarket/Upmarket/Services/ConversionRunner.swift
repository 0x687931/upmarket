import Foundation

struct ConversionRunner {
    typealias ProgressHandler = (ConversionStage) -> Void

    let pythonWorker: PythonWorker

    nonisolated init(pythonWorker: PythonWorker = PythonWorker()) {
        self.pythonWorker = pythonWorker
    }

    func analyse(fileURL: URL) async -> ComplexityAdvice? {
        guard let tempURL = try? copyToTemp(fileURL: fileURL) else { return nil }
        defer { try? FileManager.default.removeItem(at: tempURL) }
        return try? await pythonWorker.analyse(fileURL: tempURL)
    }

    func run(_ job: ConversionJob, progress: ProgressHandler? = nil) async -> ConversionResult {
        guard !Task.isCancelled else { return .failure(ConversionError.cancelled.errorDescription ?? "Conversion cancelled.") }

        progress?(.copying)
        let tempURL: URL
        do {
            tempURL = try copyToTemp(fileURL: job.sourceURL)
        } catch {
            return .failure(ConversionError.inaccessible.errorDescription ?? "Upmarket couldn't access this file.")
        }
        defer { try? FileManager.default.removeItem(at: tempURL) }

        progress?(.extracting)
        let raw = await extract(job: job, tempURL: tempURL)
        guard !Task.isCancelled else { return .failure(ConversionError.cancelled.errorDescription ?? "Conversion cancelled.") }
        guard case .success(let output) = raw else { return raw }

        progress?(.postProcessing)
        let refined = await postProcess(output)
        progress?(.complete)
        return .success(refined)
    }

    private func copyToTemp(fileURL: URL) throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileURL.pathExtension)
        try FileManager.default.copyItem(at: fileURL, to: tempURL)
        return tempURL
    }

    private func extract(job: ConversionJob, tempURL: URL) async -> ConversionResult {
        let ext = job.sourceURL.pathExtension.lowercased()
        let title = job.sourceURL.deletingPathExtension().lastPathComponent

        switch ext {
        case "pdf":
            if job.useAI {
                return await pythonWorker.convert(fileURL: tempURL, title: title, useAI: true, password: job.password)
            }
            if VisionDocumentExtractor.isAvailable {
                return await runVisionExtraction(fileURL: tempURL, title: title, password: job.password)
            }
            return await runPDFKitConversion(fileURL: tempURL, title: title, password: job.password)
        case "mp3", "m4a", "wav", "aiff", "opus":
            return await runSpeechTranscription(fileURL: tempURL, title: title)
        default:
            return await pythonWorker.convert(fileURL: tempURL, title: title, useAI: job.useAI, password: job.password)
        }
    }

    private func runVisionExtraction(fileURL: URL, title: String, password: String?) async -> ConversionResult {
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
            return await runPDFKitConversion(fileURL: fileURL, title: title, password: password)
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

    private func runPDFKitConversion(fileURL: URL, title: String, password: String?) async -> ConversionResult {
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
            return await pythonWorker.convert(fileURL: fileURL, title: title, useAI: false, password: password)
        }
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
