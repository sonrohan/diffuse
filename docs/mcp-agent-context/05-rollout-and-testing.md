# Step 5: Rollout And Testing Plan

## Implementation Order

1. Add `ReviewContextSnapshot` models and builder.
2. Persist latest snapshots and manifest.
3. Add `diffuse-mcp` helper with stdio transport.
4. Implement read-only MCP resources.
5. Implement core tools:
   - `diffuse.list_repositories`
   - `diffuse.get_review_summary`
   - `diffuse.list_changed_files`
   - `diffuse.get_file_context`
   - `diffuse.list_review_targets`
6. Add symbol tools:
   - `diffuse.find_symbols`
   - `diffuse.get_symbol_context`
   - `diffuse.explain_risk`
7. Add optional bounded source excerpt tool.
8. Add `MCPServerManager` in `diffuse/Services/` to start/stop the helper.
9. Add `AgentAccessViewModel` in `diffuse/ViewModels/`.
10. Add macOS Settings > Agent Access in `diffuse/Views/SettingsSheet.swift`.
11. Add header status and copy-agent-context actions.
12. Add HTTP transport only after stdio works.

## Test Strategy

### Swift Unit Tests

Add tests for:

- snapshot builder maps files, symbols, findings, buckets, and targets correctly
- contract metadata becomes `contractChanges`
- `_added` metadata becomes `behavioralDeltas`
- snapshot JSON round-trip
- stale detection from git fingerprint changes
- `AgentAccessViewModel` state transitions with a mocked MCP manager protocol

Per `AGENTS.md`, XCTest files must live at the project root, not under `diffuse/`. Add files such as:

```text
ReviewContextTests.swift
MCPServerManagerTests.swift
AgentAccessViewModelTests.swift
```

### Rust Unit Tests

For `diffuse-mcp`:

- manifest loading
- snapshot loading
- index construction
- path allowlist checks
- source excerpt line limits
- query filtering

### MCP Protocol Tests

Add fixtures under:

```text
diffuse-mcp/fixtures/
```

Include:

- manifest JSON
- one snapshot JSON
- sample MCP requests/responses

Test:

- `initialize`
- `tools/list`
- `resources/list`
- each tool with valid input
- each tool with invalid repo/path/snapshot input

### App Integration Tests

Manual first, automated later:

- Enable MCP in Settings.
- Confirm status becomes Running.
- Copy stdio config.
- Connect Claude Desktop/Cursor/Codex to the server.
- Ask for `diffuse.get_review_summary`.
- Run a new analysis and confirm agent sees updated snapshot.
- Change working tree and confirm stale indicator appears.

## Packaging

Update the Xcode project build phases to:

1. Build `diffuse-core`.
2. Build `diffuse-mcp`.
3. Copy both into the app bundle helpers/auxiliary executables.

The app should locate `diffuse-mcp` similarly to how `ASTAnalysisService.sidecarURL()` in `diffuse/Services/Services.swift` locates `diffuse-core`, with dev fallbacks:

```text
diffuse-mcp/target/debug/diffuse-mcp
diffuse-mcp/target/release/diffuse-mcp
```

## Backward Compatibility

The MCP feature should be additive:

- Existing analysis views continue to work when MCP is disabled.
- Snapshot persistence failure should not fail analysis.
- Server startup failure should not block app launch.
- Agents should receive a clear "no snapshot available" response instead of crashing.

## Performance Budgets

Initial targets:

- snapshot build under 150 ms for a typical PR
- snapshot load under 100 ms
- `get_review_summary` under 30 ms
- `find_symbols` under 50 ms for a snapshot with 10,000 symbols
- source excerpt under 50 ms

For large repos, do not index every source file for MCP at startup. Use the already computed changed-symbol/caller context first.

## Open Decisions

- Whether HTTP transport needs token auth in the first release.
- Whether source excerpts should be disabled by default.
- Whether the app should install configs into specific agents or only copy snippets.
- Whether snapshots should include commit-specific analysis views or only the latest full review.

Recommendation for v1: ship stdio, read-only tools, copied config snippets, and latest full review snapshots first.

## Acceptance Criteria

- A clean build includes both helper binaries.
- An external MCP client can query a real Diffuse analysis.
- Disabling MCP stops the server and removes HTTP listener if active.
- No tool mutates repository files or app analysis state.
- Stale snapshot state is visible in the macOS app.
- `xcodebuild -project diffuse.xcodeproj -scheme diffuse -configuration Debug -quiet` completes successfully.
