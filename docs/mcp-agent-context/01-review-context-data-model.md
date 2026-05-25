# Step 1: Review Context Data Model

## Goal

Create one stable, queryable "review context" layer that both the macOS app and the MCP server can read. This plan is revised for the app architecture introduced in `97f271ef80526e1b604e060103eb5786d09933ea`:

- `diffuse/Core/`: immutable Codable models, deterministic builders, analysis rules, and profiles
- `diffuse/Services/`: actors/services for filesystem, process, sidecar, persistence, and app-wide coordination
- `diffuse/ViewModels/`: `@MainActor @Observable` classes for transient UI state and UI actions
- `diffuse/Views/`: declarative SwiftUI layout only

The app already computes most of the raw material:

- changed files and hunks in `ChangedFile`
- AST symbols in `ChangedSymbol`
- semantic metadata from `diffuse-core`
- deterministic findings in `Finding`
- buckets, highlights, skim targets, and review targets in `AnalysisDetails`
- repository/profile mapping through `.diffuse.json` and built-in profiles

This step should avoid inventing a second analyzer. Build a normalized snapshot over the existing analysis output and persist enough of it for fast MCP queries.

## New Concepts

### ReviewContextSnapshot

Add a new file:

```text
diffuse/Core/ReviewContextModels.swift
```

Define Codable models that represent one analysis run as an agent-facing snapshot:

```swift
struct ReviewContextSnapshot: Codable, Identifiable {
    var id: UUID
    var repositoryPath: String
    var repositoryName: String
    var branchName: String
    var baseRef: String
    var headRef: String
    var profileId: String
    var profileDisplayName: String
    var createdAt: Date
    var run: AnalysisRun
    var files: [ReviewContextFile]
    var symbols: [ReviewContextSymbol]
    var findings: [ReviewContextFinding]
    var buckets: [ReviewContextBucket]
    var reviewTargets: [ReviewContextTarget]
    var skimTargets: [ReviewContextTarget]
    var riskHighlights: [ReviewContextHighlight]
    var riskFactors: [String]
}
```

Keep this separate from the UI models even if it initially mirrors them. The MCP contract should not break every time the SwiftUI view models change.

### ReviewContextFile

Agent-facing file entries should include:

- `id`
- `path`
- `status`
- `classification`
- `additions`
- `deletions`
- `hunks`
- `changedLineRanges`
- `symbolIds`
- `findingIds`
- `bucketIds`
- `isSkimmable`
- `needsAttention`

### ReviewContextSymbol

Agent-facing symbols should include:

- `id`
- `filePath`
- `name`
- `qualifiedName`
- `kind`
- `semanticType`
- `semanticArea`
- `startLine`
- `endLine`
- `callees`
- `callers`
- `metadata`
- `contractChanges`
- `behavioralDeltas`
- `findingIds`
- `reviewTargetIds`

Derive `contractChanges` from metadata keys prefixed with `contract_`. Derive `behavioralDeltas` from metadata keys ending with `_added`.

### ReviewContextQueryIndex

Add the in-memory/persistent index as a service actor in:

```text
diffuse/Services/ReviewContextStore.swift
```

Suggested API:

```swift
actor ReviewContextStore {
    func put(_ snapshot: ReviewContextSnapshot) async
    func latest(for repositoryPath: String) async -> ReviewContextSnapshot?
    func snapshot(id: UUID) async -> ReviewContextSnapshot?
    func listRepositories() async -> [ReviewContextRepositorySummary]
}
```

Inside each snapshot, build lookup dictionaries:

- file path to file
- symbol id to symbol
- lowercased symbol name to symbols
- semantic area to symbols
- bucket id to bucket
- finding id to finding
- review target id to target

These can be transient and rebuilt when loading the snapshot.

## Build The Snapshot

Add a pure builder in:

```text
diffuse/Core/ReviewContextBuilder.swift
```

It converts `AnalysisDetails` plus repo/profile metadata into `ReviewContextSnapshot`.

Suggested inputs:

```swift
struct ReviewContextBuildInput {
    var repo: GitRepository
    var branchName: String
    var profile: AnalysisProfile
    var details: AnalysisDetails
}
```

Call it after successful analysis in:

- `AppState.loadDetails(for:)`
- `AppState.analyzeSingleCommit(...)`
- `AppState.reRunAnalysis()`

The builder should not run git or spawn `diffuse-core`; it only normalizes already computed results. This keeps `Core` deterministic and testable.

Publication should be coordinated from `diffuse/Services/AppState.swift` or `AnalysisCoordinator` after analysis completes, but do not put snapshot indexing logic directly in `AppState`. `AppState` should call a service method such as:

```swift
await reviewContextStore.publish(input)
```

## Persistence

Persist the latest snapshot per repository under the app support directory beside the existing JSON store.

Suggested location:

```text
Application Support/diffuse/review-context/<stable-repo-id>/latest.json
```

Also keep a small manifest:

```json
{
  "version": 1,
  "repositories": [
    {
      "repositoryPath": "/path/to/repo",
      "repositoryName": "repo",
      "latestSnapshotId": "...",
      "updatedAt": "..."
    }
  ]
}
```

The MCP server can start before the app has an active UI analysis, so it should be able to answer from the latest persisted snapshot.

## Versioning

Include `schemaVersion: 1` in all MCP-facing response envelopes. Do not expose raw Swift enum names as the only source of truth; serialize stable string values.

## Acceptance Criteria

- A completed analysis produces a `ReviewContextSnapshot`.
- The snapshot round-trips through JSON.
- The latest snapshot can be loaded after app restart.
- Snapshot construction does not alter existing UI behavior.
- Snapshot data includes enough IDs to navigate from file to symbols, findings, buckets, and targets.
- No transient MCP UI state is added to `AppState`.
- Snapshot builder tests live outside `diffuse/`, for example in root-level `ReviewContextTests.swift`, because files under `diffuse/` compile into the app target.
