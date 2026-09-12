import SwiftUI
import ListenToMeCore

struct MobileHistoryView: View {
    @Bindable var session: MobileSession
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDeletion: SessionRecord?
    @State private var showDeletion = false
    @State private var sharing: SessionRecord?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(session.history) { record in
                        row(record)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", systemImage: "trash") { confirmDeletion(record) }.tint(.red)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button("Share", systemImage: "square.and.arrow.up") { sharing = record }
                                    .tint(MobileStyle.accent)
                            }
                            .contextMenu {
                                Button("Share", systemImage: "square.and.arrow.up") { sharing = record }
                                Button("Delete", systemImage: "trash", role: .destructive) { confirmDeletion(record) }
                            }
                            .accessibilityAction(named: "Share") { sharing = record }
                            .accessibilityAction(named: "Delete") { confirmDeletion(record) }
                    }
                } footer: {
                    if !session.history.isEmpty { Text("Swipe right to share, left to delete. Touch and hold for more actions.") }
                }
            }
            .alert("Delete conversation?", isPresented: $showDeletion, presenting: pendingDeletion) { record in
                Button("Delete conversation", role: .destructive) {
                    session.deleteConversation(id: record.id)
                    pendingDeletion = nil
                }
                Button("Cancel", role: .cancel) { pendingDeletion = nil }
            } message: { _ in
                Text("This removes the transcript, notes, attachments and all AI outputs from this device. It cannot be undone.")
            }
            .sheet(item: $sharing) { record in
                ConversationShareSheet(text: MobileSession.markdown(for: record))
                    .presentationDetents([.medium, .large])
            }
            .scrollContentBackground(.hidden).background(MobileStyle.canvas)
            .overlay {
                if session.history.isEmpty {
                    ContentUnavailableView("No saved conversations", systemImage: "clock",
                                           description: Text("Save a conversation to return to its words, notes and summaries."))
                }
            }
            .navigationTitle("History")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private func row(_ record: SessionRecord) -> some View {
        Button {
            session.open(record)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(record.title).font(.headline).foregroundStyle(.primary)
                    Text(record.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(record.summary.isEmpty ? AttributedString(record.notes ?? record.transcript)
                         : MarkdownText.inlineAttributed(record.summary))
                        .lineLimit(2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary).accessibilityHidden(true)
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).padding(.vertical, 4)
            .accessibilityIdentifier("history-record-\(record.id)")
    }

    private func confirmDeletion(_ record: SessionRecord) {
        pendingDeletion = record
        showDeletion = true
    }
}

private struct ConversationShareSheet: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}
