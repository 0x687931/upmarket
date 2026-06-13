import Foundation
import AppKit

/// Async file write service — prevents main thread blocking on disk I/O.
/// Handles both local and security-scoped URLs (iCloud, sandboxed locations).
actor FileWriteService {
    nonisolated static let shared = FileWriteService()

    /// Write markdown to file asynchronously, off main thread.
    /// Handles security-scoped resources automatically.
    func writeMarkdown(_ content: String, to url: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            try content.write(to: url, atomically: true, encoding: .utf8)
        }.value
    }

    /// Copy markdown to pasteboard asynchronously (non-blocking).
    func copyMarkdown(_ content: String) async {
        await Task.detached(priority: .userInitiated) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(content, forType: .string)
        }.value
    }
}
