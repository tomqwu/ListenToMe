#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import Observation
import ListenToMeCore

/// Drives the actual app view/session and real scene transitions without microphone or network access.
/// Counters deliberately stay visible in QA captures; these are never App Store listing images.
struct MobileRecordingContinuityFixture: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var session: MobileSession
    @State private var recorder: ContinuityPreviewRecorder
    @State private var backgrounds = 0

    init() {
        let recorder = ContinuityPreviewRecorder()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ContinuityUI-\(UUID())")
        let session = MobileSession(storageDirectory: root, summaryProvider: ContinuityPreviewProvider(),
                                    sharedInbox: root.appendingPathComponent("SharedInbox"),
                                    watchInbox: WatchInbox(root: root.appendingPathComponent("WatchInbox")),
                                    makeRecorder: { recorder })
        session.title = "Screen lock recording check"
        session.autoQuick = false; session.ai.correctTranscript = false
        session.speakers.enabled = false; session.savedAudio.enabled = false
        session.languageChoice = "en-US"
        _recorder = State(initialValue: recorder)
        _session = State(initialValue: session)
    }

    var body: some View {
        MobileMeetingView(session: session)
            .overlay(alignment: .top) {
                // Diagnostic text must not reduce the production workspace or intercept its controls.
                Text("Synthetic capture · starts=\(recorder.starts); stops=\(recorder.stops); backgrounds=\(backgrounds)")
                    .font(.caption2).padding(4).accessibilityIdentifier("continuityFixtureProbe")
                    .allowsHitTesting(false)
            }
            .mobileSessionLifecycle(session)
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { backgrounds += 1 }
            }
    }
}

@MainActor @Observable
private final class ContinuityPreviewRecorder: MobileRecording {
    private(set) var starts = 0
    private(set) var stops = 0
    private var timer: Task<Void, Never>?

    func start(locale: Locale, onSegment: @escaping @MainActor (TranscriptSegment) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        starts += 1
        timer = Task {
            var index = 0
            while !Task.isCancelled {
                onSegment(TranscriptSegment(source: .you, text: "Synthetic continuity sample \(index + 1).",
                                            isFinal: true, start: Double(index), end: Double(index + 1)))
                index += 1
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }
    func stop() async throws { timer?.cancel(); timer = nil; stops += 1 }
    func reconfigure() async throws {}
}

private struct ContinuityPreviewProvider: LLMProvider {
    let id = "continuity-preview-no-network"
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
#endif
