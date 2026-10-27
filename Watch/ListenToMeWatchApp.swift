import os
import SwiftUI

/// The Apple Watch companion (issue #181), embedded by the default iOS project.
@main
struct ListenToMeWatchApp: App {
    private static let log = Logger(subsystem: "com.tomwu.ListenToMe.ios.watchkitapp", category: "App")
    @State private var link: WatchLinkClient
    @State private var recorder: WatchRecorder
    @State private var outbox: WatchOutbox

    init() {
        let link = WatchLinkClient()
        let recorder: WatchRecorder
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--compatibility-denied-fixture") {
            recorder = WatchRecorder(capabilitySnapshot: {
                .init(microphoneDenied: true, battery: 1, freeBytes: Int64.max)
            })
        } else {
            recorder = WatchRecorder()
        }
        #else
        recorder = WatchRecorder()
        #endif
        // Construction does not record. Recovery still completes before the UI can start capture.
        let outbox = WatchOutbox(recordingIsActive: { [weak recorder] in recorder?.isRecording == true })
        recorder.onChunkFinalized = { [weak outbox] url, metadata in
            do { try outbox?.add(url, metadata) } catch {
                // Left in Recording/: the next launch recovers and sends it.
                Self.log.error("Chunk not moved to the outbox: \(error.localizedDescription, privacy: .public)")
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
        recorder.onStatusChange = publish
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
