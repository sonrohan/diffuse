import Foundation
import SwiftUI

// MARK: - Core Models

enum DiffLayout: String, CaseIterable, Identifiable, Codable {
    case unified = "Unified"
    case split = "Split"

    var id: String { self.rawValue }
}

enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { self.rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}



struct PullRequest: Identifiable, Codable, Hashable {
    let id: UUID
    var prNumber: Int
    var title: String
    var body: String?
    var baseSha: String
    var headSha: String
    var author: String
    var status: String
    var repository: String
    var createdAt: Date
    var updatedAt: Date
    var latestRun: AnalysisRun?

    init(id: UUID = UUID(), prNumber: Int, title: String, body: String? = nil,
         baseSha: String, headSha: String, author: String, status: String = "open",
         repository: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.prNumber = prNumber
        self.title = title
        self.body = body
        self.baseSha = baseSha
        self.headSha = headSha
        self.author = author
        self.status = status
        self.repository = repository
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct AnalysisRun: Identifiable, Codable, Hashable {
    let id: UUID
    var pullRequestId: UUID
    var baseSha: String
    var headSha: String
    var status: RunStatus
    var errorMessage: String?
    var riskScore: Int
    var createdAt: Date
    var updatedAt: Date

    enum RunStatus: String, Codable, CaseIterable {
        case queued, analyzing, completed, failed
    }

    init(id: UUID = UUID(), pullRequestId: UUID, baseSha: String, headSha: String,
         status: RunStatus = .queued, errorMessage: String? = nil, riskScore: Int = 0,
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.pullRequestId = pullRequestId
        self.baseSha = baseSha
        self.headSha = headSha
        self.status = status
        self.errorMessage = errorMessage
        self.riskScore = riskScore
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct DiffHunk: Codable, Equatable, Hashable {
    var oldStart: Int
    var oldLines: Int
    var newStart: Int
    var newLines: Int
    var lines: [String]
}

struct ChangedFile: Identifiable, Codable, Hashable {
    let id: UUID
    var analysisRunId: UUID
    var path: String
    var status: FileStatus
    var additions: Int
    var deletions: Int
    var classification: FileClassification
    var hunks: [DiffHunk]

    enum FileStatus: String, Codable { case added, modified, deleted, renamed }
    enum FileClassification: String, Codable {
        case source, test, config, documentation, generated, boilerplate
    }

    var filename: String { URL(fileURLWithPath: path).lastPathComponent }

    init(id: UUID = UUID(), analysisRunId: UUID, path: String, status: FileStatus,
         additions: Int, deletions: Int, classification: FileClassification, hunks: [DiffHunk]) {
        self.id = id
        self.analysisRunId = analysisRunId
        self.path = path
        self.status = status
        self.additions = additions
        self.deletions = deletions
        self.classification = classification
        self.hunks = hunks
    }
}

struct ChangedSymbol: Identifiable, Codable, Hashable {
    let id: UUID
    var analysisRunId: UUID
    var changedFileId: UUID
    var name: String
    var kind: SymbolKind
    var startLine: Int
    var endLine: Int
    var callers: [String]
    var callees: [String]
    /// Coarse semantic category from the AST sidecar (e.g. "function_definition", "class_declaration").
    var semanticType: String
    /// Extra key/value metadata from the AST sidecar (visibility, is_async, is_critical, semantic_area…).
    var metadata: [String: String]

    enum SymbolKind: String, Codable, Hashable {
        case function, `class`, method, `import`, export, jsx, type,
             `struct`, `enum`, `protocol`, `extension`, property, variable,
             constructor, module, decorated
    }

    init(
        id: UUID = UUID(),
        analysisRunId: UUID,
        changedFileId: UUID,
        name: String,
        kind: SymbolKind,
        startLine: Int,
        endLine: Int,
        callers: [String] = [],
        callees: [String] = [],
        semanticType: String = "",
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.analysisRunId = analysisRunId
        self.changedFileId = changedFileId
        self.name = name
        self.kind = kind
        self.startLine = startLine
        self.endLine = endLine
        self.callers = callers
        self.callees = callees
        self.semanticType = semanticType
        self.metadata = metadata
    }
}

struct Finding: Identifiable, Codable {
    let id: UUID
    var analysisRunId: UUID
    var changedFileId: UUID
    var severity: Severity
    var category: FindingCategory
    var message: String
    var lineStart: Int?
    var lineEnd: Int?
    var ruleSource: String
    var evidence: String?

    enum FindingCategory: String, Codable {
        case architecture, test, security, performance, cleanCode = "clean-code"
    }
}

// MARK: - Triage Models

enum Severity: String, Codable, CaseIterable, Comparable {
    case info, low, medium, high

    var score: Int {
        switch self { case .info: 1; case .low: 2; case .medium: 3; case .high: 4 }
    }

    static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.score < rhs.score }

    var badgeColor: BadgeVariant {
        switch self {
        case .high: .danger
        case .medium: .warning
        case .low: .info
        case .info: .neutral
        }
    }
}

enum BadgeVariant {
    case danger, warning, info, success, neutral
}

struct ReviewTarget: Identifiable, Codable {
    let id: UUID
    var priority: Int
    var severity: Severity
    var title: String
    var filePath: String
    var lineStart: Int?
    var lineEnd: Int?
    var reason: String
    var evidence: String
    var source: String
    var changedFileId: UUID?
    var hunkIndex: Int?
}

enum ChangeBucketType: String, Codable, CaseIterable {
    case behavior
    case apiContract = "api-contract"
    case data
    case authSecurity = "auth-security"
    case tests
    case ui
    case buildConfig = "build-config"
    case generated
    case docs

    var displayTitle: String {
        switch self {
        case .behavior: "Production behavior changes"
        case .apiContract: "API and contract surface"
        case .data: "Data model and persistence changes"
        case .authSecurity: "Auth and security-sensitive paths"
        case .tests: "Tests and coverage"
        case .ui: "User-facing UI changes"
        case .buildConfig: "Build, dependency, and config changes"
        case .generated: "Generated and boilerplate changes"
        case .docs: "Documentation changes"
        }
    }

    var icon: String {
        switch self {
        case .behavior: "cpu"
        case .apiContract: "arrow.left.arrow.right"
        case .data: "cylinder"
        case .authSecurity: "lock.shield"
        case .tests: "checkmark.seal"
        case .ui: "rectangle.on.rectangle"
        case .buildConfig: "wrench.and.screwdriver"
        case .generated: "wand.and.stars"
        case .docs: "doc.text"
        }
    }
}

struct ChangeBucket: Identifiable, Codable {
    let id: String
    var type: ChangeBucketType
    var title: String
    var summary: String
    var files: [String]
    var symbols: [String]
    var riskLevel: Severity
    var riskReasons: [String]
    var evidence: [String]
    var reviewOrder: Int
}

// MARK: - Symbol Review Map

/// A group of changed symbols sharing the same semantic area.
/// Used in the symbol-first review map (AST Application Plan Step 1).
struct SymbolReviewGroup: Identifiable, Codable {
    let id: UUID
    /// Raw area key from AST sidecar (e.g. "security_authentication", "payment", "general").
    var semanticArea: String
    /// Human-readable label shown in the review map header.
    var displayLabel: String
    /// SF Symbol icon name for the group.
    var iconName: String
    var symbols: [ChangedSymbol]

    init(id: UUID = UUID(), semanticArea: String, displayLabel: String, iconName: String, symbols: [ChangedSymbol]) {
        self.id = id
        self.semanticArea = semanticArea
        self.displayLabel = displayLabel
        self.iconName = iconName
        self.symbols = symbols
    }
}

enum RiskCategory: String, Codable {
    case security, contract, data, testGap = "test-gap", coupling, runtime, reviewLoad = "review-load"

    var weight: Int {
        switch self {
        case .security: 7; case .runtime: 6; case .contract: 5; case .data: 4
        case .coupling: 3; case .reviewLoad: 2; case .testGap: 1
        }
    }
}

struct RiskHighlight: Identifiable, Codable {
    let id: String
    var bucketId: String
    var severity: Severity
    var category: RiskCategory
    var title: String
    var filePath: String
    var lineStart: Int?
    var lineEnd: Int?
    var evidence: [String]
    var source: String
    var confidence: String
}

struct SkimTarget: Identifiable, Codable {
    let id: String
    var filePath: String
    var reason: String
    var classification: ChangedFile.FileClassification
    var additions: Int
    var deletions: Int

    var groupName: String {
        switch classification {
        case .generated: "Generated & Lockfiles"
        case .config: "Configuration"
        case .documentation: "Documentation"
        case .boilerplate: "Boilerplate"
        default: "Other"
        }
    }
}

// MARK: - Analysis Details (full result)

struct AnalysisDetails {
    var run: AnalysisRun
    var pr: PullRequest
    var files: [ChangedFile]
    var symbols: [ChangedSymbol]
    var findings: [Finding]
    var reviewTargets: [ReviewTarget]
    var changeBuckets: [ChangeBucket]
    var riskHighlights: [RiskHighlight]
    var skimTargets: [SkimTarget]
    var riskFactors: [String]
    /// Symbol-first review map grouped by semantic area (Step 1).
    var symbolReviewGroups: [SymbolReviewGroup]
}

// MARK: - Git Navigation Models

struct GitRepository: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var path: String
    var autoAnalyzeEnabled: Bool

    init(id: UUID = UUID(), name: String, path: String, autoAnalyzeEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.path = path
        self.autoAnalyzeEnabled = autoAnalyzeEnabled
    }

    enum CodingKeys: String, CodingKey {
        case id, name, path, autoAnalyzeEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        autoAnalyzeEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoAnalyzeEnabled) ?? true
    }
}

struct GitCommit: Identifiable, Codable, Hashable {
    var id: String { sha }
    let sha: String
    let author: String
    let subject: String
    let date: String
}

struct LocalBranchSummary: Identifiable, Codable, Hashable {
    var id: String { branch }
    let branch: String
    let isCurrent: Bool
    let isDirty: Bool
    let aheadCount: Int
    let behindCount: Int
    let upstream: String?
    let relatedPRNumber: Int?
    let relatedPRTitle: String?
    let lastAuthor: String
    let lastUpdated: String
}
