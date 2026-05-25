# Step 4: macOS App UX

## Goal

Make the MCP capability visible, controllable, and trustworthy inside the app without turning Diffuse into a server administration tool. The UX should answer:

- Is agent access enabled?
- Which repositories can agents query?
- How does an agent connect?
- What context was last published?
- Is the server healthy?

## Settings: New "Agent Access" Tab

Update:

```text
diffuse/Views/SettingsSheet.swift
```

Add a fourth tab to `SettingsSheet.SettingsTab`:

```swift
case agentAccess = "Agent Access"
```

Icon: `point.3.connected.trianglepath.dotted` or `server.rack`.

Do not put the Agent Access tab's transient state directly in `SettingsSheet`. Add:

```text
diffuse/ViewModels/AgentAccessViewModel.swift
```

The view model should be `@Observable` and `@MainActor`, matching the current `WorkspacePickerViewModel`, `BranchPickerViewModel`, `CommitScopeViewModel`, and `AnalysisViewModel` pattern.

Suggested responsibilities:

- selected workspace for the Agent Access tab
- selected setup snippet kind
- copied/config banner state
- server status polling result
- included workspace toggles
- start/stop/restart actions that call `MCPServerManager`
- generated config snippets

### Primary Controls

Top status section:

- toggle: "Enable local MCP server"
- status badge: Off, Starting, Running, Error
- transport selector: stdio config, local HTTP, or both
- port field for HTTP mode
- button: Restart Server

Keep copy short and concrete:

```text
Local agents can query Diffuse's review map, AST symbols, findings, and profile rules.
```

### Repository Access

Add a table/list of registered workspaces:

- repo name
- repo path
- latest snapshot timestamp
- included/excluded toggle
- risk score and changed file count

Default: only the selected workspace is included the first time the user enables MCP. Let the user include all later.

### Agent Setup

Provide setup blocks for common agents:

- Claude Desktop
- Cursor
- Codex
- Generic MCP stdio
- Generic local HTTP

Each block should show:

- server name: `diffuse`
- command path
- args
- config file destination if known
- copy button
- reveal helper path button

Do not auto-edit third-party config files until the user explicitly clicks an install button.

### Published Context Preview

Show a compact preview for the selected workspace:

- snapshot timestamp
- branch
- base/head
- profile
- changed files
- symbols
- findings
- review targets

Add a "Refresh Analysis" button that calls the existing analysis path.

## Main Header Indicator

In `diffuse/Views/ContentView.swift`, update `AppHeaderView` to show a small MCP status control near Settings when enabled:

- icon: `server.rack`
- green dot when running
- yellow when stale/error
- tooltip: "MCP server running: 2 workspaces published"

Clicking opens Settings > Agent Access. If the existing settings sheet cannot be opened to a specific tab yet, add a small view-model-friendly routing hook rather than adding more global UI state to `AppState`.

## Review UI Integration

Add a small "Ask Agent" or "Copy Agent Context" menu from views under `diffuse/Views/`:

- file header in the diff view
- review target row
- symbol group row

Actions:

- Copy MCP query prompt for this file/target/symbol
- Copy symbol id
- Copy file path and line range

Example copied prompt:

```text
Use the Diffuse MCP server. Call diffuse.get_file_context for repo "/path/to/repo" and path "diffuse/Services/Services.swift", then review the returned findings, symbols, and targets before inspecting source.
```

This helps bridge the mac app's visual workflow with external agents.

## Freshness And Staleness

Agents should not silently rely on stale context. The UI should show:

- latest analysis time
- whether working tree changed since publication
- whether auto-analyze is enabled

Reuse the existing git fingerprint watcher. When the fingerprint changes, mark the published snapshot stale until analysis reruns.

## Error States

Display practical errors:

- helper binary missing
- port in use
- snapshot directory unreadable
- no published repositories
- server crashed

Each should include one direct action where possible:

- Build Helper
- Choose Another Port
- Run Analysis
- Restart Server

## Acceptance Criteria

- A user can enable MCP from Settings without reading docs.
- The app shows which workspaces are exposed.
- The app can copy a valid stdio MCP config.
- The main header makes server status discoverable.
- The app marks published context stale when the repo changes.
- `AgentAccessViewModel` holds tab state and actions.
- SwiftUI views remain declarative and do not run git, filesystem, or helper-process code directly.
