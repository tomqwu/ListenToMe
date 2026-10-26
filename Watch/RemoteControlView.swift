import SwiftUI

/// Slice 1 of issue #181: a remote for the iPhone recorder. One status line and one button.
struct RemoteControlView: View {
    let link: WatchLinkClient

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 12) {
                Text(link.remoteAvailability.reason ?? WatchRemoteText.line(status: link.phoneStatus, reachable: link.isReachable,
                                          lastReply: link.lastReply, now: context.date))
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Button(isRecording ? "Stop" : "Start") {
                    let command: WatchCommand = isRecording ? .stop : .start
                    Task { await link.send(command) }
                }
                .tint(isRecording ? .red : nil)
                .disabled(link.isSending || !link.remoteAvailability.canRun)
            }
        }
    }

    private var isRecording: Bool {
        link.phoneStatus?.state == .preparing || link.phoneStatus?.state == .recording
    }
}
