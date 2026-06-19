import SwiftUI

@main
struct ListenToMeApp: App {
    var body: some Scene {
        Window("ListenToMe", id: "listentome") {
            MeetingView()
        }
        .windowResizability(.contentSize)
    }
}
