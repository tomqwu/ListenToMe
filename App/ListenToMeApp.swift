import SwiftUI

@main
struct ListenToMeApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: ApplicationLifecycle
    var body: some Scene {
        Window("ListenToMe", id: "listentome") {
            MeetingView()
                .tint(Theme.accent)
        }
        .windowResizability(.contentSize)
        .commands { ConversationMenu() }
    }
}
