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
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { Task { await session.background() } }
                    if phase == .active { session.importSharedInbox() }
                }
                .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { note in
                    guard let value = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                          AVAudioSession.InterruptionType(rawValue: value) == .began else { return }
                    Task { await session.stop() }
                }
                .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { note in
                    guard let value = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                          AVAudioSession.RouteChangeReason(rawValue: value) == .oldDeviceUnavailable else { return }
                    Task { await session.stop() }
                }
        }
    }

    @ViewBuilder private var meeting: some View {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--transcript-scroll-fixture") {
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
