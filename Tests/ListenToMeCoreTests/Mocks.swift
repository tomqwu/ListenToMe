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

/// Provider that records the user-message content of the last request it streamed.
final class RecordingProvider: LLMProvider, @unchecked Sendable {
    let id = "recording"
    let deltas: [String]
    private let lock = NSLock()
    private var _lastUser: String?
    var lastUser: String? { lock.withLock { _lastUser } }
    init(deltas: [String]) { self.deltas = deltas }
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        lock.withLock { _lastUser = request.messages.last?.content }
        return AsyncThrowingStream { continuation in
            for delta in deltas { continuation.yield(delta) }
            continuation.finish()
        }
    }
}

/// Capture mock that can emit chunks on demand (for integration tests).
final class MockCapture: AudioCapturing, @unchecked Sendable {
    let chunks: AsyncStream<AudioChunk>
    private let continuation: AsyncStream<AudioChunk>.Continuation
    init() {
        var cont: AsyncStream<AudioChunk>.Continuation!
        chunks = AsyncStream { cont = $0 }
        continuation = cont
    }
    func start() async throws {}
    func stop() { continuation.finish() }
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
    init() {
        var cont: AsyncStream<TranscriptSegment>.Continuation!
        segments = AsyncStream { cont = $0 }
        continuation = cont
    }
    private var _finishCount = 0
    /// Number of times `finish()` has been awaited (synchronized).
    var finishCount: Int { lock.withLock { _finishCount } }
    func feed(_ chunk: AudioChunk) async {
        lock.withLock { _fedChunks.append(chunk) }
    }
    func finish() async {
        lock.withLock { _finishCount += 1 }
        continuation.finish()
    }
    func emit(_ segment: TranscriptSegment) { continuation.yield(segment) }
}
