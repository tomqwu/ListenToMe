import Foundation

/// Capture and recognition use the same run-relative monotonic timeline. Delivery latency is not
/// speech latency: a valid old host timestamp must not be replaced by the callback's arrival time.
public enum CaptureTimeline {
    public static func timestamp(capturedAt: TimeInterval?, runStart: TimeInterval,
                                 deliveredAt: TimeInterval) -> TimeInterval {
        let delivered = max(0, deliveredAt - runStart)
        guard let capturedAt, capturedAt.isFinite, runStart.isFinite,
              capturedAt >= runStart, capturedAt <= deliveredAt + 0.1 else { return delivered.isFinite ? delivered : 0 }
        return capturedAt - runStart
    }

    /// Unknown/invalid recognition ranges stay untimed; never infer them from the last fed buffer.
    public static func range(start: TimeInterval, end: TimeInterval) -> (start: TimeInterval, end: TimeInterval) {
        guard start.isFinite, end.isFinite, start >= 0, end > start else { return (0, 0) }
        return (start, end)
    }
}
