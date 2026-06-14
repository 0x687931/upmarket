import AppIntents
import Foundation
import UniformTypeIdentifiers

// MARK: - App Shortcut Provider

struct UpmarketShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ConvertDocumentIntent(),
            phrases: [
                "Convert to Markdown with \(.applicationName)",
                "Convert a document with \(.applicationName)",
            ],
            shortTitle: "Convert to Markdown",
            systemImageName: "doc.text"
        )
        AppShortcut(
            intent: ConvertAndSaveIntent(),
            phrases: [
                "Convert and save with \(.applicationName)",
                "Convert document to Markdown with \(.applicationName)",
            ],
            shortTitle: "Convert & Save Markdown",
            systemImageName: "square.and.arrow.down"
        )
    }
}

// MARK: - Convert Document → Markdown string

struct ConvertDocumentIntent: AppIntent {

    static var title: LocalizedStringResource = "Convert Document"
    static var description = IntentDescription(
        "Converts a document to clean Markdown, frontmatter, or JSON output.",
        categoryName: "Documents"
    )
    static var openAppWhenRun = false  // runs silently in background

    // Note: IntentFile `supportedContentTypes` requires macOS 15; the deployment target
    // is 13.3, so input types are enforced at perform time via validateReadableInput
    // (→ SupportedInputPolicy.supports), the single source of truth.
    @Parameter(
        title: "Document",
        description: "The file to convert"
    )
    var document: IntentFile

    @Parameter(title: "Use AI", description: "Use Upmarket AI for complex or scanned documents", default: false)
    var useAI: Bool

    @Parameter(title: "Output Format", default: .markdown)
    var outputMode: OutputMode

    static var parameterSummary: some ParameterSummary {
        Summary("Convert \(\.$document)") {
            \.$useAI
            \.$outputMode
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let input = try prepareShortcutInput(document)
        defer { input.cleanup() }
        try await authorizeShortcutConversion(useAI: useAI)

        let result = await ConversionQueue.shared.convert(input.url, useAI: useAI)
        guard case .success(let output) = result else {
            throw UpmarketIntentError.conversionFailed
        }

        let formatted = OutputFormatter.format(
            output,
            sourceDisplayName: document.filename,
            mode: outputMode
        )
        return .result(value: formatted.text)
    }
}

// MARK: - Convert Document and Save

struct ConvertAndSaveIntent: AppIntent {

    static var title: LocalizedStringResource = "Convert Document and Save Output"
    static var description = IntentDescription(
        "Converts a document and returns a file to the shortcut.",
        categoryName: "Documents"
    )
    static var openAppWhenRun = false

    @Parameter(title: "Document")
    var document: IntentFile

    @Parameter(title: "Use AI", default: false)
    var useAI: Bool

    @Parameter(title: "Output Format", default: .markdown)
    var outputMode: OutputMode

    static var parameterSummary: some ParameterSummary {
        Summary("Convert \(\.$document) and save output") {
            \.$useAI
            \.$outputMode
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let input = try prepareShortcutInput(document)
        defer { input.cleanup() }
        try await authorizeShortcutConversion(useAI: useAI)

        let result = await ConversionQueue.shared.convert(input.url, useAI: useAI)
        guard case .success(let output) = result else {
            throw UpmarketIntentError.conversionFailed
        }

        let baseName = document.filename.components(separatedBy: ".").dropLast().joined(separator: ".")
        let formatted = OutputFormatter.format(
            output,
            sourceDisplayName: document.filename,
            mode: outputMode
        )
        let filename = "\(baseName.isEmpty ? "converted" : baseName).\(formatted.fileExtension)"
        let fileType: UTType = formatted.fileExtension == "json" ? .json : .plainText
        let savedFile = IntentFile(data: Data(formatted.text.utf8), filename: filename, type: fileType)
        return .result(value: savedFile)
    }
}

nonisolated extension OutputMode: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Output Format"

    static var caseDisplayRepresentations: [OutputMode: DisplayRepresentation] = [
        .markdown: "Markdown",
        .markdownWithFrontmatter: "Markdown + Frontmatter",
        .json: "JSON",
    ]
}

private struct ShortcutInput {
    let url: URL
    let workspace: URL?

    func cleanup() {
        if let workspace {
            AppWorkspace.remove(workspace)
        }
    }
}

private func prepareShortcutInput(_ document: IntentFile) throws -> ShortcutInput {
    if let fileURL = document.fileURL {
        do {
            try FileAccessService.shared.validateReadableInput(fileURL)
        } catch {
            throw UpmarketIntentError.inputRejected
        }
        return ShortcutInput(url: fileURL, workspace: nil)
    }

    guard Int64(document.data.count) <= AppWorkspace.maxInputBytes else {
        throw UpmarketIntentError.inputRejected
    }

    let workspace = try AppWorkspace.create(prefix: "intent")
    let tempURL = workspace
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension(document.filename.components(separatedBy: ".").last ?? "pdf")
    try document.data.write(to: tempURL)
    return ShortcutInput(url: tempURL, workspace: workspace)
}

@MainActor
private func authorizeShortcutConversion(useAI: Bool) async throws {
    do {
        try await ProgrammaticConversionAuthorization.authorize(useAI: useAI)
    } catch ProgrammaticConversionAuthorizationError.aiUnavailable {
        throw UpmarketIntentError.aiUnavailable
    } catch ProgrammaticConversionAuthorizationError.purchaseRequired {
        throw UpmarketIntentError.purchaseRequired
    } catch {
        if useAI {
            throw UpmarketIntentError.aiUnavailable
        }
        throw UpmarketIntentError.purchaseRequired
    }
}

// MARK: - Errors

enum UpmarketIntentError: Error, Equatable, LocalizedError {
    case noData
    case inputRejected
    case purchaseRequired
    case aiUnavailable
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .noData:            return "Upmarket couldn't read the file."
        case .inputRejected:     return "This file can't be converted safely."
        case .purchaseRequired:  return "Open Upmarket to unlock more conversions."
        case .aiUnavailable:     return "Upmarket AI is not available for this shortcut."
        case .conversionFailed:  return "Upmarket couldn't convert this document."
        }
    }
}
