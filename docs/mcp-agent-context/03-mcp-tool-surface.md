# Step 3: MCP Tool Surface

## Goal

Give agents precise, review-oriented queries instead of dumping the whole diff into context. Each tool should return small, cited slices of analysis: file paths, line numbers, symbol IDs, finding IDs, reasons, and enough metadata for an agent to decide what to inspect next.

All tool responses should use this envelope:

```json
{
  "schemaVersion": 1,
  "snapshotId": "...",
  "repositoryPath": "...",
  "generatedAt": "...",
  "data": {}
}
```

## Tool: `diffuse.list_repositories`

Lists repositories with available review snapshots.

Input:

```json
{}
```

Returns:

- repository id
- repository name
- repository path
- active branch from the snapshot
- latest snapshot id
- updated timestamp
- risk score
- changed file count

Use when an agent needs to choose a workspace.

## Tool: `diffuse.get_review_summary`

Returns the high-level map of the latest review.

Input:

```json
{
  "repositoryPath": "/path/to/repo",
  "snapshotId": "optional"
}
```

Returns:

- branch/base/head
- profile id and display name
- risk score and risk factors
- file counts by classification/status
- top buckets
- needs-attention targets
- skim target count

Use this as the first tool in an agent code-review workflow.

## Tool: `diffuse.list_changed_files`

Lists changed files with analysis metadata.

Input:

```json
{
  "repositoryPath": "/path/to/repo",
  "classification": "source|test|config|documentation|generated|boilerplate|any",
  "needsAttentionOnly": false,
  "limit": 100
}
```

Returns per file:

- path
- status
- additions/deletions
- classification
- bucket ids
- finding count
- symbol count
- changed line ranges
- skimmable flag

## Tool: `diffuse.get_file_context`

Returns all review context for one file.

Input:

```json
{
  "repositoryPath": "/path/to/repo",
  "path": "diffuse/Services.swift",
  "includeHunks": true,
  "includeSymbols": true,
  "includeFindings": true
}
```

Returns:

- file metadata
- hunks and changed line ranges
- symbols in the file
- findings in the file
- review targets in the file
- buckets containing the file

Do not return full file contents by default.

## Tool: `diffuse.find_symbols`

Searches changed symbols.

Input:

```json
{
  "repositoryPath": "/path/to/repo",
  "query": "Auth",
  "semanticArea": "security_authentication",
  "semanticType": "function_definition",
  "contractChangesOnly": false,
  "behavioralDeltasOnly": false,
  "limit": 50
}
```

Returns:

- symbol id
- file path
- name and qualified name
- semantic type and area
- lines
- callees/callers
- relevant metadata
- linked finding/review target ids

Use this when an agent asks "what changed around auth/data/public APIs/tests?"

## Tool: `diffuse.get_symbol_context`

Returns the richest bounded context for a symbol.

Input:

```json
{
  "repositoryPath": "/path/to/repo",
  "symbolId": "...",
  "includeCallers": true,
  "includeCallees": true,
  "includeRelatedFindings": true
}
```

Returns:

- symbol record
- containing file record
- related findings
- related review targets
- caller labels
- callee names
- contract change summary
- behavioral delta summary

Optional later extension: bounded source excerpt from `startLine...endLine`.

## Tool: `diffuse.list_review_targets`

Returns concrete places an agent should inspect.

Input:

```json
{
  "repositoryPath": "/path/to/repo",
  "severity": "info|low|medium|high|any",
  "bucketId": "optional",
  "limit": 25
}
```

Returns:

- priority
- severity
- title
- file path and lines
- reason
- evidence
- source
- linked file/symbol/finding ids when available

This should power "start my review" agent prompts.

## Tool: `diffuse.explain_risk`

Explains why a file, symbol, or whole snapshot is considered risky.

Input:

```json
{
  "repositoryPath": "/path/to/repo",
  "target": {
    "kind": "snapshot|file|symbol",
    "id": "optional",
    "path": "optional"
  }
}
```

Returns:

- risk factors
- matched rules/profile logic
- findings
- semantic metadata evidence
- suggested review checks

This should be deterministic and sourced from existing rules. It should not call an LLM.

## Tool: `diffuse.get_profile_context`

Explains the active `.diffuse.json` or detected built-in profile.

Input:

```json
{
  "repositoryPath": "/path/to/repo"
}
```

Returns:

- profile id/display name
- file classification rules
- buckets
- symbol groups
- enabled deterministic rules
- risk scoring settings

Use this when an agent needs to understand how Diffuse classified the code.

## Tool: `diffuse.get_source_excerpt`

Optional but useful. Returns a bounded source excerpt from the local working tree.

Input:

```json
{
  "repositoryPath": "/path/to/repo",
  "path": "diffuse/Services.swift",
  "startLine": 320,
  "endLine": 380
}
```

Limits:

- max 160 lines
- path must be under an allowed repository
- no binary files
- no files outside the repo root

Return line-numbered text. This is the only initial tool that reads source files directly.

## Tool Naming

Use the `diffuse.` prefix for all tools so agents can distinguish app-provided review context from their own repo tools.

## Acceptance Criteria

- Tool outputs are compact enough to fit agent context.
- Every finding/target/symbol response includes file path and line references.
- Query tools work without opening the macOS UI.
- Invalid repo/path/snapshot inputs return clear MCP errors.
- `get_source_excerpt` enforces repo-root and line-count limits.

