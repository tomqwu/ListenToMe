import Foundation

// Apple Watch recording limits and transfer rules (issue #181, decision 5). The watch target compiles
// this file directly, so it imports only Foundation; the watch has no test target, so every decision
// it makes about limits, rotation and retries lives here, where `swift test` covers it.

public enum WatchCapturePolicy {
    /// A new chunk starts every five minutes: a crash or a dead battery loses at most one chunk.
    public static let chunkDuration: TimeInterval = 300
    /// The hard cap per recording: 3 hours.
    public static let maximumDuration: TimeInterval = 10_800
    public static let minimumStartBattery: Float = 0.20
    public static let stopBattery: Float = 0.10
    public static let minimumFreeBytes: Int64 = 200_000_000
    /// How often the recorder checks `stopTrigger` while recording.
    public static let limitCheckInterval: TimeInterval = 30
    static let firstRetryDelay: TimeInterval = 30
    static let maximumRetryDelay: TimeInterval = 1_800

    /// Why a recording cannot start.
    public enum StartBlock: Equatable, Sendable { case lowBattery, lowStorage }
    /// Why a recording stopped by itself.
    public enum StopTrigger: Equatable, Sendable { case lowBattery, durationCap }

    /// `battery` is `WKInterfaceDevice.batteryLevel` (0...1, or -1 when unknown); `freeBytes` is `nil`
    /// when free space cannot be read. An unknown value never blocks a start by itself.
    public static func startBlock(battery: Float, freeBytes: Int64?) -> StartBlock? {
        if battery >= 0, battery < minimumStartBattery { return .lowBattery }
        if let freeBytes, freeBytes < minimumFreeBytes { return .lowStorage }
        return nil
    }

    /// `elapsed` is the wall-clock time since the recording started. An unknown battery level (-1)
    /// never stops a recording by itself.
    public static func stopTrigger(battery: Float, elapsed: TimeInterval) -> StopTrigger? {
        if elapsed >= maximumDuration { return .durationCap }
        if battery >= 0, battery <= stopBattery { return .lowBattery }
        return nil
    }

    /// The current chunk is closed and a new one opened at the next buffer boundary, so no audio is
    /// lost between them.
    public static func shouldRotate(chunkElapsed: TimeInterval) -> Bool {
        chunkElapsed >= chunkDuration
    }

    /// How long to wait before sending a chunk again after its `attempt`-th failed transfer (from 0):
    /// 30 s, doubling, at most 30 minutes.
    public static func retryDelay(attempt: Int) -> TimeInterval {
        let doublings = Double(min(max(attempt, 0), 16))
        return min(maximumRetryDelay, firstRetryDelay * pow(2, doublings))
    }

    /// The finalized chunks to send at launch: those the system is not already transferring.
    /// Paths are compared after standardizing them, in the order `finalized` lists them.
    public static func chunksToQueue(finalized: [URL], outstanding: Set<URL>) -> [URL] {
        let queued = Set(outstanding.map(pathKey))
        return finalized.filter { !queued.contains(pathKey($0)) }
    }

    public static func text(for block: StartBlock) -> String {
        switch block {
        case .lowBattery: "Charge Apple Watch above 20% to record."
        case .lowStorage: "Free up space on Apple Watch to record. 200 MB is needed."
        }
    }

    public static func text(for trigger: StopTrigger) -> String {
        switch trigger {
        case .lowBattery:
            "Recording stopped: Apple Watch battery is at 10%. What was recorded is being sent to iPhone."
        case .durationCap: "Recording stopped at the 3-hour limit. What was recorded is being sent to iPhone."
        }
    }

    private static func pathKey(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

/// Whether the watch's own microphone is recording (Slice 3).
public enum WatchCaptureState: String, Sendable {
    case idle, recording
}

/// What the watch publishes to the iPhone about its own recording: never audio or text.
public struct WatchCaptureStatus: Equatable, Sendable {
    public var state: WatchCaptureState
    public var startedAt: Date?
    /// Recordings with parts not yet delivered to the iPhone.
    public var waitingRecordings: Int

    public init(state: WatchCaptureState, startedAt: Date?, waitingRecordings: Int) {
        self.state = state
        self.startedAt = startedAt
        self.waitingRecordings = waitingRecordings
    }
}
