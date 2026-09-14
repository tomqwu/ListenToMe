import Foundation

/// Microphone authorization, mirrored AVFoundation-free so Core stays pure and testable.
/// The App layer maps `AVCaptureDevice.authorizationStatus(for: .audio)` onto these cases.
public enum MicrophoneAuthorization: Sendable, Equatable {
    case authorized, denied, restricted, notDetermined
}

/// Pre-flight decision table for pressing Listen (issue #110).
///
/// On macOS a denied microphone does NOT make `AVAudioEngine.start()` throw — the input node
/// simply delivers silence — so the app used to report "Mic: active" and record a meeting with no
/// "You" lines. Nothing in AVFoundation tells us that after the fact, so the authorization has to
/// be consulted BEFORE starting, and the "denied" case has to end in a message that points at
/// System Settings instead of a silent recording.
public enum CapturePreflight {
    public enum Decision: Sendable, Equatable {
        /// Authorization is in hand: start capture.
        case start
        /// Never asked: show the system prompt first, then re-decide via `decideAfterRequest`.
        case requestAccess
        /// Do not start. `canOpenSettings` is true when the user can fix this themselves in the
        /// Privacy & Security > Microphone pane.
        case blocked(message: String, canOpenSettings: Bool)
    }

    public static let deniedMessage =
        "Microphone access is off for ListenToMe, so your own voice would be recorded as silence. " +
        "Open System Settings > Privacy & Security > Microphone, turn on ListenToMe, then press Listen again."

    public static let restrictedMessage =
        "Microphone access is restricted on this Mac (device management or Screen Time), so your own " +
        "voice would be recorded as silence. Ask whoever manages this Mac to allow microphone access " +
        "for ListenToMe."

    /// Status yielded by a capture that was started anyway (a caller that skipped this pre-flight),
    /// so the rail is truthful instead of claiming "active" over silence.
    public static let noAccessStatus = CaptureStatus(source: .you, message: "no microphone access",
                                                     severity: .degraded)

    public static func decide(microphone: MicrophoneAuthorization) -> Decision {
        switch microphone {
        case .authorized: return .start
        case .notDetermined: return .requestAccess
        case .denied: return .blocked(message: deniedMessage, canOpenSettings: true)
        case .restricted: return .blocked(message: restrictedMessage, canOpenSettings: false)
        }
    }

    /// Decision for the answer to the one-time system prompt triggered by `.requestAccess`.
    public static func decideAfterRequest(granted: Bool) -> Decision {
        granted ? .start : .blocked(message: deniedMessage, canOpenSettings: true)
    }
}

/// Restart policy and status wording for a capture channel that died mid-meeting (issue #107):
/// an input-device change (AirPods connect, dock/undock, sleep/wake) stops `AVAudioEngine`, and
/// ScreenCaptureKit can stop the system-audio stream with an error. Both used to only *tell* the
/// user while the rail kept showing Recording; now both attempt one recovery and, if that fails,
/// say so with a status the UI can render as a visible (degraded) banner.
public enum CaptureRecovery {
    /// What happened to a channel.
    public enum Event: Sendable, Equatable {
        case microphoneInputChanged
        case systemAudioStopped(reason: String)
    }

    /// What the recovery attempt achieved.
    public enum Outcome: Sendable, Equatable {
        case resumed
        case failed(reason: String)
        /// The restart budget for this channel was already spent (don't loop on a dead device).
        case notAttempted
    }

    /// One restart attempt per channel, re-armed by a successful restart, so a permanently dead
    /// input can't spin the app in a restart loop while a second real device change still recovers.
    ///
    /// Two further guards: a channel that restarted successfully ignores another change within
    /// `restartFloor` seconds (flapping AirPods would otherwise re-arm the budget on every success
    /// and self-sustain a restart loop), and a torn-down capture refuses every restart so a
    /// notification that raced `stop()` can't bring the microphone back up after the user stopped.
    /// What the policy decided about a restart request — and, crucially, whether the user needs to
    /// hear about the refusal. `.suppressed` means the channel is fine (it just restarted, or the
    /// session is stopping), so it must stay silent; only `.budgetSpent` means a channel is really
    /// down after a failed recovery.
    public enum RestartDecision: Sendable, Equatable {
        case attempt
        case suppressed
        case budgetSpent
    }

    public struct Policy: Sendable {
        /// Minimum gap between a successful restart and the next attempt on the same channel.
        public static let restartFloor: TimeInterval = 0.5

        private var spent: Set<SpeakerSource> = []
        private var lastSuccess: [SpeakerSource: TimeInterval] = [:]
        private var isStopped = false

        public init() {}

        /// Marks the capture torn down; every later restart request is refused.
        public mutating func markStopped() { isStopped = true }

        /// Consumes this channel's restart budget. `.suppressed` when the capture is stopping or
        /// the last successful restart is less than `restartFloor` ago (the channel is healthy —
        /// say nothing); `.budgetSpent` when a previous attempt on this channel failed and was
        /// never re-armed (the channel is down — say so).
        public mutating func shouldAttemptRestart(
            for source: SpeakerSource,
            now: TimeInterval = Date().timeIntervalSinceReferenceDate
        ) -> RestartDecision {
            if isStopped { return .suppressed }
            if let last = lastSuccess[source], now - last < Self.restartFloor { return .suppressed }
            return spent.insert(source).inserted ? .attempt : .budgetSpent
        }

        /// Re-arms the channel after a restart actually worked, starting its floor window.
        public mutating func restartSucceeded(
            for source: SpeakerSource,
            now: TimeInterval = Date().timeIntervalSinceReferenceDate
        ) {
            spent.remove(source)
            lastSuccess[source] = now
        }
    }

    /// The status (if any) for a refused restart. Returns nil for `.suppressed` — a change arriving
    /// right after a successful restart, or while stopping, leaves a healthy channel, and a
    /// degraded status there would paint a red banner the session latches for the rest of the
    /// meeting. `.attempt` reports its own outcome via `status(for:outcome:)` instead.
    public static func status(for event: Event, refusal: RestartDecision) -> CaptureStatus? {
        guard refusal == .budgetSpent else { return nil }
        return status(for: event, outcome: .notAttempted)
    }

    /// The user-visible status for an event/outcome pair. Degraded statuses are the ones the UI
    /// must show as an alert rather than a grey caption.
    public static func status(for event: Event, outcome: Outcome) -> CaptureStatus {
        switch event {
        case .microphoneInputChanged:
            switch outcome {
            case .resumed:
                return CaptureStatus(source: .you, message: "input changed — resumed")
            case .failed(let reason):
                return CaptureStatus(source: .you,
                                     message: "input changed — mic stopped (\(reason)). Stop and restart.",
                                     severity: .degraded)
            case .notAttempted:
                return CaptureStatus(source: .you,
                                     message: "input changed — mic stopped. Stop and restart.",
                                     severity: .degraded)
            }
        case .systemAudioStopped(let reason):
            switch outcome {
            case .resumed:
                return CaptureStatus(source: .others, message: "system audio stopped — resumed")
            case .failed(let failure):
                return CaptureStatus(source: .others,
                                     message: "system audio stopped: \(reason) — restart failed " +
                                              "(\(failure)). Stop and restart.",
                                     severity: .degraded)
            case .notAttempted:
                return CaptureStatus(source: .others,
                                     message: "system audio stopped: \(reason). Stop and restart.",
                                     severity: .degraded)
            }
        }
    }
}
