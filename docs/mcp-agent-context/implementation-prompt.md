# Implementation Prompt

You are working in the Diffuse macOS app repository. Implement the MCP agent-context plan in small, verifiable steps.

Start by reading:

- `docs/mcp-agent-context/01-review-context-data-model.md`
- `docs/mcp-agent-context/02-local-mcp-server.md`
- `docs/mcp-agent-context/03-mcp-tool-surface.md`
- `docs/mcp-agent-context/04-mac-app-ux.md`
- `docs/mcp-agent-context/05-rollout-and-testing.md`
- `diffuse/Models.swift`
- `diffuse/Services.swift`
- `diffuse/AppState.swift`
- `diffuse/AnalysisProfile.swift`
- `diffuse/SettingsSheet.swift`
- `diffuse-core/src/main.rs`
- `diffuse-core/src/analyzer.rs`

Implementation constraints:

- Do not replace the existing analyzer. Reuse `AnalysisDetails`, `ChangedFile`, `ChangedSymbol`, `Finding`, review targets, buckets, profile rules, and `diffuse-core` output.
- Make the MCP feature additive. Existing UI analysis must work when MCP is disabled or broken.
- Keep MCP tools read-only in the first implementation.
- Bind HTTP transport only to localhost if you add it. Prefer stdio first.
- Do not expose full file contents by default. If implementing `diffuse.get_source_excerpt`, enforce repo-root validation and a maximum of 160 lines.
- Use stable JSON schemas with `schemaVersion: 1`.

Suggested milestones:

1. Add Swift models for `ReviewContextSnapshot` and related file/symbol/finding/bucket/target records.
2. Add `ReviewContextBuilder` to normalize `AnalysisDetails` into a snapshot.
3. Add `ReviewContextStore` to persist and load latest snapshots under Application Support.
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
8. Add `MCPServerManager` in Swift to start/stop the helper.
9. Add Settings > Agent Access with enable toggle, status, included workspaces, setup snippets, and context preview.
10. Add tests for snapshot building, JSON round-trip, MCP query behavior, and path safety.

Definition of done:

- Running an analysis publishes a review context snapshot.
- Restarting the app preserves the latest snapshot.
- A local MCP client can call the core tools over stdio.
- The Settings UI can enable/disable the local server and copy agent config.
- Existing analysis screens still work with MCP disabled.
- Tests cover the snapshot builder and MCP query logic.

