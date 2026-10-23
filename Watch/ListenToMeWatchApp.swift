import SwiftUI

/// The Apple Watch companion (issue #181). The iOS app embeds it only when the project is generated
/// with `WATCH_EMBED=YES`, until the release train that ships watch recording.
@main
struct ListenToMeWatchApp: App {
    @State private var link = WatchLinkClient()

    var body: some Scene {
        WindowGroup {
            RemoteControlView(link: link)
                .task { link.activate() }
        }
        // Completes every WKWatchConnectivityRefreshBackgroundTask when the closure returns.
        .backgroundTask(.watchConnectivity) { }
    }
}
