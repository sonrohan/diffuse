import AppKit
import Foundation
import Observation

@MainActor
final class MCPServerEnvironment {
    static let shared = MCPServerEnvironment()

    private var server: MCPServerService?

    func server(state: AppState) -> MCPServerService {
        if let server {
            return server
        }
        let query = AgentContextQueryService(
            stateProvider: state,
            persistence: state.coordinator.persistence
        )
        let router = MCPRequestRouter(queryService: query)
        let savedToken = UserDefaults.standard.string(forKey: MCPSettingsStorage.tokenKey)
        let service = MCPServerService(
            router: router, token: savedToken ?? MCPSettingsStorage.newToken())
        server = service
        return service
    }
}

enum MCPSettingsStorage {
    static let enabledKey = "mcpServerEnabled"
    static let tokenKey = "mcpServerToken"

    static func newToken() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }
}

@Observable
@MainActor
class MCPSettingsViewModel {
    var isRunning = false
    var endpointText = "Off"
    var tokenText = ""
    var copiedState: String?
    var allowFileRangeReads = true
    var lineRangeLimit = 250
    var recentEvents: [MCPServerEvent] = []
    var errorMessage: String?

    private let server: MCPServerService

    init(state: AppState) {
        self.server = MCPServerEnvironment.shared.server(state: state)
        Task {
            if UserDefaults.standard.bool(forKey: MCPSettingsStorage.enabledKey) {
                await startPersistedServer()
            } else {
                await refresh()
            }
        }
    }

    var readOnlyPermissionsText: String {
        allowFileRangeReads
            ? "Read-only analysis context and bounded file ranges"
            : "Read-only analysis context only"
    }

    var protocolText: String {
        "MCP Streamable HTTP"
    }

    var authHeaderText: String {
        guard !tokenText.isEmpty else { return "Authorization: Bearer <token>" }
        return "Authorization: Bearer \(tokenText)"
    }

    var connectionSummary: String {
        let endpoint = endpointText == "Off" ? "http://127.0.0.1:<port>/diffuse/mcp" : endpointText
        let token = tokenText.isEmpty ? "<token>" : tokenText
        return """
            Diffuse MCP connection
            Protocol: MCP Streamable HTTP
            URL: \(endpoint)
            Auth header: Authorization: Bearer \(token)
            Scope: read-only local review context
            """
    }

    func refresh() async {
        let status = await server.status
        apply(status)
    }

    func start() {
        Task {
            await startPersistedServer()
        }
    }

    func stop() {
        Task {
            await server.stop()
            UserDefaults.standard.set(false, forKey: MCPSettingsStorage.enabledKey)
            await refresh()
        }
    }

    func rotateToken() {
        Task {
            let status = await server.rotateToken()
            apply(status)
            persistToken(status.token)
        }
    }

    func copyConnectionDetails() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(connectionSummary, forType: .string)
        copiedState = "Connection details copied"
    }

    private func apply(_ status: MCPServerStatus) {
        isRunning = status.isRunning
        endpointText = status.endpoint ?? "Off"
        tokenText = status.token
        recentEvents = status.recentEvents
    }

    private func startPersistedServer() async {
        do {
            let status = try await server.start()
            apply(status)
            persistToken(status.token)
            UserDefaults.standard.set(true, forKey: MCPSettingsStorage.enabledKey)
            errorMessage = nil
        } catch {
            UserDefaults.standard.set(false, forKey: MCPSettingsStorage.enabledKey)
            errorMessage = error.localizedDescription
        }
    }

    private func persistToken(_ token: String) {
        guard !token.isEmpty else { return }
        UserDefaults.standard.set(token, forKey: MCPSettingsStorage.tokenKey)
    }
}
