import SwiftUI
import Observation

enum CommitFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case selected = "Selected"
    case mine = "Mine"

    var id: String { rawValue }
}

@Observable
@MainActor
class CommitScopeViewModel {
    var query: String = ""
    var filter: CommitFilter = .all
    
    // Dependency
    let state: AppState
    
    init(state: AppState) {
        self.state = state
    }
    
    var commits: [GitCommit] {
        state.commits
    }
    
    var selectedCommitSha: String? {
        state.selectedCommitSha
    }
    
    var selectedAuthor: String? {
        guard let sha = selectedCommitSha else { return nil }
        return commits.first(where: { $0.sha == sha })?.author
    }
    
    var visibleCommits: [(offset: Int, element: GitCommit)] {
        Array(commits.enumerated())
            .filter { pair in
                switch filter {
                case .all:
                    return true
                case .selected:
                    return pair.element.sha == selectedCommitSha
                case .mine:
                    guard let selectedAuthor else { return false }
                    return pair.element.author == selectedAuthor
                }
            }
            .filter { pair in
                query.isEmpty
                || pair.element.subject.fuzzyContains(query)
                || pair.element.author.fuzzyContains(query)
                || pair.element.sha.fuzzyContains(query)
                || pair.element.date.fuzzyContains(query)
                || "c\(pair.offset + 1)".fuzzyContains(query)
            }
    }
    
    var canGoToPreviousCommit: Bool {
        return selectedCommitSha != nil && !commits.isEmpty
    }
    
    var canGoToNextCommit: Bool {
        if commits.isEmpty { return false }
        if selectedCommitSha == nil { return true }
        if let sha = selectedCommitSha,
           let idx = commits.firstIndex(where: { $0.sha == sha }) {
            return idx < commits.count - 1
        }
        return false
    }
    
    func selectCommit(_ sha: String?) async {
        await state.selectCommit(sha)
    }
    
    func goToPreviousCommit() async {
        guard let sha = selectedCommitSha else { return }
        guard let idx = commits.firstIndex(where: { $0.sha == sha }) else { return }
        if idx == 0 {
            await selectCommit(nil)
        } else {
            await selectCommit(commits[idx - 1].sha)
        }
    }
    
    func goToNextCommit() async {
        if selectedCommitSha == nil {
            if let first = commits.first {
                await selectCommit(first.sha)
            }
        } else if let sha = selectedCommitSha,
                  let idx = commits.firstIndex(where: { $0.sha == sha }) {
            if idx < commits.count - 1 {
                await selectCommit(commits[idx + 1].sha)
            }
        }
    }
}

private extension String {
    func fuzzyContains(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let haystack = localizedLowercase
        let needles = trimmed.localizedLowercase.split(whereSeparator: \.isWhitespace)
        return needles.allSatisfy { haystack.contains($0) }
    }
}
