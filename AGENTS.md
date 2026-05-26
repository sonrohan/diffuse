# AI Coding Agent Guidance: Architecture & Refactoring Standards

Welcome, Agent! This document outlines the core architectural boundaries, state management rules, and development practices you **must** follow when extending or refactoring the **Chobi** codebase.

---

## 🏛️ Reference Guides

Before writing any code or modifying the repository structure, read and absorb these core documents:
1.  **[README.md](README.md)**: High-level overview of the application, technology stack, and module folders.
2.  **[macOS Architecture Guide](docs/macos_architecture_guide.md)**: Deep dive into SwiftUI MVVM, thread-safe actors, and unit testing mock structures.

---

## 🛑 Non-Negotiable Architectural Rules

To preserve the codebase's integrity and keep it modular and testable, observe the following constraints:

### 1. Do Not Bloat `AppState.swift`
*   `AppState` is a **global coordinator and long-running data store**. It is *not* a trash can for view-specific variables.
*   **Never** add transient UI states (like search texts, current selection indexes, popover presentation booleans, or active navigation rails) to `AppState`.
*   Keep `AppState` focused entirely on core app domain data: loaded repositories, active branch summaries, active PRs, and analysis run details.

### 2. Force ViewModels to Hold Transient View State
*   All search queries, category selections, active filters, highlighted detail items, and cycle states must live inside dedicated, decoupled `@Observable` classes under the `ViewModels/` domain folder.
*   Annotate all ViewModels with `@MainActor` to guarantee thread-safe UI state updates on the main thread.

### 3. Keep SwiftUI Views Dumb & Declarative
*   Views must only describe layout and visual representation.
*   **Never** launch raw asynchronous tasks, make database lookups, or perform system/Git terminal actions inside a View builder.
*   Delegate all actions and state queries directly to the View's corresponding **ViewModel** or query them via the view model's environment injection.

### 4. SwiftUI Redraw Trap & `@State` ViewModel Instantiation
*   SwiftUI views are structs that are frequently re-instantiated. If you pass a custom ViewModel directly through a SwiftUI initializer as a raw value, SwiftUI may ignore subsequent state changes on redraws.
*   **Standard Practice**: Always instantiate the ViewModel inside a View using `@State` to guarantee its lifecycle is preserved across view redraws:
    ```swift
    @State private var viewModel = WorkspacePickerViewModel(state: state)
    ```

### 5. Two-Way Bindings with `@Bindable`
*   When a View requires two-way bindings (e.g. `TextField`, `Toggle`) to an `@Observable` ViewModel's properties, wrap the view model reference with the `@Bindable` macro locally:
    ```swift
    @Bindable var viewModel = viewModel
    ```

---

## 📁 Repository Map & Folders

When adding new files, place them strictly inside the corresponding domain subfolders:
*   `Chobi/Core/`: Immutable data models (`Models.swift`), analysis rule engines, and path classification profiles.
*   `Chobi/Services/`: Services contacting Rust sidecars, running shell commands, and global synchronization (`AppState.swift`).
*   `Chobi/ViewModels/`: `@Observable` MainActor classes capturing UI actions and sorting logic.
*   `Chobi/Views/`: Layout-focused declarative views (`ContentView.swift`, panels, sheets).
*   `Tests/`: Unit and integration test suites (located outside `Chobi/` to avoid compilation in the main target).

---

## 🎨 Code Style & Formatting Standards

To ensure a cohesive and readable codebase, Chobi enforces strict code formatting using Apple's official `swift-format` engine.

### 1. Formatting Configuration
*   We use a central [`.swift-format`](.swift-format) configuration at the repository root.
*   **Indentation Rule**: Chobi enforces **4-space indentation** for Swift files to match the existing code layout. Do not use 2-space or tab indentation.

### 2. Available Formatting Scripts
Always check and format your code before pushing or requesting reviews using the provided bash scripts under `scripts/`:
*   **Auto-Format**: Run `./scripts/format.sh` to recursively format all Swift files in-place.
*   **Lint Check**: Run `./scripts/lint.sh` to perform a dry-run check of the codebase's style (this check is enforced by GitHub Actions on every Pull Request and will fail if files violate style rules).
*   **Git Pre-Commit Hook**: Run `./scripts/setup-git-hooks.sh` once to configure a Git hook that automatically runs `swift-format` on staged Swift files whenever you commit.

### 3. Style Exceptions & Ignores
When writing code that explicitly requires exceptions to style rules (e.g., matching external snake_case JSON representations from the Rust sidecar or retaining lowercase application entry points), use standard `swift-format` ignore annotations:
*   `// swift-format-ignore: RuleName` placed directly above the target declaration.
*   *Example*: Use `// swift-format-ignore: AlwaysUseLowerCamelCase` above snake_case API data structures.

---

## ✍️ Commit Message Standards (Conventional Commits)

Chobi enforces the **Conventional Commits 1.0.0** specification. All commit messages and pull request titles MUST follow this structure to facilitate automated changelog generation and semantic versioning.

### 1. Commit Structure
```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

### 2. Primary Types
*   `feat`: Introduces a new feature to the codebase (corresponds to `MINOR` in SemVer).
*   `fix`: Patches a bug in the codebase (corresponds to `PATCH` in SemVer).
*   `docs`: Documentation-only changes.
*   `style`: Changes that do not affect the meaning of the code (formatting, white-space, missing semi-colons, etc.).
*   `refactor`: A code change that neither fixes a bug nor adds a feature.
*   `perf`: A code change that improves performance.
*   `test`: Adding missing tests or correcting existing tests.
*   `build`: Changes that affect the build system or external dependencies (e.g. Xcode project settings, Cargo configurations).
*   `ci`: Changes to CI configuration files and scripts (e.g., GitHub Actions workflows).
*   `chore`: Other changes that do not modify source or test files (e.g., updating `.gitignore`).

### 3. Breaking Changes
A breaking API change (corresponding to `MAJOR` in SemVer) MUST be indicated by adding a `!` immediately after the type/scope, or by including `BREAKING CHANGE:` as a footer entry:
*   *Example with `!`*: `feat(parser)!: rewrite ast node parsing engine`
*   *Example with footer*: 
    ```
    fix: update default repository resolution path
    
    BREAKING CHANGE: the default repository directory has changed from local documents to the system application support directory.
    ```

### 4. Common Scopes
Always use parenthesized scopes to specify the module or component affected when applicable:
*   `feat(views): ...` for visual/UI modifications.
*   `fix(core): ...` for sidecar or analyzer adjustments.
*   `refactor(viewmodel): ...` for reactive view models.
*   `ci(workflow): ...` for GitHub Actions modifications.

---

## 🧪 Testing and Verification Protocol

### Target Constraints
*   Chobi is a native macOS application and utilizes `PBXFileSystemSynchronizedRootGroup` on the `Chobi/` directory. Any file placed inside that directory is automatically compiled as part of the main app target.
*   Because the main target does not link `XCTest`, unit test classes that `import XCTest` will fail to compile if placed inside the `Chobi/` folder.
*   **Rule**: Put all unit tests in the dedicated `Tests/` directory at the project root (e.g., `Tests/ArchitectureTests.swift`). This keeps them in the repository without breaking target compilation.

### Run Verification Commands
Always run local compilation checks before finishing a task:
```bash
xcodebuild -project Chobi.xcodeproj -scheme Chobi -configuration Debug -quiet
```
Confirm the build completes successfully (Exit Code `0`).
