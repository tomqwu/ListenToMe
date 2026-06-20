import Foundation

/// Captures audio and emits source-tagged chunks. Real impl lives in the app target.
public protocol AudioCapturing: Sendable {
    var chunks: AsyncStream<AudioChunk> { get }
    func start() async throws
    func stop()
}
