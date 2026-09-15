import Foundation

/// What a recognition-task callback reported.
public enum RecognitionTaskEvent: Sendable, Equatable {
    case partial
    case final
    case failure
}

/// What the owner of the callback may do with it.
public enum RecognitionTaskAction: Sendable, Equatable {
    /// The callback belongs to a superseded (or already finalized) task — do nothing at all.
    case ignore
    case deliverPartial
    case deliverFinal
    case reportFailure
}

/// Pure task-identity rule for per-source speech recognition (issue #108).
///
/// `SFSpeechRecognizer` callbacks carry no task identity, and after a final result the Speech
/// framework commonly delivers a trailing cancellation/no-speech error for the task that just
/// finished. Keying callbacks only by `SpeakerSource` therefore let a dead task's error tear down
/// the state of the task that had already replaced it — dropping its request and its replayed
/// onset audio, and letting a late partial overwrite the new task's text.
///
/// Every task is installed with a token; only callbacks carrying the source's current token may
/// act, and only until that task's own final result. The Transcriber keeps this router as the single
/// source of truth for "is this callback still relevant?", so the rule is unit-testable without the
/// Speech framework.
public struct RecognitionTaskRouter: Sendable {
    /// `live` = the task may deliver results; `finalizing` = its final result arrived and the
    /// replacement task has not been installed yet (so nothing else from it may act, but the
    /// restart it triggered is still allowed to run).
    private enum Phase: Sendable, Equatable { case live, finalizing }

    private struct Entry: Sendable { let token: UUID; var phase: Phase }

    private var entries: [SpeakerSource: Entry] = [:]

    public init() {}

    /// Registers a freshly created task for `source` and returns its token (to be captured by the
    /// task's callback closure). Any previously installed task for that source is superseded.
    @discardableResult
    public mutating func install(for source: SpeakerSource, token: UUID = UUID()) -> UUID {
        entries[source] = Entry(token: token, phase: .live)
        return token
    }

    /// The token of the task currently owning `source`, if any.
    public func current(for source: SpeakerSource) -> UUID? { entries[source]?.token }

    /// Decides what a callback carrying `token` may do, and records the resulting transition: a
    /// final result moves the task to `finalizing` (it may no longer deliver or fail), and a failure
    /// retires it outright so the next chunk lazily creates a fresh task.
    public mutating func action(for event: RecognitionTaskEvent,
                                token: UUID,
                                source: SpeakerSource) -> RecognitionTaskAction {
        guard let entry = entries[source], entry.token == token, entry.phase == .live else {
            return .ignore
        }
        switch event {
        case .partial:
            return .deliverPartial
        case .final:
            entries[source]?.phase = .finalizing
            return .deliverFinal
        case .failure:
            entries[source] = nil
            return .reportFailure
        }
    }

    /// Whether the task identified by `token` is the one whose final result is still awaiting its
    /// replacement — i.e. whether it may start the next task for `source`.
    public func mayRestart(token: UUID, for source: SpeakerSource) -> Bool {
        guard let entry = entries[source] else { return false }
        return entry.token == token && entry.phase == .finalizing
    }

    /// Retires `token` if it still owns `source` (a no-op for a superseded token).
    public mutating func retire(token: UUID, for source: SpeakerSource) {
        if entries[source]?.token == token { entries[source] = nil }
    }

    /// Forgets every source (used when the transcriber shuts down).
    public mutating func removeAll() { entries.removeAll() }
}
