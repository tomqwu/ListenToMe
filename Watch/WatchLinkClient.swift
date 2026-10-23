import Foundation
import Observation
import WatchConnectivity

/// The watch side of WatchConnectivity (issue #181). Commands go only as live messages to the paired
/// iPhone: a command is never queued, so a stale Start can never fire later. The watch makes no
/// network request of its own.
@MainActor @Observable
final class WatchLinkClient: NSObject, WCSessionDelegate {
    /// The newest status the phone has sent, by the phone's own stamp.
    private(set) var tracker = PhoneStatusTracker()
    var phoneStatus: PhoneRecorderStatus? { tracker.status }
    private(set) var isReachable = false
    private(set) var lastReply: WatchReply?
    private(set) var isSending = false
    @ObservationIgnored private let session = WCSession.default

    func activate() {
        guard WCSession.isSupported(), session.activationState != .activated else { return }
        session.delegate = self
        session.activate()
    }

    func send(_ command: WatchCommand) async {
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }
        let message = WatchLink.message(for: command)
        let outcome: Result<(WatchReply, TimeInterval?), any Error> = await withCheckedContinuation { continuation in
            // @Sendable: WatchConnectivity calls these on its own queue, not the main actor.
            session.sendMessage(message, replyHandler: { @Sendable reply in
                continuation.resume(returning: .success((Self.decodeReply(reply), WatchLink.stamp(from: reply))))
            }, errorHandler: { @Sendable error in
                continuation.resume(returning: .failure(error))
            })
        }
        switch outcome {
        case .success(let (reply, stamp)):
            isReachable = true
            // A reply older than the status already shown (a late "starting" after "recording") is dropped.
            if case .accepted(let status) = reply, !tracker.apply(status, stamp: stamp) { return }
            lastReply = reply
        case .failure:
            isReachable = false
            lastReply = nil
        }
    }

    /// A reply this build cannot read means the iPhone and watch builds disagree.
    private nonisolated static func decodeReply(_ message: [String: Any]) -> WatchReply {
        (try? WatchLink.reply(from: message)) ?? .unsupportedVersion
    }

    private func apply(context status: PhoneRecorderStatus?, stamp: TimeInterval?, reachable: Bool) {
        isReachable = reachable
        guard let status, tracker.apply(status, stamp: stamp) else { return }
        lastReply = nil
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {
        // Read the last published status so the screen shows the truth as soon as it opens.
        let context = session.receivedApplicationContext
        let status = WatchLink.phoneStatus(fromContext: context), stamp = WatchLink.stamp(from: context)
        let reachable = session.isReachable
        Task { @MainActor in self.apply(context: status, stamp: stamp, reachable: reachable) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let status = WatchLink.phoneStatus(fromContext: applicationContext)
        let stamp = WatchLink.stamp(from: applicationContext)
        let reachable = session.isReachable
        Task { @MainActor in self.apply(context: status, stamp: stamp, reachable: reachable) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.isReachable = reachable }
    }
}
