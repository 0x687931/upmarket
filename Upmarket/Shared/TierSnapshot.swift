import Foundation

/// Entitlement snapshot the app writes for out-of-process tools (CLI/MCP), which can't
/// read StoreKit. The app is the sole StoreKit authority; it persists the resolved tier
/// here on every change so the unsandboxed CLI can gate itself.
///
/// `tier`: 0 = Basic, 1 = Pro, 2 = Max (mirrors AppTier.rawValue).
/// `purchased`: true once any tier is bought (false = trial).
nonisolated struct TierSnapshot: Codable, Sendable {
    let tier: Int
    let purchased: Bool

    static let appGroupID = "group.com.upmarket.app"
    static let proTier = 1
    static let maxTier = 2

    /// The shared App Group location. The sandboxed app resolves it via its entitlement;
    /// the unsandboxed CLI lands on the same physical path via the home directory.
    static func fileURL(fileManager: FileManager = .default) -> URL? {
        let root: URL
        if let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            root = container
        } else {
            root = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Group Containers/\(appGroupID)", isDirectory: true)
        }
        return root.appendingPathComponent("entitlement.json")
    }

    static func read(fileManager: FileManager = .default) -> TierSnapshot? {
        guard let url = fileURL(fileManager: fileManager),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TierSnapshot.self, from: data)
    }

    func write(fileManager: FileManager = .default) {
        guard let url = Self.fileURL(fileManager: fileManager) else { return }
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
