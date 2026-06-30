import Foundation

enum AgentMCPServer {
    static func run() {
        var recorder = AgentMCPRunRecorder()
        while let message = readMessage() {
            guard let response = handle(message: message, recorder: &recorder) else { continue }
            writeMessage(response)
        }
    }

    static func handle(message: [String: Any]) -> [String: Any]? {
        var recorder = AgentMCPRunRecorder()
        return handle(message: message, recorder: &recorder)
    }

    private static func handle(message: [String: Any], recorder: inout AgentMCPRunRecorder) -> [String: Any]? {
        guard let method = message["method"] as? String else { return nil }
        let id = message["id"]

        switch method {
        case "initialize":
            recorder.start(request: "stdio MCP session")
            return response(id: id, result: [
                "protocolVersion": "2024-11-05",
                "serverInfo": [
                    "name": "remnant",
                    "version": "1.0.0"
                ],
                "capabilities": [
                    "tools": [:]
                ]
            ])
        case "tools/list":
            return response(id: id, result: [
                "tools": AgentCommandService.toolDefinitions()
            ])
        case "tools/call":
            return handleToolCall(id: id, message: message, recorder: &recorder)
        case "notifications/initialized":
            return nil
        default:
            return response(id: id, error: "Unsupported MCP method: \(method)")
        }
    }

    private static func handleToolCall(id: Any?, message: [String: Any], recorder: inout AgentMCPRunRecorder) -> [String: Any] {
        guard let params = message["params"] as? [String: Any],
              let name = params["name"] as? String else {
            return response(id: id, error: "tools/call requires params.name.")
        }
        let arguments = params["arguments"] as? [String: Any] ?? [:]

        if name == "complete_task" {
            let status = arguments["status"] as? String ?? "completed"
            let summary = arguments["summary"] as? String ?? ""
            recorder.complete(status: status, summary: summary)
            return response(id: id, result: toolResult([
                "status": status,
                "summary": summary
            ]))
        }

        let remnantctlArguments: [String]
        do {
            remnantctlArguments = try commandArguments(for: name, arguments: arguments)
        } catch {
            recorder.record(toolName: name, status: "failed", summary: "Invalid MCP tool arguments.")
            return response(id: id, error: error.localizedDescription)
        }

        let result = AgentCommandService.run(arguments: remnantctlArguments)
        guard result.exitCode == 0 else {
            recorder.record(toolName: name, status: "failed", summary: "Command returned a nonzero result.")
            return response(id: id, error: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        recorder.record(toolName: name, status: "completed", summary: "Tool completed.")
        return response(id: id, result: toolResult(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    private static func commandArguments(for toolName: String, arguments: [String: Any]) throws -> [String] {
        switch toolName {
        case "capabilities":
            return ["capabilities"]
        case "schema":
            return ["schema"]
        case "snapshot":
            return ["snapshot"]
        case "expenses_list":
            return ["expenses:list"]
        case "expenses_read":
            return ["expenses:read", try requiredString("id", arguments: arguments)]
        case "receipts_list":
            return ["receipts:list"]
        case "receipts_read_metadata":
            return ["receipts:read-metadata", try requiredString("id", arguments: arguments)]
        case "review_list":
            return ["review:list"]
        case "reports_summary":
            return ["reports:summary"]
        case "proposals_list":
            return ["proposals:list"]
        case "proposals_read":
            return ["proposals:read", try requiredString("id", arguments: arguments)]
        case "proposals_create":
            let temporaryURL = try writeTemporaryProposal(arguments: arguments)
            return ["proposals:create", "--json", temporaryURL.path]
        case "backup_propose":
            return ["backup:propose", "--reason", arguments["reason"] as? String ?? "Requested from MCP."]
        case "audit_propose":
            return ["audit:propose", "--reason", arguments["reason"] as? String ?? "Requested from MCP."]
        default:
            throw AgentWorkspaceError.validationFailed("Unknown MCP tool: \(toolName)")
        }
    }

    private static func writeTemporaryProposal(arguments: [String: Any]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("remnant-agent-proposal-\(UUID().uuidString).json")
        let data = try JSONSerialization.data(withJSONObject: arguments, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func requiredString(_ key: String, arguments: [String: Any]) throws -> String {
        guard let value = arguments[key] as? String, !value.isEmpty else {
            throw AgentWorkspaceError.validationFailed("MCP tool argument \(key) is required.")
        }
        return value
    }

    private static func toolResult(_ value: Any) -> [String: Any] {
        let text: String
        if let value = value as? String {
            text = value
        } else {
            text = (try? AgentCommandService.jsonString(value)) ?? "{}"
        }
        return [
            "content": [
                [
                    "type": "text",
                    "text": text
                ]
            ]
        ]
    }

    private static func response(id: Any?, result: [String: Any]) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "result": result
        ]
    }

    private static func response(id: Any?, error: String) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "error": [
                "code": -32000,
                "message": error
            ]
        ]
    }

    private static func readMessage() -> [String: Any]? {
        guard let header = readUntilHeaderTerminator() else { return nil }
        let contentLength = header
            .components(separatedBy: "\r\n")
            .compactMap { line -> Int? in
                let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2, parts[0].lowercased() == "content-length" else { return nil }
                return Int(parts[1])
            }
            .first

        guard let contentLength else { return nil }
        let data = FileHandle.standardInput.readData(ofLength: contentLength)
        guard data.count == contentLength,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func readUntilHeaderTerminator() -> String? {
        var data = Data()
        let terminator = Data("\r\n\r\n".utf8)
        while true {
            let chunk = FileHandle.standardInput.readData(ofLength: 1)
            if chunk.isEmpty {
                return data.isEmpty ? nil : String(data: data, encoding: .utf8)
            }
            data.append(chunk)
            if data.suffix(terminator.count) == terminator {
                return String(data: data.dropLast(terminator.count), encoding: .utf8)
            }
        }
    }

    private static func writeMessage(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return
        }
        let header = "Content-Length: \(data.count)\r\n\r\n"
        FileHandle.standardOutput.write(Data(header.utf8))
        FileHandle.standardOutput.write(data)
    }
}

private struct AgentMCPRunRecorder {
    private var payload = AgentRunPayload(sourceClient: "mcp")

    mutating func start(request: String) {
        if payload.request.isEmpty {
            payload.request = request
        }
        write()
    }

    mutating func record(toolName: String, status: String, summary: String) {
        payload.toolCalls.append(
            AgentToolCallPayload(
                toolName: toolName,
                status: status,
                summary: summary
            )
        )
        payload.toolCallCount = payload.toolCalls.count
        write()
    }

    mutating func complete(status: String, summary: String) {
        payload.status = AgentRunStatus(rawValue: status) ?? .completed
        payload.completedAt = Date()
        payload.summary = summary
        write()
    }

    private func write() {
        try? AgentRunFileService.write(payload: payload)
    }
}
