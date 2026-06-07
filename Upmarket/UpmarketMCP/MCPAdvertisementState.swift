import Foundation

struct MCPAdvertisementState: Codable {
    static let currentVersion = 1

    let version: Int
    let enabled: Bool
    let updatedAt: String
    let commandPath: String?
}

enum MCPPaths {
    private static let appGroupID = "group.com.upmarket.app"
    private static let mcpDirectoryName = "MCP"

    static func rootURL(fileManager: FileManager = .default) -> URL? {
        if let override = ProcessInfo.processInfo.environment["UPMARKET_MCP_STATE_ROOT"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        if let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return container
        }
        return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Upmarket/AppGroupFallback", isDirectory: true)
    }

    static func stateURL(fileManager: FileManager = .default) -> URL? {
        rootURL(fileManager: fileManager)?
            .appendingPathComponent(mcpDirectoryName, isDirectory: true)
            .appendingPathComponent("advertisement.json", isDirectory: false)
    }

    static func outputDirectory(fileManager: FileManager = .default) throws -> URL {
        guard let root = rootURL(fileManager: fileManager) else {
            throw MCPToolExecutionError("Upmarket could not prepare MCP output storage.")
        }
        let directory = root
            .appendingPathComponent(mcpDirectoryName, isDirectory: true)
            .appendingPathComponent("Outputs", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func inputDirectory(fileManager: FileManager = .default) throws -> URL {
        guard let root = rootURL(fileManager: fileManager) else {
            throw MCPToolExecutionError("Upmarket could not prepare MCP input storage.")
        }
        let directory = root
            .appendingPathComponent(mcpDirectoryName, isDirectory: true)
            .appendingPathComponent("Inputs", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func advertisementEnabled(fileManager: FileManager = .default) -> Bool {
        guard let url = stateURL(fileManager: fileManager),
              fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(MCPAdvertisementState.self, from: data),
              state.version == MCPAdvertisementState.currentVersion else {
            return false
        }
        return state.enabled
    }

    static func removeStaleOutputs(fileManager: FileManager = .default, now: Date = Date()) {
        guard let directory = try? outputDirectory(fileManager: fileManager),
              let entries = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return
        }
        let cutoff = now.addingTimeInterval(-24 * 60 * 60)
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true,
                  (values?.contentModificationDate ?? .distantPast) < cutoff else {
                continue
            }
            try? fileManager.removeItem(at: entry)
        }
    }
}
