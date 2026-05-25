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

    static func runGit(_ arguments: [String], cwd: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try? process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func fileContent(at revision: String, path filePath: String, cwd: String) -> String {
        runGit(["show", "\(revision):\(filePath)"], cwd: cwd)
    }

    static func trackedSourceFiles(cwd: String, revision: String? = nil) -> [String] {
        let output: String
        if let revision, !revision.isEmpty {
            output = runGit(["ls-tree", "-r", "--name-only", revision], cwd: cwd)
        } else {
            output = runGit(["ls-files"], cwd: cwd)
        }
        guard !output.isEmpty else { return [] }
        let supportedExtensions: Set<String> = ["swift", "kt", "kts", "ts", "tsx", "js", "jsx", "py", "rs"]
        return output.components(separatedBy: .newlines).filter { path in
            let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
            return supportedExtensions.contains(ext)
        }
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


// MARK: - AST Analysis Service
// Spawns the bundled diffuse-core sidecar to extract semantic AST symbols.

actor ASTAnalysisService {

    /// Raw JSON model matching diffuse-core's AstSymbol output.
    private struct SidecarSymbol: Codable {
        let line: Int
        let end_line: Int
        let semantic_type: String
        let name: String
        let language: String
        let metadata: [String: String]
    }

    /// Locate the bundled sidecar binary. During development it falls back to the
    /// debug build next to the project so the app can be tested without a full
    /// Xcode release build.
    private func sidecarURL() -> URL? {
        // 1. App bundle (production)
        if let url = Bundle.main.url(forAuxiliaryExecutable: "diffuse-core") {
            return url
        }
        // 2. Dev fallback — sibling directory next to the .xcodeproj
        if let bundlePath = Bundle.main.bundlePath
            .components(separatedBy: "/diffuse.app").first {
            let devBinary = URL(fileURLWithPath: bundlePath)
                .appendingPathComponent("diffuse-core/target/debug/diffuse-core")
            if FileManager.default.isExecutableFile(atPath: devBinary.path) {
                return devBinary
            }
            // Also try release build
            let releaseBinary = URL(fileURLWithPath: bundlePath)
                .appendingPathComponent("diffuse-core/target/release/diffuse-core")
            if FileManager.default.isExecutableFile(atPath: releaseBinary.path) {
                return releaseBinary
            }
        }
        return nil
    }

    /// Parse a single file and return symbols intersecting the given 1-based line numbers.
    func parseSymbols(
        for fileURL: URL,
        filePath: String,
        changedLines: [Int],
        analysisRunId: UUID,
        changedFileId: UUID
    ) async -> [ChangedSymbol] {
        guard !changedLines.isEmpty else { return [] }
        guard let helperURL = sidecarURL() else {
            print("[ASTAnalysisService] diffuse-core binary not found")
            return []
        }

        let process = Process()
        process.executableURL = helperURL
        let linesArg = changedLines.map(String.init).joined(separator: ",")
        process.arguments = ["analyze", "--file", fileURL.path, "--lines", linesArg]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()

            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            guard !data.isEmpty else { return [] }

            let sidecarSymbols = try JSONDecoder().decode([SidecarSymbol].self, from: data)
            return sidecarSymbols.map { s in
                var metadata = s.metadata
                metadata["language"] = s.language
                metadata["file_path"] = filePath
                if let symbolKey = metadata["symbol_key"] {
                    metadata["symbol_id"] = "\(filePath)::\(symbolKey)"
                }
                // Step 6: parse comma-separated callee names from metadata
                let calleeNames = metadata["callees"].map {
                    $0.split(separator: ",")
                        .map { String($0).trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                } ?? []
                return ChangedSymbol(
                    analysisRunId: analysisRunId,
                    changedFileId: changedFileId,
                    name: s.name,
                    kind: mapSymbolKind(s.semantic_type),
                    startLine: s.line,
                    endLine: s.end_line,
                    callees: calleeNames,
                    semanticType: s.semantic_type,
                    metadata: metadata
                )
            }
        } catch {
            let errOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            print("[ASTAnalysisService] error for \(fileURL.lastPathComponent): \(error) — sidecar: \(errOutput)")
            return []
        }
    }

    private func mapSymbolKind(_ semanticType: String) -> ChangedSymbol.SymbolKind {
        switch semanticType {
        case "function_definition", "function_declaration": return .function
        case "method_definition", "constructor_declaration":  return .method
        case "class_declaration":                            return .class
        case "struct_declaration":                           return .struct
        case "enum_declaration":                             return .enum
        case "protocol_declaration", "interface_declaration": return .protocol
        case "extension_declaration":                        return .extension
        case "type_alias":                                   return .type
        case "property_declaration", "variable_declaration": return .property
        case "module_declaration", "object_declaration":    return .module
        case "decorated_definition":                         return .decorated
        default:                                             return .function
        }
    }

    /// Parse symbols for contract-level comparison between the base and head versions of a file.
    /// Runs `diffuse-core compare --base <base> --head <head> --lines <csv>` and merges
    /// the returned contract-delta metadata into the existing `ChangedSymbol` array.
    func compareSymbols(
        baseURL: URL,
        headURL: URL,
        changedLines: [Int],
        existingSymbols: inout [ChangedSymbol]
    ) async {
        guard !changedLines.isEmpty else { return }
        guard let helperURL = sidecarURL() else { return }

        let process = Process()
        process.executableURL = helperURL
        let linesArg = changedLines.map(String.init).joined(separator: ",")
        process.arguments = ["compare", "--base", baseURL.path, "--head", headURL.path, "--lines", linesArg]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()

            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            guard !data.isEmpty else { return }

            let contractSymbols = try JSONDecoder().decode([SidecarSymbol].self, from: data)

            // Merge contract-delta metadata back into the matching existing symbol records.
            for cs in contractSymbols {
                let idxByKey: Int?
                if let key = cs.metadata["symbol_key"] {
                    idxByKey = existingSymbols.firstIndex { $0.metadata["symbol_key"] == key }
                } else {
                    idxByKey = nil
                }

                let fallbackIdx = existingSymbols.firstIndex {
                    $0.name == cs.name && $0.startLine == cs.line
                }

                if let idx = idxByKey ?? fallbackIdx {
                    for (key, value) in cs.metadata where key.hasPrefix("contract_") || key.hasSuffix("_added") {
                        existingSymbols[idx].metadata[key] = value
                    }
                }
            }
        } catch {
            let errOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            print("[ASTAnalysisService] compare error for \(headURL.lastPathComponent): \(error) — sidecar: \(errOutput)")
        }
    }

    func symbolsWithCallerData(repoPath: String, symbols: [ChangedSymbol], revision: String? = nil) async -> [ChangedSymbol] {
        guard !symbols.isEmpty, let helperURL = sidecarURL() else { return symbols }

        struct SymbolRef {
            let key: String
            let name: String
            let qualifiedName: String
        }

        func symbolKey(_ symbol: ChangedSymbol) -> String {
            if let key = symbol.metadata["symbol_key"], !key.isEmpty { return key }
            let scope = symbol.metadata["scope"] ?? ""
            return "\(scope)::\(symbol.semanticType)::\(symbol.name)"
        }

        func normalizedLookupName(_ value: String) -> String {
            value.replacingOccurrences(of: "::", with: ".").lowercased()
        }

        let changedRefs = symbols
            .filter { !$0.name.isEmpty && $0.name != "<anonymous>" }
            .map {
                SymbolRef(
                    key: symbolKey($0),
                    name: $0.name,
                    qualifiedName: $0.metadata["qualified_name"] ?? $0.name
                )
            }
        guard !changedRefs.isEmpty else { return symbols }

        let refsByName = Dictionary(grouping: changedRefs, by: { $0.name.lowercased() })
        var callersByKey: [String: Set<String>] = [:]
        let trackedFiles = GitService.trackedSourceFiles(cwd: repoPath, revision: revision)

        func matches(for callee: String) -> [SymbolRef] {
            let normalized = normalizedLookupName(callee)
            let isQualified = normalized.contains(".")
            if isQualified {
                return changedRefs.filter {
                    normalizedLookupName($0.qualifiedName) == normalized
                        || normalizedLookupName($0.qualifiedName).hasSuffix(".\(normalized)")
                }
            }

            let candidates = refsByName[normalized] ?? []
            return candidates.count == 1 ? candidates : []
        }

        for relativePath in trackedFiles {
            var temporaryIndexedURL: URL?
            let fileURL: URL
            if let revision, !revision.isEmpty {
                let content = GitService.fileContent(at: revision, path: relativePath, cwd: repoPath)
                guard !content.isEmpty,
                      let tmp = temporarySourceURL(prefix: "diffuse-index", filePath: relativePath, content: content) else {
                    continue
                }
                temporaryIndexedURL = tmp
                fileURL = tmp
            } else {
                fileURL = URL(fileURLWithPath: repoPath).appendingPathComponent(relativePath)
                guard FileManager.default.isReadableFile(atPath: fileURL.path) else { continue }
            }

            let process = Process()
            process.executableURL = helperURL
            process.arguments = ["index", "--file", fileURL.path]

            let stdout = Pipe()
            process.standardOutput = stdout
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                guard !data.isEmpty else { continue }

                let indexedSymbols = try JSONDecoder().decode([SidecarSymbol].self, from: data)
                for indexed in indexedSymbols {
                    let callees = indexed.metadata["callees"].map {
                        $0.split(separator: ",")
                            .map { String($0).trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                    } ?? []
                    let callerName = indexed.metadata["qualified_name"] ?? indexed.name
                    let callerLabel = "\(relativePath):\(callerName)"
                    for callee in callees {
                        for match in matches(for: callee) where match.name != indexed.name && match.qualifiedName != callerName {
                            callersByKey[match.key, default: []].insert(callerLabel)
                        }
                    }
                }
            } catch {}

            if let temporaryIndexedURL {
                try? FileManager.default.removeItem(at: temporaryIndexedURL)
            }
        }

        return symbols.map { symbol in
            var updated = symbol
            let callers = Array(callersByKey[symbolKey(symbol)] ?? []).sorted()
            if !callers.isEmpty {
                updated.callers = callers
                updated.metadata["caller_resolution"] = "indexed"
            }
            return updated
        }
    }

    func extractChangedSymbols(
        repoPath: String,
        baseRevision: String,
        headRevision: String? = nil,
        analysisRunId: UUID,
        changedFiles: [ChangedFile]
    ) async -> [ChangedSymbol] {
        var allSymbols: [ChangedSymbol] = []

        for changedFile in changedFiles where changedFile.classification == .source || changedFile.classification == .test {
            guard changedFile.status != .deleted else { continue }
            let lines = changedLinesFromHunks(changedFile.hunks)
            guard !lines.isEmpty else { continue }

            var temporaryHeadURL: URL?
            let fileURL: URL
            if let headRevision {
                let headContent = GitService.fileContent(at: headRevision, path: changedFile.path, cwd: repoPath)
                guard !headContent.isEmpty,
                      let tmp = temporarySourceURL(prefix: "diffuse-head", filePath: changedFile.path, content: headContent) else {
                    continue
                }
                temporaryHeadURL = tmp
                fileURL = tmp
            } else {
                fileURL = URL(fileURLWithPath: repoPath).appendingPathComponent(changedFile.path)
            }

            var symbols = await parseSymbols(
                for: fileURL,
                filePath: changedFile.path,
                changedLines: lines,
                analysisRunId: analysisRunId,
                changedFileId: changedFile.id
            )

            if !symbols.isEmpty {
                let baseContent = GitService.fileContent(at: baseRevision, path: changedFile.path, cwd: repoPath)
                if !baseContent.isEmpty,
                   let baseTmp = temporarySourceURL(prefix: "diffuse-base", filePath: changedFile.path, content: baseContent) {
                    await compareSymbols(
                        baseURL: baseTmp,
                        headURL: fileURL,
                        changedLines: lines,
                        existingSymbols: &symbols
                    )
                    try? FileManager.default.removeItem(at: baseTmp)
                } else if changedFile.status == .added {
                    for index in symbols.indices {
                        symbols[index].metadata["symbol_is_new"] = "true"
                        markAddedBehaviorDeltas(symbol: &symbols[index])
                        if isContractSurface(symbols[index]) {
                            symbols[index].metadata["contract_is_new_public"] = "true"
                        }
                    }
                }
            }

            if let temporaryHeadURL {
                try? FileManager.default.removeItem(at: temporaryHeadURL)
            }

            allSymbols.append(contentsOf: symbols)
        }

        return await symbolsWithCallerData(repoPath: repoPath, symbols: allSymbols, revision: headRevision)
    }

    private func temporarySourceURL(prefix: String, filePath: String, content: String) -> URL? {
        let ext = URL(fileURLWithPath: filePath).pathExtension
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)\(suffix)")
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private func isContractSurface(_ symbol: ChangedSymbol) -> Bool {
        switch symbol.metadata["visibility"] {
        case "public", "open":
            return true
        case "private", "fileprivate", "internal", "protected":
            return false
        default:
            let language = symbol.metadata["language"] ?? ""
            return language == "typescript"
                || language == "javascript"
                || language == "python"
                || symbol.semanticType == "interface_declaration"
                || symbol.semanticType == "protocol_declaration"
                || symbol.semanticType == "type_alias"
        }
    }

    private func markAddedBehaviorDeltas(symbol: inout ChangedSymbol) {
        let mappings = [
            ("has_control_flow", "control_flow_added"),
            ("has_error_handling", "error_handling_added"),
            ("has_async_behavior", "async_behavior_added"),
            ("has_persistence_write", "persistence_write_added"),
            ("has_network_call", "network_call_added"),
            ("has_auth_check", "auth_check_added"),
            ("has_deletion", "deletion_added"),
            ("has_logging", "logging_added")
        ]
        for (presenceKey, deltaKey) in mappings where symbol.metadata[presenceKey] == "true" {
            symbol.metadata[deltaKey] = "true"
        }
    }
}

/// Extract all 1-based new-side line numbers that were added or changed within a file's diff hunks.
nonisolated private func changedLinesFromHunks(_ hunks: [DiffHunk]) -> [Int] {
    var lines: [Int] = []
    for hunk in hunks {
        var currentLine = hunk.newStart
        for rawLine in hunk.lines {
            if rawLine.hasPrefix("+") && !rawLine.hasPrefix("+++") {
                lines.append(currentLine)
                currentLine += 1
            } else if !rawLine.hasPrefix("-") {
                currentLine += 1
            }
        }
    }
    return lines
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

    func getAnalysisDetails(runId: UUID, profile: AnalysisProfile) async -> AnalysisDetails? {
        guard let run = store.analysisRuns.first(where: { $0.id == runId }),
              let pr = store.pullRequests.first(where: { $0.id == run.pullRequestId }) else { return nil }

        let files = store.changedFiles.filter { $0.analysisRunId == runId }
        let symbols = store.changedSymbols.filter { $0.analysisRunId == runId }
        let findings = store.findings.filter { $0.analysisRunId == runId }

        let triage = await TriageEngine.deriveTriage(files: files, symbols: symbols, findings: findings, riskScore: run.riskScore, profile: profile)

        return AnalysisDetails(
            run: run, pr: pr, files: files, symbols: symbols, findings: findings,
            reviewTargets: triage.reviewTargets,
            changeBuckets: triage.changeBuckets,
            riskHighlights: triage.riskHighlights,
            skimTargets: triage.skimTargets,
            riskFactors: triage.riskFactors,
            symbolReviewGroups: triage.symbolReviewGroups
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
            let profile = AnalysisProfileStore.load(repoPath: path)
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
            let parsedFiles = DiffParser.parse(gitInfo.diff, profile: profile)

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

            let astService = ASTAnalysisService()
            let allSymbols = await astService.extractChangedSymbols(
                repoPath: path,
                baseRevision: gitInfo.baseSha,
                analysisRunId: run.id,
                changedFiles: changedFiles
            )
            if !allSymbols.isEmpty {
                await persistence.insertSymbols(allSymbols)
            }

            // FIX 1: Build file path map for deterministic rules
            let filePathMap: [UUID: String] = Dictionary(
                uniqueKeysWithValues: changedFiles.map { ($0.id, $0.path) }
            )

            // Run deterministic rules (FIX 1: pass filePathMap)
            let ruleResults = RulesEngine.runDeterministicRules(
                files: parsedFiles, symbols: allSymbols, filePathMap: filePathMap, profile: profile
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
            await persistence.insertFindings(allFindings)

            // Calculate risk score
            let breakdown = RulesEngine.calculateRiskScore(files: parsedFiles, symbols: allSymbols, findings:
                allFindings.map {
                    RulesEngine.RuleFinding(severity: $0.severity, category: $0.category, message: $0.message,
                                           lineStart: $0.lineStart, lineEnd: $0.lineEnd, ruleSource: $0.ruleSource, evidence: $0.evidence)
                }, profile: profile)

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

    func getDetails(for runId: UUID, repoPath: String? = nil) async -> AnalysisDetails? {
        await persistence.getAnalysisDetails(runId: runId, profile: AnalysisProfileStore.load(repoPath: repoPath))
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
