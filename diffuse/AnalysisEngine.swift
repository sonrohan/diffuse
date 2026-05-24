import Foundation

// MARK: - Git Diff Parser
// Ports diff.ts from diffuse2

struct DiffParser {

    static func classifyFile(_ path: String) -> ChangedFile.FileClassification {
        let lower = path.lowercased()

        // Generated
        if lower.contains("package-lock.json") || lower.contains("yarn.lock") ||
           lower.contains("pnpm-lock.yaml") || lower.contains("/dist/") ||
           lower.contains("/build/") || lower.contains(".next/") ||
           lower.contains("generated/") || lower.hasSuffix(".min.js") ||
           lower.hasSuffix(".map") {
            return .generated
        }

        // Tests
        if lower.contains(".test.") || lower.contains(".spec.") ||
           lower.contains("__tests__") || lower.contains("/src/test/") ||
           lower.contains("/src/androidtest/") || lower.contains("tests/") ||
           lower.contains("specs/") || lower.hasSuffix("test.kt") ||
           lower.hasSuffix("tests.kt") || lower.hasSuffix("spec.kt") {
            return .test
        }

        // Config
        if lower.hasSuffix(".json") || lower.hasSuffix(".yaml") ||
           lower.hasSuffix(".yml") || lower.hasSuffix(".properties") ||
           lower.hasSuffix(".toml") || lower.hasSuffix(".gradle") ||
           lower.hasSuffix(".gradle.kts") || lower.contains(".config.") ||
           lower.contains("rc.") || lower.contains("/gradle/") ||
           lower == "gradle.properties" || lower == "settings.gradle.kts" ||
           lower == "build.gradle.kts" || lower.hasPrefix(".") {
            return .config
        }

        // Documentation
        if lower.hasSuffix(".md") || lower.hasSuffix(".txt") ||
           lower.hasSuffix(".rst") || lower.contains("docs/") {
            return .documentation
        }

        // Boilerplate
        if lower.hasSuffix(".d.ts") || lower.contains("boilerplate") {
            return .boilerplate
        }

        return .source
    }

    struct ParsedFile {
        var oldPath: String?
        var newPath: String?
        var status: ChangedFile.FileStatus
        var additions: Int
        var deletions: Int
        var classification: ChangedFile.FileClassification
        var hunks: [DiffHunk]
    }

    static func parse(_ diffText: String) -> [ParsedFile] {
        var files: [ParsedFile] = []
        let lines = diffText.components(separatedBy: "\n")
        var current: ParsedFile?
        var currentHunk: DiffHunk?

        func commitHunk() {
            if var h = currentHunk {
                current?.hunks.append(h)
            }
            currentHunk = nil
        }

        func commitFile() {
            commitHunk()
            if let f = current, f.newPath != nil || f.oldPath != nil {
                files.append(f)
            }
            current = nil
        }

        for line in lines {
            if line.hasPrefix("diff --git ") {
                commitFile()
                current = ParsedFile(oldPath: nil, newPath: nil, status: .modified,
                                     additions: 0, deletions: 0, classification: .source, hunks: [])
                // Parse paths from "diff --git a/foo b/foo"
                let rest = String(line.dropFirst("diff --git ".count))
                let parts = rest.components(separatedBy: " ")
                if parts.count >= 2 {
                    let a = parts[0].hasPrefix("a/") ? String(parts[0].dropFirst(2)) : parts[0]
                    let b = parts[1].hasPrefix("b/") ? String(parts[1].dropFirst(2)) : parts[1]
                    current?.oldPath = a
                    current?.newPath = b
                }
                continue
            }

            guard current != nil else { continue }

            if line.hasPrefix("new file mode") { current?.status = .added; continue }
            if line.hasPrefix("deleted file mode") { current?.status = .deleted; continue }
            if line.hasPrefix("rename from ") { current?.status = .renamed; current?.oldPath = String(line.dropFirst("rename from ".count)); continue }
            if line.hasPrefix("rename to ") { current?.newPath = String(line.dropFirst("rename to ".count)); continue }
            if line.hasPrefix("--- a/") { current?.oldPath = String(line.dropFirst("--- a/".count)); continue }
            if line.hasPrefix("+++ b/") { current?.newPath = String(line.dropFirst("+++ b/".count)); continue }

            if line.hasPrefix("@@ ") {
                commitHunk()
                // Parse @@ -oldStart,oldLines +newStart,newLines @@
                let pattern = #"^@@ -(\d+),?(\d+)? \+(\d+),?(\d+)? @@"#
                if let match = line.range(of: pattern, options: .regularExpression) {
                    let m = line[match]
                    let nums = m.matches(of: /\d+/).map { Int($0.output)! }
                    if nums.count >= 3 {
                        currentHunk = DiffHunk(
                            oldStart: nums[0], oldLines: nums.count > 1 ? nums[1] : 1,
                            newStart: nums.count > 2 ? nums[2] : 0,
                            newLines: nums.count > 3 ? nums[3] : 1,
                            lines: []
                        )
                    }
                }
                continue
            }

            if currentHunk != nil {
                if line.hasPrefix("+") && !line.hasPrefix("+++") {
                    current?.additions += 1
                    currentHunk?.lines.append(line)
                } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                    current?.deletions += 1
                    currentHunk?.lines.append(line)
                } else if line.hasPrefix(" ") {
                    currentHunk?.lines.append(line)
                }
            }
        }
        commitFile()

        // Post-process: fix status and classification
        return files.map { f in
            var file = f
            let path = f.newPath ?? f.oldPath ?? ""
            file.classification = classifyFile(path)
            if f.oldPath == nil && f.newPath != nil { file.status = .added }
            else if f.oldPath != nil && f.newPath == nil { file.status = .deleted }
            else if f.oldPath != f.newPath { file.status = .renamed }
            else { file.status = .modified }
            return file
        }
    }
}

// MARK: - Rules Engine
// Ports rules.ts from diffuse2

struct RulesEngine {

    struct RuleFinding {
        var severity: Severity
        var category: Finding.FindingCategory
        var message: String
        var lineStart: Int?
        var lineEnd: Int?
        var ruleSource: String
        var evidence: String?
    }

    struct RiskBreakdown {
        var score: Int
        var factors: [String]
    }

    // FIX 1: filePathMap resolves sym.changedFileId → file path so every
    // AST-powered rule finding is attached to the correct file.
    static func runDeterministicRules(
        files: [DiffParser.ParsedFile],
        symbols: [ChangedSymbol],
        filePathMap: [UUID: String]
    ) -> [String: [RuleFinding]] {
        var fileFindings: [String: [RuleFinding]] = [:]

        func addFinding(_ path: String, _ finding: RuleFinding) {
            fileFindings[path, default: []].append(finding)
        }

        let sourceFiles = files.filter { $0.classification == .source && $0.status != .deleted }
        let testFiles = files.filter { $0.classification == .test }

        func fileBaseName(_ file: DiffParser.ParsedFile) -> String {
            let path = file.newPath ?? file.oldPath ?? ""
            return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent.lowercased()
                .replacingOccurrences(of: "screen", with: "")
                .replacingOccurrences(of: "viewmodel", with: "")
        }

        func matchingTests(for source: DiffParser.ParsedFile) -> [DiffParser.ParsedFile] {
            let base = fileBaseName(source)
            guard !base.isEmpty else { return [] }
            return testFiles.filter { test in
                let testPath = (test.newPath ?? "").lowercased()
                let testBase = fileBaseName(test)
                return testBase.contains(base) || testPath.contains(base)
            }
        }

        // Check 1: Missing tests for significant source changes
        for sf in sourceFiles where sf.additions > 10 {
            if matchingTests(for: sf).isEmpty {
                let path = sf.newPath ?? ""
                let lower = path.lowercased()
                let msg: String
                if lower.contains("/ui/screens/") || lower.hasSuffix("screen.kt") {
                    msg = "User-facing UI change (\(sf.additions) additions) without any matching UI or instrumentation test changes in this PR."
                } else if lower.contains("viewmodel") {
                    msg = "State-management change (\(sf.additions) additions) without any matching view model test changes in this PR."
                } else {
                    msg = "Significant logic change (\(sf.additions) additions) without any matching test file additions or updates in this PR."
                }
                addFinding(path, RuleFinding(
                    severity: .low, category: .test, message: msg,
                    lineStart: firstMeaningfulAddedLine(in: sf),
                    lineEnd: nil,
                    ruleSource: "standard-conventions/testing",
                    evidence: "Modified file: \(path) (\(sf.additions) lines added)"
                ))
            }
        }

        // Check 2: Database migrations without schema changes
        let migrationFiles = files.filter {
            ($0.newPath ?? "").contains("migrations/") || ($0.newPath ?? "").hasSuffix(".sql")
        }
        if !migrationFiles.isEmpty {
            let hasSchemaChanges = files.contains {
                $0.classification == .source &&
                (($0.newPath ?? "").contains("db/schema") || ($0.newPath ?? "").contains("models/"))
            }
            if !hasSchemaChanges {
                for mig in migrationFiles {
                    let path = mig.newPath ?? mig.oldPath ?? ""
                    addFinding(path, RuleFinding(
                        severity: .low, category: .architecture,
                        message: "Database schema migration detected, but no corresponding schema declarations or model changes were found in this PR.",
                        ruleSource: "database/schema-sync",
                        evidence: "Migration file: \(path)"
                    ))
                }
            }
        }

        // Check 3 (FIX 1): Removed — was a dead placeholder using UUID() that never matched.
        // Replaced with AST import-based architectural boundary checks below.
        var emittedImportViolations = Set<String>()
        for sym in symbols {
            guard let path = filePathMap[sym.changedFileId] else { continue }
            let lowerPath = path.lowercased()
            let isUISurface = lowerPath.contains("/ui/")
                || lowerPath.contains("/components/")
                || lowerPath.contains("/frontend/")
                || lowerPath.hasSuffix(".tsx")
                || lowerPath.hasSuffix(".jsx")
                || lowerPath.hasSuffix("view.swift")
                || lowerPath.hasSuffix("screen.kt")
            guard isUISurface else { continue }

            let imports = (sym.metadata["imports"] ?? "")
                .split(separator: ",")
                .map { String($0).lowercased() }
            let forbidden = imports.first {
                $0.contains("/db")
                    || $0.contains(".db")
                    || $0.contains("database")
                    || $0.contains("repository")
                    || $0.contains("persistence")
                    || $0.contains("coredata")
            }
            if let forbidden {
                let violationKey = "\(path)::\(forbidden)"
                guard emittedImportViolations.insert(violationKey).inserted else { continue }
                addFinding(path, RuleFinding(
                    severity: .medium,
                    category: .architecture,
                    message: "UI symbol '\(sym.name)' imports lower-level data infrastructure. Keep presentation code behind view models or service interfaces.",
                    lineStart: sym.startLine,
                    lineEnd: sym.endLine,
                    ruleSource: "architecture/ui-import-boundary",
                    evidence: "Import detected by AST sidecar: \(forbidden)"
                ))
            }
        }

        // Check 4 (AST-powered): Authentication / security symbol change
        for sym in symbols where sym.metadata["semantic_area"] == "security_authentication" {
            let path = filePathMap[sym.changedFileId] ?? "unknown"
            addFinding(path, RuleFinding(
                severity: .high,
                category: .security,
                message: "Auth symbol '\(sym.name)' modified. High regression risk — changes to authentication logic must be reviewed for correctness and side effects.",
                lineStart: sym.startLine,
                lineEnd: sym.endLine,
                ruleSource: "security/auth-ast",
                evidence: "AST-extracted symbol '\(sym.name)' (type: \(sym.semanticType)) in auth path."
            ))
        }

        // Check 5 (AST-powered): Cryptography symbol change
        for sym in symbols where sym.metadata["semantic_area"] == "security_cryptography" {
            let path = filePathMap[sym.changedFileId] ?? "unknown"
            addFinding(path, RuleFinding(
                severity: .high,
                category: .security,
                message: "Cryptographic symbol '\(sym.name)' modified. Encryption/signing changes carry high security risk.",
                lineStart: sym.startLine,
                lineEnd: sym.endLine,
                ruleSource: "security/crypto-ast",
                evidence: "AST-extracted symbol '\(sym.name)' (type: \(sym.semanticType)) in crypto path."
            ))
        }

        // Check 6 (AST-powered): Payment flow change
        for sym in symbols where sym.metadata["semantic_area"] == "payment" {
            let path = filePathMap[sym.changedFileId] ?? "unknown"
            addFinding(path, RuleFinding(
                severity: .medium,
                category: .security,
                message: "Payment symbol '\(sym.name)' modified. Validate billing flow correctness and test against edge cases.",
                lineStart: sym.startLine,
                lineEnd: sym.endLine,
                ruleSource: "security/payment-ast",
                evidence: "AST-extracted symbol '\(sym.name)' (type: \(sym.semanticType)) in payment path."
            ))
        }

        // Check 7 (AST-powered / Step 4): Contract change detection
        for sym in symbols {
            let path = filePathMap[sym.changedFileId] ?? "unknown"

            if sym.metadata["contract_signature_changed"] == "true" {
                addFinding(path, RuleFinding(
                    severity: .medium,
                    category: .architecture,
                    message: "Public API contract change: '\(sym.name)' signature modified. Verify all callers are compatible.",
                    lineStart: sym.startLine,
                    lineEnd: sym.endLine,
                    ruleSource: "contract/signature-changed",
                    evidence: "AST comparison detected signature change in '\(sym.name)' (\(sym.semanticType))."
                ))
            }

            if sym.metadata["contract_return_type_changed"] == "true" {
                let oldType = sym.metadata["contract_old_return_type"] ?? "unknown"
                let newType = sym.metadata["contract_new_return_type"] ?? "unknown"
                addFinding(path, RuleFinding(
                    severity: .medium,
                    category: .architecture,
                    message: "Public API contract change: '\(sym.name)' return type changed. Verify callers and serialization boundaries.",
                    lineStart: sym.startLine,
                    lineEnd: sym.endLine,
                    ruleSource: "contract/return-type-changed",
                    evidence: "AST comparison: return type changed from \(oldType) to \(newType)."
                ))
            }

            if sym.metadata["contract_is_new_public"] == "true" {
                let wasVisChanged = sym.metadata["contract_visibility_changed"] == "true"
                let oldVis = sym.metadata["contract_old_visibility"] ?? "private"
                let severity: Severity = wasVisChanged ? .high : .low
                let msg = wasVisChanged
                    ? "Visibility change: '\(sym.name)' promoted from \(oldVis) to public. Existing callers must be validated; this is a potential breaking change."
                    : "New public symbol '\(sym.name)' added to the API surface."
                addFinding(path, RuleFinding(
                    severity: severity,
                    category: .architecture,
                    message: msg,
                    lineStart: sym.startLine,
                    lineEnd: sym.endLine,
                    ruleSource: wasVisChanged ? "contract/visibility-changed" : "contract/new-public",
                    evidence: "AST comparison: '\(sym.name)' (\(sym.semanticType)) is now public."
                ))
            }
        }

        // Check 8: Symbol-aware test coverage mapping
        let testSymbols = symbols.filter { sym in
            sym.metadata["is_test"] == "true" || (filePathMap[sym.changedFileId] ?? "").lowercased().contains("test")
        }
        let productionSymbols = symbols.filter { sym in
            guard let path = filePathMap[sym.changedFileId]?.lowercased() else { return false }
            return !path.contains("test") && sym.metadata["is_test"] != "true"
        }
        for sym in productionSymbols {
            let isRisky = sym.metadata["is_critical"] == "true"
                || sym.metadata.keys.contains { $0.starts(with: "contract_") }
                || sym.metadata.keys.contains { $0.hasSuffix("_added") }
            guard isRisky, let path = filePathMap[sym.changedFileId] else { continue }

            let normalizedName = sym.name.lowercased()
            let hasRelatedTest = testSymbols.contains { testSym in
                let testPath = (filePathMap[testSym.changedFileId] ?? "").lowercased()
                let testName = testSym.name.lowercased()
                return testName.contains(normalizedName)
                    || testPath.contains(normalizedName)
                    || testSym.callees.contains(where: { $0.caseInsensitiveCompare(sym.name) == .orderedSame })
            }
            if !hasRelatedTest {
                addFinding(path, RuleFinding(
                    severity: .low,
                    category: .test,
                    message: "Risky production symbol '\(sym.name)' changed without a related test symbol update.",
                    lineStart: sym.startLine,
                    lineEnd: sym.endLine,
                    ruleSource: "testing/symbol-coverage",
                    evidence: "No changed test symbol references '\(sym.name)' by name or direct callee metadata."
                ))
            }
        }

        return fileFindings
    }

    private static func firstMeaningfulAddedLine(in file: DiffParser.ParsedFile) -> Int? {
        for hunk in file.hunks {
            var newLine = hunk.newStart
            for rawLine in hunk.lines {
                if rawLine.hasPrefix("+") && !rawLine.hasPrefix("+++") {
                    let content = String(rawLine.dropFirst()).trimmingCharacters(in: .whitespaces)
                    if isMeaningfulAddedLine(content) {
                        return newLine
                    }
                    newLine += 1
                } else if !rawLine.hasPrefix("-") {
                    newLine += 1
                }
            }
        }
        return nil
    }

    private static func isMeaningfulAddedLine(_ content: String) -> Bool {
        guard !content.isEmpty else { return false }
        if content.hasPrefix("import ") || content.hasPrefix("package ") { return false }
        if content.hasPrefix("//") || content.hasPrefix("/*") || content.hasPrefix("*") { return false }
        return true
    }

    static func calculateRiskScore(files: [DiffParser.ParsedFile], symbols: [ChangedSymbol], findings: [RuleFinding]) -> RiskBreakdown {
        var score = 0
        var factors: [String] = []

        let hasProductionChanges = files.contains { $0.classification == .source && $0.status != .deleted }
        let hasTestChanges = files.contains { $0.classification == .test }
        let hasGeneratedOnly = !files.isEmpty && files.allSatisfy { $0.classification == .generated }

        if hasGeneratedOnly {
            score -= 40
            factors.append("Generated-only or formatting-only changes (-40)")
        } else {
            if hasProductionChanges {
                score += 10
                factors.append("Production source code changed (+10)")
            }

            let hasApiChanges = files.contains {
                ($0.newPath ?? "").contains("api/") || ($0.newPath ?? "").contains("routes/")
            }
            if hasApiChanges {
                score += 20
                factors.append("Public API route files modified (+20)")
            }

            let hasSensitiveChanges = files.contains {
                let p = ($0.newPath ?? "").lowercased()
                return p.contains("auth") || p.contains("payment") || p.contains("delete") || p.contains("security")
            }
            if hasSensitiveChanges {
                score += 30
                factors.append("Sensitive paths (auth, payment, deletion) modified (+30)")
            }

            if hasProductionChanges && !hasTestChanges {
                score += 20
                factors.append("No test file additions or updates included with source changes (+20)")
            }

            let hasArchViolations = findings.contains { $0.severity == .high || $0.category == .architecture }
            if hasArchViolations {
                score += 20
                factors.append("High-severity architectural rule violation found (+20)")
            }

            if symbols.contains(where: { $0.callers.count > 5 }) {
                score += 10
                factors.append("High fan-in symbol modified (+10)")
            }

            if symbols.contains(where: { $0.metadata.keys.contains { $0.starts(with: "contract_") } }) {
                score += 10
                factors.append("AST contract surface changed (+10)")
            }

            if symbols.contains(where: { $0.metadata.keys.contains { $0.hasSuffix("_added") } }) {
                score += 10
                factors.append("AST detected newly introduced behavior (+10)")
            }

            if hasTestChanges {
                score -= 15
                factors.append("Tests added or updated for changed production area (-15)")
            }
        }

        return RiskBreakdown(score: max(0, min(100, score)), factors: factors)
    }
}

// MARK: - Triage Engine
// Ports triage.ts from diffuse2

struct TriageEngine {

    static func deriveTriage(files: [ChangedFile], symbols: [ChangedSymbol], findings: [Finding], riskScore: Int) -> (
        reviewTargets: [ReviewTarget],
        changeBuckets: [ChangeBucket],
        riskHighlights: [RiskHighlight],
        skimTargets: [SkimTarget],
        riskFactors: [String],
        symbolReviewGroups: [SymbolReviewGroup]
    ) {
        // Re-classify using path rules
        let effectiveFiles = files.map { f -> ChangedFile in
            var ef = f
            let pathClass = DiffParser.classifyFile(f.path)
            ef.classification = pathClass != .source ? pathClass : f.classification
            return ef
        }

        let fileById = Dictionary(uniqueKeysWithValues: effectiveFiles.map { ($0.id, $0) })

        // Convert for rules engine
        let parsedFiles = effectiveFiles.map { f -> DiffParser.ParsedFile in
            DiffParser.ParsedFile(
                oldPath: f.status == .added ? nil : f.path,
                newPath: f.status == .deleted ? nil : f.path,
                status: f.status,
                additions: f.additions,
                deletions: f.deletions,
                classification: f.classification,
                hunks: f.hunks
            )
        }

        // Reconstruct rule findings as RuleFinding for risk calc
        let ruleFindings = findings.map {
            RulesEngine.RuleFinding(
                severity: $0.severity, category: $0.category, message: $0.message,
                lineStart: $0.lineStart, lineEnd: $0.lineEnd, ruleSource: $0.ruleSource, evidence: $0.evidence
            )
        }

        let riskBreakdown = RulesEngine.calculateRiskScore(files: parsedFiles, symbols: symbols, findings: ruleFindings)
        let riskFactors = riskBreakdown.factors

        // Build change buckets
        var bucketDrafts: [ChangeBucketType: (files: [String], symbols: [String], riskLevel: Severity, riskReasons: [String], evidence: [String])] = [:]

        let findingsByPath: [String: [Finding]] = findings.reduce(into: [:]) { acc, f in
            let path = fileById[f.changedFileId]?.path ?? "unknown"
            acc[path, default: []].append(f)
        }

        for file in effectiveFiles {
            let fileFindings = findingsByPath[file.path] ?? []
            let type = bucketType(for: file, findings: fileFindings)
            let fileSymbols = symbols.filter { $0.changedFileId == file.id }.map { $0.name }
            let riskReasons = fileFindings.map { $0.message }
            let evidence = fileFindings.compactMap { $0.evidence }
            let fileRisk = maxSeverity(fileFindings.map { $0.severity })

            if var existing = bucketDrafts[type] {
                existing.files.append(file.path)
                existing.symbols.append(contentsOf: fileSymbols)
                existing.riskReasons.append(contentsOf: riskReasons)
                existing.evidence.append(contentsOf: evidence)
                existing.riskLevel = maxSeverity([existing.riskLevel, fileRisk])
                bucketDrafts[type] = existing
            } else {
                bucketDrafts[type] = (files: [file.path], symbols: fileSymbols,
                                      riskLevel: fileRisk, riskReasons: riskReasons, evidence: evidence)
            }
        }

        let bucketOrder: [ChangeBucketType] = [.authSecurity, .data, .apiContract, .behavior, .ui, .tests, .buildConfig, .docs, .generated]
        var changeBuckets: [ChangeBucket] = bucketDrafts.map { type, draft in
            ChangeBucket(
                id: "bucket-\(type.rawValue)", type: type,
                title: type.displayTitle,
                summary: "\(draft.files.count) file\(draft.files.count == 1 ? "" : "s") grouped as \(type.displayTitle.lowercased()).",
                files: draft.files,
                symbols: Array(Set(draft.symbols)),
                riskLevel: draft.riskLevel,
                riskReasons: Array(Set(draft.riskReasons)),
                evidence: Array(Set(draft.evidence)),
                reviewOrder: 0
            )
        }.sorted {
            if $0.riskLevel != $1.riskLevel { return $0.riskLevel > $1.riskLevel }
            let ai = bucketOrder.firstIndex(of: $0.type) ?? 99
            let bi = bucketOrder.firstIndex(of: $1.type) ?? 99
            return ai < bi
        }.enumerated().map { idx, b in
            var b2 = b
            b2.reviewOrder = idx + 1
            return b2
        }

        let bucketIdForPath: (String) -> String = { path in
            changeBuckets.first { $0.files.contains(path) }?.id ?? changeBuckets.first?.id ?? "bucket-behavior"
        }

        // Build risk highlights from findings
        let sortedFindings = findings.sorted {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            return true
        }

        let ruleHighlights: [RiskHighlight] = sortedFindings.map { f in
            let path = fileById[f.changedFileId]?.path ?? "unknown"
            return RiskHighlight(
                id: "risk-\(f.id.uuidString)",
                bucketId: bucketIdForPath(path),
                severity: f.severity,
                category: riskCategoryForFinding(f),
                title: String(f.message.split(separator: ".").first ?? Substring(f.message)),
                filePath: path,
                lineStart: f.lineStart,
                lineEnd: f.lineEnd,
                evidence: [f.evidence ?? f.ruleSource].compactMap { $0.isEmpty ? nil : $0 },
                source: "rule",
                confidence: "high"
            )
        }

        let semanticHighlights = deriveSemanticHighlights(
            symbols: symbols,
            files: effectiveFiles,
            bucketIdForPath: bucketIdForPath
        )

        let riskHighlights = (semanticHighlights + ruleHighlights).sorted {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            return $0.category.weight > $1.category.weight
        }

        // Update bucket summaries based on highlights
        changeBuckets = changeBuckets.map { bucket in
            var b = bucket
            let bHighlights = riskHighlights.filter { $0.bucketId == bucket.id }
            b.riskLevel = maxSeverity([bucket.riskLevel] + bHighlights.map { $0.severity })
            b.riskReasons = Array(Set(bHighlights.map { $0.title } + bucket.riskReasons))
            b.evidence = Array(Set(bHighlights.flatMap { $0.evidence } + bucket.evidence))
            if let first = bHighlights.first {
                b.summary = "\(bucket.files.count) file\(bucket.files.count == 1 ? "" : "s") grouped by semantic area. Key signal: \(first.title)."
            }
            return b
        }.sorted {
            if $0.riskLevel != $1.riskLevel { return $0.riskLevel > $1.riskLevel }
            let ai = bucketOrder.firstIndex(of: $0.type) ?? 99
            let bi = bucketOrder.firstIndex(of: $1.type) ?? 99
            return ai < bi
        }.enumerated().map { idx, b in
            var b2 = b; b2.reviewOrder = idx + 1; return b2
        }

        // Build review targets from medium+ highlights
        let reviewTargets: [ReviewTarget] = riskHighlights
            .filter { $0.severity >= .medium }
            .enumerated().map { idx, h in
                let matchFile = effectiveFiles.first { $0.path == h.filePath }
                return ReviewTarget(
                    id: UUID(),
                    priority: idx + 1,
                    severity: h.severity,
                    title: h.title,
                    filePath: h.filePath,
                    lineStart: h.lineStart,
                    lineEnd: h.lineEnd,
                    reason: h.title,
                    evidence: h.evidence.joined(separator: " "),
                    source: h.source,
                    changedFileId: matchFile?.id,
                    hunkIndex: matchFile.flatMap { getHunkIndex($0, lineStart: h.lineStart) }
                )
            }

        // Build skim targets
        let skimTargets: [SkimTarget] = effectiveFiles
            .filter { $0.classification != .source && $0.classification != .test }
            .map { f in
                let reason: String
                switch f.classification {
                case .generated: reason = "Automatically generated file or package lockfile."
                case .config: reason = "Configuration settings only."
                case .documentation: reason = "Documentation-only changes."
                default: reason = "Boilerplate or declaration-only code changes."
                }
                return SkimTarget(id: "skim-\(f.id.uuidString)", filePath: f.path, reason: reason,
                                  classification: f.classification, additions: f.additions, deletions: f.deletions)
            }

        // Build symbol-first review map (Step 1)
        let symbolReviewGroups = buildSymbolReviewGroups(symbols: symbols, files: effectiveFiles)

        return (reviewTargets, changeBuckets, riskHighlights, skimTargets, riskFactors, symbolReviewGroups)
    }

    // MARK: - Step 1: Symbol-first review map

    /// Group changed symbols by semantic area for the symbol-first review map.
    static func buildSymbolReviewGroups(
        symbols: [ChangedSymbol],
        files: [ChangedFile]
    ) -> [SymbolReviewGroup] {
        let fileById = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })

        // Include symbols from source and test files; skip generated/config/docs.
        let reviewSymbols = symbols.filter { sym in
            guard let classification = fileById[sym.changedFileId]?.classification else { return false }
            return classification == .source || classification == .test
        }

        guard !reviewSymbols.isEmpty else { return [] }

        // Ordered group definitions
        let groupDefs: [(area: String, label: String, icon: String)] = [
            ("security_authentication", "Authentication",  "lock.shield"),
            ("security_cryptography",  "Cryptography",    "key"),
            ("payment",                "Payment",          "creditcard"),
            ("data_deletion",          "Data Deletion",   "trash"),
            ("is_test",                "Tests",            "checkmark.seal"),
            ("general",                "Logic Changes",   "cpu"),
        ]

        var groups: [SymbolReviewGroup] = []
        var assignedIds = Set<UUID>()

        for def in groupDefs {
            let groupSymbols: [ChangedSymbol]
            if def.area == "is_test" {
                groupSymbols = reviewSymbols.filter {
                    $0.metadata["is_test"] == "true" && !assignedIds.contains($0.id)
                }
            } else if def.area == "general" {
                groupSymbols = reviewSymbols.filter { !assignedIds.contains($0.id) }
            } else {
                groupSymbols = reviewSymbols.filter {
                    $0.metadata["semantic_area"] == def.area && !assignedIds.contains($0.id)
                }
            }
            if !groupSymbols.isEmpty {
                assignedIds.formUnion(groupSymbols.map { $0.id })
                groups.append(SymbolReviewGroup(
                    semanticArea: def.area,
                    displayLabel: def.label,
                    iconName: def.icon,
                    symbols: groupSymbols
                ))
            }
        }

        return groups
    }

    // MARK: - Private helpers

    private static func maxSeverity(_ values: [Severity]) -> Severity {
        values.max() ?? .info
    }

    private static func getHunkIndex(_ file: ChangedFile, lineStart: Int?) -> Int? {
        guard let line = lineStart else { return nil }
        let idx = file.hunks.firstIndex { h in
            line >= h.newStart && line <= h.newStart + h.newLines - 1
        }
        return idx
    }

    private static func riskCategoryForFinding(_ f: Finding) -> RiskCategory {
        switch f.category {
        case .security: .security
        case .architecture: .coupling
        case .test: .testGap
        case .performance: .runtime
        default: .reviewLoad
        }
    }

    private static func bucketType(for file: ChangedFile, findings: [Finding]) -> ChangeBucketType {
        let path = file.path.lowercased()

        if file.classification == .test { return .tests }
        if file.classification == .generated || file.classification == .boilerplate { return .generated }
        if file.classification == .documentation { return .docs }
        if findings.contains(where: { $0.category == .security }) { return .authSecurity }

        if path.contains("auth") || path.contains("permission") || path.contains("security") || path.contains("secret") { return .authSecurity }
        if path.contains("migration") || path.contains("schema") || path.contains("/db/") || path.hasSuffix(".sql") { return .data }
        if path.hasSuffix("package.json") || path.hasSuffix("package-lock.json") || path.contains("vite.config") || path.contains("tsconfig") || path.contains("docker") { return .buildConfig }
        if path.contains("/viewmodels/") || path.hasSuffix("viewmodel.kt") { return .behavior }
        if path.contains("/ui/screens/") || path.contains("/components/") || path.contains("/frontend/") || path.hasSuffix(".tsx") || path.hasSuffix(".jsx") { return .ui }
        if path.contains("/data/") || path.contains("/models/") || path.contains("/domain/") { return .data }
        if findings.contains(where: { $0.category == .architecture }) { return .apiContract }

        return .behavior
    }

    /// Converts AST-extracted symbols into `RiskHighlight` objects for the triage dashboard.
    ///
    /// Replaces the old text-sniffing approach. Every classification now comes from
    /// structured `semantic_area`, `semantic_type`, and `is_test` tags produced by
    /// the diffuse-core Tree-Sitter sidecar — no substring scanning on raw diff lines.
    private static func deriveSemanticHighlights(
        symbols: [ChangedSymbol],
        files: [ChangedFile],
        bucketIdForPath: (String) -> String
    ) -> [RiskHighlight] {
        var highlights: [RiskHighlight] = []
        var counter = 0

        func add(
            filePath: String,
            severity: Severity,
            category: RiskCategory,
            title: String,
            lineStart: Int?,
            lineEnd: Int?,
            evidence: [String],
            confidence: String = "high",
            source: String = "ast-classifier"
        ) {
            highlights.append(RiskHighlight(
                id: "semantic-\(counter)",
                bucketId: bucketIdForPath(filePath),
                severity: severity,
                category: category,
                title: title,
                filePath: filePath,
                lineStart: lineStart,
                lineEnd: lineEnd,
                evidence: evidence,
                source: source,
                confidence: confidence
            ))
            counter += 1
        }

        // Build a fast lookup: changedFileId → file path
        let fileById = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0.path) })

        // --- Symbol-level highlights (from AST sidecar) ---
        for sym in symbols {
            let filePath = fileById[sym.changedFileId] ?? "unknown"
            let area = sym.metadata["semantic_area"] ?? ""

            switch area {
            case "security_authentication":
                add(filePath: filePath, severity: .high, category: .security,
                    title: "Auth symbol '\(sym.name)' modified",
                    lineStart: sym.startLine, lineEnd: sym.endLine,
                    evidence: [
                        "AST-verified: '\(sym.name)' (\(sym.semanticType)) is an authentication entry point.",
                        "Changes to auth logic must be reviewed for regressions, token invalidation, or bypass risks."
                    ])

            case "security_cryptography":
                add(filePath: filePath, severity: .high, category: .security,
                    title: "Cryptographic symbol '\(sym.name)' modified",
                    lineStart: sym.startLine, lineEnd: sym.endLine,
                    evidence: [
                        "AST-verified: '\(sym.name)' (\(sym.semanticType)) handles encryption or signing.",
                        "Cryptographic changes carry elevated risk — verify algorithm correctness and key handling."
                    ])

            case "payment":
                add(filePath: filePath, severity: .medium, category: .contract,
                    title: "Payment symbol '\(sym.name)' modified",
                    lineStart: sym.startLine, lineEnd: sym.endLine,
                    evidence: [
                        "AST-verified: '\(sym.name)' (\(sym.semanticType)) is in the payment flow.",
                        "Validate billing correctness and test edge cases (retries, partial failures, idempotency)."
                    ])

            case "data_deletion":
                add(filePath: filePath, severity: .medium, category: .data,
                    title: "Deletion symbol '\(sym.name)' modified",
                    lineStart: sym.startLine, lineEnd: sym.endLine,
                    evidence: [
                        "AST-verified: '\(sym.name)' (\(sym.semanticType)) performs data deletion.",
                        "Confirm deletion is intentional, properly scoped, and cascades are handled."
                    ])

            default:
                // Non-critical named symbol — emit a low-severity reviewLoad signal for
                // any public/exposed declaration that changed.
                if sym.metadata["visibility"] == "public" || sym.metadata["visibility"] == nil {
                    let isTest = sym.metadata["is_test"] == "true"
                    if isTest {
                        add(filePath: filePath, severity: .info, category: .testGap,
                            title: "Test '\(sym.name)' updated",
                            lineStart: sym.startLine, lineEnd: sym.endLine,
                            evidence: ["Test coverage updated for '\(sym.name)'."],
                            confidence: "medium")
                    } else if sym.semanticType == "class_declaration" || sym.semanticType == "struct_declaration"
                        || sym.semanticType == "protocol_declaration" || sym.semanticType == "interface_declaration" {
                        add(filePath: filePath, severity: .low, category: .contract,
                            title: "\(sym.semanticType.replacingOccurrences(of: "_", with: " ").capitalized) '\(sym.name)' changed",
                            lineStart: sym.startLine, lineEnd: sym.endLine,
                            evidence: ["Public type '\(sym.name)' changed — check callers and conformances."],
                            confidence: "medium")
                    }
                }
            }

            // --- Step 5: Behavioral body metadata highlights ---
            // These fire for any symbol, in addition to the semantic area checks above.

            if sym.metadata["network_call_added"] == "true" {
                add(filePath: filePath, severity: .low, category: .coupling,
                    title: "'\(sym.name)' adds a network call",
                    lineStart: sym.startLine, lineEnd: sym.endLine,
                    evidence: ["AST comparison: '\(sym.name)' introduces a network request. Verify error handling, timeouts, and retry logic."],
                    confidence: "medium",
                    source: "behavioral-scanner")
            }

            if sym.metadata["persistence_write_added"] == "true" {
                add(filePath: filePath, severity: .medium, category: .data,
                    title: "'\(sym.name)' adds a persistent write",
                    lineStart: sym.startLine, lineEnd: sym.endLine,
                    evidence: ["AST comparison: '\(sym.name)' introduces a persistence write. Confirm data model compatibility and migration."],
                    confidence: "medium",
                    source: "behavioral-scanner")
            }

            if sym.metadata["auth_check_added"] == "true" && sym.metadata["semantic_area"] != "security_authentication" {
                // Only emit if not already covered by the auth semantic area highlight
                add(filePath: filePath, severity: .high, category: .security,
                    title: "'\(sym.name)' adds an authorization check",
                    lineStart: sym.startLine, lineEnd: sym.endLine,
                    evidence: ["AST comparison: authorization guard introduced in '\(sym.name)'. Verify the check is sufficient and cannot be bypassed."],
                    confidence: "medium",
                    source: "behavioral-scanner")
            }

            if sym.metadata["deletion_added"] == "true" && sym.metadata["semantic_area"] != "data_deletion" {
                // Only emit if not already covered by the data_deletion semantic area highlight
                add(filePath: filePath, severity: .medium, category: .data,
                    title: "'\(sym.name)' adds a deletion or destructive operation",
                    lineStart: sym.startLine, lineEnd: sym.endLine,
                    evidence: ["AST comparison: destructive operation introduced in '\(sym.name)'. Confirm scope and cascade handling."],
                    confidence: "medium",
                    source: "behavioral-scanner")
            }

            if sym.metadata["async_behavior_added"] == "true" {
                add(filePath: filePath, severity: .info, category: .runtime,
                    title: "'\(sym.name)' adds async/concurrency behavior",
                    lineStart: sym.startLine, lineEnd: sym.endLine,
                    evidence: ["AST comparison: async or concurrency patterns introduced in '\(sym.name)'. Verify task scheduling and cancellation."],
                    confidence: "low",
                    source: "behavioral-scanner")
            }

        } // end for sym in symbols

        // --- File-level highlights (no sidecar data available, or non-source files) ---
        // Only fires for files that produced zero symbols (binary, unsupported language, etc.)
        let filesWithSymbols = Set(symbols.map { $0.changedFileId })
        for file in files {
            // Test files not covered by a symbol highlight
            if file.classification == .test && !filesWithSymbols.contains(file.id) {
                add(filePath: file.path, severity: .info, category: .testGap,
                    title: "Tests updated",
                    lineStart: nil, lineEnd: nil,
                    evidence: ["\(file.path) adds or updates test coverage."],
                    confidence: "medium",
                    source: "file-classifier")
            }

            // SQL migrations and config-tracked schema files — path-based, no AST needed
            let lpath = file.path.lowercased()
            if file.classification == .source && (lpath.hasSuffix(".sql") || lpath.contains("migration")) {
                add(filePath: file.path, severity: .medium, category: .data,
                    title: "Database schema migration",
                    lineStart: nil, lineEnd: nil,
                    evidence: ["Schema changes can affect existing data. Check for missing backfills or default values."],
                    source: "file-classifier")
            }

            // Large UI surfaces with no symbol detail (e.g. JSX/TSX not yet parsed)
            if !filesWithSymbols.contains(file.id) && file.classification == .source && file.additions > 20 {
                let isUI = lpath.contains("/ui/") || lpath.hasSuffix(".tsx") || lpath.hasSuffix(".jsx")
                    || lpath.hasSuffix("screen.kt") || lpath.hasSuffix(".swift")
                if isUI {
                    let screenName = URL(fileURLWithPath: file.path).deletingPathExtension().lastPathComponent
                    add(filePath: file.path, severity: .info, category: .reviewLoad,
                        title: "\(screenName) user-facing surface changed",
                        lineStart: nil, lineEnd: nil,
                        evidence: ["\(file.additions) added lines may affect visible copy, controls, or layout."],
                        confidence: "low",
                        source: "file-classifier")
                }
            }
        }

        return highlights
    }
}
