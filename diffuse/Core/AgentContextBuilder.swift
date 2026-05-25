import Foundation

enum AgentContextBuilder {
    nonisolated static let schemaVersion = "2026-05-25"

    nonisolated static func build(
        details: AnalysisDetails,
        repository: GitRepository?,
        profile: AnalysisProfile,
        selectedCommitSha: String? = nil,
        activeBranch: String? = nil,
        options: AgentContextOptions = AgentContextOptions()
    ) -> AgentReviewContext {
        let cap = cap(for: options)
        let fileById = Dictionary(uniqueKeysWithValues: details.files.map { ($0.id, $0) })
        let symbolsByFile = Dictionary(grouping: details.symbols, by: \.changedFileId)
        let findingsByFile = Dictionary(grouping: details.findings, by: \.changedFileId)
        let highlightsByFile = Dictionary(grouping: details.riskHighlights, by: \.filePath)

        let allFiles = details.files.sorted { $0.path < $1.path }
        let allSymbols = details.symbols.sorted {
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.startLine < $1.startLine
        }
        let allFindings = details.findings.sorted {
            if $0.severity != $1.severity {
                return severityRank($0.severity) > severityRank($1.severity)
            }
            if $0.message != $1.message { return $0.message < $1.message }
            return ($0.lineStart ?? 0) < ($1.lineStart ?? 0)
        }

        let files: [AgentFileContext] =
            options.includeFiles
            ? limited(allFiles, cap).items.map { file in
                mapFile(
                    file,
                    symbols: symbolsByFile[file.id] ?? [],
                    findings: findingsByFile[file.id] ?? [],
                    buckets: details.changeBuckets.filter { $0.files.contains(file.path) },
                    highlights: highlightsByFile[file.path] ?? [],
                    fileById: fileById,
                    detailLevel: options.detailLevel
                )
            }
            : []

        let symbols: [AgentSymbolContext] =
            options.includeSymbols
            ? limited(allSymbols, cap).items.map { mapSymbol($0, fileById: fileById) }
            : []

        let findingLimit = options.detailLevel == .summary ? min(cap, 10) : cap
        let limitedFindings = limited(allFindings, findingLimit)

        let targetLimit = options.detailLevel == .summary ? min(cap, 10) : cap
        let bucketLimit = options.detailLevel == .summary ? min(cap, 8) : cap
        let highlightLimit = options.detailLevel == .summary ? min(cap, 10) : cap
        let skimLimit = options.detailLevel == .summary ? min(cap, 10) : cap

        let limitedTargets = limited(
            details.reviewTargets.sorted { $0.priority < $1.priority }, targetLimit)
        let limitedBuckets = limited(
            details.changeBuckets.sorted { $0.reviewOrder < $1.reviewOrder }, bucketLimit)
        let limitedHighlights = limited(
            details.riskHighlights.sorted {
                if $0.severity != $1.severity {
                    return severityRank($0.severity) > severityRank($1.severity)
                }
                return $0.title < $1.title
            }, highlightLimit)
        let limitedSkim = limited(
            details.skimTargets.sorted { $0.filePath < $1.filePath }, skimLimit)

        let repoPath = repository?.path
        let profileSourcePath = repoPath.map { path in
            URL(fileURLWithPath: path).appendingPathComponent(AnalysisProfileStore.repoConfigPath)
                .path
        }
        let hasRepoProfile = repoPath.map(AnalysisProfileStore.hasRepoProfile(repoPath:)) ?? false
        let detectedPreset = repoPath.map(AnalysisProfileStore.detectBuiltInProfileId(repoPath:))

        return AgentReviewContext(
            schemaVersion: Self.schemaVersion,
            source: "diffuse",
            detailLevel: options.detailLevel,
            workspace: AgentWorkspaceContext(
                id: repository?.id.uuidString,
                name: repository?.name ?? details.pr.repository,
                path: repository?.path,
                activeBranch: activeBranch
            ),
            scope: AgentReviewScope(
                runId: details.run.id.uuidString,
                pullRequestId: details.pr.id.uuidString,
                pullRequestNumber: details.pr.prNumber,
                pullRequestTitle: details.pr.title,
                baseSha: details.run.baseSha,
                headSha: details.run.headSha,
                selectedCommitSha: selectedCommitSha,
                status: details.run.status.rawValue,
                createdAt: details.run.createdAt,
                updatedAt: details.run.updatedAt
            ),
            summary: mapSummary(details),
            profile: mapProfile(
                profile,
                source: hasRepoProfile ? "repository" : "builtin",
                sourcePath: hasRepoProfile ? profileSourcePath : nil,
                detectedPresetId: hasRepoProfile ? nil : detectedPreset
            ),
            reviewPlan: AgentReviewPlanContext(
                targets: limitedTargets.items.map(mapReviewTarget),
                buckets: limitedBuckets.items.map(mapBucket),
                riskHighlights: limitedHighlights.items.map(mapRiskHighlight),
                skimTargets: limitedSkim.items.map(mapSkimTarget)
            ),
            files: files,
            symbols: symbols,
            findings: limitedFindings.items.map { mapFinding($0, fileById: fileById) },
            truncated: AgentTruncation(
                files: options.includeFiles && limited(allFiles, cap).truncated,
                symbols: options.includeSymbols && limited(allSymbols, cap).truncated,
                findings: limitedFindings.truncated,
                reviewTargets: limitedTargets.truncated,
                buckets: limitedBuckets.truncated,
                riskHighlights: limitedHighlights.truncated,
                skimTargets: limitedSkim.truncated
            ),
            nextActions: [
                "diffuse.get_review_plan",
                "diffuse.explain_file",
                "diffuse.search_review_context",
            ]
        )
    }

    nonisolated static func profileContext(
        profile: AnalysisProfile,
        repository: GitRepository?,
        includeRules: Bool
    ) -> AgentProfileContext {
        let hasRepoProfile =
            repository.map { AnalysisProfileStore.hasRepoProfile(repoPath: $0.path) }
            ?? false
        let sourcePath =
            hasRepoProfile
            ? repository.map {
                URL(fileURLWithPath: $0.path).appendingPathComponent(
                    AnalysisProfileStore.repoConfigPath
                ).path
            } : nil
        let detectedPreset =
            hasRepoProfile
            ? nil
            : repository.map {
                AnalysisProfileStore.detectBuiltInProfileId(repoPath: $0.path)
            }
        var context = mapProfile(
            profile,
            source: hasRepoProfile ? "repository" : "builtin",
            sourcePath: sourcePath,
            detectedPresetId: detectedPreset
        )
        if !includeRules {
            context.ruleCounts = [:]
        }
        return context
    }

    nonisolated static func mapFile(
        _ file: ChangedFile,
        symbols: [ChangedSymbol],
        findings: [Finding],
        buckets: [ChangeBucket],
        highlights: [RiskHighlight],
        fileById: [UUID: ChangedFile],
        detailLevel: AgentContextDetailLevel
    ) -> AgentFileContext {
        let hunkLimit = detailLevel == .full ? file.hunks.count : min(file.hunks.count, 5)
        let hunks = file.hunks.prefix(hunkLimit).enumerated().map { index, hunk in
            mapHunk(hunk, index: index, detailLevel: detailLevel)
        }
        return AgentFileContext(
            id: file.id.uuidString,
            path: file.path,
            status: file.status.rawValue,
            classification: file.classification.rawValue,
            additions: file.additions,
            deletions: file.deletions,
            hunks: hunks,
            findings: findings.sorted { $0.message < $1.message }.map {
                mapFinding($0, fileById: fileById)
            },
            symbols: symbols.sorted { $0.startLine < $1.startLine }.map {
                mapSymbol($0, fileById: fileById)
            },
            buckets: buckets.sorted { $0.reviewOrder < $1.reviewOrder }.map(\.id),
            riskHighlights: highlights.sorted { $0.title < $1.title }.map(mapRiskHighlight),
            truncated: hunkLimit < file.hunks.count
        )
    }

    nonisolated static func mapSymbol(_ symbol: ChangedSymbol, fileById: [UUID: ChangedFile])
        -> AgentSymbolContext
    {
        AgentSymbolContext(
            id: symbol.id.uuidString,
            fileId: symbol.changedFileId.uuidString,
            filePath: fileById[symbol.changedFileId]?.path ?? symbol.metadata["file_path"],
            name: symbol.name,
            kind: symbol.kind.rawValue,
            semanticType: symbol.semanticType,
            language: symbol.metadata["language"],
            semanticArea: symbol.metadata["semantic_area"],
            startLine: symbol.startLine,
            endLine: symbol.endLine,
            callers: symbol.callers.sorted(),
            callees: symbol.callees.sorted(),
            contractDeltas: filteredMetadata(symbol.metadata, prefix: "contract_"),
            behaviorDeltas: filteredMetadata(symbol.metadata, suffix: "_added"),
            metadata: symbol.metadata
        )
    }

    nonisolated static func mapFinding(_ finding: Finding, fileById: [UUID: ChangedFile])
        -> AgentFindingContext
    {
        AgentFindingContext(
            id: finding.id.uuidString,
            fileId: finding.changedFileId.uuidString,
            filePath: fileById[finding.changedFileId]?.path,
            severity: finding.severity.rawValue,
            category: finding.category.rawValue,
            message: finding.message,
            lineStart: finding.lineStart,
            lineEnd: finding.lineEnd,
            ruleSource: finding.ruleSource,
            evidence: finding.evidence
        )
    }

    private nonisolated static func mapSummary(_ details: AnalysisDetails) -> AgentReviewSummary {
        AgentReviewSummary(
            riskScore: details.run.riskScore,
            changedFileCount: details.files.count,
            additions: details.files.reduce(0) { $0 + $1.additions },
            deletions: details.files.reduce(0) { $0 + $1.deletions },
            fileStatusCounts: count(details.files.map { $0.status.rawValue }),
            fileClassificationCounts: count(details.files.map { $0.classification.rawValue }),
            findingSeverityCounts: count(details.findings.map { $0.severity.rawValue }),
            findingCategoryCounts: count(details.findings.map { $0.category.rawValue }),
            symbolCount: details.symbols.count,
            topRiskFactors: Array(details.riskFactors.prefix(8))
        )
    }

    private nonisolated static func mapProfile(
        _ profile: AnalysisProfile,
        source: String,
        sourcePath: String?,
        detectedPresetId: String?
    ) -> AgentProfileContext {
        AgentProfileContext(
            id: profile.id,
            displayName: profile.displayName,
            source: source,
            sourcePath: sourcePath,
            detectedPresetId: detectedPresetId,
            fileClassificationRuleCount: profile.fileClassifications.count,
            bucketRuleCount: profile.buckets.count,
            symbolGroupRuleCount: profile.symbolGroups.count,
            semanticHighlightRuleCount: profile.semanticHighlights.count,
            fileHighlightRuleCount: profile.fileHighlights.count,
            ruleCounts: [
                "missingTests": profile.rules.missingTests == nil ? 0 : 1,
                "schemaSync": profile.rules.schemaSync == nil ? 0 : 1,
                "importBoundaries": profile.rules.importBoundaries.count,
                "semanticAreaFindings": profile.rules.semanticAreaFindings.count,
                "contractFindings": profile.rules.contractFindings.count,
                "symbolCoverage": profile.rules.symbolCoverage == nil ? 0 : 1,
            ],
            riskScoring: AgentRiskScoringContext(
                apiPathCount: profile.riskScoring.apiPaths.count,
                sensitivePathCount: profile.riskScoring.sensitivePaths.count,
                productionChangeDelta: profile.riskScoring.productionChangeDelta,
                apiPathDelta: profile.riskScoring.apiPathDelta,
                sensitivePathDelta: profile.riskScoring.sensitivePathDelta,
                missingTestsDelta: profile.riskScoring.missingTestsDelta
            )
        )
    }

    private nonisolated static func mapReviewTarget(_ target: ReviewTarget)
        -> AgentReviewTargetContext
    {
        AgentReviewTargetContext(
            id: target.id.uuidString,
            priority: target.priority,
            severity: target.severity.rawValue,
            title: target.title,
            filePath: target.filePath,
            lineStart: target.lineStart,
            lineEnd: target.lineEnd,
            reason: target.reason,
            evidence: target.evidence,
            source: target.source
        )
    }

    private nonisolated static func mapBucket(_ bucket: ChangeBucket) -> AgentBucketContext {
        AgentBucketContext(
            id: bucket.id,
            type: bucket.type.rawValue,
            title: bucket.title,
            summary: bucket.summary,
            files: bucket.files.sorted(),
            symbols: bucket.symbols.sorted(),
            riskLevel: bucket.riskLevel.rawValue,
            riskReasons: bucket.riskReasons.sorted(),
            evidence: bucket.evidence.sorted(),
            reviewOrder: bucket.reviewOrder
        )
    }

    private nonisolated static func mapRiskHighlight(_ highlight: RiskHighlight)
        -> AgentRiskHighlightContext
    {
        AgentRiskHighlightContext(
            id: highlight.id,
            bucketId: highlight.bucketId,
            severity: highlight.severity.rawValue,
            category: highlight.category.rawValue,
            title: highlight.title,
            filePath: highlight.filePath,
            lineStart: highlight.lineStart,
            lineEnd: highlight.lineEnd,
            evidence: highlight.evidence.sorted(),
            source: highlight.source,
            confidence: highlight.confidence
        )
    }

    private nonisolated static func mapSkimTarget(_ target: SkimTarget) -> AgentSkimTargetContext {
        AgentSkimTargetContext(
            id: target.id,
            filePath: target.filePath,
            reason: target.reason,
            classification: target.classification.rawValue,
            additions: target.additions,
            deletions: target.deletions,
            groupName: skimGroupName(for: target.classification)
        )
    }

    private nonisolated static func mapHunk(
        _ hunk: DiffHunk,
        index: Int,
        detailLevel: AgentContextDetailLevel
    ) -> AgentHunkContext {
        let ranges = changedLineRanges(in: hunk)
        let previewLimit: Int
        switch detailLevel {
        case .summary:
            previewLimit = 0
        case .standard:
            previewLimit = 12
        case .full:
            previewLimit = 120
        }
        let preview = Array(hunk.lines.prefix(previewLimit))
        return AgentHunkContext(
            index: index,
            oldStart: hunk.oldStart,
            oldLines: hunk.oldLines,
            newStart: hunk.newStart,
            newLines: hunk.newLines,
            changedLineRanges: ranges,
            previewLines: preview,
            truncated: hunk.lines.count > preview.count
        )
    }

    private nonisolated static func changedLineRanges(in hunk: DiffHunk) -> [AgentLineRange] {
        var ranges: [AgentLineRange] = []
        var currentLine = hunk.newStart
        var pendingStart: Int?
        var previousAdded: Int?

        func finishPending() {
            if let start = pendingStart, let end = previousAdded {
                ranges.append(AgentLineRange(start: start, end: end))
            }
            pendingStart = nil
            previousAdded = nil
        }

        for rawLine in hunk.lines {
            if rawLine.hasPrefix("+") && !rawLine.hasPrefix("+++") {
                if pendingStart == nil {
                    pendingStart = currentLine
                }
                previousAdded = currentLine
                currentLine += 1
            } else if rawLine.hasPrefix("-") {
                finishPending()
            } else {
                finishPending()
                currentLine += 1
            }
        }
        finishPending()
        return ranges
    }

    private nonisolated static func cap(for options: AgentContextOptions) -> Int {
        switch options.detailLevel {
        case .summary:
            min(options.maxItems, 20)
        case .standard:
            options.maxItems
        case .full:
            max(options.maxItems, 100)
        }
    }

    private nonisolated static func limited<T>(_ items: [T], _ limit: Int) -> (
        items: [T], truncated: Bool
    ) {
        let capped = Array(items.prefix(max(0, limit)))
        return (capped, items.count > capped.count)
    }

    private nonisolated static func count(_ values: [String]) -> [String: Int] {
        values.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    private nonisolated static func severityRank(_ severity: Severity) -> Int {
        switch severity {
        case .info:
            1
        case .low:
            2
        case .medium:
            3
        case .high:
            4
        }
    }

    private nonisolated static func skimGroupName(
        for classification: ChangedFile.FileClassification
    )
        -> String
    {
        switch classification {
        case .generated:
            "Generated & Lockfiles"
        case .config:
            "Configuration"
        case .documentation:
            "Documentation"
        case .boilerplate:
            "Boilerplate"
        default:
            "Other"
        }
    }

    private nonisolated static func filteredMetadata(_ metadata: [String: String], prefix: String)
        -> [String: String]
    {
        metadata.filter { key, _ in key.hasPrefix(prefix) }
    }

    private nonisolated static func filteredMetadata(_ metadata: [String: String], suffix: String)
        -> [String: String]
    {
        metadata.filter { key, _ in key.hasSuffix(suffix) }
    }
}
