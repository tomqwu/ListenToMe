import XCTest
@testable import ListenToMeCore

/// Proactive Quick answers: a finalized question from the *other* party fires a Quick answer
/// automatically (issue #112).
///
/// Every assertion here is made against `RecordingProvider.requestCount`, after awaiting the
/// session's in-flight proactive work — never a synchronous read of `quickSuggestion` right after
/// `ingest`, which would pass with the whole feature deleted.
@MainActor
final class ProactiveQuickTests: XCTestCase {

    /// Clock the test drives by hand so the debounce is exercised deterministically.
    private final class TestClock: @unchecked Sendable {
        private let lock = NSLock()
        private var _now: TimeInterval = 1_000
        var now: TimeInterval { lock.withLock { _now } }
        func advance(_ delta: TimeInterval) { lock.withLock { _now += delta } }
    }

    /// Provider that holds a stream open until the test releases it, so a *manual* Quick can be
    /// left mid-stream while a question is ingested.
    private final class GatedProvider: LLMProvider, @unchecked Sendable {
        let id = "gated"
        private let lock = NSLock()
        private var _requestCount = 0
        private var _release: (@Sendable () -> Void)?
        var requestCount: Int { lock.withLock { _requestCount } }
        func release() { lock.withLock { _release }?() }
        func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
            lock.withLock { _requestCount += 1 }
            return AsyncThrowingStream { continuation in
                continuation.yield("partial")
                lock.withLock { _release = { continuation.finish() } }
            }
        }
    }

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
            makeProvider: { model in model == "Q" ? provider : MockLLMProvider(id: model, deltas: ["[\(model)]"]) },
            models: [.listener: "L", .quick: "Q", .deep: "D"],
            providerAvailability: availability,
            clock: { clock.now }
        )
    }

    private func question(from source: SpeakerSource = .others,
                          _ text: String = "What is the ETA?") -> TranscriptSegment {
        TranscriptSegment(source: source, text: text, isFinal: true, start: 0, end: 1)
    }

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

    func testProactiveAnswerHoldsTheQuickPaneLikeAManualAnswer() async throws {
        let provider = RecordingProvider(deltas: ["answer"])
        let session = makeSession(provider: provider)
        try await session.start()
        await session.ingest(question())
        await session.awaitProactiveFire()

        // A proactive answer is a manual-style answer triggered automatically: it must sit in the
        // same manual-answer state, so the automatic recap does not overwrite it mid-read.
        XCTAssertTrue(session.quickAnswerOverridesRecap || session.quickRecap.isEmpty)
        XCTAssertEqual(session.quickSuggestion, "answer")
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
        while provider.requestCount == 0 { await Task.yield() }
        XCTAssertTrue(session.streamingRoles.contains(.quick))

        await session.ingest(question())
        await Task.yield()
        XCTAssertEqual(provider.requestCount, 1, "an automatic answer must not cut off a manual one")

        provider.release()
        await manual.value
        session.stop()
    }
}
