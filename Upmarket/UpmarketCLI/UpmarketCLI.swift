import Darwin
import Foundation

private let appGroupID = "group.com.upmarket.app"
private let maxInputBytes: Int64 = 500 * 1024 * 1024
private let responseTimeout: TimeInterval = 2 * 60 * 60

private enum ExitCode: Int32 {
    case success = 0
    case usage = 1
    case inputRejected = 2
    case purchaseRequired = 3
    case aiUnavailable = 4
    case conversionFailed = 5
    case outputWriteFailed = 6
}

private enum OutputFormat: String {
    case markdown
    case frontmatter
    case json
}

private struct Options {
    let inputURL: URL
    let outputURL: URL
    let useAI: Bool
    let outputFormat: OutputFormat
    let force: Bool
}

private struct CLIConversionRequest: Codable {
    let version: Int
    let inputFile: String
    let sourceDisplayName: String
    let useAI: Bool
    let outputMode: String
}

private enum CLIConversionStatus: String, Codable {
    case success
    case inputRejected
    case purchaseRequired
    case aiUnavailable
    case conversionFailed
}

private struct CLIConversionResponse: Codable {
    let version: Int
    let status: CLIConversionStatus
    let message: String?
    let output: String?
    let fileExtension: String?
}

private enum HandoffPaths {
    static func rootURL(fileManager: FileManager = .default) -> URL? {
        if let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return container
        }
        return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Upmarket/AppGroupFallback", isDirectory: true)
    }

    static func handoffDirectory(id: String, root: URL) -> URL {
        root
            .appendingPathComponent("CLIHandoffs", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
    }

    static func mcpInputDirectory(root: URL) -> URL {
        root
            .appendingPathComponent("MCP", isDirectory: true)
            .appendingPathComponent("Inputs", isDirectory: true)
    }

    static func mcpOutputDirectory(root: URL) -> URL {
        root
            .appendingPathComponent("MCP", isDirectory: true)
            .appendingPathComponent("Outputs", isDirectory: true)
    }
}

@main
private enum UpmarketCLI {
    static func main() {
        do {
            let options = try parse(arguments: Array(CommandLine.arguments.dropFirst()))
            try run(options)
            exit(ExitCode.success.rawValue)
        } catch let error as CommandError {
            if !error.message.isEmpty {
                fputs("\(error.message)\n", stderr)
            }
            exit(error.exitCode.rawValue)
        } catch {
            fputs("Upmarket could not complete this conversion.\n", stderr)
            exit(ExitCode.conversionFailed.rawValue)
        }
    }

    private static func run(_ options: Options) throws {
        guard let root = HandoffPaths.rootURL() else {
            throw CommandError(.conversionFailed, "Upmarket could not create a conversion request.")
        }
        try validateInput(options.inputURL, authorizedRoot: HandoffPaths.mcpInputDirectory(root: root))
        try validateOutputDestination(
            options.outputURL,
            force: options.force,
            authorizedRoot: HandoffPaths.mcpOutputDirectory(root: root)
        )

        let id = UUID().uuidString
        let directory = HandoffPaths.handoffDirectory(id: id, root: root)
        let inputName = handoffInputName(for: options.inputURL)
        let copiedInput = directory.appendingPathComponent(inputName, isDirectory: false)
        let requestURL = directory.appendingPathComponent("request.json")
        let responseURL = directory.appendingPathComponent("response.json")

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: options.inputURL, to: copiedInput)
            let request = CLIConversionRequest(
                version: 1,
                inputFile: inputName,
                sourceDisplayName: options.inputURL.lastPathComponent,
                useAI: options.useAI,
                outputMode: options.outputFormat.rawValue
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(request).write(to: requestURL, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw CommandError(.inputRejected, "This file cannot be converted safely.")
        }

        try openApp(handoffID: id)
        let response = try waitForResponse(at: responseURL)
        try? FileManager.default.removeItem(at: directory)

        switch response.status {
        case .success:
            guard let output = response.output else {
                throw CommandError(.conversionFailed, "Upmarket returned an unreadable conversion result.")
            }
            try writeOutput(output, to: options.outputURL, force: options.force)
        case .inputRejected:
            throw CommandError(.inputRejected, response.message ?? "This file cannot be converted safely.")
        case .purchaseRequired:
            throw CommandError(.purchaseRequired, response.message ?? "Open Upmarket to unlock more conversions.")
        case .aiUnavailable:
            throw CommandError(.aiUnavailable, response.message ?? "Upmarket AI is not available for this conversion.")
        case .conversionFailed:
            throw CommandError(.conversionFailed, response.message ?? "Upmarket could not convert this document.")
        }
    }

    private static func parse(arguments: [String]) throws -> Options {
        guard !arguments.isEmpty else {
            printUsage()
            throw CommandError(.usage, "")
        }
        if arguments == ["--help"] || arguments == ["-h"] {
            printUsage()
            throw CommandError(.success, "")
        }
        guard arguments.first == "convert" else {
            printUsage()
            throw CommandError(.usage, "Unknown command.")
        }

        var input: String?
        var output: String?
        var useAI = false
        var force = false
        var format: OutputFormat = .markdown

        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--ai":
                useAI = true
                index += 1
            case "--force":
                force = true
                index += 1
            case "-o", "--output":
                guard index + 1 < arguments.count else {
                    throw CommandError(.usage, "Missing output file.")
                }
                output = arguments[index + 1]
                index += 2
            case "--format":
                guard index + 1 < arguments.count,
                      let parsed = OutputFormat(rawValue: arguments[index + 1]) else {
                    throw CommandError(.usage, "Output format must be markdown, frontmatter, or json.")
                }
                format = parsed
                index += 2
            default:
                guard !argument.hasPrefix("-"), input == nil else {
                    throw CommandError(.usage, "Unknown option.")
                }
                input = argument
                index += 1
            }
        }

        guard let input, let output else {
            printUsage()
            throw CommandError(.usage, "Input and output files are required.")
        }

        return Options(
            inputURL: URL(fileURLWithPath: input).standardizedFileURL,
            outputURL: URL(fileURLWithPath: output).standardizedFileURL,
            useAI: useAI,
            outputFormat: format,
            force: force
        )
    }

    private static func validateInput(_ url: URL, authorizedRoot: URL) throws {
        guard isDescendant(url, of: authorizedRoot),
              SupportedInputPolicy.supports(url),
              (try? url.checkResourceIsReachable()) == true,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isReadableKey, .fileSizeKey]),
              values.isRegularFile != false,
              values.isReadable != false,
              let fileSize = values.fileSize,
              Int64(fileSize) <= maxInputBytes else {
            throw CommandError(.inputRejected, "This file cannot be converted safely.")
        }
    }

    private static func validateOutputDestination(_ url: URL, force: Bool, authorizedRoot: URL) throws {
        guard isDescendant(url, of: authorizedRoot) else {
            throw CommandError(.outputWriteFailed, "Output must be written to Upmarket MCP output storage.")
        }
        if FileManager.default.fileExists(atPath: url.path), !force {
            throw CommandError(.outputWriteFailed, "Output file already exists. Pass --force to replace it.")
        }
    }

    private static func openApp(handoffID: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["upmarket://convert?cli=\(handoffID)"]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CommandError(.conversionFailed, "Upmarket could not be opened.")
        }
    }

    private static func waitForResponse(at url: URL) throws -> CLIConversionResponse {
        let decoder = JSONDecoder()
        let deadline = Date().addingTimeInterval(responseTimeout)
        while Date() < deadline {
            if let data = try? Data(contentsOf: url) {
                return try decoder.decode(CLIConversionResponse.self, from: data)
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        throw CommandError(.conversionFailed, "Upmarket did not finish the conversion.")
    }

    private static func writeOutput(_ output: String, to url: URL, force: Bool) throws {
        let directory = url.deletingLastPathComponent()
        let temporaryURL = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try Data(output.utf8).write(to: temporaryURL)
            if FileManager.default.fileExists(atPath: url.path) {
                guard force else {
                    throw CommandError(.outputWriteFailed, "Output file already exists. Pass --force to replace it.")
                }
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
            } else {
                try FileManager.default.moveItem(at: temporaryURL, to: url)
            }
        } catch let error as CommandError {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw CommandError(.outputWriteFailed, "Could not write output file.")
        }
    }

    private static func printUsage() {
        print("""
        Usage:
          upmarket-cli convert input.pdf -o output.md [--ai] [--format markdown|frontmatter|json] [--force]
        """)
    }

    private static func handoffInputName(for url: URL) -> String {
        let fallbackExtension = url.pathExtension.isEmpty ? "dat" : url.pathExtension
        let fallback = "input.\(fallbackExtension)"
        let candidate = url.lastPathComponent
        guard !candidate.isEmpty,
              candidate != ".",
              candidate != "..",
              !candidate.contains("/"),
              !candidate.contains("\\") else {
            return fallback
        }
        return candidate
    }

    private static func isDescendant(_ url: URL, of directory: URL) -> Bool {
        let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
        let resolvedDirectory = directory.resolvingSymlinksInPath().standardizedFileURL
        let path = resolvedURL.path
        let directoryPath = resolvedDirectory.path
        return path == directoryPath || path.hasPrefix(directoryPath + "/")
    }
}

private struct CommandError: Error {
    let exitCode: ExitCode
    let message: String

    init(_ exitCode: ExitCode, _ message: String) {
        self.exitCode = exitCode
        self.message = message
    }
}

private enum SupportedInputPolicy {
    static let fileExtensions = [
        "pdf", "html", "txt", "png", "jpg", "jpeg", "gif", "tiff",
        "docx", "pptx", "xlsx", "epub", "csv", "json", "xml", "zip",
        "mp3", "m4a", "wav", "aiff", "opus",
    ]

    static func supports(_ url: URL) -> Bool {
        fileExtensions.contains(url.pathExtension.lowercased())
    }
}
