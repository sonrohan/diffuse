import Foundation
import XCTest

final class LargeChangeProcessingTests: XCTestCase {

    /// Tests that the TriageEngine can process a massive pull request containing 10,000 files
    /// and thousands of symbols quickly and correctly without blocking or crashing.
    func testProcessingTenThousandFilesPerformanceAndCorrectness() {
        let runId = UUID()

        // 1. Generate 10000 changed files of various types:
        // - 8000 source files (e.g., source.swift)
        // - 1000 test files (e.g., tests.swift)
        // - 500 configuration files (e.g., config.json)
        // - 500 documentation files (e.g., readme.md)
        var files: [ChangedFile] = []
        for i in 1...10000 {
            let classification: ChangedFile.FileClassification
            let path: String
            let status: ChangedFile.FileStatus = (i % 10 == 0) ? .added : .modified

            if i <= 8000 {
                classification = .source
                path = "Sources/ModuleA/File_\(i).swift"
            } else if i <= 9000 {
                classification = .test
                path = "Tests/ModuleATests/File_\(i - 8000)Tests.swift"
            } else if i <= 9500 {
                classification = .config
                path = "Configs/setting_\(i - 9000).json"
            } else {
                classification = .documentation
                path = "Docs/guide_\(i - 9500).md"
            }

            files.append(
                ChangedFile(
                    id: UUID(),
                    analysisRunId: runId,
                    path: path,
                    status: status,
                    additions: 15,
                    deletions: 5,
                    classification: classification,
                    hunks: [
                        DiffHunk(
                            oldStart: 1, oldLines: 10, newStart: 1, newLines: 20,
                            lines: ["+ added line", "- deleted line", "  unchanged line"]
                        )
                    ]
                )
            )
        }

        // 2. Generate 5000 changed symbols distributed across the source files
        var symbols: [ChangedSymbol] = []
        for i in 1...5000 {
            let fileIdx = i % 8000
            let matchedFile = files[fileIdx]

            symbols.append(
                ChangedSymbol(
                    id: UUID(),
                    analysisRunId: runId,
                    changedFileId: matchedFile.id,
                    name: "funcTestSymbol_\(i)",
                    kind: .function,
                    startLine: 10,
                    endLine: 20,
                    callers: ["caller_\(i)_1", "caller_\(i)_2"],
                    callees: ["callee_\(i)_1"],
                    semanticType: "function_definition",
                    metadata: [
                        "symbol_key": "key_\(i)",
                        "qualified_name": "ModuleA.File.funcTestSymbol_\(i)",
                    ]
                )
            )
        }

        // 3. Create simulated rule findings
        var findings: [Finding] = []
        for i in 1...500 {
            let fileIdx = i * 15  // Spread across files
            let matchedFile = files[fileIdx]
            findings.append(
                Finding(
                    id: UUID(),
                    analysisRunId: runId,
                    changedFileId: matchedFile.id,
                    severity: (i % 3 == 0) ? .high : .medium,
                    category: .architecture,
                    message: "Deterministic rule violation in file \(i)",
                    lineStart: 10,
                    lineEnd: 15,
                    ruleSource: "rules/architectural-check",
                    evidence: "Symbol referenced incorrectly."
                )
            )
        }

        let start = Date()

        // 4. Execute the TriageEngine
        let result = TriageEngine.deriveTriage(
            files: files,
            symbols: symbols,
            findings: findings,
            riskScore: 75,
            profile: .generic
        )

        let duration = Date().timeIntervalSince(start)

        // 5. Assertions on Performance
        // Triage of 10000 files should be fast, typically < 1s under optimization
        XCTAssertLessThan(
            duration, 3.0, "Triage of 10000 files took too long: \(duration) seconds")

        // 6. Assertions on Triage correctness
        XCTAssertFalse(result.changeBuckets.isEmpty, "Change buckets should be created")
        XCTAssertFalse(result.reviewTargets.isEmpty, "Review targets should be identified")
        XCTAssertEqual(
            result.skimTargets.count, 1000,
            "All 1000 config and documentation files should be skim targets")

        // Verify that we have categorized file types correctly
        let skimConfigs = result.skimTargets.filter { $0.classification == .config }
        let skimDocs = result.skimTargets.filter { $0.classification == .documentation }
        XCTAssertEqual(skimConfigs.count, 500)
        XCTAssertEqual(skimDocs.count, 500)

        // Verify risk highlights and priority ordering
        XCTAssertGreaterThanOrEqual(
            result.riskHighlights.count, findings.count,
            "Each rule finding should map to a risk highlight")

        // Verify symbol review grouping
        XCTAssertFalse(
            result.symbolReviewGroups.isEmpty,
            "Symbol review groups should be constructed for navigation")
    }
}
