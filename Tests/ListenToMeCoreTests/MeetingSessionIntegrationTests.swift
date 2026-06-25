import XCTest
@testable import ListenToMeCore

/// Headless end-to-end tests that exercise the real start() pump:
///   capture.chunks → transcriber.feed
///   transcriber.segments → ingest → store / proactive / listener-refresh
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
        debounce: TimeInterval = 0,
        listenerDebounce: TimeInterval = 0,
        now: @escaping @Sendable () -> TimeInterval = { 999_999 }
    ) -> SessionFixture {
        let capture = MockCapture()
        let transcriber = MockTranscriber()
        let store = ConversationStore()
        let session = MeetingSession(
            store: store,
            context: ContextEngine(debounce: debounce),
            makeCapture: { capture },
            makeTranscriber: { transcriber },
            makeProvider: { model in MockLLMProvider(id: model, deltas: ["[\(model)]"]) },
            models: [.listener: "L", .quick: "Q", .deep: "D"],
            listenerDebounce: listenerDebounce,
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

    // MARK: - Test 3: Proactive quick fires through the pump

    func testProactiveFiresThroughPumpOnRemoteQuestion() async throws {
        let fixture = makeSession(debounce: 0, now: { 999_999 })
        let session = fixture.session
        let transcriber = fixture.transcriber
        session.proactiveEnabled = true
        try await session.start()

        // Emit a finalized question from remote speaker (triggers proactive via real pump)
        let questionSeg = TranscriptSegment(source: .others, text: "Are we ready?",
                                            isFinal: true, start: 0, end: 1)
        transcriber.emit(questionSeg)

        // Wait for ingest to pick it up, then for the quick response task to complete
        await waitUntil { !session.quickSuggestion.isEmpty }
        await session.waitForResponse(.quick)

        XCTAssertEqual(session.quickSuggestion, "[Q]")

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

    func testQuickPromptIncludesCompletedListenerSummary() async throws {
        let quickProvider = RecordingProvider(deltas: ["ok"])
        let store = ConversationStore()
        let session = MeetingSession(
            store: store,
            context: ContextEngine(debounce: 0),
            makeCapture: { MockCapture() },
            makeTranscriber: { MockTranscriber() },
            makeProvider: { model in
                model == "Q"
                    ? (quickProvider as any LLMProvider)
                    : MockLLMProvider(id: model, deltas: ["[\(model)]"])
            },
            models: [.listener: "L", .quick: "Q", .deep: "D"],
            listenerDebounce: 0
        )
        store.apply(TranscriptSegment(source: .others, text: "What's the plan?",
                                      isFinal: true, start: 0, end: 1))
        await session.refreshListener()        // listener completes -> "[L]" is the saved summary
        await session.respondQuick(.answerQuestion)
        let user = quickProvider.lastUser ?? ""
        XCTAssertTrue(user.contains("Meeting summary so far"), "quick prompt should carry the summary")
        XCTAssertTrue(user.contains("[L]"), "quick prompt should include the completed summary text")
    }

    func testTranscribeAudioAppliesSegmentsAndTogglesFlag() async {
        let echo = EchoTranscriber()
        let store = ConversationStore()
        let session = MeetingSession(
            store: store,
            context: ContextEngine(debounce: 0),
            makeCapture: { MockCapture() },
            makeTranscriber: { echo },
            makeProvider: { model in MockLLMProvider(id: model, deltas: ["[\(model)]"]) },
            models: [.listener: "L", .quick: "Q", .deep: "D"]
        )
        let producer = ArrayChunkProducer([
            AudioChunk(samples: [0.1], sampleRate: 16_000, source: .others, timestamp: 0),
            AudioChunk(samples: [0.2], sampleRate: 16_000, source: .others, timestamp: 1)
        ])

        XCTAssertFalse(session.isTranscribingFile)
        await session.transcribeAudio(nextChunk: { await producer.next() })
        XCTAssertFalse(session.isTranscribingFile)               // reset after completion
        XCTAssertEqual(store.utterances.count, 2)                // one final per fed chunk
        XCTAssertEqual(store.utterances.first?.source, .others)
    }

    func testStopAndWaitAwaitsTranscriberShutdown() async throws {
        let fixture = makeSession()
        try await fixture.session.start()
        XCTAssertTrue(fixture.session.isRunning)

        await fixture.session.stopAndWait()
        XCTAssertFalse(fixture.session.isRunning)
        // Teardown is awaited, so the transcriber has finished by the time the call returns.
        XCTAssertEqual(fixture.transcriber.finishCount, 1)

        // Idempotent: a second call is a no-op (no extra finish).
        await fixture.session.stopAndWait()
        XCTAssertEqual(fixture.transcriber.finishCount, 1)
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
        let session = MeetingSession(
            store: store,
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
            makeProvider: { model in MockLLMProvider(id: model, deltas: ["[\(model)]"]) },
            models: [.listener: "L", .quick: "Q", .deep: "D"],
            listenerDebounce: 0,
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

    // MARK: - Test 6: finalized segment triggers listener refresh through pump

    func testFinalizedSegmentTriggersListenerRefreshThroughPump() async throws {
        let fixture = makeSession(listenerDebounce: 0, now: { 0 })
        let session = fixture.session
        let transcriber = fixture.transcriber
        try await session.start()

        let seg = TranscriptSegment(source: .you, text: "Just said something final.",
                                    isFinal: true, start: 0, end: 1)
        transcriber.emit(seg)

        await waitUntil { !session.listenerSummary.isEmpty }
        await session.waitForResponse(.listener)

        XCTAssertFalse(session.listenerSummary.isEmpty,
                       "listenerSummary should be populated after finalized segment")

        session.stop()
    }
}
