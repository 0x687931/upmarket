import AppKit
import Combine
import Foundation
import OSLog

struct MCPAdvertisementState: Codable, Equatable {
    static let currentVersion = 1

    let version: Int
    let enabled: Bool
    let updatedAt: String
    let commandPath: String?

    static func disabled(updatedAt: String = MCPAdvertisementState.timestamp()) -> MCPAdvertisementState {
        MCPAdvertisementState(version: currentVersion, enabled: false, updatedAt: updatedAt, commandPath: nil)
    }

    static func timestamp(date: Date = Date()) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

enum MCPIntegrationStatus: Equatable {
    case disabled
    case ready
    case commandMissing
    case appMoved

    var displayText: String {
        switch self {
        case .disabled:
            return "Disabled"
        case .ready:
            return "Ready for LM Studio"
        case .commandMissing:
            return "MCP tool missing from this app build"
        case .appMoved:
            return "Re-add to LM Studio if Upmarket was moved"
        }
    }

    var systemImage: String {
        switch self {
        case .disabled:
            return "circle"
        case .ready:
            return "checkmark.circle.fill"
        case .commandMissing, .appMoved:
            return "exclamationmark.triangle.fill"
        }
    }
}

@MainActor
final class MCPIntegrationService: ObservableObject {
    static let shared = MCPIntegrationService()

    private static let appGroupID = "group.com.upmarket.app"
    private static let mcpDirectoryName = "MCP"
    private static let stateFileName = "advertisement.json"

    private let rootURLProvider: () -> URL?
    private let bundleURLProvider: () -> URL
    private let fileManager: FileManager
    private let dateProvider: () -> Date
    private let pasteboardWriter: (String) -> Void
    private let urlOpener: (URL) -> Void

    @Published private(set) var state: MCPAdvertisementState

    convenience init() {
        self.init(
            rootURLProvider: {
                if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) {
                    return container
                }
                return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                    .appendingPathComponent("Upmarket/AppGroupFallback", isDirectory: true)
            },
            bundleURLProvider: { Bundle.main.bundleURL },
            fileManager: .default,
            dateProvider: Date.init,
            pasteboardWriter: { text in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            },
            urlOpener: { url in NSWorkspace.shared.open(url) }
        )
    }

    init(
        rootURLProvider: @escaping () -> URL?,
        bundleURLProvider: @escaping () -> URL,
        fileManager: FileManager = .default,
        dateProvider: @escaping () -> Date = Date.init,
        pasteboardWriter: @escaping (String) -> Void = { _ in },
        urlOpener: @escaping (URL) -> Void = { _ in }
    ) {
        self.rootURLProvider = rootURLProvider
        self.bundleURLProvider = bundleURLProvider
        self.fileManager = fileManager
        self.dateProvider = dateProvider
        self.pasteboardWriter = pasteboardWriter
        self.urlOpener = urlOpener
        self.state = Self.loadState(rootURLProvider: rootURLProvider, fileManager: fileManager)
    }

    var isEnabled: Bool {
        state.enabled
    }

    var commandURL: URL {
        bundleURLProvider()
            .appendingPathComponent("Contents/MacOS/upmarket-mcp", isDirectory: false)
    }

    var status: MCPIntegrationStatus {
        guard state.enabled else { return .disabled }
        guard fileManager.isExecutableFile(atPath: commandURL.path) else { return .commandMissing }
        if let advertised = state.commandPath, advertised != commandURL.path {
            return .appMoved
        }
        return .ready
    }

    var mcpJSONSnippet: String {
        let payload: [String: Any] = [
            "upmarket": [
                "command": commandURL.path
            ]
        ]
        return Self.prettyJSONString(payload)
    }

    var addToLMStudioURL: URL? {
        let config: [String: Any] = [
            "command": commandURL.path
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: config, options: [.sortedKeys]) else {
            return nil
        }
        let encoded = data.base64EncodedString()
        var components = URLComponents()
        components.scheme = "lmstudio"
        components.host = "add_mcp"
        components.queryItems = [
            URLQueryItem(name: "name", value: "upmarket"),
            URLQueryItem(name: "config", value: encoded),
        ]
        return components.url
    }

    func refresh() {
        state = Self.loadState(rootURLProvider: rootURLProvider, fileManager: fileManager)
    }

    func setAdvertisementEnabled(_ enabled: Bool) {
        let next = MCPAdvertisementState(
            version: MCPAdvertisementState.currentVersion,
            enabled: enabled,
            updatedAt: MCPAdvertisementState.timestamp(date: dateProvider()),
            commandPath: enabled ? commandURL.path : state.commandPath
        )
        save(next)
    }

    func addToLMStudio() {
        setAdvertisementEnabled(true)
        if let url = addToLMStudioURL {
            urlOpener(url)
        }
    }

    func copySnippet() {
        pasteboardWriter(mcpJSONSnippet)
    }

    private func save(_ next: MCPAdvertisementState) {
        guard let url = stateURL(createDirectory: true) else {
            state = next
            return
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(next).write(to: url, options: .atomic)
            state = next
        } catch {
            AppLog.diagnostics.error("Failed to save MCP advertisement state: \(error.localizedDescription, privacy: .private)")
            state = next
        }
    }

    private func stateURL(createDirectory: Bool) -> URL? {
        guard let root = rootURLProvider() else { return nil }
        let directory = root.appendingPathComponent(Self.mcpDirectoryName, isDirectory: true)
        if createDirectory {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent(Self.stateFileName, isDirectory: false)
    }

    private static func loadState(
        rootURLProvider: () -> URL?,
        fileManager: FileManager
    ) -> MCPAdvertisementState {
        guard let root = rootURLProvider() else { return .disabled() }
        let url = root
            .appendingPathComponent(mcpDirectoryName, isDirectory: true)
            .appendingPathComponent(stateFileName, isDirectory: false)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(MCPAdvertisementState.self, from: data),
              decoded.version == MCPAdvertisementState.currentVersion else {
            return .disabled()
        }
        return decoded
    }

    private static func prettyJSONString(_ payload: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        ),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }
}
