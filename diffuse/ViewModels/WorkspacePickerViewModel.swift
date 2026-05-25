import SwiftUI
import Observation

enum WorkspaceFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case auto = "Auto"
    case manual = "Manual"

    var id: String { rawValue }
}

@Observable
@MainActor
class WorkspacePickerViewModel {
    var query: String = ""
    var filter: WorkspaceFilter = .all
    
    // Dependencies
    let state: AppState
    
    init(state: AppState) {
        self.state = state
    }
    
    var repositories: [GitRepository] {
        state.repositories
    }
    
    var selectedRepoId: UUID? {
        state.selectedRepoId
    }
    
    var selectedRepo: GitRepository? {
        state.selectedRepo
    }
    
    var visibleRepositories: [GitRepository] {
        repositories
            .filter { repo in
                switch filter {
                case .all: true
                case .auto: repo.autoAnalyzeEnabled
                case .manual: !repo.autoAnalyzeEnabled
                }
            }
            .filter { repo in
                query.isEmpty 
                || repo.name.fuzzyContains(query) 
                || repo.path.fuzzyContains(query)
            }
            .sorted { lhs, rhs in
                if lhs.id == selectedRepoId { return true }
                if rhs.id == selectedRepoId { return false }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }
    
    func selectRepo(_ repoId: UUID) async {
        await state.selectRepo(repoId)
    }
    
    func renameWorkspace(id: UUID, newName: String) async {
        await state.renameWorkspace(id: id, newName: newName)
    }
    
    func setWorkspaceAutoAnalyze(id: UUID, enabled: Bool) async {
        await state.setWorkspaceAutoAnalyze(id: id, enabled: enabled)
    }
    
    func removeWorkspace(id: UUID) async {
        await state.coordinator.deleteRepository(id: id)
        await state.load()
    }
    
    func addAndAnalyzeRepo(path: String, baseRef: String?, autoAnalyzeEnabled: Bool) async {
        await state.analyzeRepo(path: path, baseRef: baseRef, autoAnalyzeEnabled: autoAnalyzeEnabled)
    }
}

// Helper fuzzy search implementation matching ContentView's logic
private extension String {
    func fuzzyContains(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let haystack = localizedLowercase
        let needles = trimmed.localizedLowercase.split(whereSeparator: \.isWhitespace)
        return needles.allSatisfy { haystack.contains($0) }
    }
}
