import XCTest
@testable import ListenToMeCore

@MainActor
final class ConversationTitleCoordinatorTests: XCTestCase {
    func testRepeatedRequestsJoinOneGenerationAndApplyOnce() async throws {
        let gate = NamingGate()
        let coordinator = ConversationTitleCoordinator { _, language, _ in await gate.generate(language!) }
        var results: [ConversationTitleCoordinator.Result] = []
        let first = try XCTUnwrap(coordinator.name("one", snapshot: snapshot(), language: "first", provider: nil) {
            results.append($0)
        })
        let repeated = try XCTUnwrap(coordinator.name("one", snapshot: snapshot(), language: "duplicate", provider: nil) { _ in
            XCTFail("a second apply callback must not replace the first")
        })
        await until { await gate.count == 1 }
        XCTAssertTrue(coordinator.isNaming("one"))
        await gate.release("first", title: "Budget review")
        await first.value; await repeated.value
        XCTAssertEqual(results.map(\.title), ["Budget review"])
        XCTAssertEqual(results.first?.state.source, .automatic)
        XCTAssertFalse(coordinator.isNaming("one"))
        await coordinator.wait(for: "missing")
    }

    func testCancelledOldTaskCannotClearOrApplyOverNewGeneration() async throws {
        let gate = NamingGate()
        let coordinator = ConversationTitleCoordinator { _, language, _ in await gate.generate(language!) }
        var results: [String?] = []
        let old = try XCTUnwrap(coordinator.name("one", snapshot: snapshot(), language: "old", provider: nil) {
            results.append($0.title)
        })
        await until { await gate.count == 1 }
        coordinator.cancel("one")
        let current = try XCTUnwrap(coordinator.name("one", snapshot: snapshot(), language: "new", provider: nil) {
            results.append($0.title)
        })
        await until { await gate.count == 2 }
        await gate.release("old", title: "Stale title") // deliberately ignores cancellation
        await old.value
        XCTAssertTrue(coordinator.isNaming("one"))
        XCTAssertTrue(results.isEmpty)
        await gate.release("new", title: "Current title")
        await current.value
        XCTAssertEqual(results, ["Current title"])
        XCTAssertFalse(coordinator.isNaming("one"))
    }

    func testConversationsFinishIndependentlyAndCancellationIsScoped() async throws {
        let gate = NamingGate()
        let coordinator = ConversationTitleCoordinator { _, language, _ in await gate.generate(language!) }
        var applied: [String] = []
        let old = try XCTUnwrap(coordinator.name("old", snapshot: snapshot(), language: "old", provider: nil) {
            _ in applied.append("old")
        })
        let new = try XCTUnwrap(coordinator.name("new", snapshot: snapshot(), language: "new", provider: nil) {
            _ in applied.append("new")
        })
        await until { await gate.count == 2 }
        coordinator.cancel("old"); coordinator.cancel("missing")
        await gate.release("new", title: "New record")
        await new.value
        await gate.release("old", title: "Cancelled record")
        await old.value
        XCTAssertEqual(applied, ["new"])
    }

    func testNoTitleRecordsAttemptAndTypedCalendarOrPartialOnlyTextNeverStarts() async throws {
        let coordinator = ConversationTitleCoordinator { _, _, _ in nil }
        var attempted: ConversationTitleState?
        let task = try XCTUnwrap(coordinator.name("one", snapshot: snapshot(), language: nil, provider: nil) {
            attempted = $0.state; XCTAssertNil($0.title)
        })
        await task.value
        XCTAssertEqual(attempted?.attemptedWords, snapshot().words)
        for state in [ConversationTitleState.user, .calendar] {
            XCTAssertNil(coordinator.name("one", snapshot: snapshot(state: state), language: nil, provider: nil) {
                _ in XCTFail("an explicit title must not be replaced")
            })
        }
        let unfinished = ConversationTitleCoordinator.Snapshot(title: ConversationTitle.mobileDefault,
            state: .placeholder, segments: [TranscriptSegment(source: .you, text: snapshot().spoken,
                                                             isFinal: false, start: 0, end: 10)], summary: "")
        XCTAssertNil(coordinator.name("one", snapshot: unfinished, language: nil, provider: nil) {
            _ in XCTFail("unfinished speech must not name the conversation")
        })
    }

    func testDefaultGeneratorUsesExistingSummaryWithoutAProvider() async throws {
        let coordinator = ConversationTitleCoordinator()
        let source = ConversationTitleCoordinator.Snapshot(title: ConversationTitle.mobileDefault,
            state: .placeholder, spoken: snapshot().spoken, summary: "Budget review")
        var title: String?
        let task = try XCTUnwrap(coordinator.name("one", snapshot: source, language: "en", provider: nil) {
            title = $0.title
        })
        await task.value
        XCTAssertEqual(title, "Budget review")
    }

    private func snapshot(state: ConversationTitleState = .placeholder) -> ConversationTitleCoordinator.Snapshot {
        .init(title: ConversationTitle.mobileDefault, state: state,
              spoken: String(repeating: "budget review next month ", count: 10), summary: "")
    }

    private func until(_ predicate: () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<1_000 {
            if await predicate() { return }
            await Task.yield()
        }
        XCTFail("naming did not start", file: file, line: line)
    }
}

private actor NamingGate {
    var count = 0
    var waiting: [String: CheckedContinuation<String?, Never>] = [:]
    func generate(_ key: String) async -> String? {
        count += 1
        return await withCheckedContinuation { waiting[key] = $0 }
    }
    func release(_ key: String, title: String?) { waiting.removeValue(forKey: key)?.resume(returning: title) }
}
