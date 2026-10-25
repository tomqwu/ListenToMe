import AVFoundation
import Foundation
import Observation
import WatchKit

/// Why a watch recording did not start.
enum WatchRecorderError: LocalizedError, Equatable {
    /// A limit from `WatchCapturePolicy`; the text says which.
    case blocked(String)
    case microphoneDenied
    case unavailable(String)

    static let microphoneDeniedText =
        "Microphone access is off. Allow ListenToMe in Settings on Apple Watch → Privacy & Security → Microphone."

    var errorDescription: String? {
        switch self {
        case .blocked(let text): text
        case .microphoneDenied: Self.microphoneDeniedText
        case .unavailable(let text): text
        }
    }
}

/// Records the Apple Watch microphone in chunks for the paired iPhone (issue #181, Slice 3).
///
/// Starts only from the user's tap with the app in the foreground (F5): the session is `.record` and
/// activated here, and the watch target's audio background mode keeps it running with the wrist
/// down. A red indicator is on screen for as long as it records. Finished chunks go to
/// `onChunkFinalized` (the outbox); nothing here touches the network.
@MainActor @Observable
final class WatchRecorder {
    enum Phase: Equatable {
        case idle
        case recording(startedAt: Date)
        /// Ended by a limit, an interruption, the audio system or a write failure. `canContinue` after an
        /// interruption or the audio system stopping capture (`WatchCapturePolicy.stopReason(for:)`).
        case stopped(reason: String?, canContinue: Bool)
    }

    static func writeFailureReason(_ detail: String) -> String {
        "Recording stopped: the audio could not be saved on Apple Watch (\(detail)). "
            + "What was recorded is being sent to iPhone."
    }

    private(set) var availability: FeatureAvailability = .temporarilyUnavailable(reason: "Checking recording support…")

    func refreshAvailability() {
        availability = WatchReadiness.local(microphoneDenied: AVAudioApplication.shared.recordPermission == .denied,
                                           battery: Self.batteryLevel(), freeBytes: Self.freeBytes())
    }

    private(set) var phase = Phase.idle {
        didSet { if phase != oldValue { onStatusChange?() } }
    }
    /// Publishes the watch's status to the iPhone, in any app state: on every phase change, and at
    /// every limit check while recording, so the phone can tell a live status from a stale one.
    @ObservationIgnored var onStatusChange: (() -> Void)?
    /// A finished chunk to send (Task 18's outbox).
    @ObservationIgnored var onChunkFinalized: ((URL, WatchChunkMetadata) -> Void)?
    /// The recording ended without a last chunk to carry `isLast` (its final chunk held no audio, or
    /// writing failed): the phone is told with a `WatchRecordingEnd` instead.
    @ObservationIgnored var onRecordingEnded: ((WatchRecordingEnd) -> Void)?
    @ObservationIgnored private let makeCapture: () -> any WatchChunkCapturing
    @ObservationIgnored private var capture: (any WatchChunkCapturing)?
    @ObservationIgnored private var recordingID: UUID?
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var nextIndex = 0
    @ObservationIgnored private var limitTask: Task<Void, Never>?
    @ObservationIgnored private var sessionObservers: [any NSObjectProtocol] = []

    /// Chunks being written. Anything still here at launch was never finished (see `WatchOutbox`).
    static var recordingRoot: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Recording", isDirectory: true)
    }

    /// Readable from the first unlock after a restart, so a transfer can go on while the watch is locked
    /// (the class Task 15 is to confirm keeps on watchOS).
    static var protection: [FileAttributeKey: Any] {
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
    }

    init(makeCapture: @escaping () -> any WatchChunkCapturing = { WatchEngineCapture() }) {
        self.makeCapture = makeCapture
        // Once, so every battery read below is current.
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        refreshAvailability()
    }

    var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    var canContinue: Bool {
        if case .stopped(_, true) = phase { return true }
        return false
    }

    /// What the iPhone is told; `waitingRecordings` comes from the outbox.
    func status(waitingRecordings: Int) -> WatchCaptureStatus {
        if case .recording(let startedAt) = phase {
            return WatchCaptureStatus(state: .recording, startedAt: startedAt, waitingRecordings: waitingRecordings,
                                      updatedAt: Date())
        }
        return WatchCaptureStatus(state: .idle, startedAt: nil, waitingRecordings: waitingRecordings,
                                  updatedAt: Date())
    }

    /// A new recording. Throws, without touching the microphone, when a limit blocks it.
    func start() async throws {
        guard !isRecording else { return }
        refreshAvailability()
        guard availability.canRun else { throw WatchRecorderError.blocked(availability.reason ?? "Recording unavailable") }
        // A new recording ends one left stopped after an interruption.
        if case .stopped = phase { stop() }
        try checkStart(elapsed: nil)
        try await requestMicrophone()
        let id = UUID(), started = Date()
        recordingID = id
        startedAt = started
        nextIndex = 0
        try beginRun(firstIndex: 0, startOffset: 0)
    }

    /// After an interruption: the same recording, continuing the index, placed at the wall-clock time
    /// since it started.
    func continueRecording() async throws {
        guard canContinue, let startedAt else { return }
        refreshAvailability()
        guard availability.canRun else { throw WatchRecorderError.blocked(availability.reason ?? "Recording unavailable") }
        guard nextIndex <= WatchChunkMetadata.maximumIndex else {
            throw WatchRecorderError.blocked("This recording has too many parts. Start a new recording.")
        }
        try checkStart(elapsed: Date().timeIntervalSince(startedAt))
        try await requestMicrophone()
        try beginRun(firstIndex: nextIndex, startOffset: Date().timeIntervalSince(startedAt))
    }

    /// Stop while recording; Done after a stop. Either way the recording is over.
    func stop() {
        if isRecording { endRun(unexpected: false) }
        phase = .idle
        removeEmptyFolder()
        recordingID = nil
        startedAt = nil
    }

    // MARK: Runs

    private func beginRun(firstIndex: Int, startOffset: TimeInterval) throws {
        guard let recordingID, let startedAt else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
            let folder = Self.recordingRoot.appendingPathComponent(recordingID.uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                    attributes: Self.protection)
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
            let run = WatchCaptureRun(recordingID: recordingID, startedAt: startedAt, firstIndex: firstIndex,
                                      startOffset: startOffset, folder: folder, watchBuild: build)
            let capture = makeCapture()
            try capture.start(run, onChunk: { [weak self] chunk in
                self?.onChunkFinalized?(chunk.url, chunk.metadata)
            }, onFailure: { [weak self] detail in
                self?.endWithReason(Self.writeFailureReason(detail), canContinue: false, unexpected: true)
            }, onAudioEvent: { [weak self] event in
                self?.handle(event)
            })
            self.capture = capture
        } catch {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw WatchRecorderError.unavailable("Could not start recording: \(error.localizedDescription)")
        }
        phase = .recording(startedAt: startedAt)
        observeAudioSession()
        startLimitChecks()
    }

    /// Ends the run and hands over its last chunk (marked `isLast`), or tells the phone where the
    /// recording ended when there is none.
    private func endRun(unexpected: Bool) {
        limitTask?.cancel()
        limitTask = nil
        removeSessionObservers()
        guard let capture, let recordingID, let startedAt else { return }
        self.capture = nil
        let ending = capture.stop()
        if let last = ending.last { onChunkFinalized?(last.url, last.metadata) }
        if let lastIndex = ending.lastIndex {
            nextIndex = lastIndex + 1
            if ending.last == nil || unexpected {
                onRecordingEnded?(WatchRecordingEnd(recordingID: recordingID, startedAt: startedAt,
                                                    lastIndex: lastIndex, unexpected: unexpected))
            }
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// A stop the user did not ask for: a limit, a failed write, or the audio system. The reason is on
    /// screen, and the wrist feels it (played here, so it happens with the wrist down too).
    private func endWithReason(_ reason: String, canContinue: Bool, unexpected: Bool) {
        guard isRecording else { return }
        endRun(unexpected: unexpected)
        phase = .stopped(reason: reason, canContinue: canContinue)
        if !canContinue { removeEmptyFolder() }
        WKInterfaceDevice.current().play(canContinue ? .stop : .failure)
    }

    /// An audio-system event while recording; one that stopped capture ends the run with Continue.
    private func handle(_ event: WatchAudioEvent) {
        guard let reason = WatchCapturePolicy.stopReason(for: event) else { return }
        endWithReason(reason, canContinue: true, unexpected: false)
    }

    private func removeEmptyFolder() {
        guard let recordingID else { return }
        let folder = Self.recordingRoot.appendingPathComponent(recordingID.uuidString, isDirectory: true)
        if (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    // MARK: Limits

    private func checkStart(elapsed: TimeInterval?) throws {
        let battery = Self.batteryLevel()
        if let block = WatchCapturePolicy.startBlock(battery: battery, freeBytes: Self.freeBytes()) {
            throw WatchRecorderError.blocked(WatchCapturePolicy.text(for: block))
        }
        if let elapsed, let trigger = WatchCapturePolicy.stopTrigger(battery: battery, elapsed: elapsed) {
            throw WatchRecorderError.blocked(WatchCapturePolicy.text(for: trigger))
        }
    }

    /// Checks the stop limits at most every `limitCheckInterval`, and exactly at the duration cap. Each
    /// check also catches an engine that stopped with no notification, and refreshes the status the
    /// iPhone shows.
    private func startLimitChecks() {
        limitTask?.cancel()
        limitTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let startedAt = self.startedAt, self.isRecording else { return }
                let elapsed = Date().timeIntervalSince(startedAt)
                if let trigger = WatchCapturePolicy.stopTrigger(battery: Self.batteryLevel(), elapsed: elapsed) {
                    self.endWithReason(WatchCapturePolicy.text(for: trigger), canContinue: false, unexpected: false)
                    return
                }
                if self.capture?.isRunning == false {
                    self.handle(.captureStopped)
                    return
                }
                self.onStatusChange?()
                let untilCap = WatchCapturePolicy.maximumDuration - elapsed
                let delay = max(1, min(WatchCapturePolicy.limitCheckInterval, untilCap))
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            }
        }
    }

    /// 0...1, or -1 when unknown; an unknown level never blocks or stops a recording.
    private static func batteryLevel() -> Float {
        WKInterfaceDevice.current().batteryLevel
    }

    /// `nil` when it cannot be read; unreadable free space never blocks a recording.
    private static func freeBytes() -> Int64? {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        guard let capacity = try? home.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity
        else { return nil }
        return Int64(capacity)
    }

    // MARK: Microphone and interruptions

    private func requestMicrophone() async throws {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return
        case .denied: throw WatchRecorderError.microphoneDenied
        default:
            guard await AVAudioApplication.requestRecordPermission() else { throw WatchRecorderError.microphoneDenied }
        }
    }

    /// A call or Siri, a media-services reset, or a route change that leaves no input ends the run;
    /// per F5 capture cannot resume by itself, so the user taps Continue. Which event stops capture is
    /// decided in Core (`WatchCapturePolicy.stopReason(for:)`); the engine's own configuration change
    /// comes from the capture.
    private func observeAudioSession() {
        removeSessionObservers()
        let session = AVAudioSession.sharedInstance()
        let center = NotificationCenter.default
        func observe(_ name: Notification.Name,
                     _ event: @escaping @Sendable (Notification) -> WatchAudioEvent?) -> any NSObjectProtocol {
            center.addObserver(forName: name, object: session, queue: .main) { [weak self] note in
                guard let event = event(note) else { return }
                Task { @MainActor in self?.handle(event) }
            }
        }
        sessionObservers = [
            observe(AVAudioSession.interruptionNotification) { note in
                let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                switch raw.flatMap(AVAudioSession.InterruptionType.init) {
                case .began: return .interruptionBegan
                case .ended: return .interruptionEnded
                default: return nil
                }
            },
            observe(AVAudioSession.mediaServicesWereResetNotification) { _ in .mediaServicesReset },
            observe(AVAudioSession.routeChangeNotification) { _ in
                .routeChanged(inputAvailable: AVAudioSession.sharedInstance().isInputAvailable)
            },
        ]
    }

    private func removeSessionObservers() {
        for observer in sessionObservers { NotificationCenter.default.removeObserver(observer) }
        sessionObservers = []
    }
}
