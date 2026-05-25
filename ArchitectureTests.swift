import SwiftUI
import XCTest

@testable import diffuse

@MainActor
final class ArchitectureTests: XCTestCase {

    // MARK: - WorkspacePickerViewModel Tests

    func testWorkspacePickerViewModelFiltering() async {
        let appState = AppState()

        // Mock repositories list
        appState.repositories = [
            GitRepository(name: "AppEngine", path: "/repos/app-engine", autoAnalyzeEnabled: true),
            GitRepository(name: "CoreLib", path: "/repos/core-lib", autoAnalyzeEnabled: false),
            GitRepository(name: "Website", path: "/repos/website", autoAnalyzeEnabled: true),
        ]

        let viewModel = WorkspacePickerViewModel(state: appState)

        // Test "All" filter and empty query
        viewModel.filter = .all
        viewModel.query = ""
        XCTAssertEqual(viewModel.visibleRepositories.count, 3)

        // Test query fuzzy search matching names
        viewModel.query = "core"
        XCTAssertEqual(viewModel.visibleRepositories.count, 1)
        XCTAssertEqual(viewModel.visibleRepositories.first?.name, "CoreLib")

        // Test query fuzzy search matching paths
        viewModel.query = "repos/app"
        XCTAssertEqual(viewModel.visibleRepositories.count, 1)
        XCTAssertEqual(viewModel.visibleRepositories.first?.name, "AppEngine")

        // Test segment filter "Auto" (autoAnalyzeEnabled = true)
        viewModel.query = ""
        viewModel.filter = .auto
        XCTAssertEqual(viewModel.visibleRepositories.count, 2)
        XCTAssertTrue(viewModel.visibleRepositories.allSatisfy(\.autoAnalyzeEnabled))

        // Test segment filter "Manual" (autoAnalyzeEnabled = false)
        viewModel.filter = .manual
        XCTAssertEqual(viewModel.visibleRepositories.count, 1)
        XCTAssertEqual(viewModel.visibleRepositories.first?.name, "CoreLib")
    }

    // MARK: - BranchPickerViewModel Tests

    func testBranchPickerViewModelFiltering() async {
        let appState = AppState()
        appState.selectedBranch = "feature/mvvm"

        // Mock branch summaries
        appState.localBranchSummaries = [
            LocalBranchSummary(
                branch: "main", isCurrent: false, isDirty: false, aheadCount: 0, behindCount: 0,
                upstream: "origin/main", relatedPRNumber: nil, relatedPRTitle: nil,
                lastAuthor: "Alice", lastUpdated: "2 days ago"),
            LocalBranchSummary(
                branch: "feature/mvvm", isCurrent: true, isDirty: true, aheadCount: 2,
                behindCount: 0, upstream: "origin/feature/mvvm", relatedPRNumber: 42,
                relatedPRTitle: "Harden app architecture", lastAuthor: "Rohan",
                lastUpdated: "5 mins ago"),
            LocalBranchSummary(
                branch: "feature/ast", isCurrent: false, isDirty: false, aheadCount: 0,
                behindCount: 1, upstream: "origin/feature/ast", relatedPRNumber: nil,
                relatedPRTitle: nil, lastAuthor: "Bob", lastUpdated: "1 day ago"),
        ]

        let viewModel = BranchPickerViewModel(state: appState)

        // Test "All" filter and empty query
        viewModel.filter = .all
        viewModel.query = ""
        XCTAssertEqual(viewModel.visibleSummaries.count, 3)

        // Test query matching author
        viewModel.query = "Alice"
        XCTAssertEqual(viewModel.visibleSummaries.count, 1)
        XCTAssertEqual(viewModel.visibleSummaries.first?.branch, "main")

        // Test query matching related PR Title
        viewModel.query = "architecture"
        XCTAssertEqual(viewModel.visibleSummaries.count, 1)
        XCTAssertEqual(viewModel.visibleSummaries.first?.branch, "feature/mvvm")

        // Test "Dirty" branch filter
        viewModel.query = ""
        viewModel.filter = .dirty
        XCTAssertEqual(viewModel.visibleSummaries.count, 1)
        XCTAssertEqual(viewModel.visibleSummaries.first?.branch, "feature/mvvm")

        // Test "Ahead" branch filter
        viewModel.filter = .ahead
        XCTAssertEqual(viewModel.visibleSummaries.count, 1)
        XCTAssertEqual(viewModel.visibleSummaries.first?.branch, "feature/mvvm")

        // Test "Behind" branch filter
        viewModel.filter = .behind
        XCTAssertEqual(viewModel.visibleSummaries.count, 1)
        XCTAssertEqual(viewModel.visibleSummaries.first?.branch, "feature/ast")
    }

    // MARK: - CommitScopeViewModel Tests

    func testCommitScopeViewModelTimelineCycling() async {
        let appState = AppState()

        // Mock chronological commits (reverse chronological order)
        appState.commits = [
            GitCommit(sha: "sha1", author: "Alice", subject: "Initial commit", date: "May 23"),
            GitCommit(sha: "sha2", author: "Bob", subject: "Add AST parser", date: "May 24"),
            GitCommit(
                sha: "sha3", author: "Rohan", subject: "Refactor architecture", date: "May 25"),
        ]

        let viewModel = CommitScopeViewModel(state: appState)

        // Initial state: "All Changes" (selectedCommitSha is nil)
        XCTAssertNil(viewModel.selectedCommitSha)
        XCTAssertTrue(viewModel.canGoToNextCommit)
        XCTAssertFalse(viewModel.canGoToPreviousCommit)  // Can't go left of "All changes"

        // Cycle next should go to C1 ("sha1")
        await viewModel.goToNextCommit()
        XCTAssertEqual(viewModel.selectedCommitSha, "sha1")
        XCTAssertTrue(viewModel.canGoToPreviousCommit)  // Can now go left back to "All changes"
        XCTAssertTrue(viewModel.canGoToNextCommit)

        // Cycle next should go to C2 ("sha2")
        await viewModel.goToNextCommit()
        XCTAssertEqual(viewModel.selectedCommitSha, "sha2")

        // Cycle next should go to C3 ("sha3")
        await viewModel.goToNextCommit()
        XCTAssertEqual(viewModel.selectedCommitSha, "sha3")
        XCTAssertFalse(viewModel.canGoToNextCommit)  // At latest commit, cannot cycle next

        // Cycle previous should go back to C2 ("sha2")
        await viewModel.goToPreviousCommit()
        XCTAssertEqual(viewModel.selectedCommitSha, "sha2")

        // Cycle previous should go back to C1 ("sha1")
        await viewModel.goToPreviousCommit()
        XCTAssertEqual(viewModel.selectedCommitSha, "sha1")

        // Cycle previous should go back to "All Changes" (nil)
        await viewModel.goToPreviousCommit()
        XCTAssertNil(viewModel.selectedCommitSha)
    }

    // MARK: - AnalysisViewModel Tests

    func testAnalysisViewModelTriageAndBucketSelection() async {
        let appState = AppState()

        // Mock analysis run & details
        let run = AnalysisRun(pullRequestId: UUID(), baseSha: "base", headSha: "head")
        let pr = PullRequest(
            prNumber: 5, title: "Hardening test", baseSha: "base", headSha: "head", author: "Rohan",
            repository: "test")

        let files = [
            ChangedFile(
                analysisRunId: run.id, path: "App.swift", status: .modified, additions: 10,
                deletions: 5, classification: .source, hunks: []),
            ChangedFile(
                analysisRunId: run.id, path: "AppTests.swift", status: .added, additions: 20,
                deletions: 0, classification: .test, hunks: []),
            ChangedFile(
                analysisRunId: run.id, path: "README.md", status: .modified, additions: 5,
                deletions: 0, classification: .documentation, hunks: []),
        ]

        let buckets = [
            ChangeBucket(
                id: "behavior", type: .behavior, title: "Behavior Changes",
                summary: "Production core edits", files: ["App.swift"], symbols: [],
                riskLevel: .medium, riskReasons: [], evidence: [], reviewOrder: 1),
            ChangeBucket(
                id: "tests", type: .tests, title: "Tests Changes", summary: "Unit tests edits",
                files: ["AppTests.swift"], symbols: [], riskLevel: .low, riskReasons: [],
                evidence: [], reviewOrder: 2),
        ]

        let targets = [
            ReviewTarget(
                id: UUID(), priority: 10, severity: .medium, title: "Test Target",
                filePath: "App.swift", reason: "Critical logic modified", evidence: "",
                source: "Deterministic Rules")
        ]

        appState.analysisDetails = AnalysisDetails(
            run: run,
            pr: pr,
            files: files,
            symbols: [],
            findings: [],
            reviewTargets: targets,
            changeBuckets: buckets,
            riskHighlights: [],
            skimTargets: [],
            riskFactors: [],
            symbolReviewGroups: []
        )

        let viewModel = AnalysisViewModel(state: appState)

        // Unfiltered All Changes
        viewModel.selectAllChanges()
        XCTAssertNil(viewModel.selectedBucketId)
        XCTAssertFalse(viewModel.isLowerSignalViewSelected)
        XCTAssertFalse(viewModel.isNeedsAttentionViewSelected)
        XCTAssertEqual(viewModel.bucketFiles.count, 3)  // Every changed file

        // Select Needs Attention
        viewModel.selectNeedsAttentionChanges()
        XCTAssertTrue(viewModel.isNeedsAttentionViewSelected)
        XCTAssertEqual(viewModel.bucketFiles.count, 1)  // Only App.swift which has the target
        XCTAssertEqual(viewModel.bucketFiles.first?.path, "App.swift")

        // Select Semantic Bucket "behavior"
        viewModel.selectBucket("behavior")
        XCTAssertEqual(viewModel.selectedBucketId, "behavior")
        XCTAssertEqual(viewModel.bucketFiles.count, 1)  // Only App.swift
        XCTAssertEqual(viewModel.bucketFiles.first?.path, "App.swift")

        // Select Semantic Bucket "tests"
        viewModel.selectBucket("tests")
        XCTAssertEqual(viewModel.selectedBucketId, "tests")
        XCTAssertEqual(viewModel.bucketFiles.count, 1)  // Only AppTests.swift
        XCTAssertEqual(viewModel.bucketFiles.first?.path, "AppTests.swift")
    }
}
