import Foundation

// Wire types for the CLI ⇄ app conversion handoff. Shared so the CLI (sender) and the app's
// CLIConversionBroker (receiver) agree on the on-disk protocol: the CLI writes request.json +
// the input file into CLIHandoffs/<id>/, opens upmarket://convert?cli=<id>, and polls for
// response.json (+ the produced output file). The @MainActor broker that runs the conversion
// stays in the app target.

nonisolated enum CLIHandoffPaths {
    private static let appGroupID = "group.com.upmarket.app"
    static let requestsDirectoryName = "CLIHandoffs"
    private static let fallbackDirectory = "Upmarket/AppGroupFallback"

    static func rootURL(fileManager: FileManager = .default) -> URL? {
        for candidate in candidateRootURLs(fileManager: fileManager) {
            if ensureDirectoryExists(candidate.appendingPathComponent(requestsDirectoryName, isDirectory: true), fileManager: fileManager) {
                return candidate
            }
        }
        return nil
    }

    static func parsedRootURL(from queryValue: String?, fileManager: FileManager = .default) -> URL? {
        guard let value = queryValue else { return nil }
        let path = value.removingPercentEncoding ?? value
        guard !path.isEmpty else { return nil }
        let candidate = URL(fileURLWithPath: path)
        return ensureDirectoryExists(
            candidate.appendingPathComponent(requestsDirectoryName, isDirectory: true),
            fileManager: fileManager
        ) ? candidate : nil
    }

    static func handoffDirectory(id: String, root: URL) -> URL {
        root
            .appendingPathComponent(requestsDirectoryName, isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
    }

    private static func candidateRootURLs(fileManager: FileManager) -> [URL] {
        var urls: [URL] = []
        if let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            urls.append(container)
        }
        if let fallback = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(fallbackDirectory, isDirectory: true) {
            urls.append(fallback)
        }
        return urls
    }

    private static func ensureDirectoryExists(_ url: URL, fileManager: FileManager = .default) -> Bool {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            return fileManager.isWritableFile(atPath: url.path)
        } catch {
            return false
        }
    }
}

nonisolated struct CLIConversionRequest: Codable, Equatable, Sendable {
    let version: Int
    let inputFile: String
    let sourceDisplayName: String
    let useAI: Bool
    let aiEngine: AIEngine?
    let outputMode: String

    init(
        version: Int,
        inputFile: String,
        sourceDisplayName: String,
        useAI: Bool,
        aiEngine: AIEngine? = nil,
        outputMode: String
    ) {
        self.version = version
        self.inputFile = inputFile
        self.sourceDisplayName = sourceDisplayName
        self.useAI = useAI
        self.aiEngine = aiEngine
        self.outputMode = outputMode
    }
}

nonisolated enum CLIConversionStatus: String, Codable, Sendable {
    case success
    case inputRejected
    case purchaseRequired
    case aiUnavailable
    case conversionFailed
}

nonisolated struct CLIConversionResponse: Codable, Equatable, Sendable {
    let version: Int
    let status: CLIConversionStatus
    let message: String?
    let output: String?
    let outputFile: String?
    let fileExtension: String?

    static func success(outputFile: String, fileExtension: String) -> CLIConversionResponse {
        CLIConversionResponse(version: 1, status: .success, message: nil, output: nil, outputFile: outputFile, fileExtension: fileExtension)
    }

    static func failure(_ status: CLIConversionStatus, message: String) -> CLIConversionResponse {
        CLIConversionResponse(version: 1, status: status, message: message, output: nil, outputFile: nil, fileExtension: nil)
    }
}
