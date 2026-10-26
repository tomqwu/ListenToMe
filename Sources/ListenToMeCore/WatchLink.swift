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
    public var recordingReady: Bool?
    public var recordingUnavailableReason: String?

    public init(state: PhoneRecorderState, startedAt: Date?, title: String, lastStopReason: PhoneStopReason?,
                recordingReady: Bool? = nil, recordingUnavailableReason: String? = nil) {
        self.state = state
        self.startedAt = startedAt
        self.title = title
        self.lastStopReason = lastStopReason
        self.recordingReady = recordingReady
        self.recordingUnavailableReason = recordingUnavailableReason
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
        static let stopReason = "stopReason", stamp = "at", watch = "watch", waiting = "waiting"
        static let recordingReady = "recordingReady", recordingReason = "recordingReason"
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

    /// `stamp` is when the phone built the reply (seconds since 1970); see `PhoneStatusTracker`.
    public static func message(for reply: WatchReply, stamp: TimeInterval? = nil) -> [String: Any] {
        var message: [String: Any] = [Key.version: protocolVersion]
        if let stamp { message[Key.stamp] = stamp }
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

    /// `stamp` is when the phone published the status (seconds since 1970); see `PhoneStatusTracker`.
    public static func context(for status: PhoneRecorderStatus, stamp: TimeInterval? = nil) -> [String: Any] {
        var context: [String: Any] = [Key.version: protocolVersion, Key.phone: dictionary(for: status)]
        if let stamp { context[Key.stamp] = stamp }
        return context
    }

    /// When the phone made a context or reply, or `nil` when it carries no usable stamp.
    public static func stamp(from payload: [String: Any]) -> TimeInterval? {
        guard let stamp = payload[Key.stamp] as? Double, stamp.isFinite else { return nil }
        return stamp
    }

    /// `nil` for a context from another protocol version or one that carries no phone status.
    public static func phoneStatus(fromContext context: [String: Any]) -> PhoneRecorderStatus? {
        guard context[Key.version] as? Int == protocolVersion,
              let fields = context[Key.phone] as? [String: Any] else { return nil }
        return status(from: fields)
    }

    // MARK: Watch status (the watch's application context)

    public static func context(for status: WatchCaptureStatus) -> [String: Any] {
        var fields: [String: Any] = [Key.state: status.state.rawValue, Key.waiting: status.waitingRecordings]
        if let startedAt = status.startedAt { fields[Key.startedAt] = startedAt.timeIntervalSince1970 }
        if let updatedAt = status.updatedAt { fields[Key.stamp] = updatedAt.timeIntervalSince1970 }
        return [Key.version: protocolVersion, Key.watch: fields]
    }

    /// `nil` for a context from another protocol version or one that carries no watch status.
    public static func watchStatus(fromContext context: [String: Any]) -> WatchCaptureStatus? {
        guard context[Key.version] as? Int == protocolVersion, let fields = context[Key.watch] as? [String: Any],
              let raw = fields[Key.state] as? String, let state = WatchCaptureState(rawValue: raw) else { return nil }
        return WatchCaptureStatus(state: state,
                                  startedAt: (fields[Key.startedAt] as? Double).map(Date.init(timeIntervalSince1970:)),
                                  waitingRecordings: max(0, fields[Key.waiting] as? Int ?? 0),
                                  updatedAt: (fields[Key.stamp] as? Double).map(Date.init(timeIntervalSince1970:)))
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
        if let ready = status.recordingReady { fields[Key.recordingReady] = ready }
        if let reason = status.recordingUnavailableReason { fields[Key.recordingReason] = reason }
        return fields
    }

    private static func status(from fields: [String: Any]) -> PhoneRecorderStatus? {
        guard let raw = fields[Key.state] as? String, let state = PhoneRecorderState(rawValue: raw) else { return nil }
        return PhoneRecorderStatus(state: state,
                                   startedAt: (fields[Key.startedAt] as? Double).map(Date.init(timeIntervalSince1970:)),
                                   title: fields[Key.title] as? String ?? "",
                                   lastStopReason: (fields[Key.stopReason] as? String).flatMap(PhoneStopReason.init),
                                   recordingReady: fields[Key.recordingReady] as? Bool,
                                   recordingUnavailableReason: fields[Key.recordingReason] as? String)
    }
}

/// The phone status the watch shows. Statuses reach the watch two ways, as the application context
/// and in command replies, and either can arrive late: the phone stamps each with when it was made,
/// and an older one never replaces a newer one (a late "starting" reply cannot hide "recording").
public struct PhoneStatusTracker: Equatable, Sendable {
    public private(set) var status: PhoneRecorderStatus?
    public private(set) var stamp: TimeInterval?

    public init() {}

    /// Whether something the phone made at `stamp` is no older than the status shown. Unstamped
    /// (an older phone build) counts as current.
    public func isCurrent(_ stamp: TimeInterval?) -> Bool {
        guard let stamp, let current = self.stamp else { return true }
        return stamp >= current
    }

    /// Shows `status` unless it is older than the one shown. An unstamped status is always shown.
    @discardableResult
    public mutating func apply(_ status: PhoneRecorderStatus, stamp: TimeInterval?) -> Bool {
        guard isCurrent(stamp) else { return false }
        self.status = status
        if let stamp { self.stamp = stamp }
        return true
    }
}

/// What travels with one audio chunk from the watch (Slice 2). The phone never takes a file name or
/// path from it: it stores the chunk as `<recordingID>/<index>.m4a` itself, so the type carries no
/// field that could name a file.
public struct WatchChunkMetadata: Equatable, Sendable, Codable {
    public static let maximumIndex = 999
    /// A chunk is 300 s; anything this long or longer is not one of ours.
    public static let maximumDuration: TimeInterval = 600
    public static let maximumFileBytes = 10_000_000

    public let recordingID: UUID
    public let index: Int
    /// Seconds from the start of the recording to this chunk's first sample.
    public let startOffset: TimeInterval
    public let duration: TimeInterval
    public let isLast: Bool
    public let startedAt: Date
    public let watchBuild: String

    public init(recordingID: UUID, index: Int, startOffset: TimeInterval, duration: TimeInterval, isLast: Bool,
                startedAt: Date, watchBuild: String) {
        self.recordingID = recordingID
        self.index = index
        self.startOffset = startOffset
        self.duration = duration
        self.isLast = isLast
        self.startedAt = startedAt
        self.watchBuild = watchBuild
    }

    /// The `WCSessionFileTransfer` metadata: property-list values only.
    public var transferMetadata: [String: Any] {
        [WatchWire.version: WatchLink.protocolVersion, WatchWire.recordingID: recordingID.uuidString,
         WatchWire.index: index, WatchWire.startOffset: startOffset, WatchWire.duration: duration,
         WatchWire.isLast: isLast, WatchWire.startedAt: startedAt.timeIntervalSince1970,
         WatchWire.watchBuild: watchBuild]
    }

    /// Validates every field; unknown keys are ignored.
    public init(transferMetadata metadata: [String: Any]) throws {
        try WatchWire.checkVersion(metadata)
        let recordingID = try WatchWire.uuid(metadata[WatchWire.recordingID], WatchWire.recordingID)
        let index = try WatchWire.index(metadata[WatchWire.index], WatchWire.index)
        let startOffset = try WatchWire.number(metadata[WatchWire.startOffset], WatchWire.startOffset)
        let duration = try WatchWire.number(metadata[WatchWire.duration], WatchWire.duration)
        guard startOffset >= 0 else { throw WatchLinkError.malformed("startOffset out of range") }
        guard duration > 0, duration < Self.maximumDuration else {
            throw WatchLinkError.malformed("duration out of range")
        }
        guard let isLast = metadata[WatchWire.isLast] as? Bool else { throw WatchLinkError.malformed("missing isLast") }
        guard let build = metadata[WatchWire.watchBuild] as? String else {
            throw WatchLinkError.malformed("missing watchBuild")
        }
        self.init(recordingID: recordingID, index: index, startOffset: startOffset, duration: duration, isLast: isLast,
                  startedAt: try WatchWire.date(metadata[WatchWire.startedAt]), watchBuild: build)
    }
}

/// Sent with `transferUserInfo` only when a recording ended without an `isLast` chunk, so the phone
/// knows the recording is over and which index was the last.
public struct WatchRecordingEnd: Equatable, Sendable {
    public let recordingID: UUID
    public let startedAt: Date
    public let lastIndex: Int
    /// The watch app was killed or failed mid-recording: the last few minutes may be missing.
    public let unexpected: Bool

    public init(recordingID: UUID, startedAt: Date, lastIndex: Int, unexpected: Bool) {
        self.recordingID = recordingID
        self.startedAt = startedAt
        self.lastIndex = lastIndex
        self.unexpected = unexpected
    }

    public var userInfo: [String: Any] {
        [WatchWire.version: WatchLink.protocolVersion, WatchWire.end: recordingID.uuidString,
         WatchWire.startedAt: startedAt.timeIntervalSince1970, WatchWire.lastIndex: lastIndex,
         WatchWire.unexpected: unexpected]
    }

    public init(userInfo: [String: Any]) throws {
        try WatchWire.checkVersion(userInfo)
        let recordingID = try WatchWire.uuid(userInfo[WatchWire.end], WatchWire.end)
        let lastIndex = try WatchWire.index(userInfo[WatchWire.lastIndex], WatchWire.lastIndex)
        guard let unexpected = userInfo[WatchWire.unexpected] as? Bool else {
            throw WatchLinkError.malformed("missing unexpected")
        }
        self.init(recordingID: recordingID, startedAt: try WatchWire.date(userInfo[WatchWire.startedAt]),
                  lastIndex: lastIndex, unexpected: unexpected)
    }
}

/// Keys and readers shared by the chunk metadata and the end marker.
private enum WatchWire {
    static let version = "v", recordingID = "recordingID", index = "index", startOffset = "startOffset"
    static let duration = "duration", isLast = "isLast", startedAt = "startedAt", watchBuild = "watchBuild"
    static let end = "end", lastIndex = "lastIndex", unexpected = "unexpected"

    static func checkVersion(_ fields: [String: Any]) throws {
        let found = fields[version] as? Int
        guard found == WatchLink.protocolVersion else { throw WatchLinkError.unsupportedVersion(found) }
    }

    static func uuid(_ value: Any?, _ key: String) throws -> UUID {
        guard let text = value as? String, let id = UUID(uuidString: text) else {
            throw WatchLinkError.malformed("bad \(key)")
        }
        return id
    }

    static func index(_ value: Any?, _ key: String) throws -> Int {
        guard let index = value as? Int, (0...WatchChunkMetadata.maximumIndex).contains(index) else {
            throw WatchLinkError.malformed("bad \(key)")
        }
        return index
    }

    /// A finite number, whether it arrives as a `Double` or an integer.
    static func number(_ value: Any?, _ key: String) throws -> Double {
        let number: Double?
        switch value {
        case let double as Double: number = double
        case let int as Int: number = Double(int)
        default: number = nil
        }
        guard let number, number.isFinite else { throw WatchLinkError.malformed("bad \(key)") }
        return number
    }

    static func date(_ value: Any?) throws -> Date {
        Date(timeIntervalSince1970: try number(value, startedAt))
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

    /// The line the iPhone shows while the watch records, or `nil` when it is not recording. A status
    /// not refreshed for `WatchCaptureStatus.staleAfter`, or older than the 3-hour cap (plus one limit
    /// check), is stale, as from a watch app that was killed.
    public static func watchRecordingLine(_ status: WatchCaptureStatus?, now: Date) -> String? {
        guard let status, status.state == .recording else { return nil }
        if let updatedAt = status.updatedAt, now.timeIntervalSince(updatedAt) > WatchCaptureStatus.staleAfter {
            return nil
        }
        let elapsed = status.startedAt.map { now.timeIntervalSince($0) } ?? 0
        guard elapsed <= WatchCapturePolicy.maximumDuration + WatchCapturePolicy.limitCheckInterval else { return nil }
        return "Apple Watch is recording · " + WatchLink.elapsedText(elapsed)
    }

    /// How many recordings still have parts on the watch, or `nil` when none do.
    public static func waitingText(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count == 1 ? "1 recording waiting for iPhone" : "\(count) recordings waiting for iPhone"
    }
}
