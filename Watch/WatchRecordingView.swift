import SwiftUI
import WatchKit

/// Full screen while the watch records (issue #181): a red dot and the elapsed time, so recording is
/// never invisible on the device that records, and Stop. After a stop that was not the user's, it
/// shows why, with Continue after an interruption.
struct WatchRecordingView: View {
    let recorder: WatchRecorder
    @State private var problem: String?
    @State private var isContinuing = false

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
                            if let problem {
                                Text(problem)
                                    .font(.footnote)
                                    .multilineTextAlignment(.center)
                            }
                            if canContinue {
                                Button("Continue", action: resume)
                                    .tint(.red)
                                    .disabled(isContinuing)
                            }
                            Button("Done") { recorder.stop() }
                        }
                    }
                case .idle:
                    EmptyView()
                }
            }
        }
    }

    private func stop() {
        recorder.stop()
        WKInterfaceDevice.current().play(.stop)
    }

    private func resume() {
        isContinuing = true
        problem = nil
        Task {
            defer { isContinuing = false }
            do {
                try await recorder.continueRecording()
                WKInterfaceDevice.current().play(.start)
            } catch {
                problem = error.localizedDescription
                WKInterfaceDevice.current().play(.failure)
            }
        }
    }
}
