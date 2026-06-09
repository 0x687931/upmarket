import Foundation

enum ConversionResult: Equatable, Sendable {
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
            .unsupportedOnThisMac,
            .modelUnavailable,
            .downloadFailed,
            .upgradeRequired,
            .pythonRuntime("")
        ]
        return knownErrors.first { $0.errorDescription == message }?.diagnosticCode
            ?? ConversionError.failed(message).diagnosticCode
    }
}

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

    var displayPipeline: Pipeline {
        switch self {
        case .ai:
            return .ai
        case .enhanced:
            return .enhanced
        case .pdfKit, .visionOCR, .speech, .metadata:
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

nonisolated enum OutputMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case markdown
    case markdownWithFrontmatter = "frontmatter"
    case json

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .markdown:
            return "Markdown"
        case .markdownWithFrontmatter:
            return "Markdown + Frontmatter"
        case .json:
            return "JSON"
        }
    }
}

nonisolated struct ConversionOutput: Equatable, Sendable {
    let markdown: String
    let pages: Int
    let format: String
    let title: String
    let pipeline: Pipeline
    let selectedPathway: ConversionPathway

    var usedAI: Bool { pipeline == .ai }
    var provenanceLabel: String { selectedPathway.displayPipeline.displayName }

    init(
        markdown: String,
        pages: Int,
        format: String,
        title: String,
        pipeline: Pipeline,
        selectedPathway: ConversionPathway? = nil
    ) {
        self.markdown = markdown
        self.pages = pages
        self.format = format
        self.title = title
        self.pipeline = pipeline
        self.selectedPathway = selectedPathway ?? ConversionPathway.defaultForPipeline(pipeline)
    }
}
