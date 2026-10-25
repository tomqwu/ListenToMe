import Foundation
import Observation

/// Owns the durable checkpoint marker and start date, independently of a platform view.
/// Factories stay lazy: an unchanged timer tick must not rebuild a long transcript.
@MainActor @Observable
public final class ConversationCheckpointCoordinator {
    public enum Outcome {
        case disabled, empty, unchanged, failed
        case saved(SessionRecord)
    }

    public private(set) var startedAt: Date?
    private var savedKey: SessionCheckpointKey?

    public init() {}

    /// Begin a fresh conversation or reopen one with its original date. No dirty marker carries
    /// across identities, even when the new conversation happens to have identical content.
    public func reset(startedAt: Date? = nil) {
        self.startedAt = startedAt
        savedKey = nil
    }

    public func checkpoint(
        allowed: Bool, hasContent: Bool, force: Bool = false, now: () -> Date = Date.init,
        makeKey: () -> SessionCheckpointKey,
        makeRecord: (Date) -> SessionRecord,
        persist: (SessionRecord) -> Bool
    ) -> Outcome {
        guard allowed else { return .disabled }
        guard hasContent else { return .empty }
        let key = makeKey()
        guard force || key != savedKey else { return .unchanged }
        let started = startedAt ?? now()
        let record = makeRecord(started)
        guard persist(record) else { return .failed }
        // Only a successful durable write acknowledges this version. Failure stays retryable and
        // cannot invent a start date; a previously persisted conversation keeps its original date.
        savedKey = key
        startedAt = started
        return .saved(record)
    }
}
