import Foundation

@MainActor
final class MCPStdioSnapshotProvider: AgentContextSnapshotProviding {
    private var snapshot = AgentContextSnapshot(
        repositories: [],
        selectedRepoId: nil,
        selectedBranch: nil,
        selectedCommitSha: nil,
        currentDetails: nil,
        pullRequests: []
    )

    func load(persistence: PersistenceService) async {
        let repositories = await persistence.allRepositories()
        let pullRequests = await persistence.allPullRequests()
        let selectedRepo = repositories.first
        let latestRun = pullRequests.compactMap(\.latestRun).sorted {
            $0.createdAt > $1.createdAt
        }.first
        let details: AnalysisDetails?
        if let run = latestRun {
            details = await persistence.getAnalysisDetails(
                runId: run.id,
                profile: AnalysisProfileStore.load(repoPath: selectedRepo?.path)
            )
        } else {
            details = nil
        }
        snapshot = AgentContextSnapshot(
            repositories: repositories,
            selectedRepoId: selectedRepo?.id,
            selectedBranch: nil,
            selectedCommitSha: nil,
            currentDetails: details,
            pullRequests: pullRequests
        )
    }

    func agentContextSnapshot() -> AgentContextSnapshot {
        snapshot
    }
}

enum MCPStdioServerService {
    static func run() async {
        let persistence = PersistenceService()
        let snapshotProvider = await MainActor.run { MCPStdioSnapshotProvider() }
        await snapshotProvider.load(persistence: persistence)
        let queryService = AgentContextQueryService(
            stateProvider: snapshotProvider,
            persistence: persistence
        )
        let router = MCPRequestRouter(queryService: queryService)
        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard let text = String(data: input, encoding: .utf8) else { return }

        let requests = text.split(whereSeparator: \.isNewline).map(String.init)
        for requestText in requests where !requestText.trimmingCharacters(in: .whitespaces).isEmpty
        {
            let response = await handle(requestText: requestText, router: router)
            write(response)
        }
    }

    private static func handle(requestText: String, router: MCPRequestRouter) async -> [String: Any]
    {
        guard let data = requestText.data(using: .utf8),
            let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return jsonRpcError(id: nil, code: -32700, message: "Invalid JSON-RPC request.")
        }

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
                result = ["tools": encodableObject(await router.listTools())]
            case "tools/call":
                let params = request["params"] as? [String: Any] ?? [:]
                guard let name = params["name"] as? String else {
                    throw AgentContextError(
                        code: .invalidArguments, message: "Tool name is required.")
                }
                let arguments = params["arguments"] as? [String: Any] ?? [:]
                let routed = await router.callTool(name: name, arguments: arguments)
                result = [
                    "content": routed.content,
                    "isError": routed.isError ?? false,
                ]
            case "resources/list":
                result = ["resources": encodableObject(await router.listResources())]
            case "resources/read":
                let params = request["params"] as? [String: Any] ?? [:]
                guard let uri = params["uri"] as? String else {
                    throw AgentContextError(
                        code: .invalidArguments, message: "Resource URI is required.")
                }
                let routed = await router.readResource(uri: uri)
                result = [
                    "contents": routed.content.map {
                        ["uri": uri, "mimeType": "application/json", "text": $0["text"] ?? ""]
                    }
                ]
            case "prompts/list":
                result = ["prompts": encodableObject(await router.listPrompts())]
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
            return jsonRpcError(id: id, code: -32602, message: error.code.rawValue)
        } catch {
            return jsonRpcError(id: id, code: -32603, message: error.localizedDescription)
        }
    }

    private static func encodableObject<T: Encodable>(_ value: T) -> Any {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value),
            let object = try? JSONSerialization.jsonObject(with: data)
        else {
            return [:]
        }
        return object
    }

    private static func jsonRpcError(id: Any?, code: Int, message: String) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "error": [
                "code": code,
                "message": message,
            ],
        ]
    }

    private static func write(_ response: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: response, options: []),
            let text = String(data: data, encoding: .utf8)
        else { return }
        FileHandle.standardOutput.write(Data("\(text)\n".utf8))
    }
}
