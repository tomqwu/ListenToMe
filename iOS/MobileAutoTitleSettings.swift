import SwiftUI

/// Settings → Conversations → Name conversations automatically (#221), on by default.
struct MobileAutoTitleSettings: View {
    @AppStorage(MobileSession.autoTitleKey) private var enabled = true

    var body: some View {
        Section("Conversations") {
            Toggle("Name conversations automatically", isOn: $enabled)
                .accessibilityIdentifier("nameConversationsAutomatically")
            Text("After you stop or save, a conversation still called “New conversation” gets a short title "
                 + "from its summary, from Apple Intelligence or your own Ollama server, or from keywords "
                 + "found on this device. With Ollama Cloud, a Cloud AI service or an OpenAI-compatible "
                 + "server, nothing is sent for a title: it comes from the summary or keywords. "
                 + "A title you type is never replaced.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
