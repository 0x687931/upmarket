import Foundation
import AppKit

/// Async file write service — prevents main thread blocking on disk I/O.
/// Handles both local and security-scoped URLs (iCloud, sandboxed locations).
actor FileWriteService {
    nonisolated static let shared = FileWriteService()

    func writeMarkdown(_ content: String, to url: URL) async throws {
        try write(Data(content.utf8), to: url)
    }

    func write(_ data: Data, to url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        try data.write(to: url, options: .atomic)
    }

    func writeMarkdown(
        _ content: String,
        toUniqueFileIn folder: URL,
        preferredFileName: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                folder.stopAccessingSecurityScopedResource()
            }
        }

        let outputURL = uniqueURL(
            in: folder,
            preferredFileName: preferredFileName,
            fileManager: fileManager
        )
        try Data(content.utf8).write(to: outputURL, options: .atomic)
        return outputURL
    }

    func copyMarkdown(_ content: String) async {
        await MainActor.run {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(content, forType: .string)
        }
    }

    private func uniqueURL(
        in folder: URL,
        preferredFileName: String,
        fileManager: FileManager
    ) -> URL {
        let candidate = folder.appendingPathComponent(preferredFileName)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let baseName = (preferredFileName as NSString).deletingPathExtension
        let pathExtension = (preferredFileName as NSString).pathExtension
        for index in 2...999 {
            let suffix = pathExtension.isEmpty ? "" : ".\(pathExtension)"
            let numberedURL = folder.appendingPathComponent("\(baseName) \(index)\(suffix)")
            if !fileManager.fileExists(atPath: numberedURL.path) {
                return numberedURL
            }
        }

        let suffix = pathExtension.isEmpty ? "" : ".\(pathExtension)"
        return folder.appendingPathComponent("\(baseName) \(UUID().uuidString)\(suffix)")
    }
}
