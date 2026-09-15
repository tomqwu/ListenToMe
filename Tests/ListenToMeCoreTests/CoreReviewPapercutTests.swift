import XCTest
@testable import ListenToMeCore

/// Issue #137: core review papercuts — blank-on-failure panes, no-op Listener refresh, dropped
/// queued reviews, thinking deltas and the model-locality heuristic.

/// A provider whose script the test can swap between runs: it streams `deltas`, or fails.
final class ScriptedProvider: LLMProvider, @unchecked Sendable {
    let id = "scripted"
    private let lock = NSLock()
    private var _deltas: [String]
    private var _error: Error?
    private var _requests: [LLMRequest] = []
    var requests: [LLMRequest] { lock.withLock { _requests } }

    init(deltas: [String]) { _deltas = deltas }

    func fail(with error: Error) { lock.withLock { _error = error } }
    func succeed(with deltas: [String]) { lock.withLock { _deltas = deltas; _error = nil } }

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        let (deltas, error) = lock.withLock { () -> ([String], Error?) in
            _requests.append(request)
            return (_deltas, _error)
        }
        return AsyncThrowingStream { continuation in
            if let error { continuation.finish(throwing: error); return }
            for delta in deltas { continuation.yield(delta) }
            continuation.finish()
        }
    }
}

@MainActor
final class CoreReviewPapercutTests: XCTestCase {

    private func makeSession(provider: any LLMProvider) -> (MeetingSession, ConversationStore) {
        let store = ConversationStore()
        let session = MeetingSession(
            store: store,
            context: ContextEngine(debounce: 5),
            makeCapture: { MockCapture() },
            makeTranscriber: { MockTranscriber() },
            makeProvider: { _ in provider },
            models: [.listener: "L", .quick: "Q", .deep: "D"],
            listenerDebounce: 0,
            clock: { 0 })
        return (session, store)
    }

    private func speak(_ store: ConversationStore, _ text: String, at start: Double) {
        store.apply(TranscriptSegment(source: .others, text: text, isFinal: true,
                                      start: start, end: start + 1))
    }

    // MARK: - 1. A failed manual run keeps the output the user was reading

    func testListenerKeepsPreviousSummaryWhenARefreshFails() async {
        let provider = ScriptedProvider(deltas: ["The team agreed to ship Friday."])
        let (session, store) = makeSession(provider: provider)
        speak(store, "We should ship on Friday.", at: 0)
        await session.refreshListener()
        XCTAssertEqual(session.listenerSummary, "The team agreed to ship Friday.")
        XCTAssertNil(session.roleError(.listener))

        provider.fail(with: QuickSummaryError.message("Ollama returned HTTP 500."))
        speak(store, "And we need the changelog.", at: 2)
        await session.refreshListener()

        XCTAssertEqual(session.listenerSummary, "The team agreed to ship Friday.",
                       "a transient failure must not blank the pane")
        XCTAssertEqual(session.roleError(.listener), "Ollama returned HTTP 500.")
    }

    func testQuickKeepsPreviousAnswerWhenAManualRequestFails() async {
        let provider = ScriptedProvider(deltas: ["Say yes."])
        let (session, store) = makeSession(provider: provider)
        speak(store, "Do you agree?", at: 0)
        await session.respondQuick(.answerQuestion)
        XCTAssertEqual(session.quickSuggestion, "Say yes.")

        provider.fail(with: QuickSummaryError.message("Model error: overloaded"))
        await session.respondQuick(.answerQuestion)

        XCTAssertEqual(session.quickSuggestion, "Say yes.")
        XCTAssertEqual(session.roleError(.quick), "Model error: overloaded")
    }

    func testASuccessfulRunClearsThePreviousRoleError() async {
        let provider = ScriptedProvider(deltas: ["Answer."])
        let (session, store) = makeSession(provider: provider)
        speak(store, "Question?", at: 0)
        provider.fail(with: QuickSummaryError.message("boom"))
        await session.respondDeep(.answerQuestion)
        XCTAssertEqual(session.roleError(.deep), "boom")

        provider.succeed(with: ["Detailed answer."])
        await session.respondDeep(.answerQuestion)
        XCTAssertNil(session.roleError(.deep))
        XCTAssertEqual(session.deepAnswer, "Detailed answer.")
    }

    // MARK: - 2. Listener refresh is a no-op when there is nothing new to summarize

    func testRefreshOnAnEmptyStoreNeverCallsTheModel() async {
        let provider = ScriptedProvider(deltas: ["Summary of nothing."])
        let (session, _) = makeSession(provider: provider)
        XCTAssertFalse(session.hasUnsummarizedSpeech)
        await session.refreshListener()
        XCTAssertTrue(provider.requests.isEmpty)
        XCTAssertEqual(session.listenerSummary, "")
    }

    func testASecondRefreshWithNothingNewKeepsTheSummaryAndSkipsTheModel() async {
        let provider = ScriptedProvider(deltas: ["Decision: ship Friday."])
        let (session, store) = makeSession(provider: provider)
        speak(store, "We ship Friday.", at: 0)
        await session.refreshListener()
        XCTAssertEqual(provider.requests.count, 1)
        XCTAssertFalse(session.hasUnsummarizedSpeech)

        await session.refreshListener()

        XCTAssertEqual(provider.requests.count, 1, "nothing new: the model must not be re-asked")
        XCTAssertEqual(session.listenerSummary, "Decision: ship Friday.")

        speak(store, "Also write the changelog.", at: 2)
        XCTAssertTrue(session.hasUnsummarizedSpeech)
        await session.refreshListener()
        XCTAssertEqual(provider.requests.count, 2)
    }
}
