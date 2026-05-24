# AST Application Layer Plan

Diffuse already has a Tree-sitter sidecar that extracts changed declarations from source files. The next step is to make the application layer use that structure to explain program impact, not just annotate changed lines.

Product framing: GitHub shows the patch. Diffuse should show the program impact.

## Current State

- `diffuse-core` parses supported source files with Tree-sitter and returns changed declaration symbols that overlap changed lines.
- The Swift app stores these as `ChangedSymbol` records with symbol name, kind, source span, semantic type, and metadata.
- The application layer currently uses AST metadata mostly for semantic highlights such as authentication, cryptography, payment, deletion, public type changes, and tests.
- `ChangedSymbol.callers` and `ChangedSymbol.callees` exist in the model, but are not populated.

## 1. Semantic Review Map

Show changed program entities instead of only changed files.

Examples:

- `AuthService.login()`
- `UserRepository.deleteUser()`
- `BillingClient.createCharge()`
- `RulesEngine.calculateRiskScore()`

Application value:

- Give reviewers a high-level map of changed behavior before they inspect the raw diff.
- Group review targets by symbols and semantic areas, not just file paths.
- Let users jump directly to the enclosing function, method, class, struct, protocol, or interface.

Implementation notes:

- Use existing AST symbol spans as first-class review targets.
- Add a symbol-first section to the review map.
- Preserve file-based navigation as the fallback for unsupported languages and non-source files.

## 2. Blast Radius

Populate caller and callee information so Diffuse can explain how far a change may reach.

Application value:

- Surface high fan-in symbols as higher-risk review targets.
- Show direct callers and callees for each changed symbol.
- Explain why a small diff may still be risky.

Example UI copy:

- `calculateRiskScore` is called by 7 symbols across 4 files.
- `deleteUser` calls persistence, audit logging, and authorization helpers.

Implementation notes:

- Extend `diffuse-core` to extract call expressions and references inside each changed symbol.
- Add a repository-level symbol index for supported languages.
- Resolve direct symbol references where possible; fall back to name-based matches when language semantics are ambiguous.
- Populate `ChangedSymbol.callers` and `ChangedSymbol.callees`.

## 3. API And Contract Change Detection

Compare old AST and new AST for public surface changes.

Detect:

- Function or method signature changed.
- Return type changed.
- Visibility changed.
- Public field/property changed.
- Enum case added, removed, or renamed.
- Protocol/interface requirement changed.
- Constructor signature changed.
- Type alias target changed.

Application value:

- Identify breaking or compatibility-sensitive changes that are easy to miss in GitHub.
- Create focused contract review targets.
- Drive more accurate risk scoring for SDK, API, and shared module changes.

Implementation notes:

- Add a sidecar mode that can analyze both base and head versions of a file.
- Emit stable symbol identifiers based on path, enclosing type, symbol name, and signature.
- Add `contract_delta` metadata such as `signature_changed`, `return_type_changed`, or `visibility_changed`.

## 4. Test Coverage Mapping

Connect changed production symbols to related test symbols.

Application value:

- Replace broad “no test files changed” signals with symbol-aware coverage guidance.
- Show when tests changed near the affected behavior.
- Highlight high-risk production changes without corresponding test coverage.

Examples:

- `AuthService.login()` changed; related tests in `AuthServiceTests` were updated.
- `BillingClient.refund()` changed; no tests referencing refund behavior changed.

Implementation notes:

- Use AST symbol names, file naming conventions, and call/reference data to associate tests with production symbols.
- Treat test files as first-class AST inputs instead of file-level evidence only.
- Add review-map evidence that names the related test symbols when found.

## 5. Behavioral Diff Summaries

Classify the kind of code shape change inside each changed symbol.

Detect:

- Control flow changed.
- Error handling added, removed, or changed.
- `async`, `await`, callback, or concurrency behavior changed.
- Persistence write added.
- Network call added.
- Authorization check added or removed.
- Deletion or destructive operation added.
- Logging, metrics, or audit behavior changed.

Application value:

- Help reviewers know what kind of scrutiny is needed.
- Convert raw AST facts into useful review prompts.
- Improve highlight quality without depending on LLM summaries.

Implementation notes:

- Compare selected AST node categories between base and head symbol bodies.
- Emit compact metadata such as `control_flow_changed=true`, `await_added=true`, `throws_removed=true`.
- Keep this deterministic first; LLM summarization can consume these facts later.

## 6. Reviewer Entry Points

Use AST spans to frame review around complete semantic units.

Application value:

- Jump reviewers to the full changed function or type, not only the first changed line.
- Show symbol start and end lines in the UI.
- Allow “review this symbol” interactions that include the enclosing context.

Implementation notes:

- Use existing `startLine` and `endLine` on `ChangedSymbol`.
- Prefer symbol span navigation for source files.
- Continue using hunk navigation for non-source files and unsupported languages.

## 7. Architectural Rules

Use AST import declarations, symbol kinds, and file ownership to enforce architectural boundaries.

Detect:

- UI importing database or infrastructure layers.
- Feature modules reaching across boundaries.
- Tests importing production internals that should stay private.
- Platform-specific code leaking into shared code.
- Hand-edited generated files.
- Backend-only dependencies imported into frontend code.

Application value:

- Provide local architectural feedback before review.
- Surface violations that GitHub does not understand.
- Make rule evidence precise: import name, source file, and affected symbol.

Implementation notes:

- Extend sidecar output with imports and top-level declarations.
- Add configurable boundary rules later; start with hard-coded local heuristics.
- Attach architecture findings to exact import lines where possible.

## 8. Risk Scoring Based On Code Shape

Move risk scoring from path-heavy heuristics toward AST-backed evidence.

Signals:

- Public symbol changed.
- High fan-in symbol changed.
- Critical semantic area changed.
- Function grew substantially.
- Control flow changed.
- Error handling changed.
- Async/concurrency behavior changed.
- Persistence write, network call, auth check, payment, or deletion behavior changed.
- Production symbol changed without related test symbol change.

Application value:

- Make the risk score more explainable and less noisy.
- Reduce false positives from path names alone.
- Raise small but consequential semantic changes.

Implementation notes:

- Add risk factors directly from AST metadata.
- Keep each scoring contribution explainable in `RiskBreakdown.factors`.
- Prefer additive, evidence-backed scoring over opaque aggregate labels.

## Required Fixes

### Fix 1. Preserve Symbol-To-File Mapping In Rules

Problem:

- `runDeterministicRules` receives parsed diff files and symbols, but not the `ChangedFile` records that map `changedFileId` to paths.
- There is a placeholder filter using `UUID()` that can never match.
- AST rule findings fall back to `files.first` or nonexistent `file_path` metadata.

Plan:

- Change deterministic rule input to include either `[ChangedFile]` or a `[UUID: String]` file path map.
- Resolve each symbol path from `sym.changedFileId`.
- Remove the placeholder frontend import block or implement it with the real file map.
- Stop depending on `sym.metadata["file_path"]` unless the sidecar explicitly emits it.

Acceptance criteria:

- AST findings are attached to the correct changed file.
- No rule uses `files.first` as a fallback for symbol-specific findings.
- The placeholder `changedFileId == UUID()` logic is gone.

### Fix 2. Populate Or Remove Caller/Callee Risk Logic

Problem:

- `ChangedSymbol.callers` and `ChangedSymbol.callees` exist, and risk scoring checks `callers.count > 5`, but callers are never populated.
- This makes the coupling risk factor effectively dead code.

Plan:

- Preferred: implement caller/callee extraction and repository-level reference indexing.
- Interim: remove or disable caller-count scoring until the data is real.
- Add tests that prove high fan-in symbols affect risk only when caller data exists.

Acceptance criteria:

- Risk scoring no longer depends on permanently empty fields.
- If caller/callee extraction is implemented, the UI displays direct impact evidence.

## Suggested Delivery Order

1. Fix symbol-to-file mapping in deterministic rules.
2. Remove or gate dead caller/callee scoring.
3. Add symbol-first review map using existing AST spans.
4. Add AST-backed contract change detection for public symbols.
5. Add behavioral diff metadata for control flow, errors, async, writes, and network calls.
6. Populate direct callees inside changed symbols.
7. Build repository-level caller lookup for blast radius.
8. Add test coverage mapping from changed production symbols to test symbols.
9. Move risk scoring to the new AST-backed evidence.
10. Add architectural import rules.

## Success Criteria

- A developer can open Diffuse and immediately understand which program behaviors changed.
- Review targets are symbol-first for supported source files.
- Risk highlights explain impact using AST facts, not only filenames or text snippets.
- The app surfaces blast radius, contract changes, and missing test coverage in ways GitHub cannot.
- Every AST-driven finding points to the correct file and source span.
