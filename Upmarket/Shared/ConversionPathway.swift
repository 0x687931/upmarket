import Foundation

// The conversion pipeline tier and the specific engine pathway. Shared so the app, CLI, and
// MCP all describe and route conversions identically (see ContentClassifier / the router).

enum Pipeline: String, Codable, Sendable {
    case fast = "fast"
    case enhanced = "enhanced"
    case ai = "ai"
    case none = "none"

    var displayName: String {
        switch self {
        case .fast: return "Fast"
        case .enhanced: return "Enhanced"
        case .ai: return "AI"
        case .none: return ""
        }
    }
}

enum ConversionPathway: String, Codable, Equatable, Sendable {
    case pdfKit = "pdfKit"
    case visionOCR = "visionOCR"
    case speech = "speech"
    case metadata = "metadata"
    case enhanced = "enhanced"
    case ai = "ai"
    case nativeHTML = "nativeHTML"
    case nativeOffice = "nativeOffice"
    case nativeText = "nativeText"
    case nativeEPUB = "nativeEPUB"

    var displayPipeline: Pipeline {
        switch self {
        case .ai:
            return .ai
        case .enhanced:
            return .enhanced
        case .pdfKit, .visionOCR, .speech, .metadata, .nativeHTML, .nativeOffice, .nativeText, .nativeEPUB:
            return .fast
        }
    }

    static func defaultForPipeline(_ pipeline: Pipeline) -> ConversionPathway {
        switch pipeline {
        case .ai:
            return .ai
        case .enhanced:
            return .enhanced
        case .fast, .none:
            return .pdfKit
        }
    }
}
