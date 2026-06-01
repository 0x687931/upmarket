import Foundation
import OSLog

enum AppWorkspace {
    nonisolated static let maxInputBytes: Int64 = 500 * 1024 * 1024

    nonisolated static var baseDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Upmarket/Workspaces", isDirectory: true)
    }

    nonisolated static func create(prefix: String) throws -> URL {
        let workspace = baseDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        return workspace
    }

    nonisolated static func copy(_ fileURL: URL, into workspace: URL) throws -> URL {
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        if let fileSize = values.fileSize, Int64(fileSize) > maxInputBytes {
            AppLog.fileAccess.error("Rejected oversized input: bytes=\(fileSize, privacy: .public)")
            throw ConversionError.fileTooLarge
        }

        let destination = workspace
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileURL.pathExtension)
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }
        try FileManager.default.copyItem(at: fileURL, to: destination)
        AppLog.fileAccess.info("Copied input into app workspace; ext=\(fileURL.pathExtension, privacy: .public)")
        return destination
    }

    nonisolated static func remove(_ workspace: URL) {
        do {
            try FileManager.default.removeItem(at: workspace)
            AppLog.fileAccess.info("Removed app workspace")
        } catch {
            AppLog.fileAccess.error("Failed to remove app workspace: \(error.localizedDescription, privacy: .private)")
        }
    }
}
