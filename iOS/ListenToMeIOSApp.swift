import SwiftUI
import AVFoundation

@main
struct ListenToMeIOSApp: App {
    @State private var session = MobileSession()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MobileMeetingView(session: session)
                .tint(.indigo)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { Task { await session.background() } }
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
}
