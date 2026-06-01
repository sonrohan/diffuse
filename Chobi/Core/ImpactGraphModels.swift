import Foundation

enum ImpactLevel: String, Codable, Hashable, CaseIterable {
    case low
    case medium
    case high

    var displayName: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    var badgeVariant: BadgeVariant {
        switch self {
        case .low: .success
        case .medium: .warning
        case .high: .danger
        }
    }
}

enum CallConfidence: String, Codable, Hashable {
    case exact
    case qualified
    case sameFile
    case uniqueName
    case ambiguous
    case unresolved
}

enum CallGraphConfidence: String, Codable, Hashable {
    case low
    case medium
    case high

    var displayName: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }
}

struct SymbolNode: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let qualifiedName: String
    let kind: ChangedSymbol.SymbolKind
    let semanticType: String
    let language: String
    let filePath: String
    let startLine: Int
    let endLine: Int
    let metadata: [String: String]
}

struct CallEdge: Identifiable, Codable, Hashable {
    let id: String
    let callerId: String
    let calleeId: String?
    let unresolvedCalleeName: String?
    let confidence: CallConfidence
    let sourceFilePath: String
    let sourceLine: Int?
}

struct UnresolvedCall: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let sourceFilePath: String
    let sourceLine: Int?
}

struct ImpactGraph: Codable, Hashable {
    let root: SymbolNode
    let nodes: [SymbolNode]
    let edges: [CallEdge]
    let unresolvedCalls: [UnresolvedCall]
    let summary: ImpactSummary
}

struct ImpactSummary: Codable, Hashable {
    let directCallerCount: Int
    let directCalleeCount: Int
    let transitiveCallerCount: Int
    let transitiveCalleeCount: Int
    let fileCount: Int
    let testReferenceCount: Int
    let impactLevel: ImpactLevel
    let confidence: CallGraphConfidence
}

struct SymbolImpact: Identifiable, Hashable {
    let id: UUID
    let symbol: ChangedSymbol
    let filePath: String
    let summary: ImpactSummary
    let reason: String?
    let topAffectedSymbols: [String]

    var qualifiedName: String {
        symbol.metadata["qualified_name"] ?? symbol.name
    }

    var title: String {
        qualifiedName.isEmpty ? symbol.name : qualifiedName
    }

    var location: String {
        "\(filePath):L\(symbol.startLine)"
    }

    var hasImpactData: Bool {
        !symbol.callers.isEmpty || !symbol.callees.isEmpty
    }

    var hasUsefulReason: Bool {
        reason?.isEmpty == false
    }
}

enum ImpactGraphDirection: String, CaseIterable, Identifiable {
    case callers
    case callees
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .callers: "Callers"
        case .callees: "Callees"
        case .both: "Both"
        }
    }
}

struct ImpactGraphNode: Identifiable, Hashable {
    enum Role: Hashable {
        case origin
        case caller
        case callee
    }

    let id: String
    let title: String
    let filePath: String
    let line: Int?
    let role: Role
    let isChangedInPR: Bool
    let isTest: Bool
}

struct SymbolSourceContext: Hashable {
    let symbolName: String
    let filePath: String
    let startLine: Int
    let endLine: Int
    let excerptStartLine: Int
    let excerpt: String
    let isChangedInCurrentPR: Bool
    let changedLineNumbers: Set<Int>
    let callSiteLine: Int?
}

struct InlineImpactMarker: Identifiable, Hashable {
    let id: UUID
    let rootSymbolId: UUID
    let filePath: String
    let anchorLine: Int
    let hunkIndex: Int
    let summary: String
    let metrics: ImpactSummary
    let isContinuation: Bool
}
