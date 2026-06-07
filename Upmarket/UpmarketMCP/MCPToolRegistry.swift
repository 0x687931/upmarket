import Foundation

struct MCPToolExecutionError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

struct MCPToolResult {
    let content: [[String: Any]]
    let structuredContent: [String: Any]?
    let isError: Bool

    func jsonResult() -> [String: Any] {
        var result: [String: Any] = [
            "content": content,
            "isError": isError
        ]
        if let structuredContent {
            result["structuredContent"] = structuredContent
        }
        return result
    }

    static func success(text: String, structuredContent: [String: Any]) -> MCPToolResult {
        MCPToolResult(
            content: [["type": "text", "text": text]],
            structuredContent: structuredContent,
            isError: false
        )
    }

    static func error(_ message: String) -> MCPToolResult {
        MCPToolResult(
            content: [["type": "text", "text": message]],
            structuredContent: ["status": "error", "message": message],
            isError: true
        )
    }
}

struct MCPToolRegistry {
    static let convertToolName = "convert_document_to_markdown"

    private let runner: any MCPConversionRunning

    init(runner: any MCPConversionRunning) {
        self.runner = runner
    }

    func listTools(advertisementEnabled: Bool) -> [[String: Any]] {
        advertisementEnabled ? [Self.convertToolDefinition] : []
    }

    func callTool(
        name: String,
        arguments: [String: Any],
        advertisementEnabled: Bool
    ) -> MCPToolResult? {
        guard name == Self.convertToolName else { return nil }
        guard advertisementEnabled else {
            return .error("Upmarket MCP advertisement is disabled. Enable it in Upmarket Preferences.")
        }

        do {
            let request = try UpmarketCLIRunner.ConversionRequest(arguments: arguments)
            return try runner.convert(request)
        } catch let error as MCPToolExecutionError {
            return .error(error.message)
        } catch {
            return .error("Upmarket could not convert this document.")
        }
    }

    static var convertToolDefinition: [String: Any] {
        [
            "name": convertToolName,
            "title": "Convert Document to Markdown",
            "description": "Convert a local document on this Mac to Markdown through Upmarket.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "input_path": [
                        "type": "string",
                        "description": "Absolute path to a file staged in Upmarket's approved MCP input folder."
                    ],
                    "format": [
                        "type": "string",
                        "enum": ["markdown", "frontmatter", "json"],
                        "default": "markdown"
                    ],
                    "use_ai": [
                        "type": "boolean",
                        "default": false
                    ],
                    "return_mode": [
                        "type": "string",
                        "enum": ["inline", "file"],
                        "default": "inline"
                    ],
                    "max_chars": [
                        "type": "integer",
                        "minimum": 1000,
                        "maximum": 100000,
                        "default": 20000
                    ]
                ],
                "required": ["input_path"],
                "additionalProperties": false
            ]
        ]
    }
}
