import Foundation

// The Apple Watch ↔ iPhone protocol (issue #181). The watch target compiles this file directly, so it
// imports only Foundation. Only property-list types cross the link, and no transcript text ever does.

/// A command the watch sends to the iPhone.
public enum WatchCommand: String, CaseIterable, Sendable {
    case start, stop, status
}

/// The iPhone recorder's state as the watch sees it.
public enum PhoneRecorderState: String, Sendable {
    case idle, preparing, recording, stopping
}

/// Why the iPhone recorder last stopped.
public enum PhoneStopReason: String, Sendable {
    case user, interruption, routeLost, background
}

/// What the iPhone publishes to the watch: enough to draw the remote, never the transcript.
public struct PhoneRecorderStatus: Equatable, Sendable {
    public var state: PhoneRecorderState
    public var startedAt: Date?
    public var title: String
    public var lastStopReason: PhoneStopReason?

    public init(state: PhoneRecorderState, startedAt: Date?, title: String, lastStopReason: PhoneStopReason?) {
        self.state = state
        self.startedAt = startedAt
        self.title = title
        self.lastStopReason = lastStopReason
    }
}

/// The iPhone's answer to a watch command.
public enum WatchReply: Equatable, Sendable {
    case accepted(PhoneRecorderStatus)
    /// The iPhone app is not in the foreground, so it will not touch the microphone.
    case openPhoneApp
    case busy(String)
    case unsupportedVersion
}

public enum WatchLinkError: Error, Equatable, Sendable {
    case unsupportedVersion(Int?)
    case malformed(String)
}

public enum WatchLink {
    /// The wire version, independent of the app's build number.
    public static let protocolVersion = 1

    private enum Key {
        static let version = "v", command = "cmd", reply = "reply", status = "status", busy = "busy"
        static let phone = "phone", state = "state", startedAt = "startedAt", title = "title"
        static let stopReason = "stopReason"
    }

    private enum ReplyKind: String {
        case accepted, openPhoneApp, busy, unsupportedVersion
    }

    // MARK: Commands

    public static func message(for command: WatchCommand) -> [String: Any] {
        [Key.version: protocolVersion, Key.command: command.rawValue]
    }

    public static func command(from message: [String: Any]) throws -> WatchCommand {
        try checkVersion(message)
        guard let raw = message[Key.command] as? String else { throw WatchLinkError.malformed("missing command") }
        guard let command = WatchCommand(rawValue: raw) else { throw WatchLinkError.malformed("unknown command") }
        return command
    }

    // MARK: Replies

    public static func message(for reply: WatchReply) -> [String: Any] {
        var message: [String: Any] = [Key.version: protocolVersion]
        switch reply {
        case .accepted(let status):
            message[Key.reply] = ReplyKind.accepted.rawValue
            message[Key.status] = dictionary(for: status)
        case .openPhoneApp:
            message[Key.reply] = ReplyKind.openPhoneApp.rawValue
        case .busy(let text):
            message[Key.reply] = ReplyKind.busy.rawValue
            message[Key.busy] = text
        case .unsupportedVersion:
            message[Key.reply] = ReplyKind.unsupportedVersion.rawValue
        }
        return message
    }

    public static func reply(from message: [String: Any]) throws -> WatchReply {
        try checkVersion(message)
        guard let raw = message[Key.reply] as? String, let kind = ReplyKind(rawValue: raw) else {
            throw WatchLinkError.malformed("unknown reply")
        }
        switch kind {
        case .accepted:
            guard let fields = message[Key.status] as? [String: Any], let status = status(from: fields) else {
                throw WatchLinkError.malformed("missing status")
            }
            return .accepted(status)
        case .openPhoneApp:
            return .openPhoneApp
        case .busy:
            guard let text = message[Key.busy] as? String else { throw WatchLinkError.malformed("missing busy text") }
            return .busy(text)
        case .unsupportedVersion:
            return .unsupportedVersion
        }
    }

    // MARK: Phone status (application context)

    public static func context(for status: PhoneRecorderStatus) -> [String: Any] {
        [Key.version: protocolVersion, Key.phone: dictionary(for: status)]
    }

    /// `nil` for a context from another protocol version or one that carries no phone status.
    public static func phoneStatus(fromContext context: [String: Any]) -> PhoneRecorderStatus? {
        guard context[Key.version] as? Int == protocolVersion,
              let fields = context[Key.phone] as? [String: Any] else { return nil }
        return status(from: fields)
    }

    // MARK: Display

    /// `mm:ss` under an hour, `h:mm:ss` from then on; negative or non-finite time reads as zero.
    public static func elapsedText(_ seconds: TimeInterval) -> String {
        let total = seconds.isFinite ? max(0, Int(min(seconds, 359_999).rounded(.down))) : 0
        let hours = total / 3_600, minutes = total % 3_600 / 60, rest = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest)
                         : String(format: "%02d:%02d", minutes, rest)
    }

    // MARK: Helpers

    private static func checkVersion(_ message: [String: Any]) throws {
        let version = message[Key.version] as? Int
        guard version == protocolVersion else { throw WatchLinkError.unsupportedVersion(version) }
    }

    private static func dictionary(for status: PhoneRecorderStatus) -> [String: Any] {
        var fields: [String: Any] = [Key.state: status.state.rawValue, Key.title: status.title]
        if let startedAt = status.startedAt { fields[Key.startedAt] = startedAt.timeIntervalSince1970 }
        if let reason = status.lastStopReason { fields[Key.stopReason] = reason.rawValue }
        return fields
    }

    private static func status(from fields: [String: Any]) -> PhoneRecorderStatus? {
        guard let raw = fields[Key.state] as? String, let state = PhoneRecorderState(rawValue: raw) else { return nil }
        return PhoneRecorderStatus(state: state,
                                   startedAt: (fields[Key.startedAt] as? Double).map(Date.init(timeIntervalSince1970:)),
                                   title: fields[Key.title] as? String ?? "",
                                   lastStopReason: (fields[Key.stopReason] as? String).flatMap(PhoneStopReason.init))
    }
}

/// The single status line the watch remote shows.
public enum WatchRemoteText {
    public static func line(status: PhoneRecorderStatus?, reachable: Bool, lastReply: WatchReply?,
                            now: Date) -> String {
        guard reachable else { return "iPhone not reachable" }
        switch lastReply {
        case .openPhoneApp: return "Open ListenToMe on your iPhone to record"
        case .unsupportedVersion: return "Update ListenToMe on your iPhone and Apple Watch"
        case .busy(let text): return text
        case .accepted, nil: break
        }
        guard let status else { return "Ready" }
        switch status.state {
        case .recording:
            let elapsed = status.startedAt.map { now.timeIntervalSince($0) } ?? 0
            return "iPhone is recording · " + WatchLink.elapsedText(elapsed)
        case .preparing: return "Starting on iPhone…"
        case .stopping: return "Stopping on iPhone"
        case .idle:
            return status.lastStopReason == .background ? "Stopped: ListenToMe left the foreground on iPhone" : "Ready"
        }
    }
}
