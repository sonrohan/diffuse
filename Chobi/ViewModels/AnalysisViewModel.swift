import Observation
import SwiftUI

@Observable
@MainActor
class AnalysisViewModel {
    // View-specific navigation & selection states
    var activeFileId: UUID? = nil
    var activeHunkIndex: Int? = nil
    var activeTargetId: UUID? = nil
    var isImpactInspectorVisible = false

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

    var bucketFiles: [ChangedFile] {
        state.analysisDetails?.files ?? []
    }

    var bucketHighlights: [RiskHighlight] {
        state.analysisDetails?.riskHighlights ?? []
    }

    var bucketTargets: [ReviewTarget] {
        state.analysisDetails?.reviewTargets ?? []
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
        let ordered = reorderFiles(bucketFiles, highlights: details.riskHighlights)
        let firstFile =
            ordered.first(where: { $0.classification == .source || $0.classification == .test })
            ?? ordered.first
        activeFileId = firstFile?.id
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

    func jumpToImpactRoot(_ impact: SymbolImpact) {
        activeFileId = impact.symbol.changedFileId
        activeHunkIndex = hunkIndexForLine(
            fileId: impact.symbol.changedFileId, lineStart: impact.symbol.startLine)
        activeTargetId = nil
        isImpactInspectorVisible = true
    }

    func jumpToHighlight(_ highlight: RiskHighlight) {
        guard let details = state.analysisDetails else { return }
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

    private func hunkIndexForLine(fileId: UUID, lineStart: Int?) -> Int? {
        guard let details = state.analysisDetails,
            let file = details.files.first(where: { $0.id == fileId })
        else { return nil }
        return hunkIndexForLine(file: file, lineStart: lineStart)
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
