import Foundation
import Observation
import WatchConnectivity

/// The watch side of WatchConnectivity (issue #181). Commands go only as live messages to the paired
/// iPhone: a command is never queued, so a stale Start can never fire later. The watch makes no
/// network request of its own.
@MainActor @Observable
final class WatchLinkClient: NSObject, WCSessionDelegate {
    private(set) var phoneStatus: PhoneRecorderStatus?
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
        let outcome: Result<WatchReply, any Error> = await withCheckedContinuation { continuation in
            // @Sendable: WatchConnectivity calls these on its own queue, not the main actor.
            session.sendMessage(message, replyHandler: { @Sendable reply in
                continuation.resume(returning: .success(Self.decodeReply(reply)))
            }, errorHandler: { @Sendable error in
                continuation.resume(returning: .failure(error))
            })
        }
        switch outcome {
        case .success(let reply):
            isReachable = true
            lastReply = reply
            if case .accepted(let status) = reply { phoneStatus = status }
        case .failure:
            isReachable = false
            lastReply = nil
        }
    }

    /// A reply this build cannot read means the iPhone and watch builds disagree.
    private nonisolated static func decodeReply(_ message: [String: Any]) -> WatchReply {
        (try? WatchLink.reply(from: message)) ?? .unsupportedVersion
    }

    private func apply(context status: PhoneRecorderStatus?, reachable: Bool) {
        isReachable = reachable
        guard let status else { return }
        phoneStatus = status
        lastReply = nil
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {
        // Read the last published status so the screen shows the truth as soon as it opens.
        let status = WatchLink.phoneStatus(fromContext: session.receivedApplicationContext)
        let reachable = session.isReachable
        Task { @MainActor in self.apply(context: status, reachable: reachable) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let status = WatchLink.phoneStatus(fromContext: applicationContext)
        let reachable = session.isReachable
        Task { @MainActor in self.apply(context: status, reachable: reachable) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.isReachable = reachable }
    }

    // SPIKE ONLY (#181 Task 15): reports when a `transferFile` reached the iPhone, to time U2.
    @ObservationIgnored var onFileTransferFinished: (@MainActor (String, String?) -> Void)?

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer,
                             error: (any Error)?) {
        let name = fileTransfer.file.fileURL.lastPathComponent
        let message = error?.localizedDescription
        Task { @MainActor in self.onFileTransferFinished?(name, message) }
    }
}
