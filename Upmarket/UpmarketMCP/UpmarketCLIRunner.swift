import Foundation

protocol MCPConversionRunning {
    func convert(_ request: UpmarketCLIRunner.ConversionRequest) throws -> MCPToolResult
}

struct UpmarketCLIRunner {
    enum OutputFormat: String {
        case markdown
        case frontmatter
        case json

        var fileExtension: String {
            switch self {
            case .markdown, .frontmatter:
                return "md"
            case .json:
                return "json"
            }
        }
    }

    enum ReturnMode: String {
        case inline
        case file
    }

    struct ConversionRequest {
        let inputPath: String
        let format: OutputFormat
        let useAI: Bool
        let returnMode: ReturnMode
        let maxChars: Int

        init(arguments: [String: Any]) throws {
            guard let inputPath = arguments["input_path"] as? String,
                  !inputPath.isEmpty else {
                throw MCPToolExecutionError("The tool requires input_path.")
            }
            self.inputPath = inputPath

            if let rawFormat = arguments["format"] as? String {
                guard let format = OutputFormat(rawValue: rawFormat) else {
                    throw MCPToolExecutionError("Output format must be markdown, frontmatter, or json.")
                }
                self.format = format
            } else {
                self.format = .markdown
            }

            self.useAI = (arguments["use_ai"] as? Bool) ?? false

            if let rawMode = arguments["return_mode"] as? String {
                guard let returnMode = ReturnMode(rawValue: rawMode) else {
                    throw MCPToolExecutionError("return_mode must be inline or file.")
                }
                self.returnMode = returnMode
            } else {
                self.returnMode = .inline
            }

            if let maxChars = arguments["max_chars"] as? Int {
                guard (1_000...100_000).contains(maxChars) else {
                    throw MCPToolExecutionError("max_chars must be between 1000 and 100000.")
                }
                self.maxChars = maxChars
            } else if let maxChars = arguments["max_chars"] as? Double {
                let rounded = Int(maxChars)
                guard Double(rounded) == maxChars, (1_000...100_000).contains(rounded) else {
                    throw MCPToolExecutionError("max_chars must be between 1000 and 100000.")
                }
                self.maxChars = rounded
            } else {
                self.maxChars = 20_000
            }
        }
    }

    private let cliURL: URL
    private let fileManager: FileManager

    init(
        cliURL: URL = UpmarketCLIRunner.defaultCLIURL(),
        fileManager: FileManager = .default
    ) {
        self.cliURL = cliURL
        self.fileManager = fileManager
    }

    func convert(_ request: ConversionRequest) throws -> MCPToolResult {
        guard request.inputPath.hasPrefix("/") else {
            throw MCPToolExecutionError("input_path must be an absolute local file path.")
        }
        guard !request.inputPath.contains("://") else {
            throw MCPToolExecutionError("Remote URLs are not supported.")
        }

        let inputURL = URL(fileURLWithPath: request.inputPath).standardizedFileURL
        let inputDirectory = try MCPPaths.inputDirectory(fileManager: fileManager)
        guard Self.isDescendant(inputURL, of: inputDirectory) else {
            throw MCPToolExecutionError("MCP conversion only accepts files staged in Upmarket's approved MCP input folder.")
        }
        guard (try? inputURL.checkResourceIsReachable()) == true,
              let values = try? inputURL.resourceValues(forKeys: [.isRegularFileKey, .isReadableKey]),
              values.isRegularFile != false,
              values.isReadable != false else {
            throw MCPToolExecutionError("This file cannot be converted safely.")
        }
        guard fileManager.isExecutableFile(atPath: cliURL.path) else {
            throw MCPToolExecutionError("The Upmarket command-line tool is missing from this app build.")
        }

        let outputDirectory = try MCPPaths.outputDirectory(fileManager: fileManager)
        let outputURL = outputDirectory
            .appendingPathComponent("upmarket-mcp-\(UUID().uuidString).\(request.format.fileExtension)")

        var arguments = [
            "convert",
            inputURL.path,
            "-o",
            outputURL.path,
            "--format",
            request.format.rawValue,
            "--force"
        ]
        if request.useAI {
            arguments.append("--ai")
        }

        let result = try runCLI(arguments: arguments)
        guard result.exitCode == 0 else {
            try? fileManager.removeItem(at: outputURL)
            return .error(Self.message(for: result.exitCode, stderr: result.stderr))
        }

        guard let output = try? String(contentsOf: outputURL, encoding: .utf8) else {
            try? fileManager.removeItem(at: outputURL)
            return .error("Upmarket could not prepare the MCP output file.")
        }

        let shouldReturnFile = request.returnMode == .file || output.count > request.maxChars
        let structured: [String: Any] = [
            "status": "success",
            "format": request.format.rawValue,
            "returned": shouldReturnFile ? "file" : "inline",
            "output_path": shouldReturnFile ? outputURL.path : NSNull(),
            "character_count": output.count
        ]

        if shouldReturnFile {
            return .success(
                text: "Converted document saved for MCP at \(outputURL.path).",
                structuredContent: structured
            )
        }

        try? fileManager.removeItem(at: outputURL)
        return .success(text: output, structuredContent: structured)
    }

    private func runCLI(arguments: [String]) throws -> (exitCode: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = cliURL
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }

    private static func isDescendant(_ url: URL, of directory: URL) -> Bool {
        let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
        let resolvedDirectory = directory.resolvingSymlinksInPath().standardizedFileURL
        let path = resolvedURL.path
        let directoryPath = resolvedDirectory.path
        return path == directoryPath || path.hasPrefix(directoryPath + "/")
    }

    private static func message(for exitCode: Int32, stderr: String) -> String {
        let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        switch exitCode {
        case 1:
            return "The tool arguments are invalid."
        case 2:
            return detail.isEmpty ? "This file cannot be converted safely." : detail
        case 3:
            return "Open Upmarket to unlock more conversions."
        case 4:
            return "Upmarket AI is not available for this conversion."
        case 5:
            return detail.isEmpty ? "Upmarket could not convert this document." : detail
        case 6:
            return "Upmarket could not prepare the MCP output file."
        default:
            return detail.isEmpty ? "Upmarket could not convert this document." : detail
        }
    }

    private static func defaultCLIURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["UPMARKET_MCP_CLI_PATH"],
           !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        return executableURL.deletingLastPathComponent().appendingPathComponent("upmarket-cli")
    }
}

extension UpmarketCLIRunner: MCPConversionRunning {}
