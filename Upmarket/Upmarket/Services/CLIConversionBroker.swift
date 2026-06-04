import Foundation
import OSLog

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
    let fileExtension: String?

    static func success(output: String, fileExtension: String) -> CLIConversionResponse {
        CLIConversionResponse(version: 1, status: .success, message: nil, output: output, fileExtension: fileExtension)
    }

    static func failure(_ status: CLIConversionStatus, message: String) -> CLIConversionResponse {
        CLIConversionResponse(version: 1, status: status, message: message, output: nil, fileExtension: nil)
    }
}

@MainActor
struct CLIConversionBroker {
    typealias Authorize = (_ useAI: Bool) async throws -> Void
    typealias Convert = (_ url: URL, _ useAI: Bool) async -> ConversionResult

    let rootURL: URL
    let authorize: Authorize
    let convert: Convert
    private let fileManager: FileManager

    init(
        rootURL: URL,
        fileManager: FileManager = .default,
        authorize: @escaping Authorize,
        convert: @escaping Convert
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        self.authorize = authorize
        self.convert = convert
    }

    static func live(fileManager: FileManager = .default) -> CLIConversionBroker? {
        guard let rootURL = CLIHandoffPaths.rootURL(fileManager: fileManager) else { return nil }
        return CLIConversionBroker(
            rootURL: rootURL,
            fileManager: fileManager,
            authorize: { useAI in
                try await ProgrammaticConversionAuthorization.authorize(useAI: useAI)
            },
            convert: { url, useAI in
                await ConversionQueue.shared.convert(url, useAI: useAI)
            }
        )
    }

    func handle(id: String) {
        Task { @MainActor in
            await process(id: id)
        }
    }

    func process(id: String) async {
        guard UUID(uuidString: id) != nil else { return }
        let directory = CLIHandoffPaths.handoffDirectory(id: id, root: rootURL)
        let responseURL = directory.appendingPathComponent("response.json")

        do {
            let requestURL = directory.appendingPathComponent("request.json")
            let request = try JSONDecoder().decode(CLIConversionRequest.self, from: Data(contentsOf: requestURL))
            guard request.version == 1,
                  isSafeRelativeFileName(request.inputFile),
                  let outputMode = OutputMode(rawValue: request.outputMode) else {
                try write(.failure(.inputRejected, message: "The command request could not be read."), to: responseURL)
                return
            }

            let inputURL = directory.appendingPathComponent(request.inputFile, isDirectory: false)
            do {
                try FileAccessService.shared.validateReadableInput(inputURL)
            } catch {
                try write(.failure(.inputRejected, message: FileAccessService.userVisibleMessage(for: error)), to: responseURL)
                return
            }

            do {
                try await authorize(request.useAI)
            } catch ProgrammaticConversionAuthorizationError.purchaseRequired {
                try write(.failure(.purchaseRequired, message: "Open Upmarket to unlock more conversions."), to: responseURL)
                return
            } catch ProgrammaticConversionAuthorizationError.aiUnavailable {
                try write(.failure(.aiUnavailable, message: "Upmarket AI is not available for this conversion."), to: responseURL)
                return
            } catch {
                try write(.failure(.conversionFailed, message: "Upmarket could not authorize this conversion."), to: responseURL)
                return
            }

            let result = await convert(inputURL, request.useAI)
            guard case .success(let output) = result else {
                try write(.failure(.conversionFailed, message: result.errorMessage ?? "Upmarket couldn't convert this document."), to: responseURL)
                return
            }

            let sourceDisplayName = URL(fileURLWithPath: request.sourceDisplayName).lastPathComponent
            let formatted = OutputFormatter.format(
                output,
                sourceDisplayName: sourceDisplayName.isEmpty ? inputURL.lastPathComponent : sourceDisplayName,
                mode: outputMode
            )
            try write(.success(output: formatted.text, fileExtension: formatted.fileExtension), to: responseURL)
        } catch {
            AppLog.conversion.error("CLI conversion request failed: \(error.localizedDescription, privacy: .private)")
            try? write(.failure(.conversionFailed, message: "Upmarket couldn't convert this document."), to: responseURL)
        }
    }

    private func isSafeRelativeFileName(_ value: String) -> Bool {
        !value.isEmpty
            && !value.contains("/")
            && !value.contains("\\")
            && value != "."
            && value != ".."
    }

    private func write(_ response: CLIConversionResponse, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(response)
        try data.write(to: url, options: .atomic)
    }
}
