import Foundation

enum ConversionResult: Equatable {
    case success(ConversionOutput)
    case failure(String)

    var output: ConversionOutput? {
        guard case .success(let output) = self else { return nil }
        return output
    }

    var errorMessage: String? {
        guard case .failure(let message) = self else { return nil }
        return message
    }
}

enum Pipeline: String {
    case fast = "fast"
    case enhanced = "enhanced"
    case ai = "ai"
    case none = "none"

    var displayName: String {
        switch self {
        case .fast: return ""
        case .enhanced: return "Enhanced"
        case .ai: return "AI"
        case .none: return ""
        }
    }
}

struct ConversionOutput: Equatable {
    let markdown: String
    let pages: Int
    let format: String
    let title: String
    let pipeline: Pipeline

    var usedAI: Bool { pipeline == .ai }
}
