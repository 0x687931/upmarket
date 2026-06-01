import Foundation

enum AppWorkspace {
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
        return destination
    }

    nonisolated static func remove(_ workspace: URL) {
        try? FileManager.default.removeItem(at: workspace)
    }
}
