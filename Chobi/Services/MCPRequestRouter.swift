import Foundation

struct MCPToolRegistration: Codable, Equatable, Identifiable, Sendable {
    var id: String { name }
    var name: String
    var description: String
    var inputSchema: [String: String]
}

struct MCPResourceRegistration: Codable, Equatable, Identifiable, Sendable {
    var id: String { uri }
    var uri: String
    var name: String
    var description: String
    var mimeType: String
}

struct MCPPromptRegistration: Codable, Equatable, Identifiable, Sendable {
    var id: String { name }
    var name: String
    var description: String
}

struct MCPRouteResult: Codable, Equatable, Sendable {
    var content: [[String: String]]
    var isError: Bool?
}

struct MCPPromptResult: Codable, Equatable, Sendable {
    var description: String
    var messages: [MCPPromptMessage]
}

struct MCPPromptMessage: Codable, Equatable, Sendable {
    var role: String
    var content: [String: String]
}

actor MCPRequestRouter {
    private let queryService: AgentContextQueryService
    private let encoder: JSONEncoder

    init(queryService: AgentContextQueryService) {
        self.queryService = queryService
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    }

    nonisolated static let tools: [MCPToolRegistration] = [
        MCPToolRegistration(
            name: "chobi.list_workspaces",
            description: "List registered Chobi workspaces and latest analysis status.",
            inputSchema: ["includeInactive": "boolean"]),
        MCPToolRegistration(
            name: "chobi.get_current_review_context",
            description: "Return bounded review context for the selected workspace analysis.",
            inputSchema: detailSchema),
        MCPToolRegistration(
            name: "chobi.get_run_review_context",
            description: "Return bounded review context for a specific analysis run.",
            inputSchema: detailSchema.merging(["runId": "string"], uniquingKeysWith: { $1 })),
        MCPToolRegistration(
            name: "chobi.explain_file",
            description: "Explain why a changed file matters in the analysis.",
            inputSchema: ["runId": "string?", "path": "string"]),
        MCPToolRegistration(
            name: "chobi.explain_symbol",
            description: "Explain a changed symbol and AST/profile metadata.",
            inputSchema: ["runId": "string?", "symbolName": "string"]),
        MCPToolRegistration(
            name: "chobi.search_review_context",
            description: "Search analyzed review context, not raw repository text.",
            inputSchema: ["query": "string", "types": "string[]", "limit": "integer"]),
        MCPToolRegistration(
            name: "chobi.get_review_plan",
            description: "Return ordered review targets, buckets, highlights, and skim targets.",
            inputSchema: ["runId": "string?", "focus": "string"]),
        MCPToolRegistration(
            name: "chobi.get_profile_context",
            description: "Explain the active analysis profile.",
            inputSchema: ["workspaceId": "string?", "runId": "string?", "includeRules": "boolean"]),
        MCPToolRegistration(
            name: "chobi.read_file_range",
            description: "Read a bounded line range from a workspace file.",
            inputSchema: [
                "workspaceId": "string?", "path": "string", "startLine": "integer",
                "endLine": "integer",
            ]),
    ]

    nonisolated static let resources: [MCPResourceRegistration] = [
        MCPResourceRegistration(
            uri: "chobi://workspaces", name: "Workspaces",
            description: "Registered workspaces and latest run status.",
            mimeType: "application/json"),
        MCPResourceRegistration(
            uri: "chobi://workspace/current/current-run", name: "Current Run",
            description: "Current selected review context.", mimeType: "application/json"),
        MCPResourceRegistration(
            uri: "chobi://run/current/summary", name: "Current Summary",
            description: "Current run summary.", mimeType: "application/json"),
        MCPResourceRegistration(
            uri: "chobi://run/current/review-plan", name: "Current Review Plan",
            description: "Current ordered review plan.", mimeType: "application/json"),
        MCPResourceRegistration(
            uri: "chobi://run/current/profile", name: "Current Profile",
            description: "Current profile context.", mimeType: "application/json"),
        MCPResourceRegistration(
            uri: "chobi://run/current/files", name: "Current Files",
            description: "Current changed file contexts.", mimeType: "application/json"),
        MCPResourceRegistration(
            uri: "chobi://run/current/symbols", name: "Current Symbols",
            description: "Current changed symbol contexts.", mimeType: "application/json"),
        MCPResourceRegistration(
            uri: "chobi://run/current/findings", name: "Current Findings",
            description: "Current deterministic findings.", mimeType: "application/json"),
    ]

    nonisolated static let prompts: [MCPPromptRegistration] = [
        MCPPromptRegistration(
            name: "chobi.review_change",
            description: "Use Chobi context to review a change."),
        MCPPromptRegistration(
            name: "chobi.understand_change",
            description: "Summarize a change using buckets, symbols, and profile evidence."),
        MCPPromptRegistration(
            name: "chobi.write_review_comment",
            description: "Ground review comments in Chobi findings, files, and symbols."),
    ]

    private nonisolated static let detailSchema: [String: String] = [
        "detailLevel": "summary|standard|full",
        "includeFiles": "boolean",
        "includeSymbols": "boolean",
        "maxItems": "integer",
    ]

    func listTools() -> [MCPToolRegistration] {
        Self.tools
    }

    func listResources() -> [MCPResourceRegistration] {
        Self.resources
    }

    func listPrompts() -> [MCPPromptRegistration] {
        Self.prompts
    }

    func callTool(name: String, arguments: [String: Any]) async -> MCPRouteResult {
        do {
            switch name {
            case "chobi.list_workspaces":
                return try success(await listWorkspaces(arguments))
            case "chobi.get_current_review_context":
                return try success(
                    await queryService.currentReviewContext(options: options(arguments)))
            case "chobi.get_run_review_context":
                let runId = try requiredUUID(arguments, "runId")
                return try success(
                    await queryService.runReviewContext(runId: runId, options: options(arguments)))
            case "chobi.explain_file":
                return try success(
                    await queryService.explainFile(
                        runId: optionalUUID(arguments, "runId"),
                        path: requiredString(arguments, "path"),
                        includeHunks: bool(arguments, "includeHunks", default: true),
                        includeSymbols: bool(arguments, "includeSymbols", default: true),
                        includeFindings: bool(arguments, "includeFindings", default: true),
                        maxHunkLines: int(arguments, "maxHunkLines", default: 120)
                    )
                )
            case "chobi.explain_symbol":
                return try success(
                    await queryService.explainSymbol(
                        runId: optionalUUID(arguments, "runId"),
                        path: optionalString(arguments, "path"),
                        symbolName: requiredString(arguments, "symbolName"),
                        line: optionalInt(arguments, "line"),
                        includeCallers: bool(arguments, "includeCallers", default: true),
                        includeCallees: bool(arguments, "includeCallees", default: true)
                    )
                )
            case "chobi.search_review_context":
                return try success(
                    await queryService.searchReviewContext(
                        runId: optionalUUID(arguments, "runId"),
                        query: requiredString(arguments, "query"),
                        types: stringArray(arguments, "types", default: []),
                        limit: int(arguments, "limit", default: 20)
                    )
                )
            case "chobi.get_review_plan":
                return try success(
                    await queryService.reviewPlan(
                        runId: optionalUUID(arguments, "runId"),
                        focus: string(arguments, "focus", default: "all")
                    )
                )
            case "chobi.get_profile_context":
                return try success(
                    await queryService.profileContext(
                        workspaceId: optionalUUID(arguments, "workspaceId"),
                        runId: optionalUUID(arguments, "runId"),
                        includeRules: bool(arguments, "includeRules", default: true)
                    )
                )
            case "chobi.read_file_range":
                return try success(
                    await queryService.readFileRange(
                        workspaceId: optionalUUID(arguments, "workspaceId"),
                        path: requiredString(arguments, "path"),
                        startLine: int(arguments, "startLine", default: 1),
                        endLine: int(arguments, "endLine", default: 1),
                        revision: string(arguments, "revision", default: "working")
                    )
                )
            default:
                throw AgentContextError(
                    code: .unsupportedQuery, message: "Unknown MCP tool: \(name)")
            }
        } catch let error as AgentContextError {
            return errorResult(error)
        } catch {
            return errorResult(
                AgentContextError(code: .invalidArguments, message: error.localizedDescription))
        }
    }

    func readResource(uri: String) async -> MCPRouteResult {
        do {
            switch uri {
            case "chobi://workspaces":
                return try success(await queryService.listWorkspaces())
            case "chobi://workspace/current/current-run",
                "chobi://run/current/summary",
                "chobi://run/current/files",
                "chobi://run/current/symbols",
                "chobi://run/current/findings":
                return try success(
                    await queryService.currentReviewContext(
                        options: AgentContextOptions(
                            detailLevel: .standard, includeFiles: true, includeSymbols: true)))
            case "chobi://run/current/review-plan":
                return try success(await queryService.reviewPlan(runId: nil, focus: "all"))
            case "chobi://run/current/profile":
                return try success(
                    await queryService.profileContext(
                        workspaceId: nil, runId: nil, includeRules: true))
            default:
                throw AgentContextError(
                    code: .unsupportedQuery, message: "Unknown resource URI: \(uri)")
            }
        } catch let error as AgentContextError {
            return errorResult(error)
        } catch {
            return errorResult(
                AgentContextError(code: .invalidArguments, message: error.localizedDescription))
        }
    }

    func getPrompt(name: String) throws -> MCPPromptResult {
        let text: String
        switch name {
        case "chobi.review_change":
            text =
                "Call chobi.get_review_plan first, inspect high-risk files with chobi.explain_file, then produce review findings grounded in file, line, symbol, or rule evidence."
        case "chobi.understand_change":
            text =
                "Call chobi.get_current_review_context and summarize the change using buckets, changed symbols, findings, skim targets, and profile evidence."
        case "chobi.write_review_comment":
            text =
                "Use Chobi findings and symbol/file explanations. Each review comment should cite a path and line range when available."
        default:
            throw AgentContextError(code: .unsupportedQuery, message: "Unknown prompt: \(name)")
        }
        return MCPPromptResult(
            description: name,
            messages: [MCPPromptMessage(role: "user", content: ["type": "text", "text": text])]
        )
    }

    private func listWorkspaces(_ arguments: [String: Any]) async throws -> [AgentWorkspaceSummary]
    {
        await queryService.listWorkspaces(
            includeInactive: bool(arguments, "includeInactive", default: true))
    }

    private func options(_ arguments: [String: Any]) throws -> AgentContextOptions {
        let detail = string(arguments, "detailLevel", default: "standard")
        guard let detailLevel = AgentContextDetailLevel(rawValue: detail) else {
            throw AgentContextError(code: .invalidArguments, message: "Invalid detailLevel.")
        }
        return AgentContextOptions(
            detailLevel: detailLevel,
            includeFiles: bool(arguments, "includeFiles", default: true),
            includeSymbols: bool(arguments, "includeSymbols", default: false),
            maxItems: int(arguments, "maxItems", default: 30)
        )
    }

    private func errorResult(_ error: AgentContextError) -> MCPRouteResult {
        let payload = [
            "schemaVersion": AgentContextBuilder.schemaVersion,
            "source": "chobi",
            "errorCode": error.code.rawValue,
            "message": error.message,
        ]
        return MCPRouteResult(
            content: [["type": "text", "text": jsonText(payload)]], isError: true)
    }

    private func success<T: Encodable>(_ value: T) throws -> MCPRouteResult {
        MCPRouteResult(content: [["type": "text", "text": try encodeText(value)]])
    }

    private func encodeText<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func jsonText(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
            let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return text
    }

    private func requiredString(_ args: [String: Any], _ key: String) throws -> String {
        guard let value = args[key] as? String, !value.isEmpty else {
            throw AgentContextError(code: .invalidArguments, message: "\(key) is required.")
        }
        return value
    }

    private func optionalString(_ args: [String: Any], _ key: String) -> String? {
        args[key] as? String
    }

    private func string(_ args: [String: Any], _ key: String, default defaultValue: String)
        -> String
    {
        optionalString(args, key) ?? defaultValue
    }

    private func bool(_ args: [String: Any], _ key: String, default defaultValue: Bool) -> Bool {
        args[key] as? Bool ?? defaultValue
    }

    private func int(_ args: [String: Any], _ key: String, default defaultValue: Int) -> Int {
        if let value = args[key] as? Int { return value }
        if let value = args[key] as? Double { return Int(value) }
        return defaultValue
    }

    private func optionalInt(_ args: [String: Any], _ key: String) -> Int? {
        guard args[key] != nil else { return nil }
        return int(args, key, default: 0)
    }

    private func stringArray(_ args: [String: Any], _ key: String, default defaultValue: [String])
        -> [String]
    {
        args[key] as? [String] ?? defaultValue
    }

    private func requiredUUID(_ args: [String: Any], _ key: String) throws -> UUID {
        guard let uuid = UUID(uuidString: try requiredString(args, key)) else {
            throw AgentContextError(code: .invalidArguments, message: "\(key) must be a UUID.")
        }
        return uuid
    }

    private func optionalUUID(_ args: [String: Any], _ key: String) throws -> UUID? {
        guard let value = optionalString(args, key), !value.isEmpty else { return nil }
        guard let uuid = UUID(uuidString: value) else {
            throw AgentContextError(code: .invalidArguments, message: "\(key) must be a UUID.")
        }
        return uuid
    }
}
