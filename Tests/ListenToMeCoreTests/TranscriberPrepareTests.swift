import XCTest
@testable import ListenToMeCore

/// Covers issue #99: the first-run speech-model download must not freeze teardown, and the
/// transcriber pipeline must be warmed up BEFORE audio starts flowing (so the opening seconds
/// aren't dropped by the capture stream's bounded buffer).
@MainActor
final class TranscriberPrepareTests: XCTestCase {

    /// Thread-safe one-shot flag used to detect whether an awaited call ever returned.
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var _value = false
        func set() { lock.withLock { _value = true } }
        var value: Bool { lock.withLock { _value } }
    }

    private func makeSession(capture: MockCapture, transcriber: MockTranscriber) -> MeetingSession {
        MeetingSession(
            store: ConversationStore(),
            context: ContextEngine(debounce: 0),
            makeCapture: { capture },
            makeTranscriber: { transcriber },
            makeProvider: { model in MockLLMProvider(id: model, deltas: ["[\(model)]"]) },
            models: [.listener: "L", .quick: "Q", .deep: "D"],
            listenerDebounce: 0,
            clock: { 0 }
        )
    }

    /// Polls `cond` up to `timeoutMs` milliseconds in 10 ms increments.
    private func waitUntil(_ timeoutMs: Int = 2000, _ cond: () -> Bool) async {
        var elapsed = 0
        while !cond() && elapsed < timeoutMs {
            try? await Task.sleep(nanoseconds: 10_000_000)
            elapsed += 10
        }
    }

    // MARK: - Warm-up ordering

    func testStartPreparesTranscriberBeforeStartingCapture() async throws {
        let log = OrderLog()
        let capture = MockCapture(log: log)
        let transcriber = MockTranscriber(log: log)
        let session = makeSession(capture: capture, transcriber: transcriber)

        try await session.start()

        XCTAssertEqual(transcriber.prepareCount, 1)
        guard let prepareIndex = log.index(of: "transcriber.prepare"),
              let startIndex = log.index(of: "capture.start") else {
            return XCTFail("expected both prepare and capture.start to be recorded, got \(log.events)")
        }
        XCTAssertLessThan(prepareIndex, startIndex,
                          "the transcriber pipeline must be warm before audio starts flowing")
        await session.stopAndWait()
    }

    func testTranscribeAudioPreparesBeforeTheFirstChunk() async {
        let log = OrderLog()
        let transcriber = MockTranscriber(log: log)
        let session = makeSession(capture: MockCapture(), transcriber: transcriber)

        let producer = ArrayChunkProducer([
            AudioChunk(samples: [0.1], sampleRate: 16_000, source: .you, timestamp: 0)
        ])
        await session.transcribeAudio(nextChunk: { await producer.next() },
                                      transcriber: { transcriber })

        XCTAssertEqual(transcriber.prepareCount, 1)
        guard let prepareIndex = log.index(of: "transcriber.prepare"),
              let feedIndex = log.index(of: "transcriber.feed") else {
            return XCTFail("expected prepare and feed to be recorded, got \(log.events)")
        }
        XCTAssertLessThan(prepareIndex, feedIndex)
    }

    // MARK: - Preparing state (issue #147)

    func testSessionIsPreparingUntilTheSpeechModelIsWarm() async throws {
        let capture = MockCapture()
        let transcriber = MockTranscriber(slowPrepare: true)
        let session = makeSession(capture: capture, transcriber: transcriber)
        XCTAssertFalse(session.isPreparing)

        let startTask = Task { try await session.start() }
        await waitUntil { session.isPreparing }
        XCTAssertTrue(session.isPreparing, "the rail must distinguish preparing from recording")
        XCTAssertTrue(session.isRunning)
        XCTAssertEqual(capture.startCount, 0)

        transcriber.release()
        _ = try? await startTask.value
        XCTAssertFalse(session.isPreparing, "preparing must end once capture starts")
        XCTAssertTrue(session.isRunning)
        await session.stopAndWait()
        XCTAssertFalse(session.isPreparing)
    }

    func testAutomaticReviewsDoNotDispatchWhilePreparing() async throws {
        let transcriber = MockTranscriber(slowPrepare: true)
        let publish = Self.publishDecision
        let session = MeetingSession(
            store: ConversationStore(), context: ContextEngine(debounce: 0),
            makeCapture: { MockCapture() }, makeTranscriber: { transcriber },
            makeProvider: { model in MockLLMProvider(id: model, deltas: [publish]) },
            models: [.listener: "L", .quick: "Q", .deep: "D"],
            listenerDebounce: 0, autoInterval: .milliseconds(5))
        session.autoSummaryEnabled = true
        await session.ingest(TranscriptSegment(source: .others, text: "Sarah confirms Monday.",
                                               isFinal: true, start: 0, end: 1))

        let startTask = Task { try await session.start() }
        await waitUntil { session.isPreparing }
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(session.quickReader.completedReads, 0,
                       "automatic reviews must not run against old transcript while preparing")

        transcriber.release()
        _ = try? await startTask.value
        await waitUntil { session.quickReader.completedReads > 0 }
        XCTAssertGreaterThan(session.quickReader.completedReads, 0,
                             "automation must resume once the model is warm")
        await session.stopAndWait()
    }

    private static let publishDecision = """
    {"action":"publish","context":"Monday","bullets":["Sarah confirms Monday."],"reviews":[]}
    """

    // MARK: - Teardown while the model is still downloading

    func testStopDuringPrepareCancelsPrepareAndSkipsCapture() async throws {
        let capture = MockCapture()
        let transcriber = MockTranscriber(slowPrepare: true)
        let session = makeSession(capture: capture, transcriber: transcriber)

        let startTask = Task { try await session.start() }
        await waitUntil { transcriber.prepareEntered }
        XCTAssertTrue(transcriber.prepareEntered, "prepare never ran")
        XCTAssertEqual(capture.startCount, 0, "capture must not start until prepare returns")

        // Stop while the "download" is still in flight: it must return promptly, not after minutes.
        let stopped = Flag()
        let stopTask = Task { await session.stopAndWait(); stopped.set() }
        await waitUntil { stopped.value }
        guard stopped.value else {
            stopTask.cancel(); startTask.cancel(); transcriber.release()
            return XCTFail("stopAndWait blocked behind the in-flight model download")
        }
        await stopTask.value

        XCTAssertTrue(transcriber.prepareCancelled, "prepare should have been cancelled by stop")
        XCTAssertFalse(session.isRunning)
        _ = try? await startTask.value
        XCTAssertEqual(capture.startCount, 0, "an aborted start must never start capture")
        XCTAssertEqual(transcriber.finishCount, 1)
    }

    /// The live path must use the same cancellation-racing wait as the import path: a Stop during a
    /// download whose platform call ignores cancellation must not park the start task (issue #147).
    func testStopDuringAnUncancellablePrepareDoesNotParkTheStartTask() async throws {
        let capture = MockCapture()
        let transcriber = MockTranscriber(stubbornPrepare: true)
        let session = makeSession(capture: capture, transcriber: transcriber)

        let startFinished = Flag()
        let startTask = Task { try? await session.start(); startFinished.set() }
        await waitUntil { transcriber.prepareEntered }
        XCTAssertTrue(transcriber.prepareEntered, "prepare never ran")

        await session.stopAndWait()
        await waitUntil { startFinished.value }
        guard startFinished.value else {
            startTask.cancel(); transcriber.release()
            return XCTFail("start() stayed parked inside an uncancellable model download")
        }
        await startTask.value
        XCTAssertFalse(session.isRunning)
        XCTAssertFalse(session.isPreparing)
        XCTAssertEqual(capture.startCount, 0, "an aborted start must never start capture")
        transcriber.release()   // let the abandoned prepare unwind
    }

    func testChunksBufferedAtStopAreStillFedBeforeFinalize() async throws {
        let capture = MockCapture()
        // 20 ms per chunk: 5 chunks take ~100 ms, well inside teardown's drain grace — but a pump
        // that is cancelled outright stops iterating and feeds almost none of them.
        let transcriber = MockTranscriber(feedDelayNanos: 20_000_000)
        let session = makeSession(capture: capture, transcriber: transcriber)

        try await session.start()
        let chunks = (0..<5).map {
            AudioChunk(samples: [0.3], sampleRate: 16_000, source: .others, timestamp: Double($0))
        }
        for chunk in chunks { capture.emit(chunk) }
        // No wait: Stop immediately, while the chunks are still buffered in the capture stream.
        await session.stopAndWait()

        XCTAssertEqual(transcriber.fedChunks, chunks,
                       "teardown must let the pump feed the audio buffered at Stop")
        XCTAssertEqual(transcriber.finishCount, 1)
    }

    func testCancellingAnImportDuringPrepareReturnsPromptly() async throws {
        // prepare() here ignores cancellation (like a platform download with no cancellation
        // guarantee); the import must still return when its task is cancelled.
        let transcriber = MockTranscriber(stubbornPrepare: true)
        let session = makeSession(capture: MockCapture(), transcriber: transcriber)
        let producer = ArrayChunkProducer([
            AudioChunk(samples: [0.1], sampleRate: 16_000, source: .you, timestamp: 0)
        ])

        let finished = Flag()
        let importTask = Task {
            await session.transcribeAudio(nextChunk: { await producer.next() },
                                          transcriber: { transcriber })
            finished.set()
        }
        await waitUntil { transcriber.prepareEntered }
        XCTAssertTrue(transcriber.prepareEntered, "prepare never ran")

        importTask.cancel()
        await waitUntil { finished.value }
        guard finished.value else {
            transcriber.release()
            return XCTFail("a cancelled import stayed blocked inside the model download")
        }
        await importTask.value
        XCTAssertFalse(session.isTranscribingFile)
        XCTAssertTrue(transcriber.fedChunks.isEmpty, "a cancelled import must not feed audio")
        transcriber.release()   // let the abandoned prepare unwind
    }

    func testStopCancelsACapturePumpBlockedInsideFeed() async throws {
        let capture = MockCapture()
        let transcriber = MockTranscriber(slowFeed: true)
        let session = makeSession(capture: capture, transcriber: transcriber)

        try await session.start()
        capture.emit(AudioChunk(samples: [0.1], sampleRate: 16_000, source: .you, timestamp: 0))
        await waitUntil { transcriber.feedEntered }
        XCTAssertTrue(transcriber.feedEntered, "feed never ran")

        let stopped = Flag()
        let stopTask = Task { await session.stopAndWait(); stopped.set() }
        await waitUntil { stopped.value }
        guard stopped.value else {
            stopTask.cancel(); transcriber.release()
            return XCTFail("stopAndWait blocked behind a feed stuck in a model download")
        }
        await stopTask.value

        XCTAssertTrue(transcriber.feedCancelled, "the capture pump should have been cancelled")
        XCTAssertFalse(session.isRunning)
        XCTAssertEqual(transcriber.finishCount, 1)
    }
}
