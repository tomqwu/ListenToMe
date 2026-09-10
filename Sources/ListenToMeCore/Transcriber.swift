import Foundation

/// Converts audio chunks into transcript segments. Real impl lives in the app target.
public protocol Transcribing: Sendable {
    var statusUpdates: AsyncStream<String> { get }
    var segments: AsyncStream<TranscriptSegment> { get }
    func feed(_ chunk: AudioChunk) async
    func finish() async
}

public extension Transcribing {
    var statusUpdates: AsyncStream<String> { AsyncStream { $0.finish() } }
}
