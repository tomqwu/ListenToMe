import SwiftUI

/// The Apple Watch companion (issue #181). The iOS app embeds it only when the project is generated
/// with `WATCH_EMBED=YES`, until the release train that ships watch recording.
@main
struct ListenToMeWatchApp: App {
    @State private var link = WatchLinkClient()
    // SPIKE ONLY (#181 Task 15, branch spike/181-watch-audio, never merged).
    @State private var spike = SpikeAudioModel()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 16) {
                        RemoteControlView(link: link)
                        NavigationLink("DEBUG: Task 15 audio spike") {
                            SpikeAudioView(model: spike)
                        }
                        .font(.footnote)
                    }
                }
            }
            .task {
                link.onFileTransferFinished = { name, error in spike.transferFinished(fileName: name, error: error) }
                link.activate()
            }
        }
        // Completes every WKWatchConnectivityRefreshBackgroundTask when the closure returns.
        .backgroundTask(.watchConnectivity) { }
    }
}
