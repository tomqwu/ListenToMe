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

/// Capture mock that never emits on its own (the session test drives the transcriber directly).
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
}

/// Transcriber mock whose `segments` stream is fed by the test via `emit`.
final class MockTranscriber: Transcribing, @unchecked Sendable {
    let segments: AsyncStream<TranscriptSegment>
    private let continuation: AsyncStream<TranscriptSegment>.Continuation
    init() {
        var cont: AsyncStream<TranscriptSegment>.Continuation!
        segments = AsyncStream { cont = $0 }
        continuation = cont
    }
    func feed(_ chunk: AudioChunk) async {}
    func finish() async { continuation.finish() }
    func emit(_ segment: TranscriptSegment) { continuation.yield(segment) }
}
