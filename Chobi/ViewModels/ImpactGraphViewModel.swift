import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
class ImpactGraphViewModel {
    var searchText: String = ""
    var selectedSymbolId: UUID? = nil
    var changedOnly: Bool = true
    var graphDepth: Int = 1
    var graphDirection: ImpactGraphDirection = .both
    var originImpactId: UUID? = nil
    var focusedNodeId: String? = nil
    var selectedGraphNodeId: String? = nil
    private(set) var focusBackStack: [String] = []
    private(set) var focusForwardStack: [String] = []
    private(set) var selectedSourceContext: SymbolSourceContext? = nil

    var repoPath: String? = nil
    var selectedSourceLines: [SourceCodeLine] = []
    var isLoadingSourceCode: Bool = false
    var sourceCodeError: String? = nil
    var showFullFile: Bool = false

    private(set) var impacts: [SymbolImpact] = []
    private(set) var visibleImpactsByFileId: [UUID: [SymbolImpact]] = [:]
    private(set) var sourceSymbolCount: Int = 0

    var highImpactCount: Int {
        impacts.filter { $0.summary.impactLevel == .high }.count
    }

    var totalImpactedReferenceCount: Int {
        impacts.reduce(0) { total, impact in
            total + impact.summary.directCallerCount + impact.summary.directCalleeCount
        }
    }

    var impactedFileCount: Int {
        Set(impacts.map(\.filePath)).count
    }

    var symbolsWithoutTestsCount: Int {
        impacts.filter { $0.summary.testReferenceCount == 0 && $0.hasImpactData }.count
    }

    var topImpacts: [SymbolImpact] {
        Array(reviewQueue.prefix(3))
    }

    var reviewQueue: [SymbolImpact] {
        filteredImpacts.filter { $0.hasImpactData || $0.hasUsefulReason }
    }

    var quietReviewQueue: [SymbolImpact] {
        Array(reviewQueue.prefix(hasSearchQuery ? 8 : 5))
    }

    var filteredImpacts: [SymbolImpact] {
        let sorted = impacts.sorted { lhs, rhs in
            let leftScore = impactSortScore(lhs)
            let rightScore = impactSortScore(rhs)
            if leftScore != rightScore { return leftScore > rightScore }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return sorted }

        return sorted.filter { impact in
            impact.title.lowercased().contains(query)
                || impact.symbol.name.lowercased().contains(query)
                || impact.filePath.lowercased().contains(query)
                || impact.symbol.kind.rawValue.lowercased().contains(query)
        }
    }

    var selectedImpact: SymbolImpact? {
        guard let selectedSymbolId else { return filteredImpacts.first ?? impacts.first }
        return impacts.first { $0.id == selectedSymbolId } ?? filteredImpacts.first
    }

    var originImpact: SymbolImpact? {
        guard let originImpactId else { return selectedImpact }
        return impacts.first { $0.id == originImpactId } ?? selectedImpact
    }

    var focusedNode: ImpactGraphNode? {
        visibleGraphNodes.first { $0.id == currentFocusedNodeId }
    }

    var selectedGraphNode: ImpactGraphNode? {
        guard let selectedGraphNodeId else { return focusedNode }
        return visibleGraphNodes.first { $0.id == selectedGraphNodeId } ?? focusedNode
    }

    var currentFocusedNodeId: String? {
        focusedNodeId ?? originImpact.map { nodeId(for: $0.symbol.name, filePath: $0.filePath) }
    }

    var graphPathText: String {
        guard let origin = originImpact else { return "No changed symbol selected" }
        guard let focused = focusedNode,
            focused.id != nodeId(for: origin.symbol.name, filePath: origin.filePath)
        else { return origin.symbol.name }
        return "\(origin.symbol.name) <- \(focused.title)"
    }

    var canGoBack: Bool { !focusBackStack.isEmpty }

    var canGoForward: Bool { !focusForwardStack.isEmpty }

    var visibleGraphNodes: [ImpactGraphNode] {
        guard let origin = originImpact else { return [] }
        let graphRoot = focusedImpact ?? origin
        var nodes: [ImpactGraphNode] = [
            ImpactGraphNode(
                id: nodeId(for: origin.symbol.name, filePath: origin.filePath),
                title: origin.symbol.name,
                filePath: origin.filePath,
                line: origin.symbol.startLine,
                role: .origin,
                isChangedInPR: true,
                isTest: origin.filePath.isTestPath)
        ]

        let graphRootId = nodeId(for: graphRoot.symbol.name, filePath: graphRoot.filePath)
        if !nodes.contains(where: { $0.id == graphRootId }) {
            nodes.append(
                ImpactGraphNode(
                    id: graphRootId,
                    title: graphRoot.symbol.name,
                    filePath: graphRoot.filePath,
                    line: graphRoot.symbol.startLine,
                    role: .origin,
                    isChangedInPR: true,
                    isTest: graphRoot.filePath.isTestPath))
        }

        if graphDirection == .callers || graphDirection == .both {
            nodes.append(
                contentsOf: graphRoot.symbol.callers.prefix(nodeLimit).map {
                    makeRelatedNode(row: $0, role: .caller)
                })
        }
        if graphDirection == .callees || graphDirection == .both {
            nodes.append(
                contentsOf: graphRoot.symbol.callees.prefix(nodeLimit).map {
                    makeRelatedNode(row: $0, role: .callee)
                })
        }

        return Array(Dictionary(grouping: nodes, by: \.id).compactMap { $0.value.first })
    }

    private var focusedImpact: SymbolImpact? {
        guard let currentFocusedNodeId else { return nil }
        return impacts.first { impact in
            nodeId(for: impact.symbol.name, filePath: impact.filePath) == currentFocusedNodeId
                || nodeId(for: impact.qualifiedName, filePath: impact.filePath)
                    == currentFocusedNodeId
        }
    }

    var fileImpactIndicators: [UUID: FileImpactIndicator] {
        Dictionary(
            uniqueKeysWithValues: visibleImpactsByFileId.compactMap { fileId, impacts in
                guard !impacts.isEmpty else { return nil }
                return (
                    fileId,
                    FileImpactIndicator(
                        count: impacts.count,
                        highCount: impacts.filter { $0.summary.impactLevel == .high }.count,
                        mediumCount: impacts.filter { $0.summary.impactLevel == .medium }.count,
                        callerCount: impacts.reduce(0) { $0 + $1.summary.directCallerCount },
                        changedHighImpactCount: impacts.filter {
                            $0.summary.impactLevel == .high
                        }.count,
                        weakTestCount: impacts.filter {
                            $0.summary.testReferenceCount == 0 && $0.hasImpactData
                        }.count)
                )
            }
        )
    }

    var hasSearchQuery: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var emptyStateText: String {
        if sourceSymbolCount == 0 {
            return "No changed symbols were extracted for this analysis."
        }
        if hasSearchQuery {
            return "No changed symbols match this search."
        }
        return "No caller or callee data found for changed symbols."
    }

    func load(details: AnalysisDetails, repoPath: String? = nil) {
        self.repoPath = repoPath
        sourceSymbolCount = details.symbols.count
        let filesById = Dictionary(uniqueKeysWithValues: details.files.map { ($0.id, $0.path) })
        impacts =
            details.symbols
            .map { symbol in
                let path =
                    filesById[symbol.changedFileId] ?? symbol.metadata["file_path"] ?? "unknown"
                return SymbolImpact(
                    id: symbol.id,
                    symbol: symbol,
                    filePath: path,
                    summary: makeSummary(symbol: symbol, filePath: path),
                    reason: makeReason(symbol: symbol, filePath: path),
                    affectedDomains: affectedDomains(symbol: symbol, filePath: path),
                    topAffectedSymbols: topAffectedSymbols(symbol: symbol)
                )
            }
            .filter { impact in
                switch impact.symbol.kind {
                case .function, .method, .class, .struct, .enum, .protocol, .extension, .property,
                    .constructor, .type:
                    true
                default:
                    impact.hasImpactData
                }
            }
        visibleImpactsByFileId = Dictionary(
            uniqueKeysWithValues: details.files.map { file in
                (file.id, visibleImpacts(for: file))
            })

        if let selectedSymbolId, impacts.contains(where: { $0.id == selectedSymbolId }) {
            return
        }
        selectedSymbolId = filteredImpacts.first?.id
        originImpactId = selectedSymbolId
        focusedNodeId = selectedImpact.map { nodeId(for: $0.symbol.name, filePath: $0.filePath) }
        selectedGraphNodeId = focusedNodeId
        updateSelectedSourceContext()
    }

    func select(_ impact: SymbolImpact) {
        selectedSymbolId = impact.id
        originImpactId = impact.id
        focusedNodeId = nodeId(for: impact.symbol.name, filePath: impact.filePath)
        selectedGraphNodeId = focusedNodeId
        focusBackStack = []
        focusForwardStack = []
        updateSelectedSourceContext()
    }

    func selectNextImpact() {
        selectAdjacentImpact(offset: 1)
    }

    func selectPreviousImpact() {
        selectAdjacentImpact(offset: -1)
    }

    func impacts(for file: ChangedFile) -> [SymbolImpact] {
        impacts
            .filter { $0.symbol.changedFileId == file.id }
            .sorted { lhs, rhs in
                if lhs.symbol.startLine != rhs.symbol.startLine {
                    return lhs.symbol.startLine < rhs.symbol.startLine
                }
                return impactSortScore(lhs) > impactSortScore(rhs)
            }
    }

    func visibleImpacts(for file: ChangedFile) -> [SymbolImpact] {
        let hunkImpacts = file.hunks.flatMap { hunk in
            displayImpacts(for: hunk, fileId: file.id)
        }
        var seen: Set<UUID> = []
        let unique = hunkImpacts.filter { impact in
            guard !seen.contains(impact.id) else { return false }
            seen.insert(impact.id)
            return true
        }
        if unique.isEmpty && file.hunks.isEmpty {
            return impacts(for: file).filter { $0.hasImpactData || $0.hasUsefulReason }
        }
        return unique.sorted { lhs, rhs in
            if lhs.symbol.startLine != rhs.symbol.startLine {
                return lhs.symbol.startLine < rhs.symbol.startLine
            }
            return impactSortScore(lhs) > impactSortScore(rhs)
        }
    }

    func inlineMarkers(for hunk: DiffHunk, file: ChangedFile, hunkIndex: Int)
        -> [InlineImpactMarker]
    {
        let hunkStart = hunk.newStart
        let hunkEnd = hunk.newStart + max(hunk.newLines - 1, 0)
        return displayImpacts(for: hunk, fileId: file.id).compactMap { impact in
            guard impact.hasImpactData || impact.hasUsefulReason else { return nil }
            let symbolStart = impact.symbol.startLine
            let anchor = max(hunkStart, symbolStart)
            guard anchor <= hunkEnd else { return nil }
            let firstHunkIndex = file.hunks.firstIndex { candidate in
                let end = candidate.newStart + max(candidate.newLines - 1, 0)
                return impact.symbol.startLine <= end && impact.symbol.endLine >= candidate.newStart
            }
            return InlineImpactMarker(
                id: UUID(),
                rootSymbolId: impact.id,
                filePath: file.path,
                anchorLine: anchor,
                hunkIndex: hunkIndex,
                summary: usefulSummary(for: impact),
                metrics: impact.summary,
                isContinuation: firstHunkIndex != nil && firstHunkIndex != hunkIndex)
        }
    }

    func selectGraphNode(_ node: ImpactGraphNode) {
        selectedGraphNodeId = node.id
        updateSelectedSourceContext()
    }

    func focusSelectedGraphNode() {
        guard let selectedGraphNodeId else { return }
        focus(on: selectedGraphNodeId)
    }

    func focusOrigin() {
        guard let origin = originImpact else { return }
        focus(on: nodeId(for: origin.symbol.name, filePath: origin.filePath))
    }

    func focusBack() {
        guard let previous = focusBackStack.popLast() else { return }
        if let currentFocusedNodeId {
            focusForwardStack.append(currentFocusedNodeId)
        }
        focusedNodeId = previous
        selectedGraphNodeId = previous
        updateSelectedSourceContext()
    }

    func focusForward() {
        guard let next = focusForwardStack.popLast() else { return }
        if let currentFocusedNodeId {
            focusBackStack.append(currentFocusedNodeId)
        }
        focusedNodeId = next
        selectedGraphNodeId = next
        updateSelectedSourceContext()
    }

    func usefulSummary(for impact: SymbolImpact) -> String {
        if let reason = impact.reason, !reason.isEmpty { return reason }
        return
            "\(impact.summary.directCallerCount) callers · \(impact.summary.directCalleeCount) callees · View graph"
    }

    private var nodeLimit: Int {
        max(3, min(12, graphDepth * 6))
    }

    private func focus(on nodeId: String) {
        if let currentFocusedNodeId, currentFocusedNodeId != nodeId {
            focusBackStack.append(currentFocusedNodeId)
        }
        focusForwardStack = []
        focusedNodeId = nodeId
        selectedGraphNodeId = nodeId
        updateSelectedSourceContext()
    }

    private func selectAdjacentImpact(offset: Int) {
        let queue = reviewQueue
        guard !queue.isEmpty else { return }
        let currentIndex =
            selectedSymbolId.flatMap { id in queue.firstIndex { $0.id == id } } ?? 0
        let nextIndex = (currentIndex + offset + queue.count) % queue.count
        select(queue[nextIndex])
    }

    private func updateSelectedSourceContext() {
        guard let node = selectedGraphNode else {
            selectedSourceContext = nil
            loadSourceCodeForSelectedNode()
            return
        }
        let start = node.line ?? 1
        let end = node.isChangedInPR ? (originImpact?.symbol.endLine ?? start) : start
        selectedSourceContext = SymbolSourceContext(
            symbolName: node.title,
            filePath: node.filePath,
            startLine: start,
            endLine: end,
            excerptStartLine: max(1, start - 3),
            excerpt: makeExcerpt(for: node),
            isChangedInCurrentPR: node.isChangedInPR,
            changedLineNumbers: node.isChangedInPR ? Set(start...max(start, end)) : [],
            callSiteLine: node.role == .origin ? nil : node.line)
        loadSourceCodeForSelectedNode()
    }

    func loadSourceCodeForSelectedNode() {
        guard let node = selectedGraphNode else {
            self.selectedSourceLines = []
            self.isLoadingSourceCode = false
            self.sourceCodeError = nil
            return
        }

        guard let repoPath = self.repoPath, !repoPath.isEmpty else {
            self.selectedSourceLines = []
            self.isLoadingSourceCode = false
            self.sourceCodeError = "Workspace repository path is not available."
            return
        }

        let filePath = node.filePath
        let highlightLine = node.line
        let isOrigin = node.role == .origin

        self.isLoadingSourceCode = true
        self.sourceCodeError = nil

        Task {
            do {
                let fileURL = URL(
                    fileURLWithPath: filePath, relativeTo: URL(fileURLWithPath: repoPath)
                ).standardized
                var fileContent = ""

                // Read from local workspace file if possible
                if FileManager.default.fileExists(atPath: fileURL.path),
                    let content = try? String(contentsOf: fileURL, encoding: .utf8)
                {
                    fileContent = content
                } else {
                    // Try to fall back to HEAD via git show
                    let fallback = GitService.fileContent(at: "HEAD", path: filePath, cwd: repoPath)
                    if !fallback.isEmpty {
                        fileContent = fallback
                    } else {
                        throw NSError(
                            domain: "ImpactExplorer", code: 404,
                            userInfo: [NSLocalizedDescriptionKey: "File not found: \(filePath)"])
                    }
                }

                let allLines = fileContent.components(separatedBy: .newlines)

                var finalLines: [SourceCodeLine] = []

                if showFullFile {
                    // Load all lines
                    finalLines = allLines.enumerated().map { index, lineText in
                        let lineNum = index + 1
                        let isHighlighted = highlightLine == lineNum
                        return SourceCodeLine(
                            lineNumber: lineNum, text: lineText, isHighlighted: isHighlighted)
                    }
                } else {
                    // Context mode: show 8 lines before and 16 lines after
                    let centerLine = highlightLine ?? (originImpact?.symbol.startLine ?? 1)
                    let startLine = max(1, centerLine - 8)
                    let endLine = min(allLines.count, centerLine + 16)

                    if startLine <= endLine && !allLines.isEmpty {
                        finalLines = (startLine...endLine).map { lineNum in
                            let lineText = allLines[lineNum - 1]
                            let isHighlighted: Bool
                            if isOrigin, let origin = originImpact {
                                isHighlighted =
                                    lineNum >= origin.symbol.startLine
                                    && lineNum <= origin.symbol.endLine
                            } else {
                                isHighlighted = highlightLine == lineNum
                            }
                            return SourceCodeLine(
                                lineNumber: lineNum, text: lineText, isHighlighted: isHighlighted)
                        }
                    }
                }

                self.selectedSourceLines = finalLines
                self.isLoadingSourceCode = false
            } catch {
                self.selectedSourceLines = []
                self.sourceCodeError = error.localizedDescription
                self.isLoadingSourceCode = false
            }
        }
    }

    private func makeExcerpt(for node: ImpactGraphNode) -> String {
        if node.isChangedInPR, let impact = originImpact {
            return
                "\(impact.symbol.kind.rawValue) \(impact.symbol.name)\n// Changed lines L\(impact.symbol.startLine)-L\(impact.symbol.endLine)"
        }
        let lineText = node.line.map { " at L\($0)" } ?? ""
        return "// Read-only source context\(lineText)\n\(node.title)"
    }

    func impacts(for hunk: DiffHunk, fileId: UUID) -> [SymbolImpact] {
        impacts
            .filter { impact in
                guard impact.symbol.changedFileId == fileId else { return false }
                let hunkEnd = hunk.newStart + max(hunk.newLines - 1, 0)
                return impact.symbol.startLine <= hunkEnd && impact.symbol.endLine >= hunk.newStart
            }
            .sorted { lhs, rhs in
                if impactSortScore(lhs) != impactSortScore(rhs) {
                    return impactSortScore(lhs) > impactSortScore(rhs)
                }
                return lhs.symbol.startLine < rhs.symbol.startLine
            }
    }

    private func displayImpacts(for hunk: DiffHunk, fileId: UUID) -> [SymbolImpact] {
        let hunkImpacts = impacts(for: hunk, fileId: fileId)
        return hunkImpacts.filter { candidate in
            !isContainerImpact(candidate, shadowedBy: hunkImpacts)
        }
    }

    private func isContainerImpact(_ candidate: SymbolImpact, shadowedBy impacts: [SymbolImpact])
        -> Bool
    {
        guard isContainerKind(candidate.symbol.kind) else { return false }
        return impacts.contains { other in
            guard other.id != candidate.id else { return false }
            guard other.symbol.changedFileId == candidate.symbol.changedFileId else { return false }
            guard other.hasImpactData || other.hasUsefulReason else { return false }
            return candidate.symbol.startLine <= other.symbol.startLine
                && candidate.symbol.endLine >= other.symbol.endLine
                && candidate.symbol.startLine < other.symbol.endLine
        }
    }

    private func isContainerKind(_ kind: ChangedSymbol.SymbolKind) -> Bool {
        switch kind {
        case .class, .struct, .enum, .protocol, .extension, .type:
            true
        default:
            false
        }
    }

    private func makeSummary(symbol: ChangedSymbol, filePath: String) -> ImpactSummary {
        let callerFiles = Set(
            symbol.callers.map { caller -> String in
                caller.components(separatedBy: ":").first ?? caller
            })
        let relatedFileCount = max(1, callerFiles.union([filePath]).count)
        let testReferenceCount = symbol.callers.filter { caller in
            caller.localizedCaseInsensitiveContains("test")
                || caller.localizedCaseInsensitiveContains("spec")
        }.count
        let directCallerCount = symbol.callers.count
        let directCalleeCount = symbol.callees.count
        let impactLevel = scoreImpact(
            directCallerCount: directCallerCount,
            directCalleeCount: directCalleeCount,
            fileCount: relatedFileCount,
            testReferenceCount: testReferenceCount,
            symbol: symbol
        )
        let confidence: CallGraphConfidence =
            symbol.metadata["caller_resolution"] == "indexed" || !symbol.callees.isEmpty
            ? .high : .medium

        return ImpactSummary(
            directCallerCount: directCallerCount,
            directCalleeCount: directCalleeCount,
            transitiveCallerCount: directCallerCount,
            transitiveCalleeCount: directCalleeCount,
            fileCount: relatedFileCount,
            testReferenceCount: testReferenceCount,
            impactLevel: impactLevel,
            confidence: confidence
        )
    }

    private func makeReason(symbol: ChangedSymbol, filePath: String) -> String? {
        let domains = affectedDomains(symbol: symbol, filePath: filePath)
        if domains.count >= 2 {
            return "Used by \(domains.prefix(2).joined(separator: " and ")) paths."
        }
        if filePath.isTestPath && !symbol.callees.isEmpty {
            return
                "Test behavior changes while exercising \(symbol.callees.prefix(2).joined(separator: ", "))."
        }
        if symbol.metadata["visibility"] == "public" || symbol.metadata["is_public"] == "true" {
            return
                "Public contract surface changed with \(symbol.callers.count) detected caller\(symbol.callers.count == 1 ? "" : "s")."
        }
        if symbol.callers.count >= 5 {
            return
                "High fan-in utility changed across \(Set(symbol.callers.map(pathPrefix)).count) files."
        }
        if symbol.callers.contains(where: { $0.isTestPath }) && symbol.callers.count > 1 {
            return "Production change has direct test references and runtime callers."
        }
        if symbol.callers.isEmpty && symbol.callees.isEmpty {
            return nil
        }
        if let domain = domains.first {
            return "\(domain.capitalized) path affected by this changed symbol."
        }
        return nil
    }

    private func affectedDomains(symbol: ChangedSymbol, filePath: String) -> [String] {
        let rows = [filePath] + symbol.callers + symbol.callees
        var domains: [String] = []
        func append(_ value: String) {
            if !domains.contains(value) { domains.append(value) }
        }
        for row in rows {
            let lower = row.lowercased()
            if lower.contains("view") || lower.contains("screen") || lower.contains("ui") {
                append("UI")
            }
            if lower.contains("model") || lower.contains("entity") || lower.contains("schema") {
                append("data model")
            }
            if lower.contains("store") || lower.contains("repository") || lower.contains("database")
            {
                append("persistence")
            }
            if lower.contains("api") || lower.contains("client") || lower.contains("controller") {
                append("API")
            }
            if lower.contains("analytics") || lower.contains("report") || lower.contains("snapshot")
            {
                append("analytics")
            }
        }
        return domains
    }

    private func topAffectedSymbols(symbol: ChangedSymbol) -> [String] {
        Array(symbol.callers.prefix(3).map(displayName))
    }

    private func scoreImpact(
        directCallerCount: Int,
        directCalleeCount: Int,
        fileCount: Int,
        testReferenceCount: Int,
        symbol: ChangedSymbol
    ) -> ImpactLevel {
        var score = directCallerCount * 2 + directCalleeCount + fileCount
        if symbol.metadata["visibility"] == "public" || symbol.metadata["is_public"] == "true" {
            score += 4
        }
        if testReferenceCount == 0 && directCallerCount > 0 {
            score += 2
        }
        if score >= 14 { return .high }
        if score >= 6 { return .medium }
        return .low
    }

    private func impactSortScore(_ impact: SymbolImpact) -> Int {
        let summary = impact.summary
        let levelScore: Int
        switch summary.impactLevel {
        case .high: levelScore = 10_000
        case .medium: levelScore = 5_000
        case .low: levelScore = 1_000
        }
        return levelScore + summary.directCallerCount * 100 + summary.directCalleeCount * 10
    }

    private func makeRelatedNode(row: String, role: ImpactGraphNode.Role) -> ImpactGraphNode {
        ImpactGraphNode(
            id: nodeId(for: displayName(row), filePath: pathPrefix(row)),
            title: displayName(row),
            filePath: pathPrefix(row),
            line: lineNumber(row),
            role: role,
            isChangedInPR: impacts.contains {
                $0.symbol.name == displayName(row) || $0.qualifiedName == displayName(row)
            },
            isTest: row.isTestPath)
    }

    private func nodeId(for name: String, filePath: String) -> String {
        "\(filePath)#\(name)"
    }

    private func displayName(_ row: String) -> String {
        row.components(separatedBy: ":").last ?? row
    }

    private func pathPrefix(_ row: String) -> String {
        row.components(separatedBy: ":").first ?? row
    }

    private func lineNumber(_ row: String) -> Int? {
        let parts = row.components(separatedBy: ":")
        return parts.compactMap(Int.init).first
    }
}

struct FileImpactIndicator: Hashable {
    let count: Int
    let highCount: Int
    let mediumCount: Int
    let callerCount: Int
    let changedHighImpactCount: Int
    let weakTestCount: Int

    var color: Color {
        if highCount > 0 { return .danger }
        if mediumCount > 0 { return .warning }
        return .success
    }

    var helpText: String {
        "\(count) impact signal\(count == 1 ? "" : "s")\n\(callerCount) callers of changed symbols\n\(changedHighImpactCount) changed high-impact symbols\n\(weakTestCount) weak test coverage signals"
    }
}

extension String {
    fileprivate var isTestPath: Bool {
        localizedCaseInsensitiveContains("test") || localizedCaseInsensitiveContains("spec")
    }
}

struct SourceCodeLine: Identifiable, Hashable {
    let id = UUID()
    let lineNumber: Int
    let text: String
    let isHighlighted: Bool
}
