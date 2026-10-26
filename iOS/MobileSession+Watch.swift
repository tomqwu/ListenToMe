import Foundation
import ListenToMeCore

/// The Apple Watch remote (issue #181): Start, Stop and Status from the watch, and the status the
/// watch shows. The phone never starts its microphone unless the app is active in the foreground.
extension MobileSession {
    var phoneRecorderStatus: PhoneRecorderStatus {
        PhoneRecorderStatus(state: Self.phoneState(state), startedAt: recordingStartedAt, title: title,
                            lastStopReason: stopReason.map(Self.phoneStopReason),
                            recordingReady: recordingAvailability.canRun && isForeground && applicationIsActive() && !isSummarizing,
                            recordingUnavailableReason: !isForeground || !applicationIsActive()
                                ? "Open ListenToMe on your iPhone to record"
                                : (isSummarizing ? "Generating a summary on iPhone" : recordingAvailability.reason))
    }

    func handleWatchCommand(_ command: WatchCommand) async -> WatchReply {
        // Decided from UIApplication, not `isForeground`: a watch message can launch the app in the
        // background, before any scene reports a phase.
        switch RemoteRecorderPolicy.decide(command, state: Self.phoneState(state), isActive: applicationIsActive(),
                                           isSummarizing: isSummarizing) {
        case .start:
            await refreshRecordingSupport()
            // Capability metadata can suspend; recheck foreground, state and busy status afterward.
            guard applicationIsActive(), isForeground else { return .openPhoneApp }
            guard state == .idle else { return .accepted(phoneRecorderStatus) }
            guard !isSummarizing else { return .busy("Generating a summary on iPhone") }
            guard recordingAvailability.canRun else {
                return .busy(recordingAvailability.reason ?? "Check recording settings on iPhone")
            }
            start()
        case .stop:
            // Answered at once: finalizing a long transcript can outlast the watch's reply timeout.
            // The idle status follows as the application context.
            Task { await self.stop() }
            var stopping = phoneRecorderStatus
            stopping.state = .stopping
            return .accepted(stopping)
        case .report: break
        case .reply(let reply): return reply
        }
        return .accepted(phoneRecorderStatus)
    }

    func publishWatchStatus() {
        watchLink?.publish(phoneRecorderStatus)
    }

    /// The watch's status as its application context. Only shown ("Apple Watch is recording · …"):
    /// it never starts audio or transcription here. A context from another protocol version, or one
    /// without a watch status, changes nothing.
    func receiveWatchContext(_ context: [String: Any]) {
        guard let status = WatchLink.watchStatus(fromContext: context), status != watchCaptureStatus else { return }
        watchCaptureStatus = status
    }

    private static func phoneState(_ state: State) -> PhoneRecorderState {
        switch state {
        case .idle: .idle
        case .preparing: .preparing
        case .recording: .recording
        case .stopping: .stopping
        }
    }

    private static func phoneStopReason(_ reason: StopReason) -> PhoneStopReason {
        switch reason {
        case .user: .user
        case .interruption: .interruption
        case .routeLost: .routeLost
        case .background: .background
        }
    }
}
