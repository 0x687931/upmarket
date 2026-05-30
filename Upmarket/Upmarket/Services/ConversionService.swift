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
        let converter = Python.import("docling_bridge.converter")

        var opts: [String: PythonObject] = [
            "use_vlm": PythonObject(useAI),
            "ocr": PythonObject(true)
        ]
        if let password {
            opts["password"] = PythonObject(password)
        }
        let pyOptions = PythonObject(opts)
        let pyResult = converter.convert(fileURL.path, pyOptions)

        let success      = Bool(pyResult["success"]) ?? false
        let needsPassword = Bool(pyResult["needs_password"]) ?? false

        if needsPassword {
            await MainActor.run { self.needsPassword = true }
            return .failure("This PDF is password-protected.")
        }

        if success {
            let markdown = String(pyResult["markdown"]) ?? ""
            let meta     = pyResult["metadata"]
            let pages    = Int(meta["pages"]) ?? 0
            let format   = String(meta["format"]) ?? ""
            let title    = String(meta["title"]) ?? originalURL.deletingPathExtension().lastPathComponent
            return .success(ConversionOutput(
                markdown: markdown,
                pages: pages,
                format: format,
                title: title,
                usedAI: useAI
            ))
        } else {
            let error = String(pyResult["error"]) ?? "Upmarket couldn't convert this document."
            return .failure(error)
        }
    }
}

// MARK: - Models

enum ConversionResult {
    case success(ConversionOutput)
    case failure(String)
}

struct ConversionOutput {
    let markdown: String
    let pages: Int
    let format: String
    let title: String
    let usedAI: Bool
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
