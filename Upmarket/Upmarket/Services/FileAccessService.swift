import AppKit
import Foundation
import UniformTypeIdentifiers

/// AppKit file and pasteboard operations kept out of SwiftUI views.
final class FileAccessService {
    static let shared = FileAccessService()

    private init() {}

    func chooseDocuments(allowsMultipleSelection: Bool, positioningNear window: NSWindow? = nil) -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.canChooseDirectories = false
        panel.allowedContentTypes = Self.supportedInputTypes

        if let window {
            panel.setFrameOrigin(NSPoint(x: window.frame.maxX + 8, y: window.frame.minY))
            panel.orderFrontRegardless()
        }

        guard panel.runModal() == .OK else { return [] }
        return panel.urls
    }

    func saveMarkdown(_ markdown: String, title: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = (title.isEmpty ? "converted" : title) + ".md"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    func copyMarkdown(_ markdown: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    func copyFilePath(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static let supportedInputTypes: [UTType] = [
        .pdf, .html, .png, .jpeg, .gif, .tiff,
        UTType(filenameExtension: "docx") ?? .data,
        UTType(filenameExtension: "pptx") ?? .data,
        UTType(filenameExtension: "xlsx") ?? .data,
        UTType(filenameExtension: "epub") ?? .data,
        UTType(filenameExtension: "csv") ?? .data,
        UTType(filenameExtension: "json") ?? .data,
        UTType(filenameExtension: "xml") ?? .data,
        UTType(filenameExtension: "zip") ?? .data,
        UTType(filenameExtension: "mp3") ?? .data,
        UTType(filenameExtension: "m4a") ?? .data,
        UTType(filenameExtension: "wav") ?? .data,
        UTType(filenameExtension: "aiff") ?? .data,
        UTType(filenameExtension: "opus") ?? .data,
    ]
}
