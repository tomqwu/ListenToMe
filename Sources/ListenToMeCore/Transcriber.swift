import Foundation

/// Converts audio chunks into transcript segments. Real impl lives in the app target.
public protocol Transcribing: Sendable {
    var segments: AsyncStream<TranscriptSegment> { get }
    func feed(_ chunk: AudioChunk) async
    func finish() async
}
