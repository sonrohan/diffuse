import SwiftUI
import AppKit

// MARK: - App State

@MainActor
@Observable
class AppState {
    // Registered Workspaces & Repositories
    var repositories: [GitRepository] = []
    var selectedRepoId: UUID?

    // Sidebar Toggles
    enum SidebarMode: String, Codable { case local, remote }
    var sidebarMode: SidebarMode = .local

    // PRs & Runs
    var pullRequests: [PullRequest] = []
    var selectedPRId: UUID?
    var analysisDetails: AnalysisDetails?
    
    // Remote Pull Requests
    var remotePRs: [PullRequest] = []

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
    var activeFileId: UUID?
    var activeHunkIndex: Int?
    var isAnalyzing = false
    var analysisError: String?

    let coordinator = AnalysisCoordinator()

    // Git File Watcher
    private var isWatcherRunning = false
    private var lastGitIndexDate: Date?

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

    // MARK: - Core Load & Refresh

    func load() async {
        isLoadingPRs = true
        
        // Load repositories
        repositories = await coordinator.allRepositories()
        if repositories.isEmpty {
            // Register default local developer workspaces
            let defaultRepos = [
                GitRepository(name: "diffuse", path: "/Users/rohan/repos/diffuse"),
                GitRepository(name: "diffuse2", path: "/Users/rohan/repos/diffuse2")
            ]
            for r in defaultRepos {
                _ = await coordinator.addRepository(name: r.name, path: r.path)
            }
            repositories = await coordinator.allRepositories()
        }
        
        if selectedRepoId == nil {
            selectedRepoId = repositories.first?.id
        }
        
        await refreshActiveRepo()
        isLoadingPRs = false
        
        startGitWatcher()
    }

    func selectRepo(_ id: UUID) async {
        selectedRepoId = id
        selectedPRId = nil
        selectedBucketId = nil
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

    func refreshActiveRepo() async {
        guard let repo = selectedRepo else { return }
        
        // Load local branches
        localBranches = await coordinator.listLocalBranches(repoPath: repo.path)
        
        let activeBranch = GitService.run("git rev-parse --abbrev-ref HEAD", cwd: repo.path)
        selectedBranch = activeBranch.isEmpty ? "main" : activeBranch

        // Load Pull Requests matching this repo name
        let allPRs = await coordinator.allPullRequests()
        pullRequests = allPRs.filter { $0.repository == "local/\(repo.name)" }

        // Fetch remote PRs
        remotePRs = await coordinator.listRemotePRs(repoPath: repo.path)
        localBranchSummaries = await coordinator.listLocalBranchSummaries(
            repoPath: repo.path,
            branches: localBranches,
            currentBranch: selectedBranch ?? "main",
            remotePRs: remotePRs
        )

        if selectedPRId == nil, let first = pullRequests.first {
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

    func checkoutRemotePR(_ pr: PullRequest) async {
        guard let repo = selectedRepo else { return }
        isAnalyzing = true
        analysisError = nil
        
        let localBranchName = "review/pr-\(pr.prNumber)"
        
        do {
            try await coordinator.checkoutPR(repoPath: repo.path, prNumber: pr.prNumber, branchName: localBranchName)
            sidebarMode = .local
            selectedBranch = localBranchName
            
            // Run analysis immediately
            if let analyzedPR = await coordinator.analyzeRepo(path: repo.path, baseRef: pr.baseSha) {
                pullRequests = await coordinator.allPullRequests().filter { $0.repository == "local/\(repo.name)" }
                await selectPR(analyzedPR.id)
            }
        } catch {
            analysisError = error.localizedDescription
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
            analysisDetails = await coordinator.getDetails(for: run.id)
        }
        
        isLoadingAnalysis = false

        if let details = analysisDetails {
            if let id = selectedBucketId, !details.changeBuckets.contains(where: { $0.id == id }) {
                selectedBucketId = nil
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
        
        let parsedFiles = DiffParser.parse(commitDiff)
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
        
        let ruleResults = RulesEngine.runDeterministicRules(files: parsedFiles, symbols: [])
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
        
        let breakdown = RulesEngine.calculateRiskScore(files: parsedFiles, symbols: [], findings:
            allFindings.map {
                RulesEngine.RuleFinding(severity: $0.severity, category: $0.category, message: $0.message,
                                       lineStart: $0.lineStart, lineEnd: $0.lineEnd, ruleSource: $0.ruleSource, evidence: $0.evidence)
            })
            
        let triage = TriageEngine.deriveTriage(files: changedFiles, symbols: [], findings: allFindings, riskScore: breakdown.score)
        
        var mockRun = run
        mockRun.riskScore = breakdown.score
        
        self.analysisDetails = AnalysisDetails(
            run: mockRun, pr: pr, files: changedFiles, symbols: [], findings: allFindings,
            reviewTargets: triage.reviewTargets,
            changeBuckets: triage.changeBuckets,
            riskHighlights: triage.riskHighlights,
            skimTargets: triage.skimTargets,
            riskFactors: triage.riskFactors
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
        let indexPath = URL(fileURLWithPath: repo.path).appendingPathComponent(".git/index")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: indexPath.path),
              let modDate = attrs[.modificationDate] as? Date else { return }
              
        if let last = lastGitIndexDate {
            if modDate > last {
                lastGitIndexDate = modDate
                await self.refreshActiveRepo()
            }
        } else {
            lastGitIndexDate = modDate
        }
    }


    // MARK: - Existing Navigation & Triage Helpers

    func selectAllChanges() {
        selectedBucketId = nil
        guard let details = analysisDetails else { return }
        let ordered = reorderFiles(details.files, highlights: details.riskHighlights)
        activeFileId = ordered.first?.id
        activeHunkIndex = nil
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

        var resolvedPath = path
        if path.hasPrefix("~") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let suffix = String(path.dropFirst())
            resolvedPath = home + suffix
        }

        if let pr = await coordinator.analyzeRepo(path: resolvedPath, baseRef: baseRef) {
            let repoName = URL(fileURLWithPath: resolvedPath).lastPathComponent
            let standardized = URL(fileURLWithPath: resolvedPath).standardized.path
            
            let existing = repositories.first {
                URL(fileURLWithPath: $0.path).standardized.path == standardized
            }
            
            if existing == nil {
                let newRepo = await coordinator.addRepository(name: repoName, path: resolvedPath)
                repositories = await coordinator.allRepositories()
                selectedRepoId = newRepo.id
            } else {
                selectedRepoId = existing?.id
            }
            
            await refreshActiveRepo()
            await selectPR(pr.id)
        } else {
            analysisError = coordinator.analysisError ?? "Analysis failed"
        }
        isAnalyzing = false
    }


    func reRunAnalysis() async {
        guard let pr = selectedPR, let runId = pr.latestRun?.id else { return }
        isLoadingAnalysis = true
        analysisDetails = await coordinator.getDetails(for: runId)
        isLoadingAnalysis = false
    }
}
