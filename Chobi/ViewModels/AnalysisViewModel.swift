import Observation
import SwiftUI

@Observable
@MainActor
class AnalysisViewModel {
    // View-specific navigation & selection states
    var selectedBucketId: String? = nil
    var isLowerSignalViewSelected: Bool = false
    var isNeedsAttentionViewSelected: Bool = false
    var activeFileId: UUID? = nil
    var activeHunkIndex: Int? = nil
    var activeTargetId: UUID? = nil

    // Tracking active run to handle transitions cleanly
    private var lastRunId: UUID? = nil

    // Dependency
    let state: AppState

    init(state: AppState) {
        self.state = state
        if let details = state.analysisDetails {
            resetSelection(details: details)
            lastRunId = details.run.id
        }
    }

    var details: AnalysisDetails? {
        state.analysisDetails
    }

    var selectedBucket: ChangeBucket? {
        guard let selectedBucketId, let details = state.analysisDetails else { return nil }
        return details.changeBuckets.first { $0.id == selectedBucketId }
    }

    var bucketFiles: [ChangedFile] {
        guard let details = state.analysisDetails else { return [] }
        if isNeedsAttentionViewSelected {
            let targetPaths = Set(details.reviewTargets.map(\.filePath))
            return details.files.filter { targetPaths.contains($0.path) }
        }
        if isLowerSignalViewSelected {
            let skimPaths = Set(details.skimTargets.map(\.filePath))
            return details.files.filter { skimPaths.contains($0.path) }
        }
        guard let bucket = selectedBucket else { return details.files }
        return details.files.filter { bucket.files.contains($0.path) }
    }

    var bucketHighlights: [RiskHighlight] {
        guard let details = state.analysisDetails else { return [] }
        if isNeedsAttentionViewSelected {
            let targetPaths = Set(details.reviewTargets.map(\.filePath))
            return details.riskHighlights.filter { targetPaths.contains($0.filePath) }
        }
        if isLowerSignalViewSelected { return [] }
        guard let bucket = selectedBucket else { return details.riskHighlights }
        return details.riskHighlights.filter { $0.bucketId == bucket.id }
    }

    var bucketTargets: [ReviewTarget] {
        guard let details = state.analysisDetails else { return [] }
        if isNeedsAttentionViewSelected { return details.reviewTargets }
        if isLowerSignalViewSelected { return [] }
        guard let bucket = selectedBucket else { return details.reviewTargets }
        return details.reviewTargets.filter { bucket.files.contains($0.filePath) }
    }

    var activeTarget: ReviewTarget? {
        guard let activeTargetId, let details = state.analysisDetails else { return nil }
        return details.reviewTargets.first { $0.id == activeTargetId }
    }

    func refreshIfNecessary() {
        guard let currentDetails = state.analysisDetails else { return }
        if currentDetails.run.id != lastRunId {
            lastRunId = currentDetails.run.id
            resetSelection(details: currentDetails)
        }
    }

    func resetSelection(details: AnalysisDetails) {
        if let id = selectedBucketId, !details.changeBuckets.contains(where: { $0.id == id }) {
            selectedBucketId = nil
        }
        if isLowerSignalViewSelected, details.skimTargets.isEmpty {
            isLowerSignalViewSelected = false
        }
        if isNeedsAttentionViewSelected, details.reviewTargets.isEmpty {
            isNeedsAttentionViewSelected = false
        }

        let ordered = reorderFiles(bucketFiles, highlights: details.riskHighlights)
        let firstFile =
            ordered.first(where: { $0.classification == .source || $0.classification == .test })
            ?? ordered.first
        activeFileId = firstFile?.id
        activeHunkIndex = nil
        activeTargetId = nil
    }

    func selectAllChanges() {
        selectedBucketId = nil
        isLowerSignalViewSelected = false
        isNeedsAttentionViewSelected = false
        guard let details = state.analysisDetails else { return }
        let ordered = reorderFiles(details.files, highlights: details.riskHighlights)
        activeFileId = ordered.first?.id
        activeHunkIndex = nil
        activeTargetId = nil
    }

    func selectNeedsAttentionChanges() {
        selectedBucketId = nil
        isLowerSignalViewSelected = false
        isNeedsAttentionViewSelected = true
        guard let details = state.analysisDetails else { return }
        let targetPaths = Set(details.reviewTargets.map(\.filePath))
        let files = details.files.filter { targetPaths.contains($0.path) }
        let ordered = reorderFiles(files, highlights: details.riskHighlights)
        activeFileId = ordered.first?.id
        activeHunkIndex = nil
        activeTargetId = nil
    }

    func selectBucket(_ id: String) {
        selectedBucketId = id
        isLowerSignalViewSelected = false
        isNeedsAttentionViewSelected = false
        guard let details = state.analysisDetails else { return }
        let bucket = details.changeBuckets.first { $0.id == id }
        let files =
            bucket.map { b in details.files.filter { b.files.contains($0.path) } } ?? details.files
        let ordered = reorderFiles(files, highlights: details.riskHighlights)
        activeFileId = ordered.first?.id
        activeHunkIndex = nil
        activeTargetId = nil
    }

    func selectLowerSignalChanges() {
        selectedBucketId = nil
        isLowerSignalViewSelected = true
        isNeedsAttentionViewSelected = false
        guard let details = state.analysisDetails else { return }
        let skimPaths = Set(details.skimTargets.map(\.filePath))
        let files = details.files.filter { skimPaths.contains($0.path) }
        let ordered = reorderFiles(files, highlights: details.riskHighlights)
        activeFileId = ordered.first?.id
        activeHunkIndex = nil
        activeTargetId = nil
    }

    func jumpToFile(_ fileId: UUID, hunkIndex: Int? = nil) {
        activeFileId = fileId
        activeHunkIndex = hunkIndex
        activeTargetId = nil
    }

    func toggleTarget(_ target: ReviewTarget) {
        guard activeTargetId != target.id else {
            activeTargetId = nil
            activeHunkIndex = nil
            return
        }
        activeTargetId = target.id
        if let fileId = target.changedFileId {
            activeFileId = fileId
            activeHunkIndex = target.hunkIndex
        }
    }

    func jumpToHighlight(_ highlight: RiskHighlight) {
        guard let details = state.analysisDetails else { return }
        if let bucket = details.changeBuckets.first(where: { $0.id == highlight.bucketId }) {
            selectedBucketId = bucket.id
            isLowerSignalViewSelected = false
            isNeedsAttentionViewSelected = false
        }
        if let file = details.files.first(where: { $0.path == highlight.filePath }) {
            let hunkIdx = hunkIndexForLine(file: file, lineStart: highlight.lineStart)
            jumpToFile(file.id, hunkIndex: hunkIdx)
        }
    }

    func reorderFiles(_ files: [ChangedFile], highlights: [RiskHighlight]) -> [ChangedFile] {
        var severityMap: [UUID: Severity] = [:]
        for h in highlights {
            if let file = files.first(where: { $0.path == h.filePath }) {
                let current = severityMap[file.id]
                if current == nil || h.severity > current! {
                    severityMap[file.id] = h.severity
                }
            }
        }

        return files.sorted { a, b in
            let scoreA = fileScore(a, severityMap: severityMap)
            let scoreB = fileScore(b, severityMap: severityMap)
            return scoreA > scoreB
        }
    }

    private func fileScore(_ file: ChangedFile, severityMap: [UUID: Severity]) -> Int {
        if let sev = severityMap[file.id] {
            return sev.score * 100
        }
        switch file.classification {
        case .source: return 300
        case .test: return 200
        case .config: return 100
        default: return 0
        }
    }

    private func hunkIndexForLine(file: ChangedFile, lineStart: Int?) -> Int? {
        guard let line = lineStart else { return nil }
        return file.hunks.firstIndex { h in
            line >= h.newStart && line <= h.newStart + h.newLines - 1
        }
    }

    func expandHunk(fileId: UUID, hunkIndex: Int, direction: ExpandDirection) async {
        guard let repo = state.selectedRepo,
            var details = state.analysisDetails,
            let fileIdx = details.files.firstIndex(where: { $0.id == fileId })
        else { return }

        let file = details.files[fileIdx]
        let hunk = file.hunks[hunkIndex]

        let baseRevision =
            state.selectedCommitSha != nil
            ? "\(state.selectedCommitSha!)~1" : (state.selectedPR?.baseSha ?? "HEAD~1")

        let content = GitService.fileContent(at: baseRevision, path: file.path, cwd: repo.path)
        guard !content.isEmpty else { return }

        let allLines = content.components(separatedBy: "\n")
        var updatedHunk = hunk

        switch direction {
        case .up:
            let currentStart = hunk.oldStart
            let limit: Int
            if hunkIndex > 0 {
                let prev = file.hunks[hunkIndex - 1]
                limit = prev.oldStart + prev.oldLines
            } else {
                limit = 1
            }

            let linesToFetch = min(20, currentStart - limit)
            guard linesToFetch > 0 else { return }

            let startLine = currentStart - linesToFetch
            let fetchedLines = (startLine..<(currentStart)).map { idx -> String in
                let lineContent = idx - 1 < allLines.count ? allLines[idx - 1] : ""
                return " " + lineContent
            }

            updatedHunk.lines.insert(contentsOf: fetchedLines, at: 0)
            updatedHunk.oldStart = startLine
            updatedHunk.newStart = updatedHunk.newStart - linesToFetch
            updatedHunk.oldLines += linesToFetch
            updatedHunk.newLines += linesToFetch

            details.files[fileIdx].hunks[hunkIndex] = updatedHunk

        case .down:
            let currentEnd = hunk.oldStart + hunk.oldLines
            let limit: Int
            if hunkIndex < file.hunks.count - 1 {
                limit = file.hunks[hunkIndex + 1].oldStart
            } else {
                limit = allLines.count + 1
            }

            let linesToFetch = min(20, limit - currentEnd)
            guard linesToFetch > 0 else { return }

            let fetchedLines = (currentEnd..<(currentEnd + linesToFetch)).map { idx -> String in
                let lineContent = idx - 1 < allLines.count ? allLines[idx - 1] : ""
                return " " + lineContent
            }

            updatedHunk.lines.append(contentsOf: fetchedLines)
            updatedHunk.oldLines += linesToFetch
            updatedHunk.newLines += linesToFetch

            details.files[fileIdx].hunks[hunkIndex] = updatedHunk

        case .all:
            guard hunkIndex > 0 else { return }
            let prevHunk = file.hunks[hunkIndex - 1]
            let prevEnd = prevHunk.oldStart + prevHunk.oldLines
            let currentStart = hunk.oldStart
            let gap = currentStart - prevEnd
            guard gap > 0 else { return }

            let fetchedLines = (prevEnd..<currentStart).map { idx -> String in
                let lineContent = idx - 1 < allLines.count ? allLines[idx - 1] : ""
                return " " + lineContent
            }

            var mergedHunk = prevHunk
            mergedHunk.lines.append(contentsOf: fetchedLines)
            mergedHunk.lines.append(contentsOf: hunk.lines)
            mergedHunk.oldLines = mergedHunk.oldLines + gap + hunk.oldLines
            mergedHunk.newLines = mergedHunk.newLines + gap + hunk.newLines

            details.files[fileIdx].hunks.remove(at: hunkIndex)
            details.files[fileIdx].hunks[hunkIndex - 1] = mergedHunk
        }

        state.analysisDetails = details
    }

    var selectedReviewScopeTitle: String {
        if isNeedsAttentionViewSelected { return "Needs attention" }
        if isLowerSignalViewSelected { return "Low-signal / skim" }
        return selectedBucket?.title ?? "All changes"
    }

    var selectedReviewScopeSubtitle: String {
        if isNeedsAttentionViewSelected {
            guard let details = state.analysisDetails else {
                return "Files with concrete review targets from analyzer signals."
            }
            let firstTarget = details.reviewTargets.first?.title
            let summary =
                "\(details.reviewTargets.severitySummary) across \(Set(details.reviewTargets.map(\.filePath)).count) file\(Set(details.reviewTargets.map(\.filePath)).count == 1 ? "" : "s")."
            guard let firstTarget else { return summary }
            return "\(summary) Start with: \(firstTarget)"
        }
        if isLowerSignalViewSelected {
            return "Configuration, documentation, generated, and boilerplate files."
        }
        if let selectedBucket {
            return selectedBucket.summary
        }
        return "Unfiltered branch and working tree changes."
    }

    var selectedScopeSignalCount: Int {
        bucketHighlights.filter { $0.severity >= .medium }.count
    }
}

extension Array where Element == ReviewTarget {
    fileprivate var severitySummary: String {
        let severities: [(Severity, String)] = [
            (.high, "high"),
            (.medium, "medium"),
            (.low, "low"),
            (.info, "info"),
        ]
        let parts = severities.compactMap { severity, label -> String? in
            let count = filter { $0.severity == severity }.count
            guard count > 0 else { return nil }
            return "\(count) \(label)"
        }
        if parts.isEmpty { return "0 targets" }
        return parts.joined(separator: ", ") + " target\(count == 1 ? "" : "s")"
    }
}
