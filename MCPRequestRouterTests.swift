import XCTest

@testable import Diffuse

@MainActor
final class MCPRequestRouterTests: XCTestCase {
    func testUnknownToolReturnsStructuredError() async {
        let state = AppState()
        let query = AgentContextQueryService(
            stateProvider: state,
            persistence: state.coordinator.persistence
        )
        let router = MCPRequestRouter(queryService: query)

        let result = await router.callTool(name: "diffuse.mutate_repo", arguments: [:])

        XCTAssertEqual(result.isError, true)
        XCTAssertTrue(result.content.first?["text"]?.contains("unsupported_query") == true)
    }

    func testInvalidRunIdReturnsArgumentError() async {
        let state = AppState()
        let query = AgentContextQueryService(
            stateProvider: state,
            persistence: state.coordinator.persistence
        )
        let router = MCPRequestRouter(queryService: query)

        let result = await router.callTool(
            name: "diffuse.get_run_review_context",
            arguments: ["runId": "not-a-uuid"]
        )

        XCTAssertEqual(result.isError, true)
        XCTAssertTrue(result.content.first?["text"]?.contains("invalid_arguments") == true)
    }
}
