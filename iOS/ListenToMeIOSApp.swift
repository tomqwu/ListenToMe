import SwiftUI
import AVFoundation

@main
struct ListenToMeIOSApp: App {
    @State private var session = MobileSession()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            meeting
                .tint(MobileStyle.accent)
                .task { session.importSharedInbox() }
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
