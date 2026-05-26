import Foundation

enum AgentContextDetailLevel: String, Codable, CaseIterable, Sendable {
    case summary
    case standard
    case full
}

struct AgentContextOptions: Codable, Equatable, Sendable {
    var detailLevel: AgentContextDetailLevel
    var includeFiles: Bool
    var includeSymbols: Bool
    var maxItems: Int

    nonisolated init(
        detailLevel: AgentContextDetailLevel = .standard,
        includeFiles: Bool = true,
        includeSymbols: Bool = false,
        maxItems: Int = 30
    ) {
        self.detailLevel = detailLevel
        self.includeFiles = includeFiles
        self.includeSymbols = includeSymbols
        self.maxItems = max(1, maxItems)
    }
}

struct AgentTruncation: Codable, Equatable, Sendable {
    var files: Bool
    var symbols: Bool
    var findings: Bool
    var reviewTargets: Bool
    var buckets: Bool
    var riskHighlights: Bool
    var skimTargets: Bool

    var any: Bool {
        files || symbols || findings || reviewTargets || buckets || riskHighlights || skimTargets
    }
}

struct AgentWorkspaceContext: Codable, Equatable, Sendable {
    var id: String?
    var name: String
    var path: String?
    var activeBranch: String?
}

struct AgentReviewScope: Codable, Equatable, Sendable {
    var runId: String
    var pullRequestId: String
    var pullRequestNumber: Int
    var pullRequestTitle: String
    var baseSha: String
    var headSha: String
    var selectedCommitSha: String?
    var status: String
    var createdAt: Date
    var updatedAt: Date
}

struct AgentReviewSummary: Codable, Equatable, Sendable {
    var riskScore: Int
    var changedFileCount: Int
    var additions: Int
    var deletions: Int
    var fileStatusCounts: [String: Int]
    var fileClassificationCounts: [String: Int]
    var findingSeverityCounts: [String: Int]
    var findingCategoryCounts: [String: Int]
    var symbolCount: Int
    var topRiskFactors: [String]
}

struct AgentProfileContext: Codable, Equatable, Sendable {
    var id: String
    var displayName: String
    var source: String
    var sourcePath: String?
    var detectedPresetId: String?
    var fileClassificationRuleCount: Int
    var bucketRuleCount: Int
    var symbolGroupRuleCount: Int
    var semanticHighlightRuleCount: Int
    var fileHighlightRuleCount: Int
    var ruleCounts: [String: Int]
    var riskScoring: AgentRiskScoringContext
}

struct AgentRiskScoringContext: Codable, Equatable, Sendable {
    var apiPathCount: Int
    var sensitivePathCount: Int
    var productionChangeDelta: Int
    var apiPathDelta: Int
    var sensitivePathDelta: Int
    var missingTestsDelta: Int
}

struct AgentReviewTargetContext: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var priority: Int
    var severity: String
    var title: String
    var filePath: String
    var lineStart: Int?
    var lineEnd: Int?
    var reason: String
    var evidence: String
    var source: String
}

struct AgentFileContext: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var path: String
    var status: String
    var classification: String
    var additions: Int
    var deletions: Int
    var hunks: [AgentHunkContext]
    var findings: [AgentFindingContext]
    var symbols: [AgentSymbolContext]
    var buckets: [String]
    var riskHighlights: [AgentRiskHighlightContext]
    var truncated: Bool
}

struct AgentHunkContext: Codable, Equatable, Sendable {
    var index: Int
    var oldStart: Int
    var oldLines: Int
    var newStart: Int
    var newLines: Int
    var changedLineRanges: [AgentLineRange]
    var previewLines: [String]
    var truncated: Bool
}

struct AgentLineRange: Codable, Equatable, Sendable {
    var start: Int
    var end: Int
}

struct AgentSymbolContext: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var fileId: String
    var filePath: String?
    var name: String
    var kind: String
    var semanticType: String
    var language: String?
    var semanticArea: String?
    var startLine: Int
    var endLine: Int
    var callers: [String]
    var callees: [String]
    var contractDeltas: [String: String]
    var behaviorDeltas: [String: String]
    var metadata: [String: String]
}

struct AgentFindingContext: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var fileId: String
    var filePath: String?
    var severity: String
    var category: String
    var message: String
    var lineStart: Int?
    var lineEnd: Int?
    var ruleSource: String
    var evidence: String?
}

struct AgentBucketContext: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var type: String
    var title: String
    var summary: String
    var files: [String]
    var symbols: [String]
    var riskLevel: String
    var riskReasons: [String]
    var evidence: [String]
    var reviewOrder: Int
}

struct AgentRiskHighlightContext: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var bucketId: String
    var severity: String
    var category: String
    var title: String
    var filePath: String
    var lineStart: Int?
    var lineEnd: Int?
    var evidence: [String]
    var source: String
    var confidence: String
}

struct AgentSkimTargetContext: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var filePath: String
    var reason: String
    var classification: String
    var additions: Int
    var deletions: Int
    var groupName: String
}

struct AgentReviewPlanContext: Codable, Equatable, Sendable {
    var targets: [AgentReviewTargetContext]
    var buckets: [AgentBucketContext]
    var riskHighlights: [AgentRiskHighlightContext]
    var skimTargets: [AgentSkimTargetContext]
}

struct AgentReviewContext: Codable, Equatable, Sendable {
    var schemaVersion: String
    var source: String
    var detailLevel: AgentContextDetailLevel
    var workspace: AgentWorkspaceContext
    var scope: AgentReviewScope
    var summary: AgentReviewSummary
    var profile: AgentProfileContext
    var reviewPlan: AgentReviewPlanContext
    var files: [AgentFileContext]
    var symbols: [AgentSymbolContext]
    var findings: [AgentFindingContext]
    var truncated: AgentTruncation
    var nextActions: [String]
}

struct AgentQueryMatch: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var type: String
    var title: String
    var path: String?
    var lineStart: Int?
    var lineEnd: Int?
    var snippet: String
    var score: Int
    var nextAction: String?
}

struct AgentQueryResult: Codable, Equatable, Sendable {
    var schemaVersion: String
    var source: String
    var runId: String?
    var workspaceId: String?
    var query: String
    var matches: [AgentQueryMatch]
    var truncated: Bool
    var nextActions: [String]
}

struct AgentWorkspaceSummary: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var pathBasename: String
    var selected: Bool
    var branch: String?
    var latestRunId: String?
    var latestRunStatus: String?
}

struct AgentFileRangeResult: Codable, Equatable, Sendable {
    var schemaVersion: String
    var source: String
    var workspaceId: String
    var path: String
    var revision: String
    var startLine: Int
    var endLine: Int
    var lines: [AgentNumberedLine]
    var truncated: Bool
    var nextActions: [String]
}

struct AgentNumberedLine: Codable, Equatable, Sendable {
    var line: Int
    var text: String
}
