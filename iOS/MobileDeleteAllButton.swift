import SwiftUI

/// "Delete all conversations…" in History and in Settings → Privacy (#220): destructive, confirmed with
/// the count, and unavailable while recording.
struct MobileDeleteAllButton: View {
    @Bindable var session: MobileSession
    @State private var confirming = false

    var body: some View {
        Button("Delete all conversations…", systemImage: "trash", role: .destructive) { confirming = true }
            .foregroundStyle(session.canDeleteAllConversations ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            .disabled(!session.canDeleteAllConversations)
            .accessibilityIdentifier("deleteAllConversations")
            .alert(MobileSession.deleteAllTitle(count: session.history.count), isPresented: $confirming) {
                Button("Delete all", role: .destructive) { session.deleteAllConversations() }
                    .accessibilityIdentifier("confirmDeleteAllConversations")
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(session.deleteAllMessage)
            }
        if session.busy, !session.history.isEmpty {
            Text("Stop recording or wait for the AI response to delete conversations.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
