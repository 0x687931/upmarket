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

    @Parameter(
        title: "Document",
        description: "The file to convert",
        supportedTypeIdentifiers: [
            "com.adobe.pdf",
            "public.html",
            "public.plain-text",
            "public.png",
            "public.jpeg",
            "com.compuserve.gif",
            "public.tiff",
            "org.openxmlformats.wordprocessingml.document",
            "org.openxmlformats.presentationml.presentation",
            "org.openxmlformats.spreadsheetml.sheet",
            "org.idpf.epub-container",
            "public.comma-separated-values-text",
            "public.json",
            "public.xml",
            "public.zip-archive",
            "public.mp3",
            "com.apple.m4a-audio",
            "com.microsoft.waveform-audio",
            "public.aiff-audio",
            "org.xiph.ogg-audio",
        ]
    )
    var document: IntentFile

    @Parameter(title: "Use AI", description: "Use Upmarket AI for complex or scanned documents", default: false)
    var useAI: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Convert \(\.$document) to Markdown") {
            \.$useAI
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

        return .result(value: output.markdown)
    }
}

// MARK: - Convert Document and Save

struct ConvertAndSaveIntent: AppIntent {

    static var title: LocalizedStringResource = "Convert Document and Save Markdown"
    static var description = IntentDescription(
        "Converts a document to Markdown and returns a .md file to the shortcut.",
        categoryName: "Documents"
    )
    static var openAppWhenRun = false

    @Parameter(title: "Document", supportedTypeIdentifiers: [
        "com.adobe.pdf",
        "public.html",
        "public.plain-text",
        "public.png",
        "public.jpeg",
        "com.compuserve.gif",
        "public.tiff",
        "org.openxmlformats.wordprocessingml.document",
        "org.openxmlformats.presentationml.presentation",
        "org.openxmlformats.spreadsheetml.sheet",
        "org.idpf.epub-container",
        "public.comma-separated-values-text",
        "public.json",
        "public.xml",
        "public.zip-archive",
        "public.mp3",
        "com.apple.m4a-audio",
        "com.microsoft.waveform-audio",
        "public.aiff-audio",
        "org.xiph.ogg-audio",
    ])
    var document: IntentFile

    @Parameter(title: "Use AI", default: false)
    var useAI: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Convert \(\.$document) and save Markdown") {
            \.$useAI
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
        let filename = "\(baseName.isEmpty ? "converted" : baseName).md"
        let savedFile = IntentFile(data: Data(output.markdown.utf8), filename: filename, type: .plainText)
        return .result(value: savedFile)
    }
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
    let store = StoreManager.shared
    let authorizer = ProgrammaticConversionAuthorizer(
        refreshEntitlements: {
            await store.refreshEntitlementForProgrammaticConversion()
        },
        aiUnavailableReason: { useAI in
            guard useAI else { return nil }
            return await ModelManager.shared.aiUseUnavailableReasonAfterChecking(hasPro: store.hasProOrAbove)
        },
        consumeConversion: {
            store.consumeConversion()
        }
    )
    try await authorizer.authorize(useAI: useAI)
}

@MainActor
struct ProgrammaticConversionAuthorizer {
    typealias RefreshEntitlements = () async -> Void
    typealias AIUnavailableReason = (_ useAI: Bool) async -> String?
    typealias ConsumeConversion = () -> Bool

    let refreshEntitlements: RefreshEntitlements
    let aiUnavailableReason: AIUnavailableReason
    let consumeConversion: ConsumeConversion

    func authorize(useAI: Bool) async throws {
        await refreshEntitlements()

        if await aiUnavailableReason(useAI) != nil {
            throw UpmarketIntentError.aiUnavailable
        }

        guard consumeConversion() else {
            throw UpmarketIntentError.purchaseRequired
        }
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
