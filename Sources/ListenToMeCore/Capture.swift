import Foundation

/// Captures audio and emits source-tagged chunks. Real impl lives in the app target.
public protocol AudioCapturing: Sendable {
    var statusUpdates: AsyncStream<CaptureStatus> { get }
    var chunks: AsyncStream<AudioChunk> { get }
    func start() async throws
    func stop()
}

public struct CaptureStatus: Sendable {
    /// How loudly the UI must show this status. `.degraded` means the channel is no longer
    /// capturing (a dead mic after an input change, a stopped system-audio stream) and the user
    /// must see it — a grey caption under a rail that still says Recording is not enough.
    public enum Severity: Sendable, Equatable { case normal, degraded }

    public let source: SpeakerSource
    public let message: String
    public let severity: Severity

    public init(source: SpeakerSource, message: String, severity: Severity = .normal) {
        self.source = source
        self.message = message
        self.severity = severity
    }
}

public extension AudioCapturing {
    var statusUpdates: AsyncStream<CaptureStatus> { AsyncStream { $0.finish() } }
}
