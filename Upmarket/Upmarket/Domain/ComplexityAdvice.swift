import Foundation

struct ComplexityAdvice {
    enum Recommendation: String {
        case basic = "basic"
        case aiRecommended = "ai_recommended"
        case aiRequired = "ai_required"
    }

    private static let lowQualityLanguages: Set<String> = ["ja", "zh", "ko", "ar", "he", "hi", "th"]

    let recommendation: Recommendation
    let score: Int
    let reasons: [String]
    let detectedLanguage: String?

    var suggestAI: Bool {
        recommendation == .aiRecommended || recommendation == .aiRequired
    }

    var languageQualityWarning: String? {
        guard recommendation != .basic,
              let lang = detectedLanguage,
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
