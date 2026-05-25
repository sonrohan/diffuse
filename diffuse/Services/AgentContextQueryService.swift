import Foundation

enum AgentContextErrorCode: String, Codable, Sendable {
    case workspaceNotSelected = "workspace_not_selected"
    case analysisNotReady = "analysis_not_ready"
    case runNotFound = "run_not_found"
    case fileNotFound = "file_not_found"
    case symbolNotFound = "symbol_not_found"
    case lineRangeTooLarge = "line_range_too_large"
    case pathOutsideWorkspace = "path_outside_workspace"
    case profileNotFound = "profile_not_found"
    case unsupportedQuery = "unsupported_query"
    case invalidArguments = "invalid_arguments"
    case invalidToken = "invalid_token"
}

struct AgentContextError: Error, Codable, Equatable, Sendable {
    var code: AgentContextErrorCode
    var message: String
}

struct AgentContextSnapshot: Sendable {
    var repositories: [GitRepository]
    var selectedRepoId: UUID?
    var selectedBranch: String?
    var selectedCommitSha: String?
    var currentDetails: AnalysisDetails?
    var pullRequests: [PullRequest]
}

@MainActor
protocol AgentContextSnapshotProviding: AnyObject {
    func agentContextSnapshot() -> AgentContextSnapshot
}

extension AppState: AgentContextSnapshotProviding {
    func agentContextSnapshot() -> AgentContextSnapshot {
        AgentContextSnapshot(
            repositories: repositories,
            selectedRepoId: selectedRepoId,
            selectedBranch: selectedBranch,
            selectedCommitSha: selectedCommitSha,
            currentDetails: analysisDetails,
            pullRequests: pullRequests
        )
    }
}

actor AgentContextQueryService {
    private let stateProvider: any AgentContextSnapshotProviding
    private let persistence: PersistenceService
    private let fileRangeLimit: Int

    init(
        stateProvider: any AgentContextSnapshotProviding,
        persistence: PersistenceService,
        fileRangeLimit: Int = 250
    ) {
        self.stateProvider = stateProvider
        self.persistence = persistence
        self.fileRangeLimit = fileRangeLimit
    }

    func listWorkspaces(includeInactive: Bool = true) async -> [AgentWorkspaceSummary] {
        let snapshot = await MainActor.run { stateProvider.agentContextSnapshot() }
        let prs = await persistence.allPullRequests()

        return snapshot.repositories
            .filter { includeInactive || $0.id == snapshot.selectedRepoId }
            .sorted { $0.name < $1.name }
            .map { repo in
                let repoPRs = prs.filter { $0.repository == "local/\(repo.name)" }
                let latestRun = repoPRs.compactMap(\.latestRun).sorted {
                    $0.createdAt > $1.createdAt
                }.first
                return AgentWorkspaceSummary(
                    id: repo.id.uuidString,
                    name: repo.name,
                    pathBasename: URL(fileURLWithPath: repo.path).lastPathComponent,
                    selected: repo.id == snapshot.selectedRepoId,
                    branch: repo.id == snapshot.selectedRepoId ? snapshot.selectedBranch : nil,
                    latestRunId: latestRun?.id.uuidString,
                    latestRunStatus: latestRun?.status.rawValue
                )
            }
    }

    func currentReviewContext(options: AgentContextOptions) async throws -> AgentReviewContext {
        let snapshot = await MainActor.run { stateProvider.agentContextSnapshot() }
        guard let repo = selectedRepository(in: snapshot) else {
            throw AgentContextError(
                code: .workspaceNotSelected, message: "No workspace is selected.")
        }
        guard let details = snapshot.currentDetails else {
            throw AgentContextError(
                code: .analysisNotReady,
                message: "Analyze the selected workspace before requesting review context.")
        }
        guard details.run.status == .completed else {
            throw AgentContextError(
                code: .analysisNotReady, message: "The selected analysis has not completed.")
        }
        let profile = AnalysisProfileStore.load(repoPath: repo.path)
        return AgentContextBuilder.build(
            details: details,
            repository: repo,
            profile: profile,
            selectedCommitSha: snapshot.selectedCommitSha,
            activeBranch: snapshot.selectedBranch,
            options: options
        )
    }

    func runReviewContext(runId: UUID, options: AgentContextOptions) async throws
        -> AgentReviewContext
    {
        let snapshot = await MainActor.run { stateProvider.agentContextSnapshot() }
        let repo = repository(forRunId: runId, snapshot: snapshot)
        let profile = AnalysisProfileStore.load(repoPath: repo?.path)
        guard let details = await persistence.getAnalysisDetails(runId: runId, profile: profile)
        else {
            throw AgentContextError(code: .runNotFound, message: "Analysis run was not found.")
        }
        guard details.run.status == .completed else {
            throw AgentContextError(
                code: .analysisNotReady, message: "Analysis run is not complete.")
        }
        return AgentContextBuilder.build(
            details: details,
            repository: repo,
            profile: profile,
            selectedCommitSha: nil,
            activeBranch: repo?.id == snapshot.selectedRepoId ? snapshot.selectedBranch : nil,
            options: options
        )
    }

    func explainFile(
        runId: UUID?,
        path: String,
        includeHunks: Bool,
        includeSymbols: Bool,
        includeFindings: Bool,
        maxHunkLines: Int
    ) async throws -> AgentFileContext {
        let (details, repo, _) = try await detailsForOptionalRun(runId)
        guard let file = details.files.first(where: { $0.path == path }) else {
            throw AgentContextError(code: .fileNotFound, message: "Changed file was not found.")
        }
        let fileById = Dictionary(uniqueKeysWithValues: details.files.map { ($0.id, $0) })
        var context = AgentContextBuilder.mapFile(
            file,
            symbols: includeSymbols ? details.symbols.filter { $0.changedFileId == file.id } : [],
            findings: includeFindings
                ? details.findings.filter { $0.changedFileId == file.id } : [],
            buckets: details.changeBuckets.filter { $0.files.contains(file.path) },
            highlights: details.riskHighlights.filter { $0.filePath == file.path },
            fileById: fileById,
            detailLevel: .full
        )
        if !includeHunks {
            context.hunks = []
        } else {
            context.hunks = capHunkLines(context.hunks, maxLines: max(0, maxHunkLines))
        }
        if case .none = repo {
            context.truncated = context.truncated || details.files.count > 1
        }
        return context
    }

    func explainSymbol(
        runId: UUID?,
        path: String?,
        symbolName: String,
        line: Int?,
        includeCallers: Bool,
        includeCallees: Bool
    ) async throws -> AgentSymbolContext {
        let (details, _, _) = try await detailsForOptionalRun(runId)
        let fileById = Dictionary(uniqueKeysWithValues: details.files.map { ($0.id, $0) })
        guard
            var symbol = details.symbols
                .filter({
                    $0.name == symbolName
                        && (path == nil || fileById[$0.changedFileId]?.path == path)
                        && (line == nil || ($0.startLine <= line! && $0.endLine >= line!))
                })
                .sorted(by: { $0.startLine < $1.startLine })
                .first
        else {
            throw AgentContextError(code: .symbolNotFound, message: "Changed symbol was not found.")
        }
        if !includeCallers {
            symbol.callers = []
        }
        if !includeCallees {
            symbol.callees = []
        }
        return AgentContextBuilder.mapSymbol(symbol, fileById: fileById)
    }

    func profileContext(
        workspaceId: UUID?,
        runId: UUID?,
        includeRules: Bool
    ) async throws -> AgentProfileContext {
        let snapshot = await MainActor.run { stateProvider.agentContextSnapshot() }
        let repo =
            workspaceId.flatMap { id in snapshot.repositories.first { $0.id == id } }
            ?? runId.flatMap { repository(forRunId: $0, snapshot: snapshot) }
            ?? selectedRepository(in: snapshot)
        guard let repo else {
            throw AgentContextError(
                code: .workspaceNotSelected, message: "No workspace is selected.")
        }
        return AgentContextBuilder.profileContext(
            profile: AnalysisProfileStore.load(repoPath: repo.path),
            repository: repo,
            includeRules: includeRules
        )
    }

    func reviewPlan(runId: UUID?, focus: String) async throws -> AgentReviewPlanContext {
        var context = try await reviewContextForOptionalRun(
            runId, options: .init(detailLevel: .standard))
        if focus != "all" {
            context.reviewPlan.targets = context.reviewPlan.targets.filter {
                targetMatchesFocus($0, focus: focus)
            }
            context.reviewPlan.buckets = context.reviewPlan.buckets.filter {
                bucketMatchesFocus($0, focus: focus)
            }
        }
        return context.reviewPlan
    }

    func searchReviewContext(
        runId: UUID?,
        query: String,
        types: [String],
        limit: Int
    ) async throws -> AgentQueryResult {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentContextError(code: .invalidArguments, message: "Search query is required.")
        }
        let context = try await reviewContextForOptionalRun(
            runId,
            options: AgentContextOptions(
                detailLevel: .full, includeFiles: true, includeSymbols: true)
        )
        let allowed = Set(
            types.isEmpty ? ["file", "symbol", "finding", "bucket", "profileRule"] : types)
        let needle = query.lowercased()
        var matches: [AgentQueryMatch] = []

        if allowed.contains("file") {
            matches += context.files.compactMap { file in
                scoredMatch(
                    id: file.id,
                    type: "file",
                    title: file.path,
                    path: file.path,
                    lineStart: nil,
                    lineEnd: nil,
                    text: [file.path, file.classification, file.status].joined(separator: " "),
                    query: needle,
                    nextAction: "diffuse.explain_file"
                )
            }
        }
        if allowed.contains("symbol") {
            matches += context.symbols.compactMap { symbol in
                scoredMatch(
                    id: symbol.id,
                    type: "symbol",
                    title: symbol.name,
                    path: symbol.filePath,
                    lineStart: symbol.startLine,
                    lineEnd: symbol.endLine,
                    text: [symbol.name, symbol.semanticType, symbol.semanticArea ?? ""]
                        .joined(separator: " "),
                    query: needle,
                    nextAction: "diffuse.explain_symbol"
                )
            }
        }
        if allowed.contains("finding") {
            matches += context.findings.compactMap { finding in
                scoredMatch(
                    id: finding.id,
                    type: "finding",
                    title: finding.message,
                    path: finding.filePath,
                    lineStart: finding.lineStart,
                    lineEnd: finding.lineEnd,
                    text: [finding.message, finding.category, finding.ruleSource]
                        .joined(separator: " "),
                    query: needle,
                    nextAction: "diffuse.explain_file"
                )
            }
        }
        if allowed.contains("bucket") {
            matches += context.reviewPlan.buckets.compactMap { bucket in
                scoredMatch(
                    id: bucket.id,
                    type: "bucket",
                    title: bucket.title,
                    path: nil,
                    lineStart: nil,
                    lineEnd: nil,
                    text: [bucket.title, bucket.summary, bucket.type].joined(separator: " "),
                    query: needle,
                    nextAction: "diffuse.get_review_plan"
                )
            }
        }
        if allowed.contains("profileRule") {
            matches += context.profile.ruleCounts.compactMap { key, value in
                scoredMatch(
                    id: "profile-\(key)",
                    type: "profileRule",
                    title: key,
                    path: context.profile.sourcePath,
                    lineStart: nil,
                    lineEnd: nil,
                    text: "\(key) \(value)",
                    query: needle,
                    nextAction: "diffuse.get_profile_context"
                )
            }
        }

        let sorted = matches.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.title < $1.title
        }
        let capped = Array(sorted.prefix(max(1, limit)))
        return AgentQueryResult(
            schemaVersion: AgentContextBuilder.schemaVersion,
            source: "diffuse",
            runId: context.scope.runId,
            workspaceId: context.workspace.id,
            query: query,
            matches: capped,
            truncated: sorted.count > capped.count,
            nextActions: ["diffuse.explain_file", "diffuse.explain_symbol"]
        )
    }

    func readFileRange(
        workspaceId: UUID?,
        path: String,
        startLine: Int,
        endLine: Int,
        revision: String
    ) async throws -> AgentFileRangeResult {
        let snapshot = await MainActor.run { stateProvider.agentContextSnapshot() }
        guard
            let repo =
                workspaceId.flatMap({ id in snapshot.repositories.first { $0.id == id } })
                ?? selectedRepository(in: snapshot)
        else {
            throw AgentContextError(
                code: .workspaceNotSelected, message: "No workspace is selected.")
        }
        guard startLine > 0, endLine >= startLine else {
            throw AgentContextError(code: .invalidArguments, message: "Invalid line range.")
        }
        guard endLine - startLine + 1 <= fileRangeLimit else {
            throw AgentContextError(
                code: .lineRangeTooLarge,
                message: "File range exceeds \(fileRangeLimit) lines.")
        }

        let resolvedURL = try guardedFileURL(workspacePath: repo.path, relativePath: path)
        let content: String
        if revision == "working" {
            guard FileManager.default.isReadableFile(atPath: resolvedURL.path) else {
                throw AgentContextError(code: .fileNotFound, message: "File was not found.")
            }
            content = (try? String(contentsOf: resolvedURL, encoding: .utf8)) ?? ""
        } else if revision == "base" || revision == "head" {
            let details = try await reviewContextForOptionalRun(nil, options: .init())
            let rev = revision == "base" ? details.scope.baseSha : details.scope.headSha
            content = GitService.fileContent(at: rev, path: path, cwd: repo.path)
        } else {
            throw AgentContextError(code: .invalidArguments, message: "Unsupported revision.")
        }
        guard !content.contains("\u{0}") else {
            throw AgentContextError(
                code: .fileNotFound, message: "Binary file content is not readable.")
        }

        let allLines = content.components(separatedBy: .newlines)
        guard startLine <= allLines.count else {
            throw AgentContextError(code: .fileNotFound, message: "Start line is outside the file.")
        }
        let cappedEnd = min(endLine, allLines.count)
        let numbered = (startLine...cappedEnd).map { index in
            AgentNumberedLine(line: index, text: allLines[index - 1])
        }
        return AgentFileRangeResult(
            schemaVersion: AgentContextBuilder.schemaVersion,
            source: "diffuse",
            workspaceId: repo.id.uuidString,
            path: path,
            revision: revision,
            startLine: startLine,
            endLine: cappedEnd,
            lines: numbered,
            truncated: cappedEnd < endLine,
            nextActions: ["diffuse.explain_file"]
        )
    }

    private func reviewContextForOptionalRun(
        _ runId: UUID?,
        options: AgentContextOptions
    ) async throws -> AgentReviewContext {
        if let runId {
            return try await runReviewContext(runId: runId, options: options)
        }
        return try await currentReviewContext(options: options)
    }

    private func detailsForOptionalRun(_ runId: UUID?) async throws -> (
        AnalysisDetails, GitRepository?, AgentContextSnapshot
    ) {
        let snapshot = await MainActor.run { stateProvider.agentContextSnapshot() }
        if let runId {
            let repo = repository(forRunId: runId, snapshot: snapshot)
            let profile = AnalysisProfileStore.load(repoPath: repo?.path)
            guard let details = await persistence.getAnalysisDetails(runId: runId, profile: profile)
            else {
                throw AgentContextError(code: .runNotFound, message: "Analysis run was not found.")
            }
            return (details, repo, snapshot)
        }
        guard let repo = selectedRepository(in: snapshot) else {
            throw AgentContextError(
                code: .workspaceNotSelected, message: "No workspace is selected.")
        }
        guard let details = snapshot.currentDetails else {
            throw AgentContextError(
                code: .analysisNotReady, message: "No completed analysis is loaded.")
        }
        return (details, repo, snapshot)
    }

    private func selectedRepository(in snapshot: AgentContextSnapshot) -> GitRepository? {
        guard let id = snapshot.selectedRepoId else { return nil }
        return snapshot.repositories.first { $0.id == id }
    }

    private func repository(forRunId runId: UUID, snapshot: AgentContextSnapshot) -> GitRepository?
    {
        let matchingPR = snapshot.pullRequests.first { $0.latestRun?.id == runId }
        guard let repository = matchingPR?.repository.replacingOccurrences(of: "local/", with: "")
        else { return selectedRepository(in: snapshot) }
        return snapshot.repositories.first { $0.name == repository }
            ?? selectedRepository(in: snapshot)
    }

    private func capHunkLines(_ hunks: [AgentHunkContext], maxLines: Int) -> [AgentHunkContext] {
        var remaining = maxLines
        return hunks.map { hunk in
            var copy = hunk
            if remaining <= 0 {
                copy.previewLines = []
                copy.truncated = true
                return copy
            }
            let prefix = Array(copy.previewLines.prefix(remaining))
            remaining -= prefix.count
            copy.truncated = copy.truncated || prefix.count < copy.previewLines.count
            copy.previewLines = prefix
            return copy
        }
    }

    private func targetMatchesFocus(_ target: AgentReviewTargetContext, focus: String) -> Bool {
        let text = "\(target.title) \(target.reason) \(target.source)".lowercased()
        switch focus {
        case "needs_attention":
            return target.severity == "medium" || target.severity == "high"
        case "security":
            return text.contains("security") || text.contains("auth")
        case "contracts":
            return text.contains("contract") || text.contains("api")
        case "tests":
            return text.contains("test")
        case "skim":
            return false
        default:
            return true
        }
    }

    private func bucketMatchesFocus(_ bucket: AgentBucketContext, focus: String) -> Bool {
        switch focus {
        case "security":
            return bucket.type == "auth-security"
        case "contracts":
            return bucket.type == "api-contract"
        case "tests":
            return bucket.type == "tests"
        case "skim":
            return bucket.riskLevel == "info" || bucket.riskLevel == "low"
        default:
            return true
        }
    }

    private func scoredMatch(
        id: String,
        type: String,
        title: String,
        path: String?,
        lineStart: Int?,
        lineEnd: Int?,
        text: String,
        query: String,
        nextAction: String?
    ) -> AgentQueryMatch? {
        let haystack = text.lowercased()
        guard haystack.contains(query) else { return nil }
        let exactBonus = title.lowercased().contains(query) ? 10 : 0
        return AgentQueryMatch(
            id: id,
            type: type,
            title: title,
            path: path,
            lineStart: lineStart,
            lineEnd: lineEnd,
            snippet: text,
            score: exactBonus + max(1, query.count),
            nextAction: nextAction
        )
    }

    private func guardedFileURL(workspacePath: String, relativePath: String) throws -> URL {
        let root = URL(fileURLWithPath: workspacePath).standardizedFileURL
        let candidate = URL(fileURLWithPath: relativePath, relativeTo: root).standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : "\(root.path)/"
        guard candidate.path == root.path || candidate.path.hasPrefix(rootPath) else {
            throw AgentContextError(
                code: .pathOutsideWorkspace,
                message: "Requested path resolves outside the workspace.")
        }
        return candidate
    }
}
