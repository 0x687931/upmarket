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
        do {
            try FileAccessService.shared.validateReadableInput(fileURL, maxBytes: maxInputBytes)
        } catch FileAccessError.tooLarge {
            throw ConversionError.fileTooLarge
        } catch FileAccessError.unavailable {
            throw ConversionError.sourceUnavailable
        } catch FileAccessError.notAFile, FileAccessError.unreadable {
            throw ConversionError.inaccessible
        } catch {
            AppLog.fileAccess.error("Input validation failed before workspace copy: \(error.localizedDescription, privacy: .private)")
            throw ConversionError.inaccessible
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
        AppLog.fileAccess.info("Copied input into app workspace; ext=\(fileURL.pathExtension, privacy: .public) kind=\(FileAccessService.storageKind(for: fileURL).rawValue, privacy: .public)")
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

    nonisolated static func removeStaleWorkspaces() {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for entry in entries {
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDirectory else { continue }
            do {
                try manager.removeItem(at: entry)
            } catch {
                AppLog.fileAccess.error("Failed to remove stale app workspace: \(error.localizedDescription, privacy: .private)")
            }
        }
    }
}
