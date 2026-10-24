import SwiftUI

/// Settings → Conversations → Name conversations automatically (#221), on by default.
struct MobileAutoTitleSettings: View {
    @AppStorage(MobileSession.autoTitleKey) private var enabled = true

    var body: some View {
        Section("Conversations") {
            Toggle("Name conversations automatically", isOn: $enabled)
                .accessibilityIdentifier("nameConversationsAutomatically")
            Text("After you stop or save, a conversation still called “New conversation” gets a short title "
                 + "from its summary, from your summary provider, or from keywords found on this device. "
                 + "A title you type or load from Calendar is never replaced.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
