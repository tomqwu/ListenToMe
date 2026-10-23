import Foundation
import ListenToMeCore
import WatchConnectivity

/// Where `MobileSession` publishes its recorder status for the Apple Watch (issue #181).
@MainActor
protocol WatchLinking: AnyObject {
    func publish(_ status: PhoneRecorderStatus)
}

/// The iPhone side of WatchConnectivity. It answers watch commands and publishes the recorder status
/// as the application context. Only property-list status crosses; no transcript text.
///
/// Created in `ListenToMeIOSApp.init`, before any scene exists, so a message that launches the app in
/// the background is still answered — with `openPhoneApp` until a session is attached.
@MainActor
final class PhoneWatchLink: NSObject, WCSessionDelegate, WatchLinking {
    /// Set once the scene's session is attached. `nil` means every command answers `openPhoneApp`.
    var commandHandler: (@MainActor (WatchCommand) async -> WatchReply)?
    /// Called on the main actor after a chunk or end marker was filed, so a foreground app can drain.
    var onInboxChanged: (@MainActor () -> Void)?
    private let session: WCSession
    /// Where delivered audio is filed, on the delegate queue, before the delivery call returns.
    nonisolated let inbox: WatchInbox
    private var lastStatus: PhoneRecorderStatus?

    private init(session: WCSession, inbox: WatchInbox) {
        self.session = session
        self.inbox = inbox
        super.init()
    }

    /// `nil` where WatchConnectivity is unavailable, such as on iPad.
    static func activateIfSupported(inbox: WatchInbox) -> PhoneWatchLink? {
        guard WCSession.isSupported() else { return nil }
        let link = PhoneWatchLink(session: .default, inbox: inbox)
        link.session.delegate = link
        link.session.activate()
        return link
    }

    func publish(_ status: PhoneRecorderStatus) {
        lastStatus = status
        sendLastStatus()
    }

    /// Skipped before activation and when no watch app is installed; activation and a later watch
    /// install republish the last status.
    private func sendLastStatus() {
        guard let lastStatus, session.activationState == .activated, session.isPaired,
              session.isWatchAppInstalled else { return }
        try? session.updateApplicationContext(WatchLink.context(for: lastStatus))
    }

    /// The testable core of the message handler.
    static func replyMessage(to message: [String: Any],
                             handler: (@MainActor (WatchCommand) async -> WatchReply)?) async -> [String: Any] {
        let reply: WatchReply
        do {
            let command = try WatchLink.command(from: message)
            reply = await handler?(command) ?? .openPhoneApp
        } catch {
            // A version error, or an unknown command at this version: the two builds disagree.
            reply = .unsupportedVersion
        }
        return WatchLink.message(for: reply)
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {
        Task { @MainActor in self.sendLastStatus() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// The user switched to another watch: activate again for the new one.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.sendLastStatus() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        let exchange = MessageExchange(message: message, reply: replyHandler)
        Task { @MainActor in
            exchange.reply(await Self.replyMessage(to: exchange.message, handler: self.commandHandler))
        }
    }

    /// Files the chunk synchronously (the system deletes the file when this returns), then lets a
    /// foreground app know. Never starts audio or transcription: this may run in the background.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        _ = inbox.accept(fileAt: file.fileURL, metadata: file.metadata ?? [:], now: Date())
        Task { @MainActor in self.onInboxChanged?() }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        inbox.acceptEnd(userInfo: userInfo, now: Date())
        Task { @MainActor in self.onInboxChanged?() }
    }
}

/// A received message and its reply handler. WatchConnectivity hands both over on its own queue and
/// neither is `Sendable`; the dictionary holds property-list values only and the handler is called once.
private struct MessageExchange: @unchecked Sendable {
    let message: [String: Any]
    let reply: ([String: Any]) -> Void
}
