import os
import SwiftUI

/// The Apple Watch companion (issue #181), embedded by the default iOS project.
@main
struct ListenToMeWatchApp: App {
    private static let log = Logger(subsystem: "com.tomwu.ListenToMe.ios.watchkitapp", category: "App")
    @State private var link: WatchLinkClient
    @State private var recorder: WatchRecorder
    @State private var outbox: WatchOutbox

    private static var isDesignFixture: Bool {
        #if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("--watch-design-fixture")
        #else
        false
        #endif
    }

    init() {
        let link = WatchLinkClient()
        let recorder: WatchRecorder
        #if DEBUG && targetEnvironment(simulator)
        var previewCapture: WatchPreviewCapture?
        if ProcessInfo.processInfo.arguments.contains("--compatibility-denied-fixture") {
            recorder = WatchRecorder(capabilitySnapshot: {
                .init(microphoneDenied: true, battery: 1, freeBytes: Int64.max)
            })
        } else if Self.isDesignFixture {
            let capture = WatchPreviewCapture()
            previewCapture = capture
            var permissionCalls = 0
            let delayed = ProcessInfo.processInfo.arguments.contains("--watch-preview-delay-permission")
            let interrupted = ProcessInfo.processInfo.arguments.contains("--watch-preview-interrupted")
            recorder = WatchRecorder(makeCapture: { capture }, capabilitySnapshot: {
                .init(microphoneDenied: false, battery: 1, freeBytes: Int64.max)
            }, requestPermission: {
                permissionCalls += 1
                if delayed, !(interrupted && permissionCalls == 1) { try await Task.sleep(for: .seconds(15)) }
            }, audioSession: .init(activate: {}, deactivate: {}))
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
        #if DEBUG && targetEnvironment(simulator)
        if let previewCapture, ProcessInfo.processInfo.arguments.contains("--watch-preview-interrupted") {
            Task { @MainActor in
                do {
                    try await recorder.start()
                    previewCapture.event?(.interruptionBegan)
                } catch { Self.log.error("Preview setup failed") }
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView(link: link, recorder: recorder, outbox: outbox)
                .accessibilityIdentifier(Self.isDesignFixture ? "watchPreviewFixture" : "watchRoot")
        }
        // Completes every WKWatchConnectivityRefreshBackgroundTask when the closure returns.
        .backgroundTask(.watchConnectivity) { }
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Drives the real controller/view for release captures without microphone input or audio files.
private final class WatchPreviewCapture: WatchChunkCapturing {
    var isRunning = false
    var event: (@MainActor @Sendable (WatchAudioEvent) -> Void)?
    func start(_ run: WatchCaptureRun, onChunk: @escaping @MainActor @Sendable (WatchFinishedChunk) -> Void,
               onFailure: @escaping @MainActor @Sendable (String) -> Void,
               onAudioEvent: @escaping @MainActor @Sendable (WatchAudioEvent) -> Void) throws {
        isRunning = true
        event = onAudioEvent
    }
    func stop() -> WatchCaptureEnding {
        isRunning = false
        return WatchCaptureEnding(last: nil, lastIndex: nil)
    }
}
#endif
