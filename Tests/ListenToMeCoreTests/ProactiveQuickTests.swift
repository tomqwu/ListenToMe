import XCTest
@testable import ListenToMeCore

// MARK: - Shared fixtures

/// Clock the tests drive by hand so the debounce is exercised deterministically.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: TimeInterval = 1_000
    var now: TimeInterval { lock.withLock { _now } }
    func advance(_ delta: TimeInterval) { lock.withLock { _now += delta } }
}

/// Provider that holds every stream open until the test releases it, emitting nothing before
/// then — so a request can be left in flight while the session is stopped or reset.
private final class GatedProvider: LLMProvider, @unchecked Sendable {
    let id = "gated"
    private let lock = NSLock()
    private var _requestCount = 0
    private var _releases: [@Sendable () -> Void] = []
    var requestCount: Int { lock.withLock { _requestCount } }
    func release() {
        let releases = lock.withLock { () -> [@Sendable () -> Void] in
            defer { _releases = [] }
            return _releases
        }
        for release in releases { release() }
    }
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        lock.withLock { _requestCount += 1 }
        return AsyncThrowingStream { continuation in
            lock.withLock {
                _releases.append { continuation.yield("answer"); continuation.finish() }
            }
        }
    }
}

/// Answers the automatic evaluator with a publish decision and everything else (a proactive or
/// manual Quick) with prose, so one session can exercise both Quick paths at once.
private struct SplitQuickProvider: LLMProvider {
    let id = "split"
    let answer: String
    let decision: String
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        let text = request.purpose == .quickEvaluation ? decision : answer
        return AsyncThrowingStream { continuation in
            continuation.yield(text)
            continuation.finish()
        }
    }
}

/// Polls `cond` for up to `yields` scheduler turns; returns whether it became true.
@MainActor
@discardableResult
private func settle(_ yields: Int = 50, until cond: @MainActor () -> Bool = { false }) async -> Bool {
    for _ in 0 ..< yields {
        if cond() { return true }
        await Task.yield()
    }
    return cond()
}

@MainActor
private func makeSession(
    provider: any LLMProvider,
    clock: TestClock = TestClock(),
    debounce: TimeInterval = 8,
    availability: @escaping @Sendable (String) -> String? = { _ in nil }
) -> MeetingSession {
    MeetingSession(
        store: ConversationStore(),
        context: ContextEngine(debounce: debounce),
        makeCapture: { MockCapture() },
        makeTranscriber: { MockTranscriber() },
        makeProvider: { model -> any LLMProvider in
            model == "Q" ? provider : MockLLMProvider(id: model, deltas: ["[\(model)]"])
        },
        models: [.listener: "L", .quick: "Q", .deep: "D"],
        providerAvailability: availability,
        clock: { clock.now }
    )
}

private func question(from source: SpeakerSource = .others,
                      _ text: String = "What is the ETA?") -> TranscriptSegment {
    TranscriptSegment(source: source, text: text, isFinal: true, start: 0, end: 1)
}

/// Proactive Quick answers: a finalized question from the *other* party fires a Quick answer
/// automatically (issue #112).
///
/// Every assertion here is made against `RecordingProvider.requestCount`, after awaiting the
/// session's in-flight proactive work — never a synchronous read of `quickSuggestion` right after
/// `ingest`, which would pass with the whole feature deleted.
@MainActor
final class ProactiveQuickTests: XCTestCase {

    // MARK: - Positive

    func testIngestFiresProactiveQuickForAnOthersQuestion() async throws {
        let provider = RecordingProvider(deltas: ["answer"])
        let session = makeSession(provider: provider)
        try await session.start()
        await session.ingest(question())
        await session.awaitProactiveFire()

        XCTAssertEqual(provider.requestCount, 1)
        XCTAssertEqual(session.quickSuggestion, "answer")
        session.stop()
    }

    func testProactiveAnswerHoldsTheQuickPaneAgainstANewerAutomaticRecap() async throws {
        let decision = """
        {"action":"publish","context":"ETA","bullets":["The ETA is Monday."],"reviews":[]}
        """
        let provider = SplitQuickProvider(answer: "PROACTIVE ANSWER", decision: decision)
        let clock = TestClock()
        let session = MeetingSession(
            store: ConversationStore(),
            context: ContextEngine(debounce: 8),
            makeCapture: { MockCapture() },
            makeTranscriber: { MockTranscriber() },
            makeProvider: { model -> any LLMProvider in
                model == "Q" ? provider : MockLLMProvider(id: model, deltas: ["[\(model)]"])
            },
            models: [.quick: "Q", .listener: "L"],
            autoInterval: .milliseconds(15),
            clock: { clock.now })
        try await session.start()
        session.autoSummaryEnabled = true          // the automatic recap runs alongside

        await session.ingest(question(from: .others, "What is the ETA?"))
        await session.awaitProactiveFire()
        XCTAssertEqual(session.quickSuggestion, "PROACTIVE ANSWER")

        // Let the automatic evaluator publish a *different* recap behind it.
        for _ in 0 ..< 200 where session.quickRecap.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(session.quickRecap, "- The ETA is Monday.")
        XCTAssertEqual(session.quickSuggestion, "PROACTIVE ANSWER",
                       "a newer automatic recap must not overwrite the proactive answer")
        XCTAssertTrue(session.quickAnswerOverridesRecap)

        // …and "Show recap" still returns to the recap, exactly as after a manual answer.
        session.dismissQuickAnswer()
        XCTAssertEqual(session.quickSuggestion, "- The ETA is Monday.")
        session.stop()
    }

    func testProactiveFiresAgainOnceTheDebounceHasElapsed() async throws {
        let provider = RecordingProvider(deltas: ["answer"])
        let clock = TestClock()
        let session = makeSession(provider: provider, clock: clock, debounce: 8)
        try await session.start()

        await session.ingest(question(from: .others, "What is the ETA?"))
        await session.awaitProactiveFire()
        XCTAssertEqual(provider.requestCount, 1)

        // Inside the debounce window: a second question must not fire again.
        clock.advance(3)
        await session.ingest(question(from: .others, "And the cost?"))
        await session.awaitProactiveFire()
        XCTAssertEqual(provider.requestCount, 1, "a repeat question inside the debounce must not fire")

        clock.advance(10)
        await session.ingest(question(from: .others, "And the owner?"))
        await session.awaitProactiveFire()
        XCTAssertEqual(provider.requestCount, 2)
        session.stop()
    }

    // MARK: - Negative (each fails if the matching guard is removed)

    func testProactiveDoesNotFireForYourOwnQuestion() async throws {
        let provider = RecordingProvider(deltas: ["answer"])
        let session = makeSession(provider: provider)
        try await session.start()
        await session.ingest(question(from: .you))
        await session.awaitProactiveFire()

        XCTAssertEqual(provider.requestCount, 0)
        XCTAssertEqual(session.quickSuggestion, "")
        session.stop()
    }

    func testProactiveDoesNotFireForNonQuestionRemoteSpeech() async throws {
        let provider = RecordingProvider(deltas: ["answer"])
        let session = makeSession(provider: provider)
        try await session.start()
        await session.ingest(question(from: .others, "We are done here."))
        await session.awaitProactiveFire()

        XCTAssertEqual(provider.requestCount, 0)
        session.stop()
    }

    func testProactiveDoesNotFireForANonFinalQuestion() async throws {
        let provider = RecordingProvider(deltas: ["answer"])
        let session = makeSession(provider: provider)
        try await session.start()
        await session.ingest(TranscriptSegment(source: .others, text: "What is the ETA?",
                                               isFinal: false, start: 0, end: 1))
        await session.awaitProactiveFire()

        XCTAssertEqual(provider.requestCount, 0)
        session.stop()
    }

    func testProactiveDoesNotFireWhenDisabled() async throws {
        let provider = RecordingProvider(deltas: ["answer"])
        let session = makeSession(provider: provider)
        try await session.start()
        session.proactiveEnabled = false
        await session.ingest(question())
        await session.awaitProactiveFire()

        XCTAssertEqual(provider.requestCount, 0)
        session.stop()
    }

    func testProactiveDoesNotFireWhenNotRunning() async {
        let provider = RecordingProvider(deltas: ["answer"])
        let session = makeSession(provider: provider)
        await session.ingest(question())          // never started
        await session.awaitProactiveFire()

        XCTAssertEqual(provider.requestCount, 0)
    }

    func testProactiveDoesNotFireWhenAIIsOff() async throws {
        let provider = RecordingProvider(deltas: ["answer"])
        let session = makeSession(provider: provider)
        try await session.start()
        session.aiEnabled = false
        await session.ingest(question())
        await session.awaitProactiveFire()

        XCTAssertEqual(provider.requestCount, 0)
        session.stop()
    }

    func testProactiveDoesNotFireWhenTheQuickModelIsUnavailable() async throws {
        let provider = RecordingProvider(deltas: ["answer"])
        let session = makeSession(provider: provider, availability: { _ in "Model not installed" })
        try await session.start()
        await session.ingest(question())
        await session.awaitProactiveFire()

        XCTAssertEqual(provider.requestCount, 0)
        session.stop()
    }

    func testProactiveDoesNotInterruptAManualQuickThatIsStillStreaming() async throws {
        let provider = GatedProvider()
        let session = makeSession(provider: provider)
        try await session.start()

        // Start a manual Quick and leave it mid-stream.
        let manual = Task { await session.respondQuick(.answerQuestion) }
        await settle(until: { provider.requestCount == 1 })
        XCTAssertTrue(session.streamingRoles.contains(.quick))

        await session.ingest(question())
        await settle()                      // give an unguarded fire every chance to reach the provider
        XCTAssertEqual(provider.requestCount, 1, "an automatic answer must not cut off a manual one")

        provider.release()
        await manual.value
        session.stop()
    }
}

/// Stopping or resetting a run must reach a proactive answer that was scheduled — or is already
/// streaming — before it lands in the pane of a session the user has moved on from.
@MainActor
final class ProactiveQuickCancellationTests: XCTestCase {

    // MARK: - Cancellation (stop / reset)

    func testAProactiveFireScheduledBeforeStopNeverReachesTheProvider() async throws {
        let provider = GatedProvider()
        let session = makeSession(provider: provider)
        try await session.start()

        // The fire is scheduled by `ingest` but its task body has not run yet.
        await session.ingest(question())
        session.stop()
        await settle()

        XCTAssertEqual(provider.requestCount, 0, "a question from a stopped session must not be answered")
        XCTAssertEqual(session.quickSuggestion, "")
    }

    func testAProactiveFireScheduledBeforeStopDoesNotAnswerIntoTheNextRun() async throws {
        let provider = GatedProvider()
        let session = makeSession(provider: provider)
        try await session.start()

        await session.ingest(question())
        session.stop()
        try await session.start()           // a new run: `runID` has moved on
        await settle()

        XCTAssertEqual(provider.requestCount, 0,
                       "the previous run's question must not answer into the new run")
        XCTAssertEqual(session.quickSuggestion, "")
        session.stop()
    }

    func testAnInFlightProactiveAnswerIsDiscardedWhenTheSessionStops() async throws {
        let provider = GatedProvider()
        let session = makeSession(provider: provider)
        try await session.start()

        await session.ingest(question())
        await settle(until: { provider.requestCount == 1 })
        XCTAssertTrue(session.streamingRoles.contains(.quick))

        session.stop()
        provider.release()                  // the held answer arrives after the stop
        await settle()

        XCTAssertEqual(session.quickSuggestion, "", "a stopped run's answer must not land in the pane")
        XCTAssertFalse(session.streamingRoles.contains(.quick))
    }

    func testResetConversationLeavesNoProactiveAnswerBehind() async throws {
        let provider = GatedProvider()
        let session = makeSession(provider: provider)
        try await session.start()

        await session.ingest(question())
        session.stop()                      // a reset is only allowed once the run has stopped
        session.resetConversation()
        provider.release()
        await settle()

        XCTAssertEqual(provider.requestCount, 0)
        XCTAssertEqual(session.quickSuggestion, "")
        XCTAssertEqual(session.quickRecap, "")
        XCTAssertTrue(session.store.utterances.isEmpty)
    }
}
