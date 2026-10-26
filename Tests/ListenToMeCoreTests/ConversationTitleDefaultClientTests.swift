import XCTest
import ListenToMeCore

/// A second native client object exercises the public initializer's default generator linkage.
@MainActor
final class ConversationTitleDefaultClientTests: XCTestCase {
    func testDefaultInitializerAcrossClientFilesKeepsLocalSummaryTitle() async throws {
        let coordinator = ConversationTitleCoordinator()
        let snapshot = ConversationTitleCoordinator.Snapshot(title: ConversationTitle.mobileDefault,
            state: .placeholder, spoken: String(repeating: "budget review next month ", count: 10),
            summary: "Budget review")
        var result: String?
        let task = try XCTUnwrap(coordinator.name("other-client", snapshot: snapshot, language: "en", provider: nil) {
            result = $0.title
        })
        await task.value
        XCTAssertEqual(result, "Budget review")
        XCTAssertFalse(coordinator.isNaming("other-client"))
    }
}
