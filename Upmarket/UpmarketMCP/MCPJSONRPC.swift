import Foundation

enum MCPJSONRPC {
    static func requestID(from message: [String: Any]) -> (hasID: Bool, id: Any) {
        if let id = message["id"] {
            return (true, id)
        }
        return (false, NSNull())
    }

    static func response(id: Any, result: [String: Any]) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id,
            "result": result
        ]
    }

    static func error(id: Any, code: Int, message: String) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id,
            "error": [
                "code": code,
                "message": message
            ]
        ]
    }

    static func write(_ message: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(message),
              let data = try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys]) else {
            fputs("Upmarket MCP could not serialize a JSON-RPC message.\n", stderr)
            return
        }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    static func parse(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let message = object as? [String: Any] else {
            return nil
        }
        return message
    }
}
