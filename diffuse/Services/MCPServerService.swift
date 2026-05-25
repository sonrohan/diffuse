import Foundation
import Network

struct MCPServerStatus: Equatable, Sendable {
    var isRunning: Bool
    var endpoint: String?
    var token: String
    var recentEvents: [MCPServerEvent]
}

struct MCPServerEvent: Identifiable, Equatable, Sendable {
    let id: UUID
    var timestamp: Date
    var name: String
    var status: String
    var errorCode: String?
}

actor MCPServerService {
    private static let endpointPath = "/diffuse/mcp"

    private let router: MCPRequestRouter
    private var listener: NWListener?
    private var port: UInt16?
    private var token: String
    private var events: [MCPServerEvent] = []

    init(
        router: MCPRequestRouter,
        token: String = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    ) {
        self.router = router
        self.token = token
    }

    var status: MCPServerStatus {
        MCPServerStatus(
            isRunning: listener != nil,
            endpoint: port.map { "http://127.0.0.1:\($0)\(Self.endpointPath)" },
            token: token,
            recentEvents: events
        )
    }

    func start() async throws -> MCPServerStatus {
        if listener != nil {
            return status
        }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters, on: .any)
        listener.service = nil
        listener.newConnectionHandler = { [weak self] connection in
            Task {
                await self?.handle(connection)
            }
        }
        listener.stateUpdateHandler = { state in
            if case .failed = state {
                listener.cancel()
            }
        }
        listener.start(queue: DispatchQueue(label: "diffuse.mcp.listener"))
        self.listener = listener
        self.port = listener.port?.rawValue
        record(name: "server.start", status: "ok", errorCode: nil)
        return status
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = nil
        record(name: "server.stop", status: "ok", errorCode: nil)
    }

    func rotateToken() -> MCPServerStatus {
        token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        record(name: "server.rotate_token", status: "ok", errorCode: nil)
        return status
    }

    private func handle(_ connection: NWConnection) async {
        connection.start(queue: DispatchQueue(label: "diffuse.mcp.connection"))
        do {
            let data = try await receiveRequest(connection)
            let response = await responseData(for: data)
            connection.send(
                content: response,
                completion: .contentProcessed { _ in
                    connection.cancel()
                })
        } catch {
            let response = httpResponse(
                status: "400 Bad Request",
                body: jsonRpcError(id: nil, code: -32700, message: "Invalid HTTP request"))
            connection.send(
                content: response,
                completion: .contentProcessed { _ in
                    connection.cancel()
                })
        }
    }

    private func receiveRequest(_ connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) {
                data, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: data ?? Data())
            }
        }
    }

    private func responseData(for requestData: Data) async -> Data {
        guard let requestText = String(data: requestData, encoding: .utf8) else {
            return httpResponse(
                status: "400 Bad Request",
                body: jsonRpcError(id: nil, code: -32700, message: "Request is not UTF-8."))
        }
        guard requestText.hasPrefix("POST \(Self.endpointPath) ") else {
            return httpResponse(
                status: "404 Not Found",
                body: jsonRpcError(id: nil, code: -32601, message: "Use POST \(Self.endpointPath).")
            )
        }
        guard authorized(requestText) else {
            record(
                name: "authorization", status: "error",
                errorCode: AgentContextErrorCode.invalidToken.rawValue)
            return httpResponse(
                status: "401 Unauthorized",
                body: jsonRpcError(
                    id: nil, code: -32001,
                    message: AgentContextErrorCode.invalidToken.rawValue))
        }
        guard let separator = requestText.range(of: "\r\n\r\n") else {
            return httpResponse(
                status: "400 Bad Request",
                body: jsonRpcError(id: nil, code: -32700, message: "Missing body."))
        }
        let bodyText = String(requestText[separator.upperBound...])
        guard let bodyData = bodyText.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        else {
            return httpResponse(
                status: "400 Bad Request",
                body: jsonRpcError(id: nil, code: -32700, message: "Invalid JSON body."))
        }
        let response = await handleJSONRPC(object)
        return httpResponse(status: "200 OK", body: response)
    }

    private func authorized(_ requestText: String) -> Bool {
        let expected = "Authorization: Bearer \(token)"
        return requestText.components(separatedBy: "\r\n").contains { line in
            line.caseInsensitiveCompare(expected) == .orderedSame
        }
    }

    private func handleJSONRPC(_ request: [String: Any]) async -> [String: Any] {
        let id = request["id"]
        guard let method = request["method"] as? String else {
            return jsonRpcError(id: id, code: -32600, message: "Missing JSON-RPC method.")
        }

        do {
            let result: Any
            switch method {
            case "initialize":
                result = [
                    "protocolVersion": "2025-06-18",
                    "serverInfo": ["name": "diffuse", "version": "1.0.0"],
                    "capabilities": [
                        "tools": [:],
                        "resources": [:],
                        "prompts": [:],
                    ],
                ]
            case "tools/list":
                result = ["tools": routerEncodableList(await router.listTools())]
            case "tools/call":
                let params = request["params"] as? [String: Any] ?? [:]
                guard let name = params["name"] as? String else {
                    throw AgentContextError(
                        code: .invalidArguments, message: "Tool name is required.")
                }
                let arguments = params["arguments"] as? [String: Any] ?? [:]
                let routed = await router.callTool(name: name, arguments: arguments)
                record(
                    name: name,
                    status: routed.isError == true ? "error" : "ok",
                    errorCode: routed.isError == true ? "tool_error" : nil)
                result = [
                    "content": routed.content,
                    "isError": routed.isError ?? false,
                ]
            case "resources/list":
                result = ["resources": routerEncodableList(await router.listResources())]
            case "resources/read":
                let params = request["params"] as? [String: Any] ?? [:]
                guard let uri = params["uri"] as? String else {
                    throw AgentContextError(
                        code: .invalidArguments, message: "Resource URI is required.")
                }
                let routed = await router.readResource(uri: uri)
                record(
                    name: uri,
                    status: routed.isError == true ? "error" : "ok",
                    errorCode: routed.isError == true ? "resource_error" : nil)
                result = [
                    "contents": routed.content.map {
                        ["uri": uri, "mimeType": "application/json", "text": $0["text"] ?? ""]
                    }
                ]
            case "prompts/list":
                result = ["prompts": routerEncodableList(await router.listPrompts())]
            case "prompts/get":
                let params = request["params"] as? [String: Any] ?? [:]
                guard let name = params["name"] as? String else {
                    throw AgentContextError(
                        code: .invalidArguments, message: "Prompt name is required.")
                }
                let prompt = try await router.getPrompt(name: name)
                result = [
                    "description": prompt.description,
                    "messages": prompt.messages.map { message in
                        [
                            "role": message.role,
                            "content": message.content,
                        ]
                    },
                ]
            default:
                return jsonRpcError(id: id, code: -32601, message: "Unsupported method: \(method)")
            }
            return ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result]
        } catch let error as AgentContextError {
            record(name: method, status: "error", errorCode: error.code.rawValue)
            return jsonRpcError(id: id, code: -32602, message: error.code.rawValue)
        } catch {
            record(
                name: method, status: "error",
                errorCode: AgentContextErrorCode.invalidArguments.rawValue)
            return jsonRpcError(id: id, code: -32603, message: error.localizedDescription)
        }
    }

    private func httpResponse(status: String, body: [String: Any]) -> Data {
        let bodyData =
            (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
        let headers = [
            "HTTP/1.1 \(status)",
            "Content-Type: application/json",
            "Content-Length: \(bodyData.count)",
            "Connection: close",
            "",
            "",
        ].joined(separator: "\r\n")
        var data = Data(headers.utf8)
        data.append(bodyData)
        return data
    }

    private func jsonRpcError(id: Any?, code: Int, message: String) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "error": [
                "code": code,
                "message": message,
            ],
        ]
    }

    private func routerEncodableList<T: Encodable>(_ value: T) -> Any {
        encodableObject(value)
    }

    private func encodableObject<T: Encodable>(_ value: T) -> Any {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value),
            let object = try? JSONSerialization.jsonObject(with: data)
        else {
            return [:]
        }
        return object
    }

    private func record(name: String, status: String, errorCode: String?) {
        events.insert(
            MCPServerEvent(
                id: UUID(), timestamp: Date(), name: name, status: status, errorCode: errorCode),
            at: 0
        )
        events = Array(events.prefix(20))
    }
}
