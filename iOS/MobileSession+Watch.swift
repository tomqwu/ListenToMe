import Foundation
import ListenToMeCore

/// The Apple Watch remote (issue #181): Start, Stop and Status from the watch, and the status the
/// watch shows. The phone never starts its microphone unless the app is active in the foreground.
extension MobileSession {
    var phoneRecorderStatus: PhoneRecorderStatus {
        PhoneRecorderStatus(state: Self.phoneState(state), startedAt: recordingStartedAt, title: title,
                            lastStopReason: stopReason.map(Self.phoneStopReason))
    }

    func handleWatchCommand(_ command: WatchCommand) async -> WatchReply {
        // Decided from UIApplication, not `isForeground`: a watch message can launch the app in the
        // background, before any scene reports a phase.
        switch RemoteRecorderPolicy.decide(command, state: Self.phoneState(state), isActive: applicationIsActive(),
                                           isSummarizing: isSummarizing) {
        case .start: start()
        case .stop: await stop()
        case .report: break
        case .reply(let reply): return reply
        }
        return .accepted(phoneRecorderStatus)
    }

    func publishWatchStatus() {
        watchLink?.publish(phoneRecorderStatus)
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
