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
        if let base = baseRef, !base.isEmpty {
            diff = GitService.run("git diff \(base)", cwd: repoPath)
        } else {
            // Try main, then HEAD~1
            diff = GitService.run("git diff main", cwd: repoPath)
            if diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                diff = GitService.run("git diff HEAD~1", cwd: repoPath)
            }
        }

        if diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw GitError.noDiff("No diff found against main or HEAD~1. Make sure you have local changes or commits.")
        }

        // Deterministic base SHA and PR number
        let baseSha = GitService.run("git rev-parse \(baseRef ?? "HEAD~1")", cwd: repoPath).prefix(40).description
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
}
