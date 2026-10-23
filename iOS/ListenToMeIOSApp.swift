import SwiftUI
import AVFoundation

@main
struct ListenToMeIOSApp: App {
    @State private var session = MobileSession()
    @Environment(\.scenePhase) private var scenePhase
    /// Active before any scene exists, so a watch message that launches the app in the background is
    /// answered (with "open the iPhone app") instead of reaching the microphone (issue #181).
    private let watchLink: PhoneWatchLink?

    init() {
        watchLink = PhoneWatchLink.activateIfSupported()
    }

    var body: some Scene {
        WindowGroup {
            meeting
                .tint(MobileStyle.accent)
                .task {
                    session.importSharedInbox()
                    attachWatchLink()
                }
                .onOpenURL { session.importFile($0) }
                .onChange(of: session.busy) { _, busy in if !busy { session.importSharedInbox() } }
                // The lifecycle rules live in MobileSession so unit tests can drive them.
                .onChange(of: scenePhase) { _, phase in
                    // Synchronously, before the hop: the app can be suspended before the Task runs.
                    session.flushPendingSave()
                    Task { await session.handleScenePhase(phase) }
                }
                .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { note in
                    guard let event = MobileSession.interruption(from: note) else { return }
                    Task { await session.handleInterruption(event.type, options: event.options) }
                }
                .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { note in
                    guard let reason = MobileSession.routeChangeReason(from: note) else { return }
                    Task { await session.handleRouteChange(reason) }
                }
        }
    }

    private func attachWatchLink() {
        guard let watchLink else { return }
        let session = session
        watchLink.commandHandler = { await session.handleWatchCommand($0) }
        session.watchLink = watchLink
        session.publishWatchStatus()
    }

    @ViewBuilder private var meeting: some View {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--incremental-summary-fixture") {
            MobileIncrementalSummaryFixture()
        } else if ProcessInfo.processInfo.arguments.contains("--speech-correction-fixture") {
            MobileCorrectionFixture()
        } else if ProcessInfo.processInfo.arguments.contains("--automatic-summary-fixture") {
            MobileAutomaticSummaryFixture()
        } else if ProcessInfo.processInfo.arguments.contains("--transcript-scroll-fixture") {
            MobileTranscriptFixture()
        } else if ProcessInfo.processInfo.arguments.contains("--design-review-fixture") {
            MobileDesignFixture()
        } else {
            MobileMeetingView(session: session)
        }
        #else
        MobileMeetingView(session: session)
        #endif
    }
}
