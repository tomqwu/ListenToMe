import SwiftUI
import ListenToMeCore

/// Separate instances keep capture problems visible when file or calendar work fails.
struct MeetingErrorBanner: View {
    let message: String
    let dismissLabel: String
    let dismiss: () -> Void
    let openSettings: (String) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("⚠️ \(message)")
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Actions are derived from this banner's message, never another operation's state.
            if message == CapturePreflight.deniedMessage {
                Button("Open Settings") { openSettings("Privacy_Microphone") }
            }
            if message == CalendarLookup.denied.message {
                Button("Open Calendar privacy settings") { openSettings("Privacy_Calendars") }
            }
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .help("Dismiss this message")
                .accessibilityLabel(dismissLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
        .background(Theme.windowBackground)
    }
}
