import XCTest

@testable import Chobi

@MainActor
final class AgentContextQueryServiceTests: XCTestCase {
    func testReadFileRangeRejectsPathOutsideWorkspace() async {
        let state = AppState()
        let repo = GitRepository(name: "Repo", path: NSTemporaryDirectory())
        state.repositories = [repo]
        state.selectedRepoId = repo.id

        let service = AgentContextQueryService(
            stateProvider: state,
            persistence: state.coordinator.persistence,
            fileRangeLimit: 5
        )

        do {
            _ = try await service.readFileRange(
                workspaceId: repo.id,
                path: "../outside.txt",
                startLine: 1,
                endLine: 1,
                revision: "working"
            )
            XCTFail("Expected path_outside_workspace")
        } catch let error as AgentContextError {
            XCTAssertEqual(error.code, .pathOutsideWorkspace)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testReadFileRangeRejectsOversizedRange() async {
        let state = AppState()
        let repo = GitRepository(name: "Repo", path: NSTemporaryDirectory())
        state.repositories = [repo]
        state.selectedRepoId = repo.id

        let service = AgentContextQueryService(
            stateProvider: state,
            persistence: state.coordinator.persistence,
            fileRangeLimit: 5
        )

        do {
            _ = try await service.readFileRange(
                workspaceId: repo.id,
                path: "file.txt",
                startLine: 1,
                endLine: 6,
                revision: "working"
            )
            XCTFail("Expected line_range_too_large")
        } catch let error as AgentContextError {
            XCTAssertEqual(error.code, .lineRangeTooLarge)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
