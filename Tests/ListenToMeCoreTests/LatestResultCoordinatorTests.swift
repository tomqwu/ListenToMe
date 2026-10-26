import XCTest
@testable import ListenToMeCore

@MainActor
final class LatestResultCoordinatorTests: XCTestCase {
    func testLatestResultSurvivesAnOlderUncooperativeReply() async {
        let coordinator = LatestResultCoordinator<String>()
        var reply: CheckedContinuation<String, Never>?
        var current = "Original status"
        let old = coordinator.start(load: { await withCheckedContinuation { reply = $0 } }, apply: { current = $0 })
        for _ in 0..<200 where reply == nil { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(reply)
        await coordinator.start(load: { "Current status" }, apply: { current = $0 }).value
        reply?.resume(returning: "Obsolete status")
        await old.value
        XCTAssertEqual(current, "Current status")
    }

    func testCloseDiscardsAPendingResult() async {
        let coordinator = LatestResultCoordinator<String>()
        var reply: CheckedContinuation<String, Never>?
        var publications = 0
        let work = coordinator.start(load: { await withCheckedContinuation { reply = $0 } },
                                     apply: { _ in publications += 1 })
        for _ in 0..<200 where reply == nil { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(reply)
        coordinator.cancel()
        reply?.resume(returning: "Late device result")
        await work.value
        XCTAssertEqual(publications, 0)
    }

    func testCancellationBeforeExecutionStartsNoQuery() async {
        let coordinator = LatestResultCoordinator<String>()
        var queries = 0, publications = 0
        let work = coordinator.start(load: { queries += 1; return "Unrequested result" },
                                     apply: { _ in publications += 1 })
        coordinator.cancel()
        await work.value
        XCTAssertEqual(queries, 0)
        XCTAssertEqual(publications, 0)
    }

    func testReplacementBeforeExecutionQueriesOnlyTheLatestSelection() async {
        let coordinator = LatestResultCoordinator<String>()
        var queries: [String] = [], published: [String] = []
        let old = coordinator.start(load: { queries.append("old"); return "old" }, apply: { published.append($0) })
        let current = coordinator.start(load: { queries.append("current"); return "current" }, apply: { published.append($0) })
        await old.value
        await current.value
        XCTAssertEqual(queries, ["current"])
        XCTAssertEqual(published, ["current"])
    }
}
