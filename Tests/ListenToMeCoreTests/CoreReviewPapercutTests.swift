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

/// Streams a reasoning phase before the answer, like a thinking model on Ollama.
struct ThinkingProvider: LLMProvider {
    let id = "thinking"
    let reasoningDelay: Duration
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("Answer.")
            continuation.finish()
        }
    }
    func streamEvents(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.thinking("The user asked about the rollout, so "))
                try? await Task.sleep(for: reasoningDelay)
                continuation.yield(.content("Answer."))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
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

    /// Issue #113 crossing #137: with the ledger caught up a refresh carries the *provisional*
    /// lines, so unfinalized speech counts as unsummarized — but only until it has been sent.
    func testRefreshRunsForNewProvisionalSpeechAndThenStopsUntilItChanges() async {
        let provider = ScriptedProvider(deltas: ["Summary."])
        let (session, store) = makeSession(provider: provider)
        speak(store, "We shipped the beta.", at: 0)
        await session.refreshListener()
        XCTAssertEqual(provider.requests.count, 1)
        XCTAssertFalse(session.hasUnsummarizedSpeech)

        store.apply(TranscriptSegment(source: .others,
                                      text: "And what should we do about the migration deadline?",
                                      isFinal: false, start: 2, end: 3))
        XCTAssertTrue(session.hasUnsummarizedSpeech, "a fresh hypothesis is speech nobody summarized")
        await session.refreshListener()
        XCTAssertEqual(provider.requests.count, 2)
        XCTAssertTrue(provider.requests.last?.messages.last?.content.contains("migration deadline") == true)

        XCTAssertFalse(session.hasUnsummarizedSpeech, "the same wording must not re-enable Refresh")
        await session.refreshListener()
        XCTAssertEqual(provider.requests.count, 2)
    }

    // MARK: - 4. A reasoning phase is a status, never answer text

    func testThinkingIsShownAsAStatusAndKeptOutOfTheAnswer() async throws {
        let (session, store) = makeSession(provider: ThinkingProvider(reasoningDelay: .milliseconds(80)))
        speak(store, "How is the rollout going?", at: 0)
        let run = Task { await session.respondDeep(.answerQuestion) }

        let deadline = ContinuousClock.now + .seconds(2)
        while session.roleStatus(.deep) == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(session.roleStatus(.deep), "Thinking…",
                       "a reasoning model must not leave the pane looking hung")
        XCTAssertEqual(session.deepAnswer, "", "reasoning is never written into the pane")

        await run.value
        XCTAssertEqual(session.deepAnswer, "Answer.")
        XCTAssertNil(session.roleStatus(.deep))
    }

    /// Cancelling bumps the generation, so `run`'s own cleanup is skipped: without clearing it here
    /// a cancelled reasoning model would leave "Thinking…" on screen for good.
    func testCancellingARunClearsTheThinkingStatus() async throws {
        let (session, store) = makeSession(provider: ThinkingProvider(reasoningDelay: .seconds(5)))
        speak(store, "How is the rollout going?", at: 0)
        let run = Task { await session.respondDeep(.answerQuestion) }
        let deadline = ContinuousClock.now + .seconds(2)
        while session.roleStatus(.deep) == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(session.roleStatus(.deep), "Thinking…")

        session.cancelResponse(.deep)
        XCTAssertNil(session.roleStatus(.deep))
        run.cancel()
    }
}
