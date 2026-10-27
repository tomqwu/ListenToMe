import SwiftUI
import WatchKit

/// The watch's first screen (issue #181, Slice 3): record on the watch, recordings still waiting for
/// the iPhone, and below them the Slice 1 remote for the iPhone's own recorder.
struct WatchRootView: View {
    static let consentKey = "watchRecordingConsentShownV2"
    static let consentText = "Only record people who have agreed to be recorded. The audio goes only to your "
        + "iPhone when connected. It transcribes on-device and keeps audio for playback only when "
        + "\"Save audio recordings\" is on; otherwise it deletes audio after transcription."

    let link: WatchLinkClient
    let recorder: WatchRecorder
    let outbox: WatchOutbox
    @AppStorage(WatchRootView.consentKey) private var consentShown = false
    @State private var showConsent = false
    @State private var confirmDelete = false
    @State private var preparation = WatchPreparation()
    @State private var continuationPreparation = WatchPreparation()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Button(action: record) {
                    Label("Record", systemImage: "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .tint(.red)
                .disabled(preparation.isPending || !recorder.availability.canRun)
                if let reason = recorder.availability.reason {
                    Text(reason).font(.footnote).multilineTextAlignment(.center)
                }
                if let startProblem = preparation.problem {
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
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                recorder.refreshAvailability()
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            preparation.sceneChanged(phase, isRecording: recorder.isRecording) { recorder.stop() }
        }
        .onDisappear {
            preparation.sceneChanged(scenePhase, isRecording: recorder.isRecording) { recorder.stop() }
        }
        .fullScreenCover(isPresented: recordingScreenShown) {
            WatchRecordingView(recorder: recorder, preparation: continuationPreparation)
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
    }

    /// Shown for as long as there is a recording: the red indicator while it records, and the reason
    /// (with Continue after an interruption) once it stops. Dismissing it ends the recording.
    private var recordingScreenShown: Binding<Bool> {
        Binding(get: { recorder.phase != .idle }, set: { shown in
            if !shown {
                continuationPreparation.cancel { recorder.stop() }
                if recorder.phase != .idle { recorder.stop() }
            }
        })
    }

    private func record() {
        guard consentShown else { showConsent = true; return }
        start()
    }

    private func start() {
        let currentRecorder = recorder
        preparation.run(operation: { try await currentRecorder.start() },
                        onSuccess: { WKInterfaceDevice.current().play(.start) },
                        onFailure: { WKInterfaceDevice.current().play(.failure) })
    }
}
