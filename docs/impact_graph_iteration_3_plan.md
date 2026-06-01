# Impact Graph Iteration 3 Plan

## Goal

Make Impact quieter, more contextual, and more exploratory.

The current iteration has the right broad concept, but the UX is still too noisy and not connected tightly enough to the code:

- The graph is not interactive enough.
- Users should be able to focus into any function or symbol, click through its graph, and inspect the relevant code even when it is not part of the PR.
- Current impact summaries are not useful enough.
- Impact items in code files appear grouped near the top of the file instead of near the code they explain.
- File tree icons and tags are unclear.
- Manual tags like `test` add visual noise without explaining impact.
- The sidebar is too noisy.

This iteration should make Impact feel less like a report and more like an interactive code-review navigation layer.

## Product Direction

The central concept should be:

> "Start from a changed symbol, understand its impact, then freely navigate the dependency graph while always seeing the relevant code."

Impact should no longer rely on generic summaries. Instead, it should provide:

- Precise code-local markers.
- A focused graph explorer.
- Clear impact counts in the file tree.
- A quiet review queue.
- Source preview for any selected symbol, including symbols outside the PR.

## Key UX Decisions

### 1. Make the Graph a Real Explorer

The graph should allow users to move through the codebase, not just view a static impact diagram.

Users should be able to:

- Click any node.
- Refocus the graph around that node.
- Move backward/forward through graph focus history.
- See callers and callees for the focused symbol.
- Open the relevant source range for the focused symbol.
- Keep a breadcrumb back to the original changed symbol.

Example graph header:

```text
Graph Focus
Current: HabitViewModel.addHabit(...)
Origin: Habit.addHabit(...) changed in this PR

Path
Habit.addHabit(...) <- HabitViewModel.addHabit(...)
```

Graph controls:

```text
[Back] [Origin] [Focus Selected] [Depth: 1 v] [Callers] [Callees] [Both]
```

Click behavior:

1. Single click selects a node and shows code preview.
2. Double click or `Focus` recenters the graph on that symbol.
3. `Origin` jumps back to the PR-changed symbol.
4. `Open in Review` opens the file/source panel at the symbol range.

### 2. Show Code for Any Selected Symbol

The graph detail panel must show the relevant code for the selected symbol, even if it is not in the PR.

For changed symbols:

- Show the diff hunk.
- Highlight changed lines.
- Show callers/callees around the changed root.

For unchanged symbols:

- Show read-only source excerpt.
- Highlight the function/symbol range.
- Show the call site if the relationship is known.
- Clearly label it as outside the PR.

Example:

```text
Selected symbol
HabitViewModel.addHabit(...)
app/src/main/.../HabitViewModel.kt:L42-L64
Outside this PR

Connection to PR change
Calls Habit.addHabit(...) at L51

[Open file] [Focus graph here]
```

This addresses the core exploration use case: understanding complex code paths even outside the diff.

### 3. Replace Generic Impact Summaries With Useful Review Signals

Current impact summaries are too generic. Replace them with specific, actionable signals.

Avoid:

```text
High impact
10 callers · 5 callees · 3 files
```

Prefer:

```text
Used by UI creation flow and analytics snapshots
10 callers across 3 files · 5 test references
Most relevant: HabitViewModel.addHabit(), DashboardScreen, buildWeeklySnapshots()
```

Impact copy should explain why the reviewer should care.

Signal types:

- UI path affected
- Data model behavior affected
- Persistence path affected
- API/contract surface affected
- Analytics/reporting output affected
- Test coverage weak or missing
- High fan-in utility changed
- Cross-layer dependency changed

Every summary should include one short reason:

```text
Reason: This changed model constructor is used by both UI creation and analytics scoring.
```

If Chobi cannot produce a meaningful reason, do not show a full summary. Show only compact metrics and a graph action.

### 4. Anchor Inline Items to the Correct Code Region

Impact items must appear next to the changed symbol or hunk they describe, not all at the top of the file.

Placement rules:

- If a changed symbol range is known, place its impact marker directly above that symbol's first changed hunk.
- If multiple hunks are inside the same symbol, show one marker at the first hunk and small continuation markers on later hunks.
- If a hunk cannot be mapped to a symbol, place a low-emphasis marker directly above that hunk.
- Never collect all impact items at the top of the file.

Example:

```text
@@ -57,13 +61,22 @@

Impact: Used by UI creation flow and analytics snapshots
10 callers · 3 files · View graph

fun addHabit(...)
```

For dense files, use a compact row:

```text
High impact · UI creation + analytics · 10 callers · View graph
```

The inline marker should be visually quiet and no taller than necessary.

### 5. Redesign File Tree Impact Indicators

The current icons/tags next to file tree items are unclear. Remove manual tags like `test`.

File tree indicators should represent clear impact information only.

Replace arbitrary icons/tags with a consistent impact badge:

```text
HabitViewModel.kt       9
DashboardScreen.kt      3
HabitAnalyticsTest.kt   2
```

The number should mean one thing:

> Number of review-relevant impact signals in this file.

Tooltip/popover:

```text
9 impact signals
6 callers of changed symbols
2 changed high-impact symbols
1 weak test coverage signal
```

Use color only for severity:

- Red: high impact signals present
- Amber: medium impact signals present
- Blue/gray: low impact only

Remove labels like `test` from the tree. A file being a test can be represented by normal file path/name, not a custom tag.

### 6. Quiet the Sidebar

The sidebar should not be a long stream of everything Chobi knows.

New sidebar model:

```text
Review Next
3 high-priority items

1. Habit.addHabit(...)
   UI creation + analytics affected
   10 callers · 3 files

2. buildWeeklySnapshots(...)
   Analytics output affected
   6 callers · weak tests

Show more...
```

Rules:

- Show only top 3-5 review targets by default.
- Collapse low-priority items.
- Remove duplicate sections that answer the same question.
- Do not show raw symbol lists unless the user searches.
- Search results should replace the queue temporarily, not append more noise below it.
- Keep details in the main review panel or graph inspector, not the sidebar.

Sidebar sections should be:

1. Review Next
2. Areas, collapsed by default if noisy
3. Search, only when active

Avoid separate always-visible sections for Impact, Review Next, Areas, Signals, and raw symbols at the same time.

## Graph Explorer Design

### Layout

Use a three-part detail view:

```text
Impact Graph

[Graph canvas]

Selected Symbol
HabitViewModel.addHabit(...)
Outside this PR · app/src/.../HabitViewModel.kt:L42-L64

[Code preview]
```

Recommended structure:

- Left/top: graph canvas
- Right/bottom: selected symbol details and code preview
- Header: origin, current focus, path, graph controls

### Node Design

Node labels should be readable and compact:

```text
Habit.addHabit(...)
HabitViewModel.addHabit(...)
DashboardScreen
```

Node visual states:

- Origin changed symbol: accent ring
- Current focused symbol: filled accent
- Changed in PR: green/change marker
- Outside PR: neutral
- Test symbol/file: subtle checkmark or flask icon only if clear
- Ambiguous/unresolved: muted warning style

Do not use too many icon types. Prefer text and consistent color.

### Edge Design

Edges should indicate direction:

```text
caller -> callee
```

On hover or selection:

```text
HabitViewModel.addHabit() calls Habit.addHabit(...) at L51
Confidence: high
```

For ambiguous edges:

```text
Possible call by symbol name
Type resolution unavailable
```

### Navigation

The graph should maintain:

- Origin changed symbol
- Current focused symbol
- Selected symbol
- Path from selected symbol to origin when available
- Back/forward focus history

This lets users explore without getting lost.

## Code Preview Requirements

The detail panel should support two source modes:

### Diff Mode

Used when selected symbol is part of the PR.

Show:

- Changed hunk
- Symbol range
- Added/removed lines
- Inline impact marker

### Source Mode

Used when selected symbol is outside the PR.

Show:

- Read-only source excerpt
- Symbol range
- Call site line if selected through an edge
- File path and line number

Source mode should be visually distinct from diff mode:

```text
Outside this PR
Read-only source context
```

## Information Architecture

The product should use one primary review prioritization surface:

### Review Next

Purpose:

- Decide what to inspect next.
- Rank changed symbols/files by impact, severity, and test signal.
- Stay quiet by default.

### Impact Evidence

Purpose:

- Explain why a Review Next item matters.
- Appear inline near changed code.
- Power the graph explorer.

### Graph Explorer

Purpose:

- Let users move through dependencies.
- Show source for selected symbols.
- Support deeper code understanding outside the PR.

Do not present Review Next and Impact as parallel top-level queues.

## Data and Service Requirements

### Store Root and Focus Separately

The graph model must distinguish:

- Origin/root changed symbol
- Current focused symbol
- Selected symbol

Suggested model:

```swift
struct ImpactGraphSession: Identifiable, Codable, Hashable {
    let id: UUID
    let originSymbol: SymbolNode
    var focusedSymbol: SymbolNode
    var selectedSymbol: SymbolNode?
    var visibleGraph: ImpactGraph
    var focusHistory: [SymbolNode]
}
```

### Add Source Context Lookup

Impact services need a way to fetch code context for any symbol:

```swift
func sourceContext(for symbol: SymbolNode, relation: ImpactRelationship?) async throws -> SymbolSourceContext
```

Suggested model:

```swift
struct SymbolSourceContext: Codable, Hashable {
    let symbol: SymbolNode
    let filePath: String
    let startLine: Int
    let endLine: Int
    let excerptStartLine: Int
    let excerpt: String
    let isChangedInCurrentPR: Bool
    let changedLineNumbers: Set<Int>
    let callSiteLine: Int?
}
```

### Improve Inline Placement Data

Each impact marker needs a precise placement target:

```swift
struct InlineImpactMarker: Identifiable, Codable, Hashable {
    let id: UUID
    let rootSymbolId: String?
    let filePath: String
    let anchorLine: Int
    let hunkId: String?
    let summary: String
    let metrics: ImpactMetrics
}
```

Markers should be generated from symbol ranges and diff hunk ranges, not file-level aggregation.

## ViewModel Requirements

Add or extend a MainActor ViewModel for graph exploration:

```text
Chobi/ViewModels/ImpactGraphExplorerViewModel.swift
```

Responsibilities:

- Current origin symbol
- Current focused symbol
- Selected graph node
- Focus history
- Graph depth and direction filters
- Loading source context for selected symbol
- Switching between diff mode and source mode
- Exposing quiet sidebar review targets
- Exposing inline marker placement models

Do not add these transient states to `AppState`.

## Implementation Phases

### Phase 1: Reduce Noise and Fix Placement

- Merge Impact and Review Next into one quiet sidebar queue.
- Limit sidebar to top 3-5 review targets by default.
- Remove manual file tree tags like `test`.
- Replace file tree icons/tags with one clear impact count badge.
- Place inline impact markers at symbol/hunk anchor lines instead of top of file.
- Hide generic impact summaries when Chobi cannot produce a useful reason.

This phase makes the current UI less noisy and more understandable.

### Phase 2: Useful Impact Copy

- Replace generic summaries with specific review signals.
- Add reason strings like `Used by UI creation flow and analytics snapshots`.
- Show top affected symbols only when they are meaningfully ranked.
- Add empty/low-confidence fallback states instead of overexplaining.

This phase makes impact summaries worth reading.

### Phase 3: Interactive Graph Explorer

- Add focusable graph nodes.
- Add origin/current focus/selected symbol state.
- Add graph focus history.
- Add `Origin`, `Back`, and `Focus Selected` controls.
- Support caller/callee/both direction filters.
- Keep root cause visible while exploring.

This phase turns the graph into an exploration tool.

### Phase 4: Source Preview Outside the PR

- Add source context lookup for any symbol.
- Show diff mode for PR-changed symbols.
- Show read-only source mode for unchanged symbols.
- Highlight symbol ranges and call site lines.
- Add `Open file` and `Focus graph here` actions.

This phase supports the key use case of following impact beyond the PR.

### Phase 5: Polish Graph Readability

- Cap visible nodes and group overflow.
- Improve edge labels and hover details.
- Add confidence labels only where useful.
- Tune node colors and icons.
- Add graph empty/loading/error states.

This phase makes the graph feel clean and reliable.

## Acceptance Criteria

This iteration is successful when:

- The sidebar feels quiet and focused.
- Review Next and Impact no longer compete.
- File tree indicators have one clear meaning.
- Manual tags like `test` are removed from the file tree.
- Inline impact markers appear near the relevant changed hunk/symbol.
- Generic impact summaries are replaced by specific review signals or omitted.
- The graph lets users click any symbol, inspect code, and refocus around that symbol.
- Users can inspect source for symbols outside the PR.
- The original PR-changed symbol remains visible while exploring related symbols.

## Non-Goals

- Full semantic type resolution.
- Whole-repo graph rendering by default.
- Zoekt integration.
- Replacing the main diff viewer.
- Showing every symbol in the sidebar.

## Product Summary

This iteration should make Impact feel like a quiet, contextual navigation system:

1. The sidebar tells the user what to review next.
2. Inline markers explain impact exactly where the relevant code changed.
3. The graph lets users explore dependencies interactively.
4. Selecting any symbol shows the relevant code, even outside the PR.
5. The UI removes noisy tags, duplicate queues, and generic summaries.

The result should be a calmer review surface with a much more powerful drill-down path.
