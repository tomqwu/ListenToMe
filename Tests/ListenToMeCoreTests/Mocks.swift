import Foundation
@testable import ListenToMeCore

/// Yields a fixed list of deltas, then finishes.
struct MockLLMProvider: LLMProvider {
    let id: String
    let deltas: [String]
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            for delta in deltas { continuation.yield(delta) }
            continuation.finish()
        }
    }
}

/// Provider that records the last request it streamed (and optionally declares a context window).
final class RecordingProvider: LLMProvider, @unchecked Sendable {
    let id = "recording"
    let deltas: [String]
    let maxPromptCharacters: Int?
    private let lock = NSLock()
    private var _lastRequest: LLMRequest?
    var lastRequest: LLMRequest? { lock.withLock { _lastRequest } }
    var lastUser: String? { lock.withLock { _lastRequest?.messages.last?.content } }
    init(deltas: [String], maxPromptCharacters: Int? = nil) {
        self.deltas = deltas
        self.maxPromptCharacters = maxPromptCharacters
    }
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        lock.withLock { _lastRequest = request }
        return AsyncThrowingStream { continuation in
            for delta in deltas { continuation.yield(delta) }
            continuation.finish()
        }
    }
}

/// Transcriber mock that emits one final segment per fed chunk (for file-transcription tests).
final class EchoTranscriber: Transcribing, @unchecked Sendable {
    let segments: AsyncStream<TranscriptSegment>
    private let continuation: AsyncStream<TranscriptSegment>.Continuation
    init() {
        var cont: AsyncStream<TranscriptSegment>.Continuation!
        segments = AsyncStream { cont = $0 }
        continuation = cont
    }
    func feed(_ chunk: AudioChunk) async {
        continuation.yield(TranscriptSegment(source: chunk.source, text: "seg",
                                             isFinal: true, start: chunk.timestamp, end: chunk.timestamp))
    }
    func finish() async { continuation.finish() }
}

/// Hands out a fixed array of chunks one at a time (then nil), for `transcribeAudio` tests.
final class ArrayChunkProducer: @unchecked Sendable {
    private let chunks: [AudioChunk]
    private let lock = NSLock()
    private var index = 0
    init(_ chunks: [AudioChunk]) { self.chunks = chunks }
    func next() async -> AudioChunk? {
        lock.withLock {
            guard index < chunks.count else { return nil }
            defer { index += 1 }
            return chunks[index]
        }
    }
}

/// Thread-safe ordered event log shared by mocks so tests can assert call ORDER across the
/// capture and the transcriber (e.g. `prepare` before `capture.start`).
final class OrderLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [String] = []
    func record(_ event: String) { lock.withLock { _events.append(event) } }
    var events: [String] { lock.withLock { _events } }
    func index(of event: String) -> Int? { events.firstIndex(of: event) }
}

/// Capture mock that can emit chunks on demand (for integration tests).
final class MockCapture: AudioCapturing, @unchecked Sendable {
    let chunks: AsyncStream<AudioChunk>
    private let continuation: AsyncStream<AudioChunk>.Continuation
    /// Status channel, so tests can drive the session's capture-status handling (e.g. the
    /// degraded-capture banner) exactly like the real DualChannelCapture does.
    let statusUpdates: AsyncStream<CaptureStatus>
    private let statusContinuation: AsyncStream<CaptureStatus>.Continuation
    private let log: OrderLog?
    private let lock = NSLock()
    private var _startCount = 0
    /// Number of times `start()` was called (synchronized).
    var startCount: Int { lock.withLock { _startCount } }
    init(log: OrderLog? = nil) {
        self.log = log
        var cont: AsyncStream<AudioChunk>.Continuation!
        chunks = AsyncStream { cont = $0 }
        continuation = cont
        let statuses = AsyncStream<CaptureStatus>.makeStream()
        statusUpdates = statuses.stream
        statusContinuation = statuses.continuation
    }
    func start() async throws {
        lock.withLock { _startCount += 1 }
        log?.record("capture.start")
    }
    func stop() { continuation.finish(); statusContinuation.finish() }
    /// Push a capture status (e.g. a degraded recovery status) into the session's status pump.
    func emitStatus(_ status: CaptureStatus) { statusContinuation.yield(status) }
    /// Push a chunk into the stream so the session's capture→transcriber pump can deliver it.
    func emit(_ chunk: AudioChunk) { continuation.yield(chunk) }
}

/// Transcriber mock whose `segments` stream is fed by the test via `emit`.
/// Also records every chunk delivered via `feed` for integration tests.
final class MockTranscriber: Transcribing, @unchecked Sendable {
    let segments: AsyncStream<TranscriptSegment>
    private let continuation: AsyncStream<TranscriptSegment>.Continuation
    /// `feed` runs on the session's pump task while tests read on the main actor;
    /// the lock keeps appends and snapshot reads from racing (e.g. under TSAN).
    private let lock = NSLock()
    private var _fedChunks: [AudioChunk] = []
    /// Synchronized snapshot of chunks delivered to `feed(_:)`.
    var fedChunks: [AudioChunk] {
        lock.withLock { _fedChunks }
    }
    private let log: OrderLog?
    /// When true, `prepare()`/`feed(_:)` block (like a first-run speech-model download) until
    /// `release()` is called or the surrounding Task is cancelled.
    private let slowPrepare: Bool
    /// Like `slowPrepare`, but IGNORES cancellation — stands in for a platform download call with no
    /// cancellation guarantee (e.g. `AssetInventory.downloadAndInstall()`).
    private let stubbornPrepare: Bool
    private let slowFeed: Bool
    /// Per-chunk `feed` cost, so tests can tell a *drained* capture pump from a pre-emptively
    /// cancelled one (a cancelled pump stops iterating instead of finishing the remaining chunks).
    private let feedDelayNanos: UInt64
    private var _released = false
    private var _prepareCount = 0
    private var _prepareEntered = false
    private var _prepareCancelled = false
    private var _feedEntered = false
    private var _feedCancelled = false
    /// Number of times `prepare()` was called (synchronized).
    var prepareCount: Int { lock.withLock { _prepareCount } }
    /// True once `prepare()` has started running.
    var prepareEntered: Bool { lock.withLock { _prepareEntered } }
    /// True when a blocked `prepare()` returned because its Task was cancelled.
    var prepareCancelled: Bool { lock.withLock { _prepareCancelled } }
    /// True once `feed(_:)` has started running.
    var feedEntered: Bool { lock.withLock { _feedEntered } }
    /// True when a blocked `feed(_:)` returned because its Task was cancelled.
    var feedCancelled: Bool { lock.withLock { _feedCancelled } }

    init(log: OrderLog? = nil, slowPrepare: Bool = false, stubbornPrepare: Bool = false,
         slowFeed: Bool = false, feedDelayNanos: UInt64 = 0) {
        self.log = log
        self.slowPrepare = slowPrepare
        self.stubbornPrepare = stubbornPrepare
        self.slowFeed = slowFeed
        self.feedDelayNanos = feedDelayNanos
        var cont: AsyncStream<TranscriptSegment>.Continuation!
        segments = AsyncStream { cont = $0 }
        continuation = cont
    }
    private var _finishCount = 0
    /// Number of times `finish()` has been awaited (synchronized).
    var finishCount: Int { lock.withLock { _finishCount } }
    /// Unblocks a slow `prepare()`/`feed(_:)` without cancelling it.
    func release() { lock.withLock { _released = true } }

    /// Blocks until `release()` or Task cancellation. Returns true when it was cancelled.
    private func blockUntilReleasedOrCancelled() async -> Bool {
        while !Task.isCancelled {
            if lock.withLock({ _released }) { return false }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return true
    }

    func prepare() async {
        lock.withLock { _prepareCount += 1; _prepareEntered = true }
        log?.record("transcriber.prepare")
        if stubbornPrepare {
            // Detached, so it doesn't inherit the caller's cancellation: awaiting it blocks until
            // `release()` no matter who cancels, exactly like an uncancellable platform download.
            await Task.detached { [self] in
                while !lock.withLock({ _released }) {
                    try? await Task.sleep(nanoseconds: 5_000_000)
                }
            }.value
            return
        }
        guard slowPrepare else { return }
        let cancelled = await blockUntilReleasedOrCancelled()
        lock.withLock { _prepareCancelled = cancelled }
    }

    func feed(_ chunk: AudioChunk) async {
        if feedDelayNanos > 0 { try? await Task.sleep(nanoseconds: feedDelayNanos) }
        lock.withLock { _fedChunks.append(chunk); _feedEntered = true }
        log?.record("transcriber.feed")
        guard slowFeed else { return }
        let cancelled = await blockUntilReleasedOrCancelled()
        lock.withLock { _feedCancelled = cancelled }
    }
    func finish() async {
        lock.withLock { _finishCount += 1 }
        log?.record("transcriber.finish")
        continuation.finish()
    }
    func emit(_ segment: TranscriptSegment) { continuation.yield(segment) }
}
