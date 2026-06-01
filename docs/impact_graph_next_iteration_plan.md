# Impact Graph Next Iteration Plan

## Goal

Make Impact feel like part of code review, not a separate sidebar feature.

The current UX has useful raw ingredients, but the workflow is not intuitive enough:

- Impact is isolated in the sidebar instead of integrated into the code review panel.
- Impact items do not clearly explain which code change caused the impact.
- Clicking an impact item jumps users into a dependency list without preserving the originating changed symbol or diff context.
- The feature does not yet provide the promised visual dependency/impact graph as a deeper drill-down.
- **Review Next** and **Impact** currently compete with each other because both appear to be independent prioritization systems.

The next iteration should center the experience around this question:

> "I changed this code. What depends on it, what does it depend on, and where should I review next?"

## Product Direction

Impact should become a contextual review layer.

The left sidebar can still summarize high-impact changed symbols, but the primary entry point should be inside the code review panel near the actual changed code.

The ideal flow:

1. User reviews a changed file.
2. Chobi detects changed symbols in the visible diff.
3. Each meaningful changed symbol gets a compact **Impact Summary** directly in the review panel.
4. User clicks the summary.
5. A detail view opens showing:
    - The core change that caused the impact
    - Direct callers
    - Direct callees
    - Test coverage signals
    - A visual dependency/impact graph
6. Selecting any caller/callee still keeps the original changed symbol visible as the root cause.

## UX Principles

### Put Impact Where Review Happens

The code review panel is the user's main workspace. Impact should appear there first.

Do not make the user discover Impact by scanning a long sidebar list.

### Always Preserve Cause and Effect

Every impact drill-down must answer:

- What changed?
- Where did it change?
- Why is this item impacted?
- How is the impacted item connected to the changed code?

If the user clicks `HabitViewModel`, the UI should still show that the underlying cause is something like:

```text
Changed root
Habit.addHabit(...) changed at Habit.kt:L59-L81

Selected impact
HabitViewModel calls Habit through getWeeklySnapshots()
```

### Prefer Review Guidance Over Raw Graph Data

The graph is a deeper exploration tool. The default should remain a concise review summary.

The user should not need to interpret a graph just to know what to review next.

### Make the Sidebar a Queue, Not the Explanation

The sidebar should help users find high-impact changed symbols. It should not be the only place where Impact is explained.

### Separate Priority From Evidence

**Review Next** should be the single prioritized action queue.

**Impact** should be the evidence that explains why something is in that queue.

Do not present Review Next and Impact as two competing sections with separate rankings. If both exist at once, the user has to decide which list to trust. The product should make that decision for them.

Recommended hierarchy:

```text
Review Next
1. Habit.addHabit(...) changed high-impact model behavior
   Impact: 10 callers · 5 callees · 3 files · 5 tests
   Reason: Used by UI creation flow and analytics snapshots.
   [Review change] [View impact graph]

2. buildWeeklySnapshots(...) affects analytics output
   Impact: 6 callers · 13 callees · 4 files · 1 test
   Reason: Consumes changed Habit priority and weekly target fields.
   [Review change] [View impact graph]
```

In this model, Impact is not a separate destination competing for attention. It is attached to each recommended review action.

## Primary UX Changes

## 1. Add Impact Summaries to the Code Review Panel

In the changed file/diff panel, show a compact impact summary attached to each changed symbol or meaningful diff hunk.

Example:

```text
fun addHabit(...)

Impact: High
10 callers · 5 callees · 3 files · 5 tests
Most affected: HabitViewModel, DashboardScreen, HabitAnalytics
[View Impact]
```

Placement options:

- Inline block above the changed symbol
- Small summary card between diff hunks
- Right-side annotation aligned with the changed function

Recommended first version: an inline compact block above the changed symbol. It is easiest to understand and easiest to implement without requiring a new split-view model.

The summary should include:

- Impact level
- Direct callers count
- Direct callees count
- Touched files count
- Test references count
- Top 2-3 most relevant impacted symbols
- Button to open detail graph

## 2. Add a Review-Level Impact Summary

At the top of the code review panel, add a concise review-wide impact summary.

Example:

```text
Impact Summary
3 high-impact symbols changed
56 total impacted references across 15 files
2 changed symbols have no direct test references

Highest impact:
1. Habit.addHabit(...) - 10 callers
2. buildWeeklySnapshots(...) - 6 callers
3. getWeeklyPlanScore() - 4 callers
```

This gives the user a quick mental model before diving into individual changes.

It should live near the existing review scope/header area, not buried in the sidebar.

## 3. Merge Sidebar Impact Into Review Next

The sidebar should become a compact review queue ranked by impact, severity, and test signal.

Current problem: the sidebar contains both **Impact** and **Review Next**, but it is unclear which one should drive review order.

New structure:

```text
REVIEW NEXT

3 high-priority review targets

Habit.addHabit(...)
High impact · Data model behavior
10 callers · 5 callees · 3 files
Changed in Habit.kt:L59

buildWeeklySnapshots(...)
High impact · Analytics behavior
6 callers · 13 callees · 4 files
Changed in HabitAnalytics.kt:L18

Other Changed Symbols
...
```

Remove the separate sidebar **Impact** section once the Review Next queue includes impact metrics and graph entry points.

If a secondary Impact-only list is still needed temporarily during migration, make it visually subordinate and label it clearly as a filter/view of the same queue:

```text
Filter: High impact only
```

Click behavior:

1. Scroll the diff to the root changed symbol.
2. Highlight the changed symbol/hunk.
3. Open the impact detail panel for that symbol.

The click should not only select the impact item. It must reconnect the user to the core code change that caused the impact.

## 4. Add an Impact Detail Drawer

Clicking **View Impact** opens a detail drawer or inspector.

Recommended layout:

```text
Impact Detail

Changed Root
Habit.addHabit(...)
app/src/main/.../Habit.kt:L59-L81
[Jump to change]

Summary
High impact because this symbol has 10 callers across 3 files.
5 tests reference this path.

Tabs
[Overview] [Callers] [Callees] [Graph] [Tests]
```

### Overview Tab

Show cause and effect together:

```text
Changed root
Habit.addHabit(...) changed default priority and sanitization logic.

Most impacted paths
1. HabitViewModel.addHabit()
   Calls changed constructor path used by UI habit creation.

2. DashboardScreen
   Displays derived habit priority and weekly target data.

3. HabitAnalytics.buildWeeklySnapshots()
   Consumes habit priority and weekly target fields.
```

The overview should include a **Why this matters** line if Chobi can derive one from metadata:

```text
Why this matters
The changed symbol is part of the data model and is consumed by UI and analytics paths.
```

### Callers Tab

Incoming dependencies.

Group by file:

```text
HabitViewModel.kt
  addHabit(...)                  direct caller
  getWeeklySnapshots()           downstream caller

DashboardScreen.kt
  HabitSummaryCard(...)          transitive caller
```

Each row should show:

- Caller symbol
- File path
- Line
- Direct or transitive badge
- Confidence
- Connection path

Example connection path:

```text
HabitViewModel.addHabit() -> Habit.addHabit(...)
```

### Callees Tab

Outgoing dependencies.

Show what the changed root depends on:

```text
Habit.addHabit(...)
  -> name.trim()
  -> coerceIn(...)
  -> Habit(...)
```

This helps answer whether the changed logic is isolated or built on other app behavior.

### Graph Tab

Show a visual graph with the changed root anchored.

Graph requirements:

- Root changed symbol is always centered and visually distinct.
- Callers appear above or left.
- Callees appear below or right.
- Selected node details appear beside or below the graph.
- Clicking any node updates the details, but does not lose the root cause.
- Breadcrumb/path remains visible:

```text
Root: Habit.addHabit(...)
Selected: DashboardScreen
Path: DashboardScreen -> HabitViewModel -> Habit.addHabit(...)
```

Default graph:

- Depth 1
- Max visible nodes: 20
- Group overflow by file/module
- Expand controls for noisy groups

Avoid rendering the full graph by default.

### Tests Tab

Show review-useful test signal:

```text
Tests

Direct references
* HabitAnalyticsTest.buildWeeklySnapshots_usesPriority()

Likely related tests
* HabitAnalyticsTest.kt
* HabitViewModelTest.kt

Coverage signal: Partial
Tests cover analytics usage, but no direct test covers addHabit default priority.
```

## 5. Preserve Root Cause on Impact Item Clicks

This is the most important behavior fix from the feedback.

When the user clicks an impact item, Chobi should show both:

- The selected impacted symbol
- The root changed symbol that caused the impact

Suggested detail header:

```text
Impact path
Changed: Habit.addHabit(...) at Habit.kt:L59
Selected: HabitViewModel at HabitViewModel.kt:L14

Connection
HabitViewModel.addHabit() calls Habit.addHabit(...)
```

If the relationship is transitive:

```text
Connection
DashboardScreen -> HabitViewModel.addHabit() -> Habit.addHabit(...)
```

If Chobi cannot explain the connection confidently:

```text
Connection
Possible reference by symbol name. Exact type resolution unavailable.
```

## Information Architecture

The new UX should have three layers:

### Layer 1: Review Summary

Lives at the top of the code review panel.

Purpose:

- Summarize total impact of the PR.
- Identify the highest-priority review targets.
- Surface missing/weak test signals.
- Explain how much impact influenced the review ranking.

This should use the label **Review Next**, with impact metrics embedded inside each item.

### Layer 2: Inline Symbol Impact Evidence

Lives near changed hunks/functions.

Purpose:

- Explain impact in context.
- Give a local entry point for deeper inspection.
- Support the Review Next recommendation with visible evidence.

### Layer 3: Impact Detail / Graph

Lives in a drawer, inspector, or modal-like panel.

Purpose:

- Let the user explore dependencies and impact paths.
- Show graph visualization.
- Preserve root cause while inspecting impacted symbols.

This is the detail layer behind a Review Next item or inline Impact card.

## Data Requirements

To support this UX, Impact data needs to become root-aware.

Add or derive a root-centered model:

```swift
struct ChangedSymbolImpact: Identifiable, Codable, Hashable {
    let id: UUID
    let rootSymbol: SymbolNode
    let summary: ImpactSummary
    let directCallers: [ImpactRelationship]
    let directCallees: [ImpactRelationship]
    let transitiveCallers: [ImpactRelationship]
    let tests: [ImpactTestReference]
}

struct ImpactRelationship: Identifiable, Codable, Hashable {
    let id: UUID
    let rootSymbolId: String
    let relatedSymbol: SymbolNode
    let direction: ImpactDirection
    let depth: Int
    let path: [SymbolNode]
    let confidence: CallConfidence
    let explanation: String
}
```

Important: impacted items should not be freestanding rows. They should always be attached to a `rootSymbol`.

This avoids the current UX problem where clicking an impact item loses the core change.

## ViewModel Plan

Add a dedicated ViewModel:

```text
Chobi/ViewModels/ImpactReviewViewModel.swift
```

Responsibilities:

- Hold selected root changed symbol
- Hold selected impact relationship
- Hold active tab
- Hold graph depth
- Hold search/filter state
- Coordinate jump-to-diff behavior through existing app state/services
- Expose display-ready summaries for the review panel and sidebar

Do not put this state in `AppState`.

## Service Plan

Extend the existing impact/call graph service work with root-aware queries:

```swift
func impactSummary(for changedSymbol: ChangedSymbol) async -> ChangedSymbolImpact
func impactSummaries(for changedSymbols: [ChangedSymbol]) async -> [ChangedSymbolImpact]
func impactGraph(rootSymbolId: String, depth: Int) async -> ImpactGraph
func relationshipPath(from relatedSymbolId: String, to rootSymbolId: String) async -> [SymbolNode]
```

The important service behavior is not just "find related symbols." It must also explain the path from related symbol back to the changed root.

## Visual Design Notes

The screenshot already has a clean, restrained aesthetic. Preserve that.

Changes should make hierarchy clearer:

- Impact summaries in the review panel should use compact, low-height cards.
- Use a colored left border or small badge for impact level, not large colored blocks.
- Avoid making the sidebar Impact section visually heavier than the diff.
- Use monospaced names for symbols.
- Use muted file paths.
- Keep counts scannable.
- Use direct labels like `Changed root`, `Selected impact`, `Connection`, and `Review next`.

Recommended inline impact card:

```text
| High impact | Habit.addHabit(...)
| 10 callers · 5 callees · 3 files · 5 tests
| Most affected: HabitViewModel, DashboardScreen, HabitAnalytics
| [View graph] [Jump callers]
```

## Implementation Phases

### Phase 1: Make Existing Impact Contextual

- Add review-level Impact Summary to the code review panel.
- Add inline Impact Summary for changed symbols with existing caller/callee data.
- Merge sidebar Impact and Review Next into one prioritized **Review Next** queue.
- Attach impact metrics and graph actions to each Review Next item.
- Update sidebar click behavior to jump to the root changed symbol.
- When an impact row is selected, show the root changed symbol and selected impacted item together.
- Rename sidebar placeholder/search copy from "Search changed symbols" to something clearer, such as "Search review targets."

This phase should make the current feature understandable without changing the indexing model.

### Phase 2: Add Impact Detail Drawer

- Add detail drawer/inspector opened from inline cards and sidebar rows.
- Implement Overview, Callers, Callees, and Tests tabs.
- Show root cause and connection path in every tab.
- Add empty states and confidence messaging.

This phase makes Impact useful for real review.

### Phase 3: Add Visual Graph

- Add Graph tab.
- Center graph on changed root.
- Show callers and callees with grouped overflow.
- Add depth control.
- Keep breadcrumb visible when selecting graph nodes.
- Cap visible nodes to avoid graph clutter.

This phase delivers the requested visual dependency/impact graph without making it the default cognitive burden.

### Phase 4: Improve Relationship Explanations

- Add path explanations for direct and transitive relationships.
- Add confidence labels.
- Improve ambiguous match handling.
- Add "possible reference" language when resolution is syntactic only.

This phase makes the feature trustworthy.

### Phase 5: Review Guidance and Tests

- Add "Review next" ranking based on impact score, changed root, and test signal.
- Add test coverage hints.
- Add missing-direct-test warnings where useful.
- Add ViewModel tests for selection, root preservation, tab state, and impact filtering.
- Add service tests for relationship path construction and cycle handling.

## Acceptance Criteria

The next iteration is successful when:

- A reviewer can see Impact from the code review panel without using the sidebar.
- Review Next and Impact no longer appear as competing sidebar sections.
- Review Next is the single prioritized action queue.
- Impact appears as evidence attached to review targets and as a drill-down graph.
- Clicking a sidebar Impact item scrolls to or highlights the changed code that caused it.
- Opening Impact detail always shows the changed root symbol.
- Clicking an impacted dependency never loses root-cause context.
- The graph view visually shows callers/callees around the changed root.
- The default experience is still readable without opening the graph.
- The UI helps decide what to review next.

## Non-Goals for This Iteration

- Full semantic type resolution.
- Zoekt integration.
- Repo-wide symbol search beyond what is already needed for changed-symbol impact.
- Rendering an unrestricted whole-repo graph.
- Replacing the diff viewer.

## Product Summary

The next iteration should make Impact feel like a code review assistant:

1. Start from the changed code.
2. Summarize impact inline.
3. Let users dive deeper when needed.
4. Preserve the root change throughout exploration.
5. Use the graph as an optional visual explanation, not the main interface.

This directly addresses the current UX gap and makes the feature more useful during real review.
