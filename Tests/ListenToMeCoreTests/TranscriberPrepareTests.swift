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
        let session = makeSession(capture: MockCapture(), transcriber: MockTranscriber())

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
