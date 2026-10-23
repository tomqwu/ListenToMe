import SwiftUI

/// The Apple Watch companion (issue #181). The iOS app embeds it only when the project is generated
/// with `WATCH_EMBED=YES`, until the release train that ships watch recording.
@main
struct ListenToMeWatchApp: App {
    @State private var link: WatchLinkClient
    @State private var recorder: WatchRecorder
    @State private var outbox: WatchOutbox

    init() {
        let link = WatchLinkClient()
        // Cleans up chunks a killed launch left unfinished before anything can record.
        let outbox = WatchOutbox()
        let recorder = WatchRecorder()
        recorder.onChunkFinalized = { [weak outbox] url, metadata in
            do { try outbox?.add(url, metadata) } catch {
                // Left in Recording/: the next launch reports the recording as ended unexpectedly.
            }
        }
        recorder.onRecordingEnded = { [weak outbox] end in outbox?.sendEnd(end) }
        link.outbox = outbox
        // The iPhone shows "Apple Watch is recording"; published from the models, not a view, so it
        // stays current with the wrist down.
        let publish = { [weak link, weak recorder, weak outbox] in
            guard let link, let recorder else { return }
            link.publish(recorder.status(waitingRecordings: outbox?.waitingRecordings ?? 0))
        }
        recorder.onPhaseChange = publish
        outbox.onChange = publish
        publish()
        // Activated here, not when a screen appears: background transfers and their `didFinish`
        // need an active session even when the system launches the app only for them.
        link.activate()
        _link = State(initialValue: link)
        _recorder = State(initialValue: recorder)
        _outbox = State(initialValue: outbox)
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView(link: link, recorder: recorder, outbox: outbox)
        }
        // Completes every WKWatchConnectivityRefreshBackgroundTask when the closure returns.
        .backgroundTask(.watchConnectivity) { }
    }
}
