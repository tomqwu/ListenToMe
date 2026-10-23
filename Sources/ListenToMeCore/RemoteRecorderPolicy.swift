import Foundation

/// What the iPhone does with a command from the Apple Watch remote (issue #181).
public enum RemoteRecorderDecision: Equatable, Sendable {
    /// Start the iPhone recorder.
    case start
    /// Stop the iPhone recorder.
    case stop
    /// Change nothing; answer with the current status.
    case report
    /// Change nothing; answer with this reply.
    case reply(WatchReply)
}

public enum RemoteRecorderPolicy {
    /// A watch Start never reaches the microphone unless the iPhone app is active in the foreground:
    /// a WatchConnectivity message can wake the app in the background, before any scene exists.
    public static func decide(_ command: WatchCommand, state: PhoneRecorderState, isActive: Bool,
                              isSummarizing: Bool) -> RemoteRecorderDecision {
        switch (command, state) {
        case (.start, _) where !isActive:
            return .reply(.openPhoneApp)
        case (.start, .idle):
            return isSummarizing ? .reply(.busy("Generating a summary on iPhone")) : .start
        case (.start, .stopping):
            return .reply(.busy("Stopping on iPhone"))
        case (.start, .preparing), (.start, .recording):
            return .report
        case (.stop, .preparing), (.stop, .recording):
            return .stop
        case (.stop, .idle), (.stop, .stopping), (.status, _):
            return .report
        }
    }
}
