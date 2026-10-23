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
    private let session: WCSession
    private var lastStatus: PhoneRecorderStatus?

    private init(session: WCSession) {
        self.session = session
        super.init()
    }

    /// `nil` where WatchConnectivity is unavailable, such as on iPad.
    static func activateIfSupported() -> PhoneWatchLink? {
        guard WCSession.isSupported() else { return nil }
        let link = PhoneWatchLink(session: .default)
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

    /// SPIKE ONLY (#181 Task 15, branch spike/181-watch-audio, never merged). Logs the receipt time
    /// and size of a watch chunk and keeps a copy in `Documents/WatchSpike/`, with one CSV row per
    /// file in `Documents/WatchSpike/receipts.csv`. The file must be moved before this returns.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let receivedAt = Date()
        let manager = FileManager.default
        let folder = manager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WatchSpike", isDirectory: true)
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = file.metadata?["name"] as? String ?? file.fileURL.lastPathComponent
        let bytes = ((try? manager.attributesOfItem(atPath: file.fileURL.path))?[.size] as? NSNumber)?.int64Value ?? -1
        let destination = folder.appendingPathComponent(name)
        try? manager.removeItem(at: destination)
        try? manager.copyItem(at: file.fileURL, to: destination)
        let sentAt = (file.metadata?["sentAt"] as? Double).map { Date(timeIntervalSince1970: $0) }
        let delta = sentAt.map { String(format: "%.1f", receivedAt.timeIntervalSince($0)) } ?? ""
        let stamp = ISO8601DateFormatter().string(from: receivedAt)
        let row = "\(stamp),\(name),\(bytes),\(sentAt.map { ISO8601DateFormatter().string(from: $0) } ?? ""),\(delta)\n"
        NSLog("[spike181] received %@ %lld B at %@; sent-to-received %@ s (two clocks)", name, bytes, stamp, delta)
        let log = folder.appendingPathComponent("receipts.csv")
        if let handle = try? FileHandle(forWritingTo: log) {
            handle.seekToEndOfFile()
            handle.write(Data(row.utf8))
            try? handle.close()
        } else {
            try? Data(("receivedAt,name,bytes,sentAt,secondsSentToReceived\n" + row).utf8).write(to: log)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        let exchange = MessageExchange(message: message, reply: replyHandler)
        Task { @MainActor in
            exchange.reply(await Self.replyMessage(to: exchange.message, handler: self.commandHandler))
        }
    }
}

/// A received message and its reply handler. WatchConnectivity hands both over on its own queue and
/// neither is `Sendable`; the dictionary holds property-list values only and the handler is called once.
private struct MessageExchange: @unchecked Sendable {
    let message: [String: Any]
    let reply: ([String: Any]) -> Void
}
