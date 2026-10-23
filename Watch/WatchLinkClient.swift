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
    /// Recorded chunks waiting for the iPhone (Slice 3).
    @ObservationIgnored var outbox: WatchOutbox?
    /// The watch's own recording status, sent again once the session is active.
    @ObservationIgnored private var captureStatus: WatchCaptureStatus?

    /// Tells the iPhone whether this watch is recording (application context: the latest wins).
    func publish(_ status: WatchCaptureStatus) {
        captureStatus = status
        sendCaptureStatus()
    }

    private func sendCaptureStatus() {
        guard let captureStatus, session.activationState == .activated else { return }
        try? session.updateApplicationContext(WatchLink.context(for: captureStatus))
    }

    /// Called from the app's `init`, so the session is active for background transfers and their
    /// `didFinish` before any screen appears (and when the system wakes the app for them).
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
            // Any reply older than the status already shown (a late "starting" after "recording", or a
            // late "busy" after the summary ended) is dropped.
            guard tracker.isCurrent(stamp) else { return }
            if case .accepted(let status) = reply { tracker.apply(status, stamp: stamp) }
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
        let outstanding = OutstandingTransfers(transfers: session.outstandingFileTransfers)
        Task { @MainActor in
            self.apply(context: status, stamp: stamp, reachable: reachable)
            // Chunks left from an earlier launch, or finished before activation, are sent now.
            if activationState == .activated { self.outbox?.reconcileAtLaunch(outstanding: outstanding.transfers) }
            self.sendCaptureStatus()
        }
    }

    /// A chunk transfer ended. Its audio is deleted only on success; see `WatchOutbox`.
    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer,
                             error: (any Error)?) {
        let url = fileTransfer.file.fileURL
        Task { @MainActor in self.outbox?.transferFinished(fileURL: url, error: error) }
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

/// The outstanding transfers handed from the WatchConnectivity queue to the main actor. They are
/// only read there, after activation, to tell which chunks the system is already sending.
private struct OutstandingTransfers: @unchecked Sendable {
    let transfers: [WCSessionFileTransfer]
}
