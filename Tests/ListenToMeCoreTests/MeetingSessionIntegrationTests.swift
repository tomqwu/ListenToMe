import XCTest
@testable import ListenToMeCore

/// Headless end-to-end tests that exercise the real start() pump:
///   capture.chunks → transcriber.feed
///   transcriber.segments → ingest → store / proactive
///
/// Each test holds direct references to the mock capture/transcriber so it can
/// drive them from outside the session after start() is called.
@MainActor
final class MeetingSessionIntegrationTests: XCTestCase {

    // MARK: - Helpers

    private struct SessionFixture {
        let session: MeetingSession
        let capture: MockCapture
        let transcriber: MockTranscriber
    }

    /// Builds a session where the factories capture the test-held mock instances.
    private func makeSession(
        deltas: [String] = ["ok"],
        debounce: TimeInterval = 0,
        now: @escaping @Sendable () -> TimeInterval = { 999_999 }
    ) -> SessionFixture {
        let capture = MockCapture()
        let transcriber = MockTranscriber()
        let store = ConversationStore()
        let router = ModelRouter(default: MockLLMProvider(id: "mock", deltas: deltas))
        let session = MeetingSession(
            store: store,
            router: router,
            context: ContextEngine(debounce: debounce),
            makeCapture: { capture },
            makeTranscriber: { transcriber },
            clock: now
        )
        return SessionFixture(session: session, capture: capture, transcriber: transcriber)
    }

    /// Polls `cond` up to `timeoutMs` milliseconds in 10 ms increments.
    private func waitUntil(_ timeoutMs: Int = 1000, _ cond: () -> Bool) async {
        var elapsed = 0
        while !cond() && elapsed < timeoutMs {
            try? await Task.sleep(nanoseconds: 10_000_000)
            elapsed += 10
        }
    }

    // MARK: - Test 1: Transcript flows through the pump (segments → ingest → store)

    func testTranscriptSegmentsFlowThroughPumpIntoStore() async throws {
        let fixture = makeSession()
        let session = fixture.session
        let transcriber = fixture.transcriber
        try await session.start()
        XCTAssertTrue(session.isRunning)

        let seg1 = TranscriptSegment(source: .others, text: "Hello pump",
                                     isFinal: true, start: 0, end: 1)
        let seg2 = TranscriptSegment(source: .you, text: "Indeed",
                                     isFinal: true, start: 1, end: 2)
        transcriber.emit(seg1)
        transcriber.emit(seg2)

        await waitUntil { session.store.utterances.count >= 2 }

        XCTAssertEqual(session.store.utterances.map(\.text), ["Hello pump", "Indeed"])

        session.stop()
    }

    // MARK: - Test 2: Chunks flow from capture → transcriber.feed

    func testAudioChunksFlowFromCaptureToTranscriberFeed() async throws {
        let fixture = makeSession()
        let session = fixture.session
        let capture = fixture.capture
        let transcriber = fixture.transcriber
        try await session.start()

        let chunk = AudioChunk(samples: [0.1, 0.2], sampleRate: 16000,
                               source: .you, timestamp: 0)
        capture.emit(chunk)

        await waitUntil { transcriber.fedChunks.count >= 1 }

        XCTAssertEqual(transcriber.fedChunks.count, 1)
        XCTAssertEqual(transcriber.fedChunks[0], chunk)

        session.stop()
    }

    // MARK: - Test 3: Proactive fires through the pump

    func testProactiveFiresThroughPumpOnRemoteQuestion() async throws {
        let fixture = makeSession(
            deltas: ["Great ", "answer."],
            debounce: 0,
            now: { 999_999 }   // far future so debounce is always satisfied
        )
        let session = fixture.session
        let transcriber = fixture.transcriber
        session.proactiveEnabled = true
        try await session.start()

        // Emit a finalized question from remote speaker (triggers proactive via real pump)
        let questionSeg = TranscriptSegment(source: .others, text: "Are we ready?",
                                            isFinal: true, start: 0, end: 1)
        transcriber.emit(questionSeg)

        // Wait for ingest to pick it up, then for the response task to complete
        await waitUntil { !session.suggestion.isEmpty }
        await session.waitForResponse()

        XCTAssertEqual(session.suggestion, "Great answer.")

        session.stop()
    }

    // MARK: - Test 4: stop() halts and is idempotent

    func testStopHaltsSessionAndIsIdempotent() async throws {
        let session = makeSession().session
        try await session.start()
        XCTAssertTrue(session.isRunning)

        session.stop()
        XCTAssertFalse(session.isRunning)

        // Second stop must not crash
        session.stop()
        XCTAssertFalse(session.isRunning)
    }

    // MARK: - Test 5: restart creates fresh capture/transcriber and pump works again

    func testRestartCreatesFreshPumpAndDeliversSegments() async throws {
        // Use a thread-safe tracker to work around Swift 6's @Sendable closure capture rules.
        final class InstanceTracker: @unchecked Sendable {
            var captures: [MockCapture] = []
            var transcribers: [MockTranscriber] = []
        }
        let tracker = InstanceTracker()

        let store = ConversationStore()
        let router = ModelRouter(default: MockLLMProvider(id: "mock", deltas: ["ok"]))
        let session = MeetingSession(
            store: store,
            router: router,
            context: ContextEngine(debounce: 0),
            makeCapture: {
                let c = MockCapture()
                tracker.captures.append(c)
                return c
            },
            makeTranscriber: {
                let t = MockTranscriber()
                tracker.transcribers.append(t)
                return t
            },
            clock: { 0 }
        )

        // First run
        try await session.start()
        XCTAssertTrue(session.isRunning)
        session.stop()
        XCTAssertFalse(session.isRunning)

        // Second run
        try await session.start()
        XCTAssertTrue(session.isRunning, "Session should be running after restart")

        // Each start should create a new capture and transcriber
        XCTAssertEqual(tracker.captures.count, 2, "Expected two capture instances (one per start)")
        XCTAssertEqual(tracker.transcribers.count, 2, "Expected two transcriber instances (one per start)")

        // Drive the second transcriber — segments should land in the store
        let seg = TranscriptSegment(source: .you, text: "After restart",
                                    isFinal: true, start: 10, end: 11)
        tracker.transcribers[1].emit(seg)

        await waitUntil { session.store.utterances.count >= 1 }

        XCTAssertEqual(session.store.utterances.map(\.text), ["After restart"])

        session.stop()
    }
}
