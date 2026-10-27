import SwiftUI
import WatchKit

/// Full screen while the watch records (issue #181): a red dot and the elapsed time, so recording is
/// never invisible on the device that records, and Stop. After a stop that was not the user's, it
/// shows why, with Continue after an interruption.
struct WatchRecordingView: View {
    let recorder: WatchRecorder
    let preparation: WatchPreparation
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 10) {
                switch recorder.phase {
                case .recording(let startedAt):
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.red)
                            .frame(width: 10, height: 10)
                        Text("Recording")
                    }
                    .accessibilityElement(children: .combine)
                    Text(WatchLink.elapsedText(context.date.timeIntervalSince(startedAt)))
                        .font(.title2.monospacedDigit())
                    Button("Stop", action: stop)
                        .tint(.red)
                case .stopped(let reason, let canContinue):
                    ScrollView {
                        VStack(spacing: 10) {
                            Text(reason ?? "Recording stopped.")
                                .font(.footnote)
                                .multilineTextAlignment(.center)
                            if let problem = preparation.problem {
                                Text(problem)
                                    .font(.footnote)
                                    .multilineTextAlignment(.center)
                            }
                            if canContinue {
                                if let reason = recorder.availability.reason {
                                    Text(reason).font(.footnote).multilineTextAlignment(.center)
                                }
                                Button("Continue", action: resume)
                                    .tint(.red)
                                    .disabled(preparation.isPending || !recorder.availability.canRun)
                            }
                            Button("Done") { preparation.cancel(); recorder.stop() }
                        }
                    }
                case .idle:
                    EmptyView()
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            preparation.sceneChanged(phase, isRecording: recorder.isRecording) { recorder.stop() }
        }
        .onDisappear {
            // Explicit Done/dismissal cancels through the owning root; inactive consent is allowed.
            preparation.sceneChanged(scenePhase, isRecording: recorder.isRecording) { recorder.stop() }
        }
    }

    private func stop() {
        recorder.stop()
        WKInterfaceDevice.current().play(.stop)
    }

    private func resume() {
        let currentRecorder = recorder
        preparation.run(operation: { try await currentRecorder.continueRecording() },
                        onSuccess: { WKInterfaceDevice.current().play(.start) },
                        onFailure: { WKInterfaceDevice.current().play(.failure) })
    }
}
