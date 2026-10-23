import SwiftUI
import WatchKit

/// The watch's first screen (issue #181, Slice 3): record on the watch, recordings still waiting for
/// the iPhone, and below them the Slice 1 remote for the iPhone's own recorder.
struct WatchRootView: View {
    static let consentKey = "watchRecordingConsentShown"
    static let consentText = "Only record people who have agreed to be recorded. The audio goes only to your "
        + "iPhone, which transcribes it on-device and then deletes it."

    let link: WatchLinkClient
    let recorder: WatchRecorder
    let outbox: WatchOutbox
    @AppStorage(WatchRootView.consentKey) private var consentShown = false
    @State private var showConsent = false
    @State private var confirmDelete = false
    @State private var isStarting = false
    @State private var startProblem: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Button(action: record) {
                    Label("Record", systemImage: "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .tint(.red)
                .disabled(isStarting)
                if let startProblem {
                    Text(startProblem)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }
                if let waiting = WatchRemoteText.waitingText(outbox.waitingRecordings) {
                    Text(waiting)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                    Button("Delete", role: .destructive) { confirmDelete = true }
                }
                Divider()
                Text("iPhone")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                RemoteControlView(link: link)
            }
        }
        .fullScreenCover(isPresented: recordingScreenShown) {
            WatchRecordingView(recorder: recorder)
        }
        .alert("Before you record", isPresented: $showConsent) {
            Button("Record") {
                consentShown = true
                start()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(Self.consentText)
        }
        .confirmationDialog("Delete recordings that have not reached iPhone?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { outbox.deleteWaiting() }
        }
        .onChange(of: recorder.phase) { _, phase in
            // A limit or a failed write ended it: the reason is on screen, and the wrist feels it.
            if case .stopped(_, let canContinue) = phase {
                WKInterfaceDevice.current().play(canContinue ? .stop : .failure)
            }
        }
    }

    /// Shown for as long as there is a recording: the red indicator while it records, and the reason
    /// (with Continue after an interruption) once it stops. Dismissing it ends the recording.
    private var recordingScreenShown: Binding<Bool> {
        Binding(get: { recorder.phase != .idle }, set: { shown in
            if !shown, recorder.phase != .idle { recorder.stop() }
        })
    }

    private func record() {
        guard consentShown else { showConsent = true; return }
        start()
    }

    private func start() {
        isStarting = true
        startProblem = nil
        Task {
            defer { isStarting = false }
            do {
                try await recorder.start()
                WKInterfaceDevice.current().play(.start)
            } catch {
                startProblem = error.localizedDescription
                WKInterfaceDevice.current().play(.failure)
            }
        }
    }
}
