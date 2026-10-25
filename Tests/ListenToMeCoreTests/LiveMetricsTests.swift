import XCTest
@testable import ListenToMeCore

@MainActor
final class LiveMetricsTests: XCTestCase {
    func testPCMLevelsDistinguishSilenceMissingAndSeparateSources() throws {
        let levels = LiveAudioLevels()
        XCTAssertNil(levels.sample(for: .you, now: 0))
        levels.ingest(.init(samples: [0, 0], sampleRate: 16_000, source: .you, timestamp: 0), now: 1)
        XCTAssertEqual(levels.sample(for: .you, now: 1)?.fraction, 0)
        levels.ingest(.init(samples: [0.5, -0.5], sampleRate: 16_000, source: .others, timestamp: 0), now: 1)
        XCTAssertEqual(try XCTUnwrap(levels.sample(for: .others, now: 1)).decibels, -6.0206, accuracy: 0.001)
        levels.ingest(.init(samples: [1], sampleRate: 16_000, source: .you, timestamp: 0), now: 1.01)
        XCTAssertEqual(levels.sample(for: .you, now: 1.01)?.fraction, 0, "Display updates are bounded to 20 Hz")
        levels.ingest(.init(samples: [], sampleRate: 16_000, source: .you, timestamp: 0), now: 2)
        XCTAssertNil(levels.sample(for: .you, now: 2))
        levels.ingest(.init(samples: [.nan], sampleRate: 16_000, source: .you, timestamp: 0), now: 3)
        XCTAssertEqual(levels.sample(for: .you, now: 3)?.fraction, 0)
        levels.reset()
        XCTAssertNil(levels.sample(for: .others, now: 1))
    }

    func testHeldFeedDoesNotMakeBufferedOldAudioFreshWhenItDrains() async throws {
        let capture = MockCapture()
        let transcriber = MockTranscriber(slowFeed: true)
        let session = MeetingSession(store: ConversationStore(), context: ContextEngine(debounce: 0),
            makeCapture: { capture }, makeTranscriber: { transcriber },
            makeProvider: { _ in MockLLMProvider(id: "test", deltas: []) }, models: [:])
        try await session.start()
        capture.emit(.init(samples: [0], sampleRate: 16_000, source: .you, timestamp: 0,
                           capturedAtUptime: ProcessInfo.processInfo.systemUptime))
        for _ in 0..<200 where !transcriber.feedEntered { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertTrue(transcriber.feedEntered)
        capture.emit(.init(samples: [1], sampleRate: 16_000, source: .others, timestamp: 1,
                           capturedAtUptime: ProcessInfo.processInfo.systemUptime - 5))
        transcriber.release()
        for _ in 0..<200 where transcriber.fedChunks.count < 2 { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertEqual(transcriber.fedChunks.count, 2)
        XCTAssertNil(session.audioLevels.sample(for: .others, now: ProcessInfo.processInfo.systemUptime))
        capture.emit(.init(samples: [1], sampleRate: 16_000, source: .others, timestamp: 6,
                           capturedAtUptime: ProcessInfo.processInfo.systemUptime))
        for _ in 0..<200 where transcriber.fedChunks.count < 3 { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertEqual(session.audioLevels.sample(for: .others, now: ProcessInfo.processInfo.systemUptime)?.fraction, 1)
        await session.stopAndWait()
    }

    func testTimingForwardsContentAndDistinguishesThinkingFromFirstAnswer() async throws {
        let timings = ResponseTimings()
        let clock = MetricsClock()
        let provider = timings.instrument(MetricsEvents(), role: .quick, clock: { clock.next() })
        XCTAssertEqual(provider.id, "events")
        XCTAssertEqual(provider.maxPromptCharacters, 99)
        var events: [LLMStreamEvent] = []
        for try await event in provider.streamEvents(.init(system: "", messages: [])) { events.append(event) }
        XCTAssertEqual(events, [.thinking("Thinking"), .content(""), .content("Answer"), .outputLimitReached])
        let result = try XCTUnwrap(timings.measurements[.quick])
        XCTAssertEqual(result.firstContent, 0.25)
        XCTAssertEqual(result.elapsed, 0.5)
        XCTAssertEqual(result.outcome, .completed)
    }

    func testFailureAndEmptyCompletionHaveNoFirstContent() async {
        let timings = ResponseTimings()
        for fail in [false, true] {
            let provider = timings.instrument(MetricsEmpty(fail: fail), role: .deep)
            do { for try await _ in provider.stream(.init(system: "", messages: [])) {} } catch {}
            XCTAssertNil(timings.measurements[.deep]?.firstContent)
            XCTAssertEqual(timings.measurements[.deep]?.outcome, fail ? .failed : .completed)
        }
    }

    func testOldResponseCannotOverwriteReplacementOrRepopulateReset() async throws {
        let timings = ResponseTimings()
        let held = MetricsHeld()
        let old = timings.instrument(held, role: .listener)
        let oldTask = Task { for try await _ in old.stream(.init(system: "", messages: [])) {} }
        for _ in 0..<1_000 where timings.measurements[.listener] == nil { await Task.yield() }
        let replacement = timings.instrument(MetricsEmpty(fail: false), role: .listener)
        for try await _ in replacement.stream(.init(system: "", messages: [])) {}
        let expected = timings.measurements[.listener]
        oldTask.cancel()
        _ = try? await oldTask.value
        XCTAssertEqual(timings.measurements[.listener], expected)
        timings.clear(.listener)
        XCTAssertNil(timings.measurements[.listener])
        let another = timings.instrument(MetricsHeld(), role: .quick)
        let resetTask = Task { for try await _ in another.stream(.init(system: "", messages: [])) {} }
        for _ in 0..<1_000 where timings.measurements[.quick] == nil { await Task.yield() }
        timings.reset(); resetTask.cancel(); _ = try? await resetTask.value
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(timings.measurements.isEmpty)
    }

    func testCancellationIsNotCompletedAndCaptureMeterUsesPCM() async throws {
        let timings = ResponseTimings()
        let provider = timings.instrument(MetricsHeld(), role: .quick)
        let task = Task { for try await _ in provider.stream(.init(system: "", messages: [])) {} }
        for _ in 0..<1_000 where timings.measurements[.quick] == nil { await Task.yield() }
        task.cancel(); _ = try? await task.value
        for _ in 0..<1_000 where timings.measurements[.quick]?.outcome != .cancelled { await Task.yield() }
        XCTAssertEqual(timings.measurements[.quick]?.outcome, .cancelled)
        let capture = MockCapture()
        let session = MeetingSession(store: ConversationStore(), context: ContextEngine(debounce: 0),
            makeCapture: { capture }, makeTranscriber: { MockTranscriber() },
            makeProvider: { _ in MockLLMProvider(id: "test", deltas: []) }, models: [:])
        try await session.start()
        capture.emit(.init(samples: [1, -1], sampleRate: 16_000, source: .others, timestamp: 0))
        for _ in 0..<1_000 where session.audioLevels.sample(for: .others, now: ProcessInfo.processInfo.systemUptime) == nil {
            await Task.yield()
        }
        XCTAssertEqual(session.audioLevels.sample(for: .others, now: ProcessInfo.processInfo.systemUptime)?.fraction, 1)
        XCTAssertFalse(session.captureUnavailable(.others))
        capture.emitStatus(.init(source: .others, message: "Failed", severity: .degraded))
        for _ in 0..<1_000 where !session.captureUnavailable(.others) { await Task.yield() }
        XCTAssertTrue(session.captureUnavailable(.others))
        await session.stopAndWait()
    }
}

private final class MetricsClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time = 100.0
    func next() -> Double { lock.withLock { defer { time += 0.25 }; return time } }
}
private struct MetricsEvents: LLMProvider {
    let id = "events"
    let maxPromptCharacters: Int? = 99
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> { AsyncThrowingStream { $0.finish() } }
    func streamEvents(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { stream in
            stream.yield(.thinking("Thinking")); stream.yield(.content("")); stream.yield(.content("Answer"))
            stream.yield(.outputLimitReached); stream.finish()
        }
    }
}
private struct MetricsEmpty: LLMProvider {
    let id = "empty"
    let fail: Bool
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { stream in
            if fail { stream.finish(throwing: CocoaError(.fileReadUnknown)) } else { stream.finish() }
        }
    }
}
private struct MetricsHeld: LLMProvider {
    let id = "held"
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> { AsyncThrowingStream { _ in } }
}
