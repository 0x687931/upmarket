import Foundation

@main
enum UpmarketMCP {
    static func main() {
        MCPPaths.removeStaleOutputs()
        let registry = MCPToolRegistry(runner: UpmarketCLIRunner())

        while let line = readLine(strippingNewline: true) {
            guard let request = MCPJSONRPC.parse(line) else {
                MCPJSONRPC.write(MCPJSONRPC.error(id: NSNull(), code: -32700, message: "Parse error"))
                continue
            }

            let idInfo = MCPJSONRPC.requestID(from: request)
            guard let method = request["method"] as? String else {
                if idInfo.hasID {
                    MCPJSONRPC.write(MCPJSONRPC.error(id: idInfo.id, code: -32600, message: "Invalid request"))
                }
                continue
            }

            switch method {
            case "initialize":
                guard idInfo.hasID else { continue }
                MCPJSONRPC.write(MCPJSONRPC.response(id: idInfo.id, result: initializeResult(from: request)))

            case "notifications/initialized":
                continue

            case "ping":
                guard idInfo.hasID else { continue }
                MCPJSONRPC.write(MCPJSONRPC.response(id: idInfo.id, result: [:]))

            case "tools/list":
                guard idInfo.hasID else { continue }
                let tools = registry.listTools(advertisementEnabled: MCPPaths.advertisementEnabled())
                MCPJSONRPC.write(MCPJSONRPC.response(id: idInfo.id, result: ["tools": tools]))

            case "tools/call":
                guard idInfo.hasID else { continue }
                handleToolCall(request, id: idInfo.id, registry: registry)

            default:
                if idInfo.hasID {
                    MCPJSONRPC.write(MCPJSONRPC.error(id: idInfo.id, code: -32601, message: "Method not found"))
                }
            }
        }
    }

    private static func initializeResult(from request: [String: Any]) -> [String: Any] {
        let params = request["params"] as? [String: Any]
        let requestedVersion = params?["protocolVersion"] as? String
        return [
            "protocolVersion": requestedVersion ?? "2025-11-25",
            "capabilities": [
                "tools": [
                    "listChanged": false
                ]
            ],
            "serverInfo": [
                "name": "upmarket",
                "version": "1.0.0"
            ]
        ]
    }

    private static func handleToolCall(_ request: [String: Any], id: Any, registry: MCPToolRegistry) {
        guard let params = request["params"] as? [String: Any],
              let name = params["name"] as? String else {
            MCPJSONRPC.write(MCPJSONRPC.error(id: id, code: -32602, message: "Invalid tool call"))
            return
        }
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        guard let result = registry.callTool(
            name: name,
            arguments: arguments,
            advertisementEnabled: MCPPaths.advertisementEnabled()
        ) else {
            MCPJSONRPC.write(MCPJSONRPC.error(id: id, code: -32602, message: "Unknown tool: \(name)"))
            return
        }
        MCPJSONRPC.write(MCPJSONRPC.response(id: id, result: result.jsonResult()))
    }
}
