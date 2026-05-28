import Foundation

func runStressTest() {
    print("🚀 Starting triage stress test for 10,000 files on CI...")
    let runId = UUID()

    // 1. Generate 10,000 changed files of various types:
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

    // 2. Generate 5,000 changed symbols distributed across the source files
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
        let fileIdx = i * 15
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

    print("✅ CI Triage Stress Test completed successfully!")
    print("⏱️ Time taken: \(String(format: "%.4f", duration)) seconds")
    print("📊 Results:")
    print("   - Change Buckets: \(result.changeBuckets.count)")
    print("   - Review Targets: \(result.reviewTargets.count)")
    print("   - Skim Targets: \(result.skimTargets.count)")
    print("   - Risk Highlights: \(result.riskHighlights.count)")
    print("   - Symbol Review Groups: \(result.symbolReviewGroups.count)")

    assert(duration < 5.0, "Triage of 10000 files took too long")
    assert(result.changeBuckets.count > 0, "No change buckets created")
    assert(result.reviewTargets.count > 0, "No review targets identified")
    assert(result.skimTargets.count == 1000, "Should have 1000 skim targets")
    assert(result.riskHighlights.count >= 500, "Should have at least 500 risk highlights")
    assert(result.symbolReviewGroups.count > 0, "No symbol review groups created")

    print("\n🎉 ALL CI PERFORMANCE AND CORRECTNESS ASSERTIONS PASSED!")
}
@main
struct CITestRunner {
    static func main() {
        runStressTest()
    }
}
