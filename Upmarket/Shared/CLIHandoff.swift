import Foundation

// Wire types for the CLI ⇄ app conversion handoff. Shared so the CLI (sender) and the app's
// CLIConversionBroker (receiver) agree on the on-disk protocol: the CLI writes request.json +
// the input file into CLIHandoffs/<id>/, opens upmarket://convert?cli=<id>, and polls for
// response.json (+ the produced output file). The @MainActor broker that runs the conversion
// stays in the app target.

nonisolated enum CLIHandoffPaths {
    private static let appGroupID = "group.com.upmarket.app"
    static let requestsDirectoryName = "CLIHandoffs"

    static func rootURL(fileManager: FileManager = .default) -> URL? {
        if let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return container
        }
        return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Upmarket/AppGroupFallback", isDirectory: true)
    }

    static func handoffDirectory(id: String, root: URL) -> URL {
        root
            .appendingPathComponent(requestsDirectoryName, isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
    }
}

nonisolated struct CLIConversionRequest: Codable, Equatable, Sendable {
    let version: Int
    let inputFile: String
    let sourceDisplayName: String
    let useAI: Bool
    let outputMode: String
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
