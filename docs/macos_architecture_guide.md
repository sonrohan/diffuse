# macOS App Architecture Guide: Modern, Standard MVVM

This document outlines the standard, modern architectural patterns for a native macOS application built with SwiftUI. It is designed to ensure the codebase is predictable, testable, and immediately familiar to any experienced Apple platform engineer, while remaining accessible for AI coding agents to refactor.

---

## 1. Core Architectural Paradigm: Modern MVVM

Apple’s modern standard for SwiftUI uses a declarative View driven by a state-retaining, MainActor-isolated **ViewModel** powered by the Swift `Observation` framework.

This architecture ensures a clean unidirectional data flow:
* **Passive View**: Declarative struct layout that reflects view state.
* **Observable ViewModel**: `@Observable` class annotated with `@MainActor` that coordinates view-specific transient state and interaction logic.
* **Service Context**: Asynchronous execution context (such as thread-safe `actor`s) for Git command execution and sidecar communication.

---

## 2. State Management & Data Flow

Avoid static runtime states or forcing the UI layer to poll the file system. Use Apple's native macros to establish unidirectional data flow.

### The `@Observable` Macro (Swift 5.9+)
The modern standard replaces the legacy `ObservableObject` and `@Published` wrappers with a simple compiler macro. 

* **ViewModel Definition:** Mark the class with `@Observable`. Any standard property inside it automatically becomes observable.
* **View Binding:** Use `@Bindable` when a View needs two-way binding (like a text field or toggle) to a ViewModel property.

---

## 3. Reference Architecture Implementation

Below is a predictable, highly testable template for a local developer tool that inspects a directory.

### A. Model Layer
Represents your immutable data structures. Plain structs that conform to `Identifiable`, `Equatable`, and `Codable` where appropriate. Keep models free of business logic or UI concepts.

```swift
import Foundation

struct LocalProject: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let path: URL
    var fileCount: Int
}
```

### B. Service Layer
Handles raw inputs, outputs, processes, and network requests. Defined as `actor`s (for thread-safe concurrency) or classes. Services are stateless or manage systemic states independent of any specific UI view.

```swift
import Foundation

protocol ProjectInspectorServiceProtocol: Sendable {
    func inspectDirectory(at url: URL) async throws -> LocalProject
}

actor ProjectInspectorService: ProjectInspectorServiceProtocol {
    func inspectDirectory(at url: URL) async throws -> LocalProject {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw NSError(domain: "DirectoryError", code: 404, userInfo: [NSLocalizedDescriptionKey: "Directory not found"])
        }
        
        let contents = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        let fileCount = contents.filter { !$0.hasDirectoryPath }.count
        
        return LocalProject(
            name: url.lastPathComponent,
            path: url,
            fileCount: fileCount
        )
    }
}
```

### C. ViewModel Layer
An `@Observable` class running on `@MainActor`. It is responsible for bridging Views and Services, managing view-specific interaction states (such as active selections, filters, search text, error displays, and progress wheels), and executing actions.

```swift
import SwiftUI
import Observation

@Observable
@MainActor
class ProjectInspectorViewModel {
    // Observable UI states
    var selectedPath: String = ""
    var project: LocalProject?
    var isLoading: Bool = false
    var errorMessage: String? = nil
    
    // Dependency injection
    private let service: ProjectInspectorServiceProtocol
    
    init(service: ProjectInspectorServiceProtocol = ProjectInspectorService()) {
        self.service = service
    }
    
    var projectDetails: String {
        guard let project else { return "No project loaded" }
        return "\(project.name) contains \(project.fileCount) files."
    }
    
    func analyzeDirectory() async {
        guard let url = URL(string: selectedPath) ?? URL(fileURLWithPath: selectedPath) else {
            errorMessage = "Invalid directory path URL"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            project = try await service.inspectDirectory(at: url)
        } catch {
            errorMessage = error.localizedDescription
            project = nil
        }
        
        isLoading = false
    }
}
```

### D. View Layer
Purely declarative and layout-focused. Views hold view-local states or view models. They do not invoke service classes directly. All actions are forwarded to the ViewModel.

```swift
import SwiftUI

struct ProjectInspectorView: View {
    @State private var viewModel = ProjectInspectorViewModel()
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                TextField("Repository Path", text: $viewModel.selectedPath)
                    .textFieldStyle(.roundedBorder)
                
                Button("Inspect") {
                    Task {
                        await viewModel.analyzeDirectory()
                    }
                }
                .disabled(viewModel.isLoading)
            }
            
            Divider()
            
            if viewModel.isLoading {
                ProgressView("Analyzing local folder...")
            } else if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
            } else if let project = viewModel.project {
                VStack(alignment: .leading, spacing: 8) {
                    Text(project.name)
                        .font(.title2)
                        .bold()
                    Text("Path: \(project.path.path)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(viewModel.projectDetails)
                        .font(.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.windowBackgroundColor))
                .cornerRadius(8)
            } else {
                Text("Select a folder to begin inspection")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(width: 480, height: 320)
    }
}
```

---

## 4. Separation of Concerns & Best Practices

1. **Keep Views Dumb:** A view should only know *how* to represent visual nodes and lay out elements. It should never perform Git commands, access local directories, or parse raw string payloads. Forward all events to the ViewModel.
2. **ViewModel Survives Redraws:** In SwiftUI, view structs are frequently destroyed and recreated when state modifications occur. Placing ViewModels inside `@State` guarantees the VM instance is preserved across redraws:
   ```swift
   @State private var viewModel = WorkspaceViewModel()
   ```
3. **Use Two-way Bindings via `@Bindable`:** When a child view needs two-way binding to a VM's property, wrap the VM reference with the `@Bindable` macro:
   ```swift
   struct PathInputView: View {
       @Bindable var viewModel: ProjectInspectorViewModel
       var body: some View {
           TextField("Path", text: $viewModel.selectedPath)
       }
   }
   ```
4. **MainActor Execution:** All UI-retaining ViewModels must be annotated with `@MainActor`. This ensures all state transitions and observable property modifications are executed on the Main thread automatically.

---

## 5. Unit Testing the MVVM Structure

Because state and business logic are decoupled from SwiftUI's layout tree, writing unit tests for your ViewModels is straightforward. We can inject mock services to verify standard behaviors and failure cases.

> [!NOTE]
> All unit tests are organized inside the `Tests/` directory at the project root. They are located outside the `Chobi/` directory to prevent the main app target (which doesn't link `XCTest`) from trying to compile them.

```swift
import XCTest
@testable import Chobi

// Mock Service for Unit Testing
class MockProjectService: ProjectInspectorServiceProtocol, @unchecked Sendable {
    var mockResult: LocalProject?
    var shouldFail = false
    
    func inspectDirectory(at url: URL) async throws -> LocalProject {
        if shouldFail {
            throw NSError(domain: "TestError", code: 500, userInfo: [NSLocalizedDescriptionKey: "Mock Inspection Failed"])
        }
        return mockResult ?? LocalProject(name: "MockApp", path: url, fileCount: 42)
    }
}

@MainActor
final class ProjectInspectorViewModelTests: XCTestCase {
    
    func testAnalyzeDirectorySuccess() async {
        let mockService = MockProjectService()
        let expectedProject = LocalProject(name: "MyRepo", path: URL(fileURLWithPath: "/path/to/MyRepo"), fileCount: 15)
        mockService.mockResult = expectedProject
        
        let viewModel = ProjectInspectorViewModel(service: mockService)
        viewModel.selectedPath = "/path/to/MyRepo"
        
        await viewModel.analyzeDirectory()
        
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.project, expectedProject)
        XCTAssertEqual(viewModel.projectDetails, "MyRepo contains 15 files.")
    }
    
    func testAnalyzeDirectoryFailure() async {
        let mockService = MockProjectService()
        mockService.shouldFail = true
        
        let viewModel = ProjectInspectorViewModel(service: mockService)
        viewModel.selectedPath = "/invalid/path"
        
        await viewModel.analyzeDirectory()
        
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.errorMessage, "Mock Inspection Failed")
        XCTAssertNil(viewModel.project)
    }
}
```
