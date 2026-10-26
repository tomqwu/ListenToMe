import XCTest
@testable import ListenToMeCore

@MainActor
final class ResponseStopTests: XCTestCase {
    func testStopKeepsPartialRejectsLateTokensAndAllowsRestart() async throws {
        let provider = StoppableFixtureProvider()
        let model = MeetingSession(store: ConversationStore(), context: ContextEngine(debounce: 0),
                                   makeCapture: { MockCapture() }, makeTranscriber: { MockTranscriber() },
                                   makeProvider: { _ in provider }, models: [.quick: "fixture"])
        let first = Task { await model.respondQuick(.answerQuestion) }
        await provider.started()
        provider.send("Partial answer")
        for _ in 0..<100 where model.quickSuggestion != "Partial answer" {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(model.quickSuggestion, "Partial answer")
        model.stopResponse(.quick)
        XCTAssertTrue(model.stoppedResponseRoles.contains(.quick))
        XCTAssertFalse(model.streamingRoles.contains(.quick))
        XCTAssertTrue(model.manualQuickAnswer.isFresh(at: Date().timeIntervalSince1970))
        provider.send(" obsolete tail")
        provider.finish()
        await first.value
        XCTAssertEqual(model.quickSuggestion, "Partial answer")
        XCTAssertNil(model.roleError(.quick))
        let second = Task { await model.respondQuick(.answerQuestion) }
        await provider.started()
        XCTAssertFalse(model.stoppedResponseRoles.contains(.quick))
        provider.send("New answer")
        provider.finish()
        await second.value
        XCTAssertEqual(model.quickSuggestion, "New answer")
        model.stopResponse(.quick)
        XCTAssertFalse(model.stoppedResponseRoles.contains(.quick), "Idle Stop must not label a completed answer partial")
        let third = Task { await model.respondQuick(.recap) }
        await provider.started()
        model.stopResponse(.quick)
        provider.finish()
        await third.value
        XCTAssertTrue(model.stoppedResponseRoles.contains(.quick))
        model.resetConversation()
        XCTAssertTrue(model.stoppedResponseRoles.isEmpty)
    }
}

private final class StoppableFixtureProvider: LLMProvider, @unchecked Sendable {
    let id = "stoppable"
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<String, Error>.Continuation?
    private let starts = AsyncStream<Void>.makeStream()
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            lock.withLock { self.continuation = continuation }
            starts.continuation.yield(())
        }
    }
    func started() async { for await _ in starts.stream { return } }
    func send(_ text: String) { lock.withLock { continuation }?.yield(text) }
    func finish() { lock.withLock { continuation }?.finish() }
}
