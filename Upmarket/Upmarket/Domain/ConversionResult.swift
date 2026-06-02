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

    var diagnosticCode: String? {
        guard case .failure(let message) = self else { return nil }
        let knownErrors: [ConversionError] = [
            .inaccessible,
            .passwordRequired,
            .cancelled,
            .noProgress,
            .memoryPressure,
            .fileTooLarge,
            .sourceUnavailable,
            .pythonRuntime("")
        ]
        return knownErrors.first { $0.errorDescription == message }?.diagnosticCode
            ?? ConversionError.failed(message).diagnosticCode
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
