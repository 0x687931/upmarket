import AppKit
import Foundation
import OSLog
import UniformTypeIdentifiers

enum StorageLocationKind: String, Equatable {
    case local
    case iCloudDrive
    case fileProvider
    case externalVolume
    case networkVolume
}

enum FileAccessError: Error, Equatable, LocalizedError {
    case unavailable
    case unreadable
    case notAFile
    case unsupportedType
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "This document is not available on this Mac. Download it and try again."
        case .unreadable:
            return "Upmarket couldn't access this file. Please try again."
        case .notAFile:
            return "Choose a document file to convert."
        case .unsupportedType:
            return "Choose a supported document file to convert."
        case .tooLarge:
            return "This document is too large to convert safely."
        }
    }
}

enum SupportedInputPolicy {
    nonisolated static let typeIdentifiers: [String] = ToolFormatCapabilityMatrix.acceptedTypeIdentifiers

    nonisolated static let contentTypes: [UTType] = ToolFormatCapabilityMatrix.acceptedContentTypes

    nonisolated static func supports(_ url: URL) -> Bool {
        ToolFormatCapabilityMatrix.accepts(url)
    }
}

/// AppKit file and pasteboard operations kept out of SwiftUI views.
final class FileAccessService {
    nonisolated static let shared = FileAccessService()

    private init() {}

    func chooseDocuments(allowsMultipleSelection: Bool, positioningNear window: NSWindow? = nil) -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.canChooseDirectories = false
        panel.allowedContentTypes = SupportedInputPolicy.contentTypes

        if let window {
            panel.setFrameOrigin(NSPoint(x: window.frame.maxX + 8, y: window.frame.minY))
            panel.orderFrontRegardless()
        }

        guard panel.runModal() == .OK else { return [] }
        AppLog.fileAccess.info("Selected input batch count=\(panel.urls.count, privacy: .public)")
        return panel.urls
    }

    func chooseSaveDirectory(message: String, positioningNear window: NSWindow? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = message

        if let window {
            panel.setFrameOrigin(NSPoint(x: window.frame.maxX + 8, y: window.frame.minY))
            panel.orderFrontRegardless()
        } else {
            panel.orderFrontRegardless()
        }

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        AppLog.fileAccess.info("Selected save directory kind=\(Self.storageKind(for: url).rawValue, privacy: .public)")
        return url
    }

    func loadFileURLs(from providers: [NSItemProvider], receiveURL: @escaping @MainActor (URL) -> Void) {
        AppLog.fileAccess.info("Loading dropped input batch count=\(providers.count, privacy: .public)")
        loadFileURL(from: providers, at: 0, receiveURL: receiveURL)
    }

    private func loadFileURL(
        from providers: [NSItemProvider],
        at index: Int,
        receiveURL: @escaping @MainActor (URL) -> Void
    ) {
        guard providers.indices.contains(index) else { return }
        providers[index].loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            if let data = item as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil) {
                DispatchQueue.main.async {
                    receiveURL(url)
                    self.loadFileURL(from: providers, at: index + 1, receiveURL: receiveURL)
                }
            } else {
                DispatchQueue.main.async {
                    self.loadFileURL(from: providers, at: index + 1, receiveURL: receiveURL)
                }
            }
        }
    }

    func saveMarkdown(_ markdown: String, title: String) -> URL? {
        let signpost = AppSignpost.conversion.beginInterval("saveOutput")
        defer { AppSignpost.conversion.endInterval("saveOutput", signpost) }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = (title.isEmpty ? "converted" : title) + ".md"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        do {
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
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

    func copySupportReport(_ report: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }

    func copyFilePath(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    nonisolated static func userVisibleMessage(for error: Error) -> String {
        if let fileError = error as? FileAccessError,
           let message = fileError.errorDescription {
            return message
        }
        if let conversionError = error as? ConversionError,
           let message = conversionError.errorDescription {
            return message
        }
        if let message = (error as? LocalizedError)?.errorDescription,
           !message.isEmpty {
            return message
        }
        return FileAccessError.unreadable.errorDescription ?? "Upmarket couldn't access this file. Please try again."
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    nonisolated func validateReadableInput(_ url: URL, maxBytes: Int64 = AppWorkspace.maxInputBytes) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard (try? url.checkResourceIsReachable()) == true else {
            AppLog.fileAccess.error("Input unavailable before copy; kind=\(Self.storageKind(for: url).rawValue, privacy: .public)")
            throw FileAccessError.unavailable
        }

        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isReadableKey,
            .fileSizeKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ])

        guard values.isRegularFile != false else { throw FileAccessError.notAFile }
        guard values.isReadable != false else { throw FileAccessError.unreadable }
        guard SupportedInputPolicy.supports(url) else {
            throw FileAccessError.unsupportedType
        }
        if let fileSize = values.fileSize, Int64(fileSize) > maxBytes {
            AppLog.fileAccess.error("Rejected oversized input: bytes=\(fileSize, privacy: .public)")
            throw FileAccessError.tooLarge
        }

        if values.isUbiquitousItem == true,
           let status = values.ubiquitousItemDownloadingStatus,
           status != .current,
           status != .downloaded {
            AppLog.fileAccess.error("Cloud-backed input is not local; status=\(String(describing: status), privacy: .public)")
            throw FileAccessError.unavailable
        }
    }

    nonisolated static func storageKind(for url: URL) -> StorageLocationKind {
        let path = url.standardizedFileURL.path
        if path.contains("/Library/Mobile Documents/") || path.contains("/Mobile Documents/") {
            return .iCloudDrive
        }
        if path.contains("/Library/CloudStorage/") {
            return .fileProvider
        }
        if path.hasPrefix("/Volumes/") {
            return .externalVolume
        }
        if path.hasPrefix("/Network/") || path.hasPrefix("/net/") {
            return .networkVolume
        }
        return .local
    }
}
