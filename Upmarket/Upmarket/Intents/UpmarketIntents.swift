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

    static var title: LocalizedStringResource = "Convert Document to Markdown"
    static var description = IntentDescription(
        "Converts a document to clean Markdown text using Upmarket's on-device AI.",
        categoryName: "Documents"
    )
    static var openAppWhenRun = false  // runs silently in background

    @Parameter(title: "Document", description: "The file to convert", supportedTypeIdentifiers: [
        "public.pdf", "org.openxmlformats.wordprocessingml.document",
        "org.openxmlformats.presentationml.presentation",
        "org.openxmlformats.spreadsheetml.sheet",
        "public.html", "public.plain-text"
    ])
    var document: IntentFile

    @Parameter(title: "Use AI", description: "Use Upmarket AI for complex or scanned documents", default: false)
    var useAI: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Convert \(\.$document) to Markdown") {
            \.$useAI
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // Write to temp file for conversion
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(document.filename.components(separatedBy: ".").last ?? "pdf")

        try document.data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        await ConversionService.shared.convert(fileURL: tempURL, useAI: useAI)

        while await ConversionService.shared.isConverting {
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        guard case .success(let output) = await ConversionService.shared.result else {
            throw UpmarketIntentError.conversionFailed
        }

        return .result(value: output.markdown)
    }
}

// MARK: - Convert Document and Save

struct ConvertAndSaveIntent: AppIntent {

    static var title: LocalizedStringResource = "Convert Document and Save Markdown"
    static var description = IntentDescription(
        "Converts a document to Markdown and saves the .md file next to the original.",
        categoryName: "Documents"
    )
    static var openAppWhenRun = false

    @Parameter(title: "Document", supportedTypeIdentifiers: [
        "public.pdf", "org.openxmlformats.wordprocessingml.document",
        "org.openxmlformats.presentationml.presentation",
        "public.html"
    ])
    var document: IntentFile

    @Parameter(title: "Use AI", default: false)
    var useAI: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Convert \(\.$document) and save Markdown") {
            \.$useAI
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(document.filename.components(separatedBy: ".").last ?? "pdf")

        try document.data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        await ConversionService.shared.convert(fileURL: tempURL, useAI: useAI)
        while await ConversionService.shared.isConverting {
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        guard case .success(let output) = await ConversionService.shared.result else {
            throw UpmarketIntentError.conversionFailed
        }

        // Save the markdown
        let baseName = document.filename.components(separatedBy: ".").dropLast().joined(separator: ".")
        let saveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(baseName.isEmpty ? "converted" : baseName)
            .appendingPathExtension("md")

        try output.markdown.write(to: saveURL, atomically: true, encoding: .utf8)

        let savedFile = IntentFile(fileURL: saveURL, filename: saveURL.lastPathComponent)
        return .result(value: savedFile)
    }
}

// MARK: - Errors

enum UpmarketIntentError: Error, LocalizedError {
    case noData
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .noData:            return "Upmarket couldn't read the file."
        case .conversionFailed:  return "Upmarket couldn't convert this document."
        }
    }
}
