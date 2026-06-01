import Foundation
import Observation

@Observable
@MainActor
class ImpactGraphViewModel {
    var searchText: String = ""
    var selectedSymbolId: UUID? = nil
    var changedOnly: Bool = true

    private(set) var impacts: [SymbolImpact] = []
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
        Array(filteredImpacts.prefix(3))
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

    func load(details: AnalysisDetails) {
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
                    summary: makeSummary(symbol: symbol, filePath: path)
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

        if let selectedSymbolId, impacts.contains(where: { $0.id == selectedSymbolId }) {
            return
        }
        selectedSymbolId = filteredImpacts.first?.id
    }

    func select(_ impact: SymbolImpact) {
        selectedSymbolId = impact.id
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
}
