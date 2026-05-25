# AI Coding Agent Guidance: Architecture & Refactoring Standards

Welcome, Agent! This document outlines the core architectural boundaries, state management rules, and development practices you **must** follow when extending or refactoring the **Diffuse** codebase.

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
*   `diffuse/Core/`: Immutable data models (`Models.swift`), analysis rule engines, and path classification profiles.
*   `diffuse/Services/`: Services contacting Rust sidecars, running shell commands, and global synchronization (`AppState.swift`).
*   `diffuse/ViewModels/`: `@Observable` MainActor classes capturing UI actions and sorting logic.
*   `diffuse/Views/`: Layout-focused declarative views (`ContentView.swift`, panels, sheets).

---

## 🧪 Testing and Verification Protocol

### Target Constraints
*   Diffuse is a native macOS application and utilizes `PBXFileSystemSynchronizedRootGroup` on the `diffuse/` directory. Any file placed inside that directory is automatically compiled as part of the main app target.
*   Because the main target does not link `XCTest`, unit test classes that `import XCTest` will fail to compile if placed inside the `diffuse/` folder.
*   **Rule**: Put all unit tests in the project root directory (e.g., `ArchitectureTests.swift`). This keeps them in the repository without breaking target compilation.

### Run Verification Commands
Always run local compilation checks before finishing a task:
```bash
xcodebuild -project diffuse.xcodeproj -scheme diffuse -configuration Debug -quiet
```
Confirm the build completes successfully (Exit Code `0`).
