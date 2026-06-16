import Foundation
import OSLog

// CLIHandoffPaths + CLIConversionRequest/Status/Response now live in Shared/CLIHandoff.swift
// so the CLI (sender) and this broker (receiver) share the on-disk protocol.

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
            let outputFile = "output.\(formatted.fileExtension)"
            let outputURL = directory.appendingPathComponent(outputFile, isDirectory: false)
            try Data(formatted.text.utf8).write(to: outputURL, options: .atomic)
            try write(.success(outputFile: outputFile, fileExtension: formatted.fileExtension), to: responseURL)
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
