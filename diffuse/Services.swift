import Foundation
import Combine


// MARK: - Git Service
// Handles running git commands and analyzing local repos

actor GitService {

    enum GitError: Error, LocalizedError {
        case notAGitRepo(String)
        case noDiff(String)
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAGitRepo(let p): "Not a git repository: \(p)"
            case .noDiff(let msg): msg
            case .commandFailed(let msg): msg
            }
        }
    }

    static func run(_ command: String, cwd: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // suppress stderr

        try? process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func gatherDiff(repoPath: String, baseRef: String?) throws -> (
        diff: String, branchName: String, commitSubject: String,
        baseSha: String, headSha: String, author: String, prNumber: Int
    ) {
        // Verify it's a git repo
        let checkGit = GitService.run("git rev-parse --show-toplevel 2>/dev/null", cwd: repoPath)
        guard !checkGit.isEmpty else {
            throw GitError.notAGitRepo(repoPath)
        }

        let branchName = GitService.run("git rev-parse --abbrev-ref HEAD", cwd: repoPath)
        let commitSubject = GitService.run("git log -1 --pretty=%s", cwd: repoPath)
        let headSha = GitService.run("git rev-parse HEAD", cwd: repoPath)
        let author = GitService.run("git config user.name", cwd: repoPath)

        // Get diff
        var diff = ""
        var resolvedBaseRef = baseRef
        if let base = baseRef, !base.isEmpty {
            diff = GitService.run("git diff \(base)", cwd: repoPath)
        } else {
            // Try main, then HEAD~1
            diff = GitService.run("git diff main", cwd: repoPath)
            if diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                resolvedBaseRef = "HEAD~1"
                diff = GitService.run("git diff HEAD~1", cwd: repoPath)
            } else {
                resolvedBaseRef = "main"
            }
        }

        if diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw GitError.noDiff("No diff found against main or HEAD~1. Make sure you have local changes or commits.")
        }

        // Deterministic base SHA and PR number
        let baseSha = GitService.run("git rev-parse \(resolvedBaseRef ?? "HEAD~1")", cwd: repoPath).prefix(40).description
        let prNumber = stableHash(branchName) % 1000 + 1

        return (diff, branchName.isEmpty ? "feature-branch" : branchName,
                commitSubject.isEmpty ? "Local analysis" : commitSubject,
                baseSha.isEmpty ? String(repeating: "0", count: 40) : baseSha,
                headSha.isEmpty ? String(repeating: "1", count: 40) : headSha,
                author.isEmpty ? "local-developer" : author,
                prNumber)
    }

    private func stableHash(_ s: String) -> Int {
        var hash = 0
        for ch in s.unicodeScalars {
            hash = (hash << 5) &- hash &+ Int(ch.value)
        }
        return abs(hash)
    }

    func listCommits(repoPath: String, baseRef: String, headRef: String) -> [GitCommit] {
        let format = "%H|%an|%s|%ad"
        let output = GitService.run("git log --pretty=format:\"\(format)\" --reverse \(baseRef)..\(headRef)", cwd: repoPath)
        guard !output.isEmpty else { return [] }
        
        return output.components(separatedBy: .newlines).compactMap { line -> GitCommit? in
            let parts = line.components(separatedBy: "|")
            guard parts.count >= 4 else { return nil }
            return GitCommit(sha: parts[0], author: parts[1], subject: parts[2], date: parts[3])
        }
    }

    func diffForCommit(repoPath: String, sha: String) -> String {
        return GitService.run("git show \(sha)", cwd: repoPath)
    }

    func listLocalBranches(repoPath: String) -> [String] {
        let output = GitService.run("git branch --format=\"%(refname:short)\"", cwd: repoPath)
        guard !output.isEmpty else { return ["main"] }
        return output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.contains(" ") }
    }

    func listLocalBranchSummaries(repoPath: String, branches: [String], currentBranch: String, remotePRs: [PullRequest]) -> [LocalBranchSummary] {
        let dirty = !GitService.run("git status --porcelain", cwd: repoPath).isEmpty

        return branches.map { branch in
            let quotedBranch = shellQuote(branch)
            let upstream = resolvedUpstream(repoPath: repoPath, branch: branch)
            let counts = aheadBehindCounts(repoPath: repoPath, upstream: upstream, branch: branch)
            let last = GitService.run("git log -1 --pretty=format:%an'|'%cr \(quotedBranch)", cwd: repoPath)
            let lastParts = last.components(separatedBy: "|")
            let author = lastParts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
            let updated = lastParts.dropFirst().first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
            let relatedPR = remotePRs.first { pr in
                let headBranch = pr.headSha.replacingOccurrences(of: "origin/", with: "")
                return headBranch == branch || branch == "review/pr-\(pr.prNumber)"
            }

            return LocalBranchSummary(
                branch: branch,
                isCurrent: branch == currentBranch,
                isDirty: branch == currentBranch && dirty,
                aheadCount: counts.ahead,
                behindCount: counts.behind,
                upstream: upstream,
                relatedPRNumber: relatedPR?.prNumber,
                relatedPRTitle: relatedPR?.title,
                lastAuthor: author.isEmpty ? "unknown" : author,
                lastUpdated: updated.isEmpty ? "unknown" : updated
            )
        }
    }

    private func resolvedUpstream(repoPath: String, branch: String) -> String? {
        let quotedBranch = shellQuote(branch)
        let configured = GitService.run("git rev-parse --abbrev-ref \(quotedBranch)@{upstream} 2>/dev/null", cwd: repoPath)
        if !configured.isEmpty { return configured }

        let originBranch = "origin/\(branch)"
        let exists = GitService.run("git rev-parse --verify --quiet \(shellQuote(originBranch))", cwd: repoPath)
        return exists.isEmpty ? nil : originBranch
    }

    private func aheadBehindCounts(repoPath: String, upstream: String?, branch: String) -> (ahead: Int, behind: Int) {
        guard let upstream else { return (0, 0) }
        let output = GitService.run("git rev-list --left-right --count \(shellQuote(upstream))...\(shellQuote(branch))", cwd: repoPath)
        let parts = output.split(whereSeparator: { $0 == " " || $0 == "\t" }).compactMap { Int($0) }
        guard parts.count == 2 else { return (0, 0) }
        return (parts[1], parts[0])
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    func checkoutPR(repoPath: String, prNumber: Int, branchName: String) throws {
        let ghCheck = GitService.run("which gh", cwd: repoPath)
        if !ghCheck.isEmpty {
            let output = GitService.run("gh pr checkout \(prNumber) 2>&1", cwd: repoPath)
            if output.contains("error") || output.contains("Failed") {
                try manualCheckout(repoPath: repoPath, prNumber: prNumber, branchName: branchName)
            }
        } else {
            try manualCheckout(repoPath: repoPath, prNumber: prNumber, branchName: branchName)
        }
    }

    private func manualCheckout(repoPath: String, prNumber: Int, branchName: String) throws {
        _ = GitService.run("git fetch origin pull/\(prNumber)/head:\(branchName) 2>/dev/null", cwd: repoPath)
        let output = GitService.run("git checkout \(branchName) 2>&1", cwd: repoPath)
        if output.contains("error") {
            throw GitError.commandFailed("Failed to checkout branch \(branchName): \(output)")
        }
    }

    func listRemotePRs(repoPath: String) -> [PullRequest] {
        let repoName = URL(fileURLWithPath: repoPath).lastPathComponent
        let ghCheck = GitService.run("which gh", cwd: repoPath)
        if !ghCheck.isEmpty {
            let output = GitService.run("gh pr list --json number,title,author,headRefName,baseRefName 2>/dev/null", cwd: repoPath)
            if !output.isEmpty, let data = output.data(using: .utf8) {
                struct GHPR: Codable {
                    let number: Int
                    let title: String
                    struct GHAuthor: Codable { let login: String }
                    let author: GHAuthor
                    let headRefName: String
                    let baseRefName: String
                }
                if let ghprs = try? JSONDecoder().decode([GHPR].self, from: data) {
                    return ghprs.map { g -> PullRequest in
                        PullRequest(
                            prNumber: g.number,
                            title: g.title,
                            baseSha: g.baseRefName,
                            headSha: g.headRefName,
                            author: g.author.login,
                            repository: "local/\(repoName)"
                        )
                    }
                }
            }
        }
        
        let output = GitService.run("git branch -r --format=\"%(refname:short)|%(authorname)|%(committerdate:short)\"", cwd: repoPath)
        guard !output.isEmpty else { return [] }
        return output.components(separatedBy: .newlines).compactMap { line -> PullRequest? in
            let parts = line.components(separatedBy: "|")
            guard parts.count >= 3, !parts[0].isEmpty else { return nil }
            let name = parts[0].replacingOccurrences(of: "origin/", with: "")
            if name == "HEAD" || name == "main" || name == "master" { return nil }
            
            var hash = 0
            for ch in name.unicodeScalars { hash = (hash << 5) &- hash &+ Int(ch.value) }
            let prNum = abs(hash) % 1000 + 1

            return PullRequest(
                prNumber: prNum,
                title: "Review changes from branch \(name)",
                baseSha: "main",
                headSha: parts[0],
                author: parts[1].isEmpty ? "git-developer" : parts[1],
                repository: "local/\(repoName)"
            )
        }
    }
}


// MARK: - Persistence Service
// Simple JSON-based persistence (no external DB dependency)

actor PersistenceService {

    private let storageDir: URL

    struct Store: Codable {
        var pullRequests: [PullRequest] = []
        var analysisRuns: [AnalysisRun] = []
        var changedFiles: [ChangedFile] = []
        var changedSymbols: [ChangedSymbol] = []
        var findings: [Finding] = []
        var repositories: [GitRepository]? = []
    }

    private var store = Store()


    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("diffuse", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.storageDir = dir

        let file = dir.appendingPathComponent("store.json")
        if let data = try? Data(contentsOf: file),
           let decoded = try? JSONDecoder().decode(Store.self, from: data) {
            self.store = decoded
        } else {
            self.store = Store()
        }
    }

    private func save() {
        let file = storageDir.appendingPathComponent("store.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(store) {
            try? data.write(to: file, options: .atomic)
        }
    }

    func allPullRequests() -> [PullRequest] {
        var prs = store.pullRequests.sorted { $0.updatedAt > $1.updatedAt }
        // Attach latest run
        for i in prs.indices {
            prs[i].latestRun = store.analysisRuns
                .filter { $0.pullRequestId == prs[i].id }
                .sorted { $0.createdAt > $1.createdAt }
                .first
        }
        return prs
    }

    func upsertPullRequest(_ pr: PullRequest) -> PullRequest {
        if let idx = store.pullRequests.firstIndex(where: { $0.id == pr.id }) {
            store.pullRequests[idx] = pr
        } else {
            store.pullRequests.append(pr)
        }
        save()
        return pr
    }

    func insertRun(_ run: AnalysisRun) {
        store.analysisRuns.append(run)
        save()
    }

    func updateRun(_ run: AnalysisRun) {
        if let idx = store.analysisRuns.firstIndex(where: { $0.id == run.id }) {
            store.analysisRuns[idx] = run
            save()
        }
    }

    func insertFiles(_ files: [ChangedFile]) {
        store.changedFiles.append(contentsOf: files)
        save()
    }

    func insertSymbols(_ symbols: [ChangedSymbol]) {
        store.changedSymbols.append(contentsOf: symbols)
        save()
    }

    func insertFindings(_ findings: [Finding]) {
        store.findings.append(contentsOf: findings)
        save()
    }

    func getAnalysisDetails(runId: UUID) -> AnalysisDetails? {
        guard let run = store.analysisRuns.first(where: { $0.id == runId }),
              let pr = store.pullRequests.first(where: { $0.id == run.pullRequestId }) else { return nil }

        let files = store.changedFiles.filter { $0.analysisRunId == runId }
        let symbols = store.changedSymbols.filter { $0.analysisRunId == runId }
        let findings = store.findings.filter { $0.analysisRunId == runId }

        let triage = TriageEngine.deriveTriage(files: files, symbols: symbols, findings: findings, riskScore: run.riskScore)

        return AnalysisDetails(
            run: run, pr: pr, files: files, symbols: symbols, findings: findings,
            reviewTargets: triage.reviewTargets,
            changeBuckets: triage.changeBuckets,
            riskHighlights: triage.riskHighlights,
            skimTargets: triage.skimTargets,
            riskFactors: triage.riskFactors
        )
    }

    func getFilesForRun(_ runId: UUID) -> [ChangedFile] {
        store.changedFiles.filter { $0.analysisRunId == runId }
    }

    func getRunsForPR(_ prId: UUID) -> [AnalysisRun] {
        store.analysisRuns.filter { $0.pullRequestId == prId }.sorted { $0.createdAt > $1.createdAt }
    }

    func allRepositories() -> [GitRepository] {
        return store.repositories ?? []
    }

    func addRepository(name: String, path: String, autoAnalyzeEnabled: Bool = true) -> GitRepository {
        let standardized = URL(fileURLWithPath: path).standardized.path
        if let existing = store.repositories?.first(where: {
            URL(fileURLWithPath: $0.path).standardized.path == standardized
        }) {
            return existing
        }

        let repo = GitRepository(name: name, path: path, autoAnalyzeEnabled: autoAnalyzeEnabled)
        if store.repositories == nil {
            store.repositories = []
        }
        store.repositories?.append(repo)
        save()
        return repo
    }

    func deleteRepository(id: UUID) {
        store.repositories?.removeAll { $0.id == id }
        save()
    }

    func renameRepository(id: UUID, newName: String) {
        if let idx = store.repositories?.firstIndex(where: { $0.id == id }) {
            store.repositories?[idx].name = newName
            save()
        }
    }

    func setRepositoryAutoAnalyze(id: UUID, enabled: Bool) {
        if let idx = store.repositories?.firstIndex(where: { $0.id == id }) {
            store.repositories?[idx].autoAnalyzeEnabled = enabled
            save()
        }
    }

    func deleteAll() {
        store = Store()
        save()
    }
}


// MARK: - Analysis Coordinator
// Orchestrates the full analysis pipeline

@MainActor
class AnalysisCoordinator: ObservableObject {

    let persistence = PersistenceService()
    let git = GitService()

    @Published var isAnalyzing = false
    @Published var analysisError: String?

    func analyzeRepo(path: String, baseRef: String? = nil) async -> PullRequest? {
        isAnalyzing = true
        analysisError = nil
        defer { isAnalyzing = false }

        do {
            let gitInfo = try await git.gatherDiff(repoPath: path, baseRef: baseRef)
            let repoName = URL(fileURLWithPath: path).lastPathComponent

            // Upsert PR
            var pr = PullRequest(
                prNumber: gitInfo.prNumber,
                title: gitInfo.commitSubject,
                baseSha: gitInfo.baseSha,
                headSha: gitInfo.headSha,
                author: gitInfo.author,
                repository: "local/\(repoName)"
            )
            // Check for existing PR with same repo+number
            let existing = await persistence.allPullRequests()
            if let existingPR = existing.first(where: { $0.repository == pr.repository && $0.prNumber == pr.prNumber }) {
                pr = existingPR
                pr.headSha = gitInfo.headSha
                pr.updatedAt = Date()
            }
            pr = await persistence.upsertPullRequest(pr)

            // Create analysis run
            var run = AnalysisRun(pullRequestId: pr.id, baseSha: pr.baseSha, headSha: pr.headSha, status: .analyzing)
            await persistence.insertRun(run)

            // Parse diff
            let parsedFiles = DiffParser.parse(gitInfo.diff)

            // Create ChangedFile records
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
            await persistence.insertFiles(changedFiles)

            // Run deterministic rules
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
            await persistence.insertFindings(allFindings)

            // Calculate risk score
            let breakdown = RulesEngine.calculateRiskScore(files: parsedFiles, symbols: [], findings:
                allFindings.map {
                    RulesEngine.RuleFinding(severity: $0.severity, category: $0.category, message: $0.message,
                                           lineStart: $0.lineStart, lineEnd: $0.lineEnd, ruleSource: $0.ruleSource, evidence: $0.evidence)
                })

            run.status = .completed
            run.riskScore = breakdown.score
            run.updatedAt = Date()
            await persistence.updateRun(run)

            pr.latestRun = run
            pr = await persistence.upsertPullRequest(pr)
            return pr

        } catch {
            analysisError = error.localizedDescription
            return nil
        }
    }

    func allPullRequests() async -> [PullRequest] {
        await persistence.allPullRequests()
    }

    func getDetails(for runId: UUID) async -> AnalysisDetails? {
        await persistence.getAnalysisDetails(runId: runId)
    }

    func allRepositories() async -> [GitRepository] {
        await persistence.allRepositories()
    }

    func addRepository(name: String, path: String, autoAnalyzeEnabled: Bool = true) async -> GitRepository {
        await persistence.addRepository(name: name, path: path, autoAnalyzeEnabled: autoAnalyzeEnabled)
    }

    func deleteRepository(id: UUID) async {
        await persistence.deleteRepository(id: id)
    }

    func renameRepository(id: UUID, newName: String) async {
        await persistence.renameRepository(id: id, newName: newName)
    }

    func setRepositoryAutoAnalyze(id: UUID, enabled: Bool) async {
        await persistence.setRepositoryAutoAnalyze(id: id, enabled: enabled)
    }

    func listCommits(repoPath: String, baseRef: String, headRef: String) async -> [GitCommit] {
        await git.listCommits(repoPath: repoPath, baseRef: baseRef, headRef: headRef)
    }

    func listLocalBranches(repoPath: String) async -> [String] {
        await git.listLocalBranches(repoPath: repoPath)
    }

    func listLocalBranchSummaries(repoPath: String, branches: [String], currentBranch: String, remotePRs: [PullRequest]) async -> [LocalBranchSummary] {
        await git.listLocalBranchSummaries(repoPath: repoPath, branches: branches, currentBranch: currentBranch, remotePRs: remotePRs)
    }

    func listRemotePRs(repoPath: String) async -> [PullRequest] {
        await git.listRemotePRs(repoPath: repoPath)
    }

    func checkoutPR(repoPath: String, prNumber: Int, branchName: String) async throws {
        try await git.checkoutPR(repoPath: repoPath, prNumber: prNumber, branchName: branchName)
    }
}
