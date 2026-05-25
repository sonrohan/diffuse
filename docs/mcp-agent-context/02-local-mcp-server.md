# Step 2: Local MCP Server Architecture

## Goal

Expose Diffuse's review context to any local agent that supports MCP: Cursor, Antigravity, Codex, Claude Desktop, and similar tools. The macOS app should host and manage the server internally, while the server should only expose local, read-only code-review intelligence by default.

## Recommended Shape

Use a bundled local helper process rather than implementing the MCP protocol directly inside SwiftUI.

Recommended components:

- `diffuse-core`: keep as the Rust AST sidecar.
- `diffuse-mcp`: add a new Rust binary that implements the MCP server.
- macOS app: starts/stops `diffuse-mcp`, writes connection config, and feeds it the snapshot directory path.

Why a helper process:

- MCP SDK support is much better in Rust/TypeScript than in native Swift.
- The app can crash/relaunch independently of the server.
- Agents can connect to a stable process without depending on the SwiftUI lifecycle.
- It keeps protocol parsing, JSON-RPC, and transport concerns out of UI code.

## Transport

Support two modes:

### 1. stdio

This is the most compatible transport for desktop agents.

An agent launches:

```json
{
  "mcpServers": {
    "diffuse": {
      "command": "/Applications/Diffuse.app/Contents/Helpers/diffuse-mcp",
      "args": [
        "--snapshot-dir",
        "/Users/<user>/Library/Application Support/diffuse/review-context"
      ]
    }
  }
}
```

### 2. local HTTP/SSE

Use this for agents that prefer connecting to an already-running app-hosted service.

Suggested default:

```text
127.0.0.1:48736
```

The app should make the port configurable and auto-select a free port if occupied.

## Server Runtime

`diffuse-mcp` should:

1. Accept configuration:
   - `--snapshot-dir`
   - `--transport stdio|http`
   - `--host 127.0.0.1`
   - `--port 48736`
   - `--allow-repo <path>` repeated, optional allowlist
2. Load the manifest and latest snapshots.
3. Watch the snapshot directory for changes.
4. Serve MCP tools and resources from the latest in-memory snapshot.
5. Never mutate source files.

## App Integration

Add a new actor:

```swift
actor MCPServerManager {
    func start(config: MCPServerConfig) async throws
    func stop() async
    func status() async -> MCPServerStatus
    func writeAgentConfig(kind: AgentKind) async throws -> URL
}
```

`MCPServerManager` should be owned by `AppState` or an app-level service singleton. It should start when enabled in settings, not automatically for every user.

## Security Model

Default behavior:

- Bind only to `127.0.0.1`.
- Read only from Diffuse's snapshot directory.
- Do not expose raw file contents unless the tool specifically needs a bounded excerpt.
- Do not run shell commands.
- Do not perform git checkout, git fetch, or writes through MCP.
- Require a user-visible enabled toggle in the macOS app.

Optional later behavior:

- Per-repository allowlist.
- One-time local token for HTTP transport.
- Tool-level permissions for source excerpts.
- "private metadata redaction" mode for paths and author names.

## MCP Resources

Expose these resources:

- `diffuse://repositories`
- `diffuse://repositories/{repoId}/latest`
- `diffuse://snapshots/{snapshotId}/summary`
- `diffuse://snapshots/{snapshotId}/files`
- `diffuse://snapshots/{snapshotId}/symbols`
- `diffuse://snapshots/{snapshotId}/findings`
- `diffuse://snapshots/{snapshotId}/profile`

Resources are useful when agents want bulk context. Tools are for targeted queries.

## Acceptance Criteria

- The app can start and stop the MCP helper.
- The helper can serve `tools/list`, `resources/list`, and at least one query tool over stdio.
- The helper reloads new snapshots without restart.
- HTTP mode binds only to localhost.
- No MCP tool writes to the repository.

