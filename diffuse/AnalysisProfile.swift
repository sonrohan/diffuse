import Foundation

struct AnalysisPresetDescriptor: Identifiable, Hashable {
    var id: String
    var displayName: String
}

struct AnalysisProfile: Codable {
    var version: Int
    var id: String
    var displayName: String
    var extends: [String]
    var fileClassifications: [FileClassificationRule]
    var buckets: [BucketRule]
    var symbolGroups: [SymbolGroupRule]
    var rules: RuleProfile
    var semanticHighlights: [SemanticHighlightRule]
    var fileHighlights: [FileHighlightRule]
    var riskScoring: RiskScoringProfile

    nonisolated static let generic = AnalysisProfileStore.loadBuiltIn(id: "generic")

    enum CodingKeys: String, CodingKey {
        case version, id, displayName, extends, fileClassifications, buckets, symbolGroups, rules, semanticHighlights, fileHighlights, riskScoring
    }

    nonisolated init(
        version: Int = 1,
        id: String,
        displayName: String,
        extends: [String] = [],
        fileClassifications: [FileClassificationRule] = [],
        buckets: [BucketRule] = [],
        symbolGroups: [SymbolGroupRule] = [],
        rules: RuleProfile = RuleProfile(),
        semanticHighlights: [SemanticHighlightRule] = [],
        fileHighlights: [FileHighlightRule] = [],
        riskScoring: RiskScoringProfile = RiskScoringProfile()
    ) {
        self.version = version
        self.id = id
        self.displayName = displayName
        self.extends = extends
        self.fileClassifications = fileClassifications
        self.buckets = buckets
        self.symbolGroups = symbolGroups
        self.rules = rules
        self.semanticHighlights = semanticHighlights
        self.fileHighlights = fileHighlights
        self.riskScoring = riskScoring
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? "custom"
        self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? id
        self.extends = try container.decodeIfPresent([String].self, forKey: .extends) ?? []
        self.fileClassifications = try container.decodeIfPresent([FileClassificationRule].self, forKey: .fileClassifications) ?? []
        self.buckets = try container.decodeIfPresent([BucketRule].self, forKey: .buckets) ?? []
        self.symbolGroups = try container.decodeIfPresent([SymbolGroupRule].self, forKey: .symbolGroups) ?? []
        self.rules = try container.decodeIfPresent(RuleProfile.self, forKey: .rules) ?? RuleProfile()
        self.semanticHighlights = try container.decodeIfPresent([SemanticHighlightRule].self, forKey: .semanticHighlights) ?? []
        self.fileHighlights = try container.decodeIfPresent([FileHighlightRule].self, forKey: .fileHighlights) ?? []
        self.riskScoring = try container.decodeIfPresent(RiskScoringProfile.self, forKey: .riskScoring) ?? RiskScoringProfile()
    }

    func classifyFile(_ path: String) -> ChangedFile.FileClassification {
        for rule in fileClassifications where rule.matches(path: path) {
            return rule.classificationValue
        }
        return .source
    }

    func bucketRule(for file: ChangedFile, findings: [Finding], symbols: [ChangedSymbol]) -> BucketRule? {
        buckets.first { $0.matches(file: file, findings: findings, symbols: symbols) }
    }
}

struct FileClassificationRule: Codable {
    var classification: String
    var paths: [String]

    var classificationValue: ChangedFile.FileClassification {
        ChangedFile.FileClassification(rawValue: classification) ?? .source
    }

    func matches(path: String) -> Bool {
        PatternMatcher.matchesAny(path, patterns: paths)
    }
}

struct BucketRule: Codable {
    var id: String
    var type: String
    var title: String
    var paths: [String]?
    var classifications: [String]?
    var findingCategories: [String]?
    var symbolSemanticAreas: [String]?
    var symbolSemanticTypes: [String]?
    var symbolNames: [String]?
    var symbolMetadataEquals: [String: String]?
    var symbolMetadataMatches: [String: [String]]?
    var symbolCallees: [String]?

    var bucketType: ChangeBucketType {
        ChangeBucketType(rawValue: type) ?? .behavior
    }

    func matches(file: ChangedFile, findings: [Finding], symbols: [ChangedSymbol]) -> Bool {
        if let classifications, classifications.contains(file.classification.rawValue) {
            return true
        }
        if let paths, PatternMatcher.matchesAny(file.path, patterns: paths) {
            return true
        }
        if let findingCategories {
            let categories = Set(findingCategories)
            if findings.contains(where: { categories.contains($0.category.rawValue) }) {
                return true
            }
        }
        if let symbolSemanticAreas {
            let areas = Set(symbolSemanticAreas)
            if symbols.contains(where: { areas.contains($0.metadata["semantic_area"] ?? "") }) {
                return true
            }
        }
        if let symbolSemanticTypes {
            let types = Set(symbolSemanticTypes)
            if symbols.contains(where: { types.contains($0.semanticType) }) {
                return true
            }
        }
        if let symbolNames {
            if symbols.contains(where: { PatternMatcher.matchesAny($0.name, patterns: symbolNames) }) {
                return true
            }
        }
        if let symbolMetadataEquals {
            if symbols.contains(where: { symbol in
                symbolMetadataEquals.allSatisfy { symbol.metadata[$0.key] == $0.value }
            }) {
                return true
            }
        }
        if let symbolMetadataMatches {
            if symbols.contains(where: { symbol in
                symbolMetadataMatches.allSatisfy { key, patterns in
                    guard let value = symbol.metadata[key] else { return false }
                    return PatternMatcher.matchesAny(value, patterns: patterns)
                }
            }) {
                return true
            }
        }
        if let symbolCallees {
            if symbols.contains(where: { symbol in
                symbol.callees.contains { callee in PatternMatcher.matchesAny(callee, patterns: symbolCallees) }
            }) {
                return true
            }
        }
        return false
    }
}

struct SymbolGroupRule: Codable {
    var id: String
    var label: String
    var icon: String
    var semanticAreas: [String]?
    var metadataEquals: [String: String]?
    var fallback: Bool?

    func matches(_ symbol: ChangedSymbol) -> Bool {
        if let semanticAreas, semanticAreas.contains(symbol.metadata["semantic_area"] ?? "") {
            return true
        }
        if let metadataEquals, metadataEquals.allSatisfy({ symbol.metadata[$0.key] == $0.value }) {
            return true
        }
        return false
    }
}

struct RuleProfile: Codable {
    var missingTests: MissingTestsRule?
    var schemaSync: SchemaSyncRule?
    var importBoundaries: [ImportBoundaryRule]
    var semanticAreaFindings: [SemanticAreaFindingRule]
    var contractFindings: [MetadataFindingRule]
    var symbolCoverage: SymbolCoverageRule?

    enum CodingKeys: String, CodingKey {
        case missingTests, schemaSync, importBoundaries, semanticAreaFindings, contractFindings, symbolCoverage
    }

    nonisolated init(
        missingTests: MissingTestsRule? = nil,
        schemaSync: SchemaSyncRule? = nil,
        importBoundaries: [ImportBoundaryRule] = [],
        semanticAreaFindings: [SemanticAreaFindingRule] = [],
        contractFindings: [MetadataFindingRule] = [],
        symbolCoverage: SymbolCoverageRule? = nil
    ) {
        self.missingTests = missingTests
        self.schemaSync = schemaSync
        self.importBoundaries = importBoundaries
        self.semanticAreaFindings = semanticAreaFindings
        self.contractFindings = contractFindings
        self.symbolCoverage = symbolCoverage
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.missingTests = try container.decodeIfPresent(MissingTestsRule.self, forKey: .missingTests)
        self.schemaSync = try container.decodeIfPresent(SchemaSyncRule.self, forKey: .schemaSync)
        self.importBoundaries = try container.decodeIfPresent([ImportBoundaryRule].self, forKey: .importBoundaries) ?? []
        self.semanticAreaFindings = try container.decodeIfPresent([SemanticAreaFindingRule].self, forKey: .semanticAreaFindings) ?? []
        self.contractFindings = try container.decodeIfPresent([MetadataFindingRule].self, forKey: .contractFindings) ?? []
        self.symbolCoverage = try container.decodeIfPresent(SymbolCoverageRule.self, forKey: .symbolCoverage)
    }
}

struct MissingTestsRule: Codable {
    var enabled: Bool
    var minimumAdditions: Int
    var sourceClassifications: [String]
    var testClassifications: [String]
    var message: String
}

struct SchemaSyncRule: Codable {
    var enabled: Bool
    var migrationPaths: [String]
    var schemaPaths: [String]
    var message: String
}

struct ImportBoundaryRule: Codable {
    var id: String
    var sourcePaths: [String]
    var forbiddenImports: [String]
    var severity: String
    var category: String
    var message: String
}

struct SemanticAreaFindingRule: Codable {
    var id: String
    var semanticArea: String?
    var paths: [String]?
    var symbolNames: [String]?
    var metadataEquals: [String: String]?
    var severity: String
    var category: String
    var message: String
}

struct MetadataFindingRule: Codable {
    var id: String
    var metadataEquals: [String: String]
    var severity: String
    var category: String
    var message: String
}

struct SymbolCoverageRule: Codable {
    var enabled: Bool
    var riskMetadataPrefixes: [String]
    var riskMetadataSuffixes: [String]
    var riskMetadataEquals: [String: String]
    var message: String
}

struct SemanticHighlightRule: Codable {
    var id: String
    var semanticArea: String?
    var paths: [String]?
    var symbolNames: [String]?
    var metadataEquals: [String: String]?
    var severity: String
    var category: String
    var title: String
    var evidence: String
}

struct FileHighlightRule: Codable {
    var id: String
    var classifications: [String]?
    var paths: [String]?
    var minimumAdditions: Int?
    var requiresNoSymbols: Bool?
    var severity: String
    var category: String
    var title: String
    var evidence: String
}

struct RiskScoringProfile: Codable {
    var generatedOnlyDelta: Int
    var productionChangeDelta: Int
    var apiPathDelta: Int
    var sensitivePathDelta: Int
    var missingTestsDelta: Int
    var architectureFindingDelta: Int
    var highFanInDelta: Int
    var contractDelta: Int
    var behaviorAddedDelta: Int
    var testChangeDelta: Int
    var apiPaths: [String]
    var sensitivePaths: [String]

    enum CodingKeys: String, CodingKey {
        case generatedOnlyDelta, productionChangeDelta, apiPathDelta, sensitivePathDelta, missingTestsDelta
        case architectureFindingDelta, highFanInDelta, contractDelta, behaviorAddedDelta, testChangeDelta
        case apiPaths, sensitivePaths
    }

    nonisolated init(
        generatedOnlyDelta: Int = -40,
        productionChangeDelta: Int = 10,
        apiPathDelta: Int = 20,
        sensitivePathDelta: Int = 30,
        missingTestsDelta: Int = 20,
        architectureFindingDelta: Int = 20,
        highFanInDelta: Int = 10,
        contractDelta: Int = 10,
        behaviorAddedDelta: Int = 10,
        testChangeDelta: Int = -15,
        apiPaths: [String] = [],
        sensitivePaths: [String] = []
    ) {
        self.generatedOnlyDelta = generatedOnlyDelta
        self.productionChangeDelta = productionChangeDelta
        self.apiPathDelta = apiPathDelta
        self.sensitivePathDelta = sensitivePathDelta
        self.missingTestsDelta = missingTestsDelta
        self.architectureFindingDelta = architectureFindingDelta
        self.highFanInDelta = highFanInDelta
        self.contractDelta = contractDelta
        self.behaviorAddedDelta = behaviorAddedDelta
        self.testChangeDelta = testChangeDelta
        self.apiPaths = apiPaths
        self.sensitivePaths = sensitivePaths
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.generatedOnlyDelta = try container.decodeIfPresent(Int.self, forKey: .generatedOnlyDelta) ?? -40
        self.productionChangeDelta = try container.decodeIfPresent(Int.self, forKey: .productionChangeDelta) ?? 10
        self.apiPathDelta = try container.decodeIfPresent(Int.self, forKey: .apiPathDelta) ?? 20
        self.sensitivePathDelta = try container.decodeIfPresent(Int.self, forKey: .sensitivePathDelta) ?? 30
        self.missingTestsDelta = try container.decodeIfPresent(Int.self, forKey: .missingTestsDelta) ?? 20
        self.architectureFindingDelta = try container.decodeIfPresent(Int.self, forKey: .architectureFindingDelta) ?? 20
        self.highFanInDelta = try container.decodeIfPresent(Int.self, forKey: .highFanInDelta) ?? 10
        self.contractDelta = try container.decodeIfPresent(Int.self, forKey: .contractDelta) ?? 10
        self.behaviorAddedDelta = try container.decodeIfPresent(Int.self, forKey: .behaviorAddedDelta) ?? 10
        self.testChangeDelta = try container.decodeIfPresent(Int.self, forKey: .testChangeDelta) ?? -15
        self.apiPaths = try container.decodeIfPresent([String].self, forKey: .apiPaths) ?? []
        self.sensitivePaths = try container.decodeIfPresent([String].self, forKey: .sensitivePaths) ?? []
    }
}

enum AnalysisProfileStore {
    nonisolated static let repoConfigPath = ".diffuse.json"
    nonisolated static let builtInPresets: [AnalysisPresetDescriptor] = [
        AnalysisPresetDescriptor(id: "generic", displayName: "Generic repository"),
        AnalysisPresetDescriptor(id: "ios-swift", displayName: "iOS / Swift"),
        AnalysisPresetDescriptor(id: "android-kotlin", displayName: "Android / Kotlin"),
        AnalysisPresetDescriptor(id: "react-typescript", displayName: "React / TypeScript"),
        AnalysisPresetDescriptor(id: "node-service", displayName: "Node service"),
        AnalysisPresetDescriptor(id: "go-service", displayName: "Go service"),
        AnalysisPresetDescriptor(id: "rust-crate", displayName: "Rust crate"),
        AnalysisPresetDescriptor(id: "python-service", displayName: "Python service")
    ]

    nonisolated static func load(repoPath: String?) -> AnalysisProfile {
        if let repoPath, let profile = loadRepoProfile(repoPath: repoPath) {
            return profile
        }
        if let repoPath {
            return loadBuiltIn(id: detectBuiltInProfileId(repoPath: repoPath))
        }
        return .generic
    }

    nonisolated static func loadRepoProfile(repoPath: String) -> AnalysisProfile? {
        let root = URL(fileURLWithPath: repoPath)
        let candidates = [repoConfigPath, ".diffuse/config.json"]
        for candidate in candidates {
            let url = root.appendingPathComponent(candidate)
            if let profile = decodeProfile(at: url) {
                return profile
            }
        }
        return nil
    }

    nonisolated static func hasRepoProfile(repoPath: String) -> Bool {
        loadRepoProfile(repoPath: repoPath) != nil
    }

    nonisolated static func writeDefaultProfile(repoPath: String) throws {
        try writeProfile(repoPath: repoPath, presetId: detectBuiltInProfileId(repoPath: repoPath))
    }

    nonisolated static func writeProfile(repoPath: String, presetId: String) throws {
        let root = URL(fileURLWithPath: repoPath)
        let destination = root.appendingPathComponent(repoConfigPath)
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }

        let template: [String: Any] = [
            "version": 1,
            "id": "repo",
            "displayName": "Repo analysis profile",
            "extends": [presetId]
        ]
        let data = try JSONSerialization.data(withJSONObject: template, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: destination, options: .withoutOverwriting)
    }

    nonisolated static func loadBuiltIn(id: String) -> AnalysisProfile {
        guard let profile = decodeRawBuiltIn(id: id) else {
            preconditionFailure("Missing bundled analysis profile: \(id)")
        }
        return resolve(profile)
    }

    nonisolated static func detectBuiltInProfileId(repoPath: String) -> String {
        let root = URL(fileURLWithPath: repoPath)
        func exists(_ relativePath: String) -> Bool {
            FileManager.default.fileExists(atPath: root.appendingPathComponent(relativePath).path)
        }
        func rootEntry(hasSuffix suffix: String) -> Bool {
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
            return entries.contains { $0.hasSuffix(suffix) }
        }

        if exists("Package.swift") || exists("Podfile") || exists("iosApp") || rootEntry(hasSuffix: ".xcodeproj") || rootEntry(hasSuffix: ".xcworkspace") {
            return "ios-swift"
        }
        if exists("build.gradle") || exists("build.gradle.kts") || exists("settings.gradle") || exists("settings.gradle.kts") {
            return "android-kotlin"
        }
        if exists("package.json") {
            if exists("next.config.js") || exists("vite.config.ts") || exists("vite.config.js") {
                return "react-typescript"
            }
            return "node-service"
        }
        if exists("go.mod") {
            return "go-service"
        }
        if exists("Cargo.toml") {
            return "rust-crate"
        }
        if exists("pyproject.toml") || exists("requirements.txt") {
            return "python-service"
        }
        return "generic"
    }

    nonisolated private static func decodeProfile(at url: URL) -> AnalysisProfile? {
        guard let data = try? Data(contentsOf: url),
              let profile = try? JSONDecoder().decode(AnalysisProfile.self, from: data) else {
            return nil
        }
        return resolve(profile)
    }

    nonisolated private static func decodeRawBuiltIn(id: String) -> AnalysisProfile? {
        let decoder = JSONDecoder()
        let bundleURL = Bundle.main.url(forResource: id, withExtension: "json", subdirectory: "AnalysisProfiles")
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("AnalysisProfiles/\(id).json")
        let urls = [bundleURL, sourceURL].compactMap { $0 }

        for url in urls {
            if let data = try? Data(contentsOf: url),
               let profile = try? decoder.decode(AnalysisProfile.self, from: data) {
                return profile
            }
        }
        return nil
    }

    nonisolated private static func resolve(_ profile: AnalysisProfile) -> AnalysisProfile {
        guard !profile.extends.isEmpty else { return profile }
        let parent = profile.extends
            .map(loadBuiltIn)
            .reduce(AnalysisProfile(version: profile.version, id: profile.id, displayName: profile.displayName)) {
                $0.merging(overrides: $1)
            }
        return parent.merging(overrides: profile)
    }
}

private extension AnalysisProfile {
    nonisolated func merging(overrides child: AnalysisProfile) -> AnalysisProfile {
        var merged = self
        merged.version = child.version
        merged.id = child.id
        merged.displayName = child.displayName
        merged.extends = child.extends
        merged.fileClassifications = mergeByClassification(fileClassifications, child.fileClassifications)
        merged.buckets = mergeById(buckets, child.buckets, id: \.id)
        merged.symbolGroups = mergeById(symbolGroups, child.symbolGroups, id: \.id)
        merged.rules = rules.merging(overrides: child.rules)
        merged.semanticHighlights = mergeById(semanticHighlights, child.semanticHighlights, id: \.id)
        merged.fileHighlights = mergeById(fileHighlights, child.fileHighlights, id: \.id)
        merged.riskScoring = riskScoring.merging(overrides: child.riskScoring)
        return merged
    }

    nonisolated func mergeById<T>(_ parent: [T], _ child: [T], id: KeyPath<T, String>) -> [T] {
        var result = parent
        for item in child {
            if let index = result.firstIndex(where: { $0[keyPath: id] == item[keyPath: id] }) {
                result[index] = item
            } else {
                result.append(item)
            }
        }
        return result
    }

    nonisolated func mergeByClassification(_ parent: [FileClassificationRule], _ child: [FileClassificationRule]) -> [FileClassificationRule] {
        var result = parent
        for item in child {
            if let index = result.firstIndex(where: { $0.classification == item.classification }) {
                var mergedRule = result[index]
                mergedRule.paths = Array(Set(mergedRule.paths + item.paths)).sorted()
                result[index] = mergedRule
            } else {
                result.append(item)
            }
        }
        return result
    }
}

private extension RuleProfile {
    nonisolated func merging(overrides child: RuleProfile) -> RuleProfile {
        RuleProfile(
            missingTests: child.missingTests ?? missingTests,
            schemaSync: child.schemaSync ?? schemaSync,
            importBoundaries: mergeById(importBoundaries, child.importBoundaries, id: \.id),
            semanticAreaFindings: mergeById(semanticAreaFindings, child.semanticAreaFindings, id: \.id),
            contractFindings: mergeById(contractFindings, child.contractFindings, id: \.id),
            symbolCoverage: child.symbolCoverage ?? symbolCoverage
        )
    }

    nonisolated func mergeById<T>(_ parent: [T], _ child: [T], id: KeyPath<T, String>) -> [T] {
        var result = parent
        for item in child {
            if let index = result.firstIndex(where: { $0[keyPath: id] == item[keyPath: id] }) {
                result[index] = item
            } else {
                result.append(item)
            }
        }
        return result
    }
}

private extension RiskScoringProfile {
    nonisolated func merging(overrides child: RiskScoringProfile) -> RiskScoringProfile {
        RiskScoringProfile(
            generatedOnlyDelta: child.generatedOnlyDelta,
            productionChangeDelta: child.productionChangeDelta,
            apiPathDelta: child.apiPathDelta,
            sensitivePathDelta: child.sensitivePathDelta,
            missingTestsDelta: child.missingTestsDelta,
            architectureFindingDelta: child.architectureFindingDelta,
            highFanInDelta: child.highFanInDelta,
            contractDelta: child.contractDelta,
            behaviorAddedDelta: child.behaviorAddedDelta,
            testChangeDelta: child.testChangeDelta,
            apiPaths: Array(Set(apiPaths + child.apiPaths)).sorted(),
            sensitivePaths: Array(Set(sensitivePaths + child.sensitivePaths)).sorted()
        )
    }
}

enum ProfileValue {
    static func severity(_ raw: String) -> Severity {
        Severity(rawValue: raw) ?? .low
    }

    static func findingCategory(_ raw: String) -> Finding.FindingCategory {
        Finding.FindingCategory(rawValue: raw) ?? .architecture
    }

    static func riskCategory(_ raw: String) -> RiskCategory {
        RiskCategory(rawValue: raw) ?? .reviewLoad
    }
}

enum TemplateRenderer {
    static func render(_ template: String, values: [String: String]) -> String {
        values.reduce(template) { result, item in
            result.replacingOccurrences(of: "{\(item.key)}", with: item.value)
        }
    }
}

enum PatternMatcher {
    static func matchesAny(_ value: String, patterns: [String]) -> Bool {
        patterns.contains { matches(value, pattern: $0) }
    }

    static func matches(_ value: String, pattern: String) -> Bool {
        let normalizedValue = value.replacingOccurrences(of: "\\", with: "/").lowercased()
        let normalizedPattern = pattern.replacingOccurrences(of: "\\", with: "/").lowercased()
        let regex = "^" + NSRegularExpression.escapedPattern(for: normalizedPattern)
            .replacingOccurrences(of: "\\*\\*", with: ".*")
            .replacingOccurrences(of: "\\*", with: "[^/]*") + "$"
        return normalizedValue.range(of: regex, options: .regularExpression) != nil
    }
}
