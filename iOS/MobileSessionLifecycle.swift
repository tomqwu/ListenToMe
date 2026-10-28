import SwiftUI

/// Explicitly binds the session owned by an app or fixture to its scene, including cold launch.
/// A meeting view can also be presented inside another owner, so it must not install this itself.
@MainActor
final class MobileSessionPhaseBridge {
    private let session: MobileSession
    private var pending: Task<Void, Never>?
    private var pendingPhase: ScenePhase?

    init(session: MobileSession) { self.session = session }

    func synchronize(_ phase: ScenePhase) {
        pending?.cancel()
        pendingPhase = phase
        session.observeScenePhase(phase)
        // Suspension can follow inactive before the asynchronous handler gets an execution slot.
        session.flushPendingSave()
        if phase == .active { session.savedAudio.applyRetention() }
        let session = session
        pending = Task {
            // A cancelled queued handler must not mutate session eligibility or its scene generation.
            guard !Task.isCancelled else { return }
            await session.handleScenePhase(phase)
        }
    }

    func detach() {
        // An owner disappearing must not erase the latest privacy suspension or stop its microphone.
        // Only a pending activation has become obsolete; inactive/background delivery remains valid.
        if pendingPhase == .active { pending?.cancel(); pending = nil }
    }
}

private struct MobileSessionLifecycleModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var bridge: MobileSessionPhaseBridge

    init(session: MobileSession) { _bridge = State(initialValue: MobileSessionPhaseBridge(session: session)) }

    func body(content: Content) -> some View {
        content
            .task {
                guard !Task.isCancelled else { return }
                bridge.synchronize(scenePhase)
            }
            .onChange(of: scenePhase) { _, phase in bridge.synchronize(phase) }
            .onDisappear { bridge.detach() }
    }
}

extension View {
    func mobileSessionLifecycle(_ session: MobileSession) -> some View {
        modifier(MobileSessionLifecycleModifier(session: session))
    }
}
