import Foundation

/// Captures audio and emits source-tagged chunks. Real impl lives in the app target.
public protocol AudioCapturing: Sendable {
    var statusUpdates: AsyncStream<CaptureStatus> { get }
    var chunks: AsyncStream<AudioChunk> { get }
    func start() async throws
    func stop()
}

public struct CaptureStatus: Sendable {
    public let source: SpeakerSource
    public let message: String
    public init(source: SpeakerSource, message: String) { self.source = source; self.message = message }
}

public extension AudioCapturing {
    var statusUpdates: AsyncStream<CaptureStatus> { AsyncStream { $0.finish() } }
}
