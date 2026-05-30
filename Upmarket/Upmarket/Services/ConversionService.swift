import Foundation
import Combine
import PythonKit

final class ConversionService: ObservableObject {

    static let shared = ConversionService()

    let objectWillChange = PassthroughSubject<Void, Never>()

    private(set) var isConverting = false {
        willSet { objectWillChange.send() }
    }

    private(set) var isAnalysing = false {
        willSet { objectWillChange.send() }
    }

    private(set) var result: ConversionResult? {
        willSet { objectWillChange.send() }
    }

    private(set) var complexityAdvice: ComplexityAdvice? {
        willSet { objectWillChange.send() }
    }

    private(set) var needsPassword = false {
        willSet { objectWillChange.send() }
    }

    private init() {}

    func reset() {
        result = nil
        complexityAdvice = nil
        needsPassword = false
    }

    // MARK: - Analyse

    /// Fast pre-scan to detect whether Upmarket AI would give better results.
    /// Calls completion on main thread with advice (or nil on failure).
    func analyse(fileURL: URL, completion: @escaping (ComplexityAdvice?) -> Void) {
        guard let tempURL = try? copyToTemp(fileURL: fileURL) else {
            completion(nil)
            return
        }

        isAnalysing = true

        Task.detached(priority: .userInitiated) {
            let analyser = Python.import("docling_bridge.analyser")
            let pyResult = analyser.analyse(tempURL.path)
            try? FileManager.default.removeItem(at: tempURL)

            let success = Bool(pyResult["success"]) ?? false
            guard success else {
                await MainActor.run {
                    self.isAnalysing = false
                    completion(nil)
                }
                return
            }

            let recommendation = String(pyResult["recommendation"]) ?? "basic"
            let score = Int(pyResult["score"]) ?? 0
            var reasons: [String] = []
            for item in pyResult["reasons"] {
                if let s = String(item) { reasons.append(s) }
            }

            let detectedLanguage = String(pyResult["signals"]["detected_language"]) ?? nil

            let advice = ComplexityAdvice(
                recommendation: ComplexityAdvice.Recommendation(rawValue: recommendation) ?? .basic,
                score: score,
                reasons: reasons,
                detectedLanguage: detectedLanguage == "None" ? nil : detectedLanguage
            )

            await MainActor.run {
                self.isAnalysing = false
                self.complexityAdvice = advice
                completion(advice)
            }
        }
    }

    // MARK: - Convert

    func convert(fileURL: URL, useAI: Bool = false, password: String? = nil) {
        guard !isConverting else { return }
        isConverting = true
        result = nil

        let tempURL: URL
        do {
            tempURL = try copyToTemp(fileURL: fileURL)
        } catch {
            result = .failure("Upmarket couldn't access this file. Please try again.")
            isConverting = false
            return
        }

        Task.detached(priority: .userInitiated) {
            let output = await self.runConversion(fileURL: tempURL, originalURL: fileURL, useAI: useAI, password: password)
            try? FileManager.default.removeItem(at: tempURL)
            await MainActor.run {
                self.result = output
                self.isConverting = false
            }
        }
    }

    // MARK: - Private

    private func copyToTemp(fileURL: URL) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileURL.pathExtension)
        try FileManager.default.copyItem(at: fileURL, to: tmp)
        return tmp
    }

    private func runConversion(fileURL: URL, originalURL: URL, useAI: Bool, password: String?) async -> ConversionResult {
        let ext = originalURL.pathExtension.lowercased()
        let title = originalURL.deletingPathExtension().lastPathComponent

        // Step 1: Extract raw content
        let raw: ConversionResult
        if ext == "pdf" && !useAI {
            raw = runPDFKitConversion(fileURL: fileURL, title: title, password: password)
        } else {
            raw = await runPythonConversion(fileURL: fileURL, title: title, ext: ext, useAI: useAI, password: password)
        }

        // Step 2: Post-process successful conversions through NL + Writing Tools
        guard case .success(let output) = raw else { return raw }
        let refined = await postProcess(output)
        return .success(refined)
    }

    /// Two-stage post-processing:
    /// 1. NaturalLanguage — sentence boundaries, paragraph reconstruction, language detection
    /// 2. WritingToolsRefiner — Apple Intelligence cleanup (macOS 15.1+ / Apple Silicon only)
    private func postProcess(_ output: ConversionOutput) async -> ConversionOutput {
        // Stage 1: NaturalLanguage structuring
        let nlInput = TextStructurer.Input(
            rawMarkdown: output.markdown,
            detectedLanguage: nil
        )
        let nlResult = TextStructurer.refine(nlInput)

        // Stage 2: Writing Tools (graceful no-op on unsupported platforms)
        let wtResult = await WritingToolsRefinerAdapter.refine(
            markdown: nlResult.markdown,
            language: nlResult.detectedLanguage
        )

        return ConversionOutput(
            markdown: wtResult.markdown,
            pages: output.pages,
            format: output.format,
            title: output.title,
            pipeline: output.pipeline
        )
    }

    private func runPDFKitConversion(fileURL: URL, title: String, password: String?) -> ConversionResult {
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
            Task { await MainActor.run { self.needsPassword = true } }
            return .failure("This PDF is password-protected.")
        } catch {
            return runPythonConversionSync(fileURL: fileURL, title: title, ext: "pdf", useAI: false, password: password)
        }
    }

    private func runPythonConversionSync(fileURL: URL, title: String, ext: String, useAI: Bool, password: String?) -> ConversionResult {
        let converter = Python.import("docling_bridge.converter")
        var opts: [String: PythonObject] = [
            "use_ai": PythonObject(useAI),
            "use_enhanced": PythonObject(true),
            "ocr": PythonObject(true)
        ]
        if let password { opts["password"] = PythonObject(password) }
        let pyResult = converter.convert(fileURL.path, PythonObject(opts))
        return parsePythonResult(pyResult, title: title)
    }

    private func runPythonConversion(fileURL: URL, title: String, ext: String, useAI: Bool, password: String?) async -> ConversionResult {
        let converter = Python.import("docling_bridge.converter")
        var opts: [String: PythonObject] = [
            "use_ai": PythonObject(useAI),
            "use_enhanced": PythonObject(true),
            "ocr": PythonObject(true)
        ]
        if let password { opts["password"] = PythonObject(password) }
        let pyResult = converter.convert(fileURL.path, PythonObject(opts))

        let needsPwd = Bool(pyResult["needs_password"]) ?? false
        if needsPwd {
            await MainActor.run { self.needsPassword = true }
            return .failure("This PDF is password-protected.")
        }

        return parsePythonResult(pyResult, title: title)
    }

    private func parsePythonResult(_ pyResult: PythonObject, title: String) -> ConversionResult {
        let success = Bool(pyResult["success"]) ?? false
        if success {
            let markdown    = String(pyResult["markdown"]) ?? ""
            let meta        = pyResult["metadata"]
            let pages       = Int(meta["pages"]) ?? 0
            let format      = String(meta["format"]) ?? ""
            let pipelineStr = String(pyResult["pipeline"]) ?? "fast"
            let pipeline    = Pipeline(rawValue: pipelineStr) ?? .fast
            return .success(ConversionOutput(
                markdown: markdown, pages: pages,
                format: format, title: title, pipeline: pipeline
            ))
        } else {
            return .failure(String(pyResult["error"]) ?? "Upmarket couldn't convert this document.")
        }
    }
}

// MARK: - Models

enum ConversionResult {
    case success(ConversionOutput)
    case failure(String)
}

enum Pipeline: String {
    case fast     = "fast"      // PyMuPDF4LLM — zero download
    case enhanced = "enhanced"  // Layout models — 172MB
    case ai       = "ai"        // Upmarket AI — 500MB Pro
    case none     = "none"

    var displayName: String {
        switch self {
        case .fast:     return ""
        case .enhanced: return "Enhanced"
        case .ai:       return "AI"
        case .none:     return ""
        }
    }
}

struct ConversionOutput {
    let markdown: String
    let pages: Int
    let format: String
    let title: String
    let pipeline: Pipeline
    var usedAI: Bool { pipeline == .ai }
}

struct ComplexityAdvice {
    enum Recommendation: String {
        case basic = "basic"
        case aiRecommended = "ai_recommended"
        case aiRequired = "ai_required"
    }

    // Languages where Docling quality may be reduced
    private static let lowQualityLanguages: Set<String> = ["ja", "zh", "ko", "ar", "he", "hi", "th"]

    let recommendation: Recommendation
    let score: Int
    let reasons: [String]
    let detectedLanguage: String?

    var suggestAI: Bool {
        recommendation == .aiRecommended || recommendation == .aiRequired
    }

    /// Warning shown for languages with known quality limitations
    var languageQualityWarning: String? {
        guard let lang = detectedLanguage,
              Self.lowQualityLanguages.contains(lang) else { return nil }
        let name = Locale.current.localizedString(forLanguageCode: lang) ?? lang.uppercased()
        return "This looks like a \(name) document. We're working on improving quality for \(name) — results may vary."
    }

    var userMessage: String {
        switch recommendation {
        case .basic: return ""
        case .aiRecommended: return "Upmarket AI may give better results for this document."
        case .aiRequired: return "This document looks complex. Upmarket AI is recommended."
        }
    }
}
