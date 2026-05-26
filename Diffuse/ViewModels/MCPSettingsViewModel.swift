import AppKit
import Foundation
import Observation

enum MCPConfigurationTab: String, CaseIterable, Identifiable {
    case claudeCode = "Claude Code"
    case codex = "Codex"
    case manual = "Manual"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .claudeCode:
            "sparkles"
        case .codex:
            "terminal"
        case .manual:
            "curlybraces.square"
        }
    }

    var title: String {
        switch self {
        case .claudeCode:
            "Claude Code"
        case .codex:
            "Codex"
        case .manual:
            "Custom"
        }
    }

    var subtitle: String {
        switch self {
        case .claudeCode:
            "One terminal command"
        case .codex:
            "Register with the CLI"
        case .manual:
            "Drop-in JSON config"
        }
    }
}

@Observable
@MainActor
class MCPSettingsViewModel {
    var selectedConfiguration: MCPConfigurationTab = .codex
    var copiedState: String?

    private let appExecutablePath = "/Applications/Diffuse.app/Contents/MacOS/diffuse"

    init(state _: AppState) {}

    var configurationSnippet: String {
        switch selectedConfiguration {
        case .claudeCode:
            """
            claude mcp add diffuse --transport stdio -- "\(appExecutablePath)" "--mcp-server"
            """
        case .codex:
            """
            codex mcp add diffuse -- "\(appExecutablePath)" "--mcp-server"
            """
        case .manual:
            """
            {
              "mcpServers": {
                "diffuse": {
                  "command": "\(appExecutablePath)",
                  "args": ["--mcp-server"],
                  "env": {}
                }
              }
            }
            """
        }
    }

    var configurationHelpText: String {
        switch selectedConfiguration {
        case .claudeCode:
            "Run this command in Terminal to add Diffuse MCP to Claude Code."
        case .codex:
            "Run this command in Terminal to add Diffuse MCP to Codex."
        case .manual:
            "Add this JSON to your AI tool's MCP configuration file."
        }
    }

    var aboutText: String {
        "MCP lets AI coding tools query Diffuse's local review context through a stdio process. Agents can list workspaces, inspect review plans, explain files and symbols, search analyzed context, and read bounded file ranges."
    }

    func copyConfiguration() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(configurationSnippet, forType: .string)
        copiedState = "Configuration copied"
    }
}
