import SwiftUI
import AppKit

// MARK: - App State

@MainActor
@Observable
class AppState {
    var pullRequests: [PullRequest] = []
    var selectedPRId: UUID?
    var analysisDetails: AnalysisDetails?
    var isLoadingPRs = false
    var isLoadingAnalysis = false
    var selectedBucketId: String?
    var activeFileId: UUID?
    var activeHunkIndex: Int?
    var isAnalyzing = false
    var analysisError: String?

    let coordinator = AnalysisCoordinator()

    var selectedPR: PullRequest? {
        pullRequests.first { $0.id == selectedPRId }
    }

    var selectedBucket: ChangeBucket? {
        analysisDetails?.changeBuckets.first { $0.id == selectedBucketId }
            ?? analysisDetails?.changeBuckets.first
    }

    var bucketFiles: [ChangedFile] {
        guard let details = analysisDetails else { return [] }
        guard let bucket = selectedBucket else { return details.files }
        return details.files.filter { bucket.files.contains($0.path) }
    }

    var bucketHighlights: [RiskHighlight] {
        guard let details = analysisDetails else { return [] }
        guard let bucket = selectedBucket else { return details.riskHighlights }
        return details.riskHighlights.filter { $0.bucketId == bucket.id }
    }

    var bucketTargets: [ReviewTarget] {
        guard let details = analysisDetails else { return [] }
        guard let bucket = selectedBucket else { return details.reviewTargets }
        return details.reviewTargets.filter { bucket.files.contains($0.filePath) }
    }

    func load() async {
        isLoadingPRs = true
        pullRequests = await coordinator.allPullRequests()
        isLoadingPRs = false

        if let first = pullRequests.first, selectedPRId == nil {
            selectedPRId = first.id
        }
        if let id = selectedPRId {
            await loadDetails(for: id)
        }
    }

    func selectPR(_ id: UUID) async {
        selectedPRId = id
        selectedBucketId = nil
        activeFileId = nil
        activeHunkIndex = nil
        analysisDetails = nil
        await loadDetails(for: id)
    }

    private func loadDetails(for prId: UUID) async {
        guard let pr = pullRequests.first(where: { $0.id == prId }),
              let run = pr.latestRun else { return }
        isLoadingAnalysis = true
        analysisDetails = await coordinator.getDetails(for: run.id)
        isLoadingAnalysis = false

        if let details = analysisDetails {
            // Auto-select first bucket and file
            let firstBucket = details.changeBuckets.first
            selectedBucketId = firstBucket?.id

            let bucketFiles = firstBucket.map { b in
                details.files.filter { b.files.contains($0.path) }
            } ?? details.files

            let ordered = reorderFiles(bucketFiles, highlights: details.riskHighlights)
            let firstFile = ordered.first(where: { $0.classification == .source || $0.classification == .test }) ?? ordered.first
            activeFileId = firstFile?.id
            activeHunkIndex = nil
        }
    }

    func selectBucket(_ id: String) {
        selectedBucketId = id
        guard let details = analysisDetails else { return }
        let bucket = details.changeBuckets.first { $0.id == id }
        let files = bucket.map { b in details.files.filter { b.files.contains($0.path) } } ?? details.files
        let ordered = reorderFiles(files, highlights: details.riskHighlights)
        activeFileId = ordered.first?.id
        activeHunkIndex = nil
    }

    func jumpToFile(_ fileId: UUID, hunkIndex: Int? = nil) {
        activeFileId = fileId
        activeHunkIndex = hunkIndex
    }

    func jumpToHighlight(_ highlight: RiskHighlight) {
        guard let details = analysisDetails else { return }
        if let bucket = details.changeBuckets.first(where: { $0.id == highlight.bucketId }) {
            selectedBucketId = bucket.id
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

    func analyzeRepo(path: String, baseRef: String? = nil) async {
        isAnalyzing = true
        analysisError = nil

        if let pr = await coordinator.analyzeRepo(path: path, baseRef: baseRef) {
            pullRequests = await coordinator.allPullRequests()
            await selectPR(pr.id)
        } else {
            analysisError = coordinator.analysisError ?? "Analysis failed"
        }
        isAnalyzing = false
    }

    func reRunAnalysis() async {
        guard let pr = selectedPR, let runId = pr.latestRun?.id else { return }
        // Re-derive triage from existing data
        isLoadingAnalysis = true
        analysisDetails = await coordinator.getDetails(for: runId)
        isLoadingAnalysis = false
    }
}
