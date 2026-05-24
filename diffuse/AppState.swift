import SwiftUI
import AppKit

// MARK: - App State

@MainActor
@Observable
class AppState {
    // Registered Workspaces & Repositories
    var repositories: [GitRepository] = []
    var selectedRepoId: UUID?

    // PRs & Runs
    var pullRequests: [PullRequest] = []
    var selectedPRId: UUID?
    var analysisDetails: AnalysisDetails?
    
    // Local Git State
    var localBranches: [String] = []
    var localBranchSummaries: [LocalBranchSummary] = []
    var selectedBranch: String?

    // Commit Timeline
    var commits: [GitCommit] = []
    var selectedCommitSha: String? = nil // nil = "All Changes"

    // UI Loading & Navigation States
    var isLoadingPRs = false
    var isLoadingAnalysis = false
    var selectedBucketId: String?
    var isLowerSignalViewSelected = false
    var activeFileId: UUID?
    var activeHunkIndex: Int?
    var diffLayout: DiffLayout = .unified
    var isAnalyzing = false

    var analysisError: String?

    let coordinator = AnalysisCoordinator()

    // Git File Watcher
    private var isWatcherRunning = false
    private var lastGitFingerprint: String?

    // Computed Properties
    var selectedRepo: GitRepository? {
        repositories.first { $0.id == selectedRepoId }
    }

    var selectedPR: PullRequest? {
        pullRequests.first { $0.id == selectedPRId }
    }

    var selectedBranchSummary: LocalBranchSummary? {
        guard let selectedBranch else { return localBranchSummaries.first(where: \.isCurrent) }
        return localBranchSummaries.first { $0.branch == selectedBranch }
    }

    var selectedBucket: ChangeBucket? {
        guard let selectedBucketId else { return nil }
        return analysisDetails?.changeBuckets.first { $0.id == selectedBucketId }
    }

    var bucketFiles: [ChangedFile] {
        guard let details = analysisDetails else { return [] }
        if isLowerSignalViewSelected {
            let skimPaths = Set(details.skimTargets.map(\.filePath))
            return details.files.filter { skimPaths.contains($0.path) }
        }
        guard let bucket = selectedBucket else { return details.files }
        return details.files.filter { bucket.files.contains($0.path) }
    }

    var bucketHighlights: [RiskHighlight] {
        guard let details = analysisDetails else { return [] }
        if isLowerSignalViewSelected { return [] }
        guard let bucket = selectedBucket else { return details.riskHighlights }
        return details.riskHighlights.filter { $0.bucketId == bucket.id }
    }

    var bucketTargets: [ReviewTarget] {
        guard let details = analysisDetails else { return [] }
        if isLowerSignalViewSelected { return [] }
        guard let bucket = selectedBucket else { return details.reviewTargets }
        return details.reviewTargets.filter { bucket.files.contains($0.filePath) }
    }

    // MARK: - Core Load & Refresh

    func load() async {
        isLoadingPRs = true
        
        repositories = await coordinator.allRepositories()
        
        if selectedRepoId == nil {
            selectedRepoId = repositories.first?.id
        }
        
        await refreshActiveRepo()
        isLoadingPRs = false
        
        startGitWatcher()
    }

    func selectRepo(_ id: UUID) async {
        selectedRepoId = id
        lastGitFingerprint = nil
        selectedPRId = nil
        selectedBucketId = nil
        isLowerSignalViewSelected = false
        activeFileId = nil
        activeHunkIndex = nil
        analysisDetails = nil
        commits = []
        localBranchSummaries = []
        selectedCommitSha = nil
        
        isLoadingPRs = true
        await refreshActiveRepo()
        isLoadingPRs = false
    }

    func renameWorkspace(id: UUID, newName: String) async {
        await coordinator.renameRepository(id: id, newName: newName)
        await load()
    }

    func setWorkspaceAutoAnalyze(id: UUID, enabled: Bool) async {
        await coordinator.setRepositoryAutoAnalyze(id: id, enabled: enabled)
        repositories = await coordinator.allRepositories()
    }

    func refreshActiveRepo() async {
        guard let repo = selectedRepo else { return }
        
        // Load local branches
        localBranches = await coordinator.listLocalBranches(repoPath: repo.path)
        
        let activeBranch = GitService.run("git rev-parse --abbrev-ref HEAD", cwd: repo.path)
        selectedBranch = activeBranch.isEmpty ? "main" : activeBranch

        // Load Pull Requests matching this repo name
        let allPRs = await coordinator.allPullRequests()
        pullRequests = allPRs.filter { $0.repository == "local/\(repo.name)" }

        localBranchSummaries = await coordinator.listLocalBranchSummaries(
            repoPath: repo.path,
            branches: localBranches,
            currentBranch: selectedBranch ?? "main",
            remotePRs: []
        )

        if selectedPRId == nil, let first = pullRequests.first {
            selectedPRId = first.id
        }

        if let id = selectedPRId {
            await loadDetails(for: id)
        }
    }

    func refreshWorkspace() async {
        isLoadingPRs = true
        await refreshActiveRepo()
        isLoadingPRs = false
    }

    func selectPR(_ id: UUID) async {
        selectedPRId = id
        selectedBucketId = nil
        isLowerSignalViewSelected = false
        activeFileId = nil
        activeHunkIndex = nil
        analysisDetails = nil
        selectedCommitSha = nil // Reset timeline to "All Changes"
        await loadDetails(for: id)
    }

    func selectBranch(_ branch: String) async {
        guard let repo = selectedRepo else { return }
        isAnalyzing = true
        analysisError = nil
        
        // Checkout local branch
        _ = GitService.run("git checkout \(branch)", cwd: repo.path)
        selectedBranch = branch
        
        // Run full analysis on this branch compared to main
        if let pr = await coordinator.analyzeRepo(path: repo.path, baseRef: "main") {
            pullRequests = await coordinator.allPullRequests().filter { $0.repository == "local/\(repo.name)" }
            await selectPR(pr.id)
        } else {
            analysisError = coordinator.analysisError ?? "Branch analysis failed"
        }
        isAnalyzing = false
    }

    func loadDetails(for prId: UUID) async {
        guard let pr = pullRequests.first(where: { $0.id == prId }),
              let run = pr.latestRun else { return }
        isLoadingAnalysis = true
        
        // Fetch chronological commits for timeline
        if let repo = selectedRepo {
            commits = await coordinator.listCommits(repoPath: repo.path, baseRef: pr.baseSha, headRef: pr.headSha)
        } else {
            commits = []
        }

        // Analyze specific commit or full PR
        if let sha = selectedCommitSha {
            if let repo = selectedRepo {
                await analyzeSingleCommit(repoPath: repo.path, sha: sha, pr: pr, run: run)
            }
        } else {
            analysisDetails = await coordinator.getDetails(for: run.id, repoPath: selectedRepo?.path)
        }
        
        isLoadingAnalysis = false

        if let details = analysisDetails {
            if let id = selectedBucketId, !details.changeBuckets.contains(where: { $0.id == id }) {
                selectedBucketId = nil
            }
            if isLowerSignalViewSelected, details.skimTargets.isEmpty {
                isLowerSignalViewSelected = false
            }

            let ordered = reorderFiles(bucketFiles, highlights: details.riskHighlights)
            let firstFile = ordered.first(where: { $0.classification == .source || $0.classification == .test }) ?? ordered.first
            activeFileId = firstFile?.id
            activeHunkIndex = nil
        }
    }

    private func analyzeSingleCommit(repoPath: String, sha: String, pr: PullRequest, run: AnalysisRun) async {
        let commitDiff = GitService.run("git diff \(sha)~1..\(sha)", cwd: repoPath)
        guard !commitDiff.isEmpty else {
            self.analysisDetails = nil
            return
        }

        let profile = AnalysisProfileStore.load(repoPath: repoPath)
        let parsedFiles = DiffParser.parse(commitDiff, profile: profile)
        let changedFiles = parsedFiles.map { pf -> ChangedFile in
            ChangedFile(
                analysisRunId: run.id,
                path: pf.newPath ?? pf.oldPath ?? "unknown",
                status: pf.status,
                additions: pf.additions,
                deletions: pf.deletions,
                classification: pf.classification,
                hunks: pf.hunks
            )
        }

        let astService = ASTAnalysisService()
        let allSymbols = await astService.extractChangedSymbols(
            repoPath: repoPath,
            baseRevision: "\(sha)~1",
            headRevision: sha,
            analysisRunId: run.id,
            changedFiles: changedFiles
        )
        
        let ruleResults = RulesEngine.runDeterministicRules(
            files: parsedFiles, symbols: allSymbols,
            filePathMap: Dictionary(uniqueKeysWithValues: changedFiles.map { ($0.id, $0.path) }),
            profile: profile
        )
        var allFindings: [Finding] = []
        for (path, rulefindings) in ruleResults {
            let matchFile = changedFiles.first { $0.path == path }
            guard let fileId = matchFile?.id else { continue }
            let dbFindings = rulefindings.map { rf -> Finding in
                Finding(
                    id: UUID(), analysisRunId: run.id, changedFileId: fileId,
                    severity: rf.severity, category: rf.category, message: rf.message,
                    lineStart: rf.lineStart, lineEnd: rf.lineEnd,
                    ruleSource: rf.ruleSource, evidence: rf.evidence
                )
            }
            allFindings.append(contentsOf: dbFindings)
        }
        
        let breakdown = RulesEngine.calculateRiskScore(files: parsedFiles, symbols: allSymbols, findings:
            allFindings.map {
                RulesEngine.RuleFinding(severity: $0.severity, category: $0.category, message: $0.message,
                                       lineStart: $0.lineStart, lineEnd: $0.lineEnd, ruleSource: $0.ruleSource, evidence: $0.evidence)
            }, profile: profile)
            
        let triage = TriageEngine.deriveTriage(files: changedFiles, symbols: allSymbols, findings: allFindings, riskScore: breakdown.score, profile: profile)
        
        var mockRun = run
        mockRun.riskScore = breakdown.score
        
        self.analysisDetails = AnalysisDetails(
            run: mockRun, pr: pr, files: changedFiles, symbols: allSymbols, findings: allFindings,
            reviewTargets: triage.reviewTargets,
            changeBuckets: triage.changeBuckets,
            riskHighlights: triage.riskHighlights,
            skimTargets: triage.skimTargets,
            riskFactors: triage.riskFactors,
            symbolReviewGroups: triage.symbolReviewGroups
        )
    }

    func selectCommit(_ sha: String?) async {
        selectedCommitSha = sha
        if let prId = selectedPRId {
            await loadDetails(for: prId)
        }
    }

    // MARK: - Local Git Directory Watcher

    func startGitWatcher() {
        guard !isWatcherRunning else { return }
        isWatcherRunning = true
        
        Task { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                guard let self = self, self.isWatcherRunning else { break }
                await self.checkGitIndex()
            }
        }
    }

    func stopGitWatcher() {
        isWatcherRunning = false
    }

    private func checkGitIndex() async {
        guard let repo = selectedRepo else { return }

        let fingerprint = gitFingerprint(repoPath: repo.path)
        guard !fingerprint.isEmpty else { return }

        if let last = lastGitFingerprint {
            if fingerprint != last {
                lastGitFingerprint = fingerprint
                if repo.autoAnalyzeEnabled, !isAnalyzing, !isLoadingAnalysis {
                    await reRunAnalysis()
                } else {
                    await refreshActiveRepo()
                }
            }
        } else {
            lastGitFingerprint = fingerprint
        }
    }

    private func gitFingerprint(repoPath: String) -> String {
        let head = GitService.run("git rev-parse HEAD 2>/dev/null", cwd: repoPath)
        let status = GitService.run("git status --porcelain", cwd: repoPath)
        return "\(head)\n\(status)"
    }


    // MARK: - Existing Navigation & Triage Helpers

    func selectAllChanges() {
        selectedBucketId = nil
        isLowerSignalViewSelected = false
        guard let details = analysisDetails else { return }
        let ordered = reorderFiles(details.files, highlights: details.riskHighlights)
        activeFileId = ordered.first?.id
        activeHunkIndex = nil
    }

    func selectBucket(_ id: String) {
        selectedBucketId = id
        isLowerSignalViewSelected = false
        guard let details = analysisDetails else { return }
        let bucket = details.changeBuckets.first { $0.id == id }
        let files = bucket.map { b in details.files.filter { b.files.contains($0.path) } } ?? details.files
        let ordered = reorderFiles(files, highlights: details.riskHighlights)
        activeFileId = ordered.first?.id
        activeHunkIndex = nil
    }

    func selectLowerSignalChanges() {
        selectedBucketId = nil
        isLowerSignalViewSelected = true
        guard let details = analysisDetails else { return }
        let skimPaths = Set(details.skimTargets.map(\.filePath))
        let files = details.files.filter { skimPaths.contains($0.path) }
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
            isLowerSignalViewSelected = false
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

    func analyzeRepo(path: String, baseRef: String? = nil, autoAnalyzeEnabled: Bool = true) async {
        isAnalyzing = true
        analysisError = nil

        var resolvedPath = path
        if path.hasPrefix("~") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let suffix = String(path.dropFirst())
            resolvedPath = home + suffix
        }

        let repoName = URL(fileURLWithPath: resolvedPath).lastPathComponent
        let standardized = URL(fileURLWithPath: resolvedPath).standardized.path
        let existing = repositories.first {
            URL(fileURLWithPath: $0.path).standardized.path == standardized
        }

        if existing == nil {
            let newRepo = await coordinator.addRepository(name: repoName, path: resolvedPath, autoAnalyzeEnabled: autoAnalyzeEnabled)
            repositories = await coordinator.allRepositories()
            selectedRepoId = newRepo.id
        } else {
            selectedRepoId = existing?.id
        }

        selectedPRId = nil
        selectedBucketId = nil
        isLowerSignalViewSelected = false
        activeFileId = nil
        activeHunkIndex = nil
        analysisDetails = nil
        commits = []
        selectedCommitSha = nil

        let analysisBaseRef = baseRef ?? defaultAnalysisBaseRef(repoPath: resolvedPath)
        if let pr = await coordinator.analyzeRepo(path: resolvedPath, baseRef: analysisBaseRef) {
            await refreshActiveRepo()
            await selectPR(pr.id)
        } else {
            analysisError = coordinator.analysisError ?? "Analysis failed"
            await refreshActiveRepo()
        }
        isAnalyzing = false
    }


    func reRunAnalysis() async {
        guard let repo = selectedRepo else { return }
        isAnalyzing = true
        analysisError = nil

        let baseRef = defaultAnalysisBaseRef(repoPath: repo.path)
        let previousSelection = selectedCommitSha
        selectedCommitSha = nil

        if let pr = await coordinator.analyzeRepo(path: repo.path, baseRef: baseRef) {
            pullRequests = await coordinator.allPullRequests().filter { $0.repository == "local/\(repo.name)" }
            selectedPRId = pr.id
            selectedBucketId = nil
            isLowerSignalViewSelected = false
            activeFileId = nil
            activeHunkIndex = nil

            await refreshActiveRepo()

            if let previousSelection, commits.contains(where: { $0.sha == previousSelection }) {
                await selectCommit(previousSelection)
            }
        } else {
            analysisError = coordinator.analysisError ?? "Analysis failed"
        }

        isAnalyzing = false
    }

    private func defaultAnalysisBaseRef(repoPath: String) -> String? {
        if !GitService.run("git rev-parse --verify main 2>/dev/null", cwd: repoPath).isEmpty {
            return "main"
        }
        if !GitService.run("git rev-parse --verify master 2>/dev/null", cwd: repoPath).isEmpty {
            return "master"
        }
        return selectedPR?.baseSha.isEmpty == false ? selectedPR?.baseSha : nil
    }

    func expandHunk(fileId: UUID, hunkIndex: Int, direction: ExpandDirection) async {
        guard let repo = selectedRepo,
              let details = analysisDetails,
              let fileIdx = details.files.firstIndex(where: { $0.id == fileId }) else { return }
        
        let file = details.files[fileIdx]
        let hunk = file.hunks[hunkIndex]
        
        let baseRevision = selectedCommitSha != nil ? "\(selectedCommitSha!)~1" : (selectedPR?.baseSha ?? "HEAD~1")
        
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
            
            analysisDetails?.files[fileIdx].hunks[hunkIndex] = updatedHunk
            
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
            
            analysisDetails?.files[fileIdx].hunks[hunkIndex] = updatedHunk
            
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
            
            analysisDetails?.files[fileIdx].hunks.remove(at: hunkIndex)
            analysisDetails?.files[fileIdx].hunks[hunkIndex - 1] = mergedHunk
        }
    }
}

enum ExpandDirection {
    case up, down, all
}
