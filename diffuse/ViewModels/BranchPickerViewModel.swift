import Observation
import SwiftUI

enum BranchFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case current = "Current"
    case dirty = "Dirty"
    case ahead = "Ahead"
    case behind = "Behind"
    case pullRequest = "PR"

    var id: String { rawValue }
}

@Observable
@MainActor
class BranchPickerViewModel {
    var query: String = ""
    var filter: BranchFilter = .all

    // Dependency
    let state: AppState

    init(state: AppState) {
        self.state = state
    }

    var selectedBranch: String? {
        state.selectedBranch
    }

    private var summaries: [LocalBranchSummary] {
        if !state.localBranchSummaries.isEmpty { return state.localBranchSummaries }
        return state.localBranches.map { branch in
            LocalBranchSummary(
                branch: branch,
                isCurrent: branch == state.selectedBranch,
                isDirty: false,
                aheadCount: 0,
                behindCount: 0,
                upstream: nil,
                relatedPRNumber: nil,
                relatedPRTitle: nil,
                lastAuthor: "unknown",
                lastUpdated: "unknown"
            )
        }
    }

    var visibleSummaries: [LocalBranchSummary] {
        summaries
            .filter { branch in
                switch filter {
                case .all: true
                case .current: branch.branch == selectedBranch || branch.isCurrent
                case .dirty: branch.isDirty
                case .ahead: branch.aheadCount > 0
                case .behind: branch.behindCount > 0
                case .pullRequest: branch.relatedPRNumber != nil
                }
            }
            .filter { branch in
                query.isEmpty
                    || branch.branch.fuzzyContains(query)
                    || branch.lastAuthor.fuzzyContains(query)
                    || (branch.relatedPRTitle?.fuzzyContains(query) ?? false)
                    || (branch.upstream?.fuzzyContains(query) ?? false)
            }
            .sorted { lhs, rhs in
                if lhs.branch == selectedBranch { return true }
                if rhs.branch == selectedBranch { return false }
                if lhs.isDirty != rhs.isDirty { return lhs.isDirty }
                let lhsChanged = lhs.aheadCount + lhs.behindCount
                let rhsChanged = rhs.aheadCount + rhs.behindCount
                if lhsChanged != rhsChanged { return lhsChanged > rhsChanged }
                return lhs.branch.localizedCaseInsensitiveCompare(rhs.branch) == .orderedAscending
            }
    }

    func selectBranch(_ branch: String) async {
        await state.selectBranch(branch)
    }
}

extension String {
    fileprivate func fuzzyContains(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let haystack = localizedLowercase
        let needles = trimmed.localizedLowercase.split(whereSeparator: \.isWhitespace)
        return needles.allSatisfy { haystack.contains($0) }
    }
}
