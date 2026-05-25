# Implementation Prompt

You are working in the Diffuse macOS app repository. Implement the MCP agent-context plan in small, verifiable steps.

Start by reading:

- `AGENTS.md`
- `README.md`
- `docs/macos_architecture_guide.md`
- `docs/mcp-agent-context/01-review-context-data-model.md`
- `docs/mcp-agent-context/02-local-mcp-server.md`
- `docs/mcp-agent-context/03-mcp-tool-surface.md`
- `docs/mcp-agent-context/04-mac-app-ux.md`
- `docs/mcp-agent-context/05-rollout-and-testing.md`
- `diffuse/Core/Models.swift`
- `diffuse/Core/AnalysisProfile.swift`
- `diffuse/Core/AnalysisEngine.swift`
- `diffuse/Services/Services.swift`
- `diffuse/Services/AppState.swift`
- `diffuse/ViewModels/AnalysisViewModel.swift`
- `diffuse/Views/SettingsSheet.swift`
- `diffuse/Views/ContentView.swift`
- `diffuse-core/src/main.rs`
- `diffuse-core/src/analyzer.rs`

Implementation constraints:

- Do not replace the existing analyzer. Reuse `AnalysisDetails`, `ChangedFile`, `ChangedSymbol`, `Finding`, review targets, buckets, profile rules, and `diffuse-core` output.
- Make the MCP feature additive. Existing UI analysis must work when MCP is disabled or broken.
- Keep MCP tools read-only in the first implementation.
- Bind HTTP transport only to localhost if you add it. Prefer stdio first.
- Do not expose full file contents by default. If implementing `diffuse.get_source_excerpt`, enforce repo-root validation and a maximum of 160 lines.
- Use stable JSON schemas with `schemaVersion: 1`.
- Preserve the current MVVM boundaries:
  - `diffuse/Core/`: Codable models and deterministic builders.
  - `diffuse/Services/`: actors/services for persistence, process management, git, sidecars, and synchronization.
  - `diffuse/ViewModels/`: `@MainActor @Observable` transient UI state and actions.
  - `diffuse/Views/`: declarative SwiftUI layout only.
- Do not bloat `AppState` with Agent Access UI state. `AppState` may own or expose long-running services, but tab-local state belongs in `AgentAccessViewModel`.
- Put XCTest files at the project root, not under `diffuse/`.

Suggested milestones:

1. Add Swift models for `ReviewContextSnapshot` and related file/symbol/finding/bucket/target records in `diffuse/Core/ReviewContextModels.swift`.
2. Add `ReviewContextBuilder` in `diffuse/Core/ReviewContextBuilder.swift` to normalize `AnalysisDetails` into a snapshot.
3. Add `ReviewContextStore` in `diffuse/Services/ReviewContextStore.swift` to persist and load latest snapshots under Application Support.
4. Call snapshot publication after successful analysis without changing existing UI behavior.
5. Add a new Rust `diffuse-mcp` binary that reads the snapshot manifest and serves stdio MCP.
6. Implement these MCP tools first:
   - `diffuse.list_repositories`
   - `diffuse.get_review_summary`
   - `diffuse.list_changed_files`
   - `diffuse.get_file_context`
   - `diffuse.list_review_targets`
7. Add symbol-oriented tools:
   - `diffuse.find_symbols`
   - `diffuse.get_symbol_context`
   - `diffuse.explain_risk`
8. Add `MCPServerManager` in `diffuse/Services/MCPServerManager.swift` to start/stop the helper.
9. Add `AgentAccessViewModel` in `diffuse/ViewModels/AgentAccessViewModel.swift`.
10. Add Settings > Agent Access in `diffuse/Views/SettingsSheet.swift` with enable toggle, status, included workspaces, setup snippets, and context preview.
11. Add tests for snapshot building, JSON round-trip, MCP query behavior, path safety, and Agent Access view-model behavior.

Definition of done:

- Running an analysis publishes a review context snapshot.
- Restarting the app preserves the latest snapshot.
- A local MCP client can call the core tools over stdio.
- The Settings UI can enable/disable the local server and copy agent config.
- Existing analysis screens still work with MCP disabled.
- Tests cover the snapshot builder and MCP query logic.
- The app still passes `xcodebuild -project diffuse.xcodeproj -scheme diffuse -configuration Debug -quiet`.
