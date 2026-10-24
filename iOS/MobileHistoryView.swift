import SwiftUI
import ListenToMeCore

struct MobileHistoryView: View {
    @Bindable var session: MobileSession
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDeletion: SessionRecord?
    @State private var showDeletion = false
    @State private var sharing: SessionRecord?
    @State private var query = ""
    @State private var pendingWatchDeletion: WatchInboxRow?
    @State private var showWatchDeletion = false

    /// Same keyword ranking the Mac History sheet uses, so a phrase said in one standup is
    /// reachable without scrolling two months of conversations.
    private var results: [SessionRecord] { session.historyMatching(query) }

    var body: some View {
        NavigationStack {
            List {
                if let warning = session.archiveWarning {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .font(.footnote).foregroundStyle(.orange)
                                .accessibilityIdentifier("history-archive-warning")
                            Button("Dismiss") { session.dismissArchiveWarning() }
                                .font(.footnote).buttonStyle(.borderless)
                        }
                    }
                }
                if !session.watchInboxRows.isEmpty || !session.watchInboxProblems.isEmpty {
                    Section("Waiting from Apple Watch") {
                        if !session.watchInboxProblems.isEmpty { watchProblems }
                        ForEach(session.watchInboxRows) { watchRow($0) }
                    }
                }
                Section {
                    ForEach(results) { record in
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
                                let audio = session.savedAudio.fileURLs(for: record.id)
                                if !audio.isEmpty {
                                    ShareLink(items: audio) { Label("Share audio", systemImage: "waveform") }
                                }
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
                Text("This removes the transcript, notes, attachments, saved audio and all AI outputs from this device. "
                     + "It cannot be undone.")
            }
            .alert("Delete this Apple Watch audio?", isPresented: $showWatchDeletion,
                   presenting: pendingWatchDeletion) { row in
                Button("Delete audio", role: .destructive) {
                    session.deleteWatchRecording(row.id)
                    pendingWatchDeletion = nil
                }
                Button("Cancel", role: .cancel) { pendingWatchDeletion = nil }
            } message: { _ in
                Text("Text already transcribed stays in History.")
            }
            .sheet(item: $sharing) { record in
                ConversationShareSheet(text: MobileSession.readableShareText(for: record))
                    .presentationDetents([.medium, .large])
            }
            .scrollContentBackground(.hidden).background(MobileStyle.canvas)
            .overlay {
                if session.history.isEmpty && session.watchInboxRows.isEmpty {
                    ContentUnavailableView("No saved conversations", systemImage: "clock",
                                           description: Text("Save a conversation to return to its words, notes and summaries."))
                } else if results.isEmpty, !session.history.isEmpty, session.watchInboxRows.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .onAppear {
                session.reloadHistory()
                session.refreshWatchInboxRows()
            }
            .searchable(text: $query, prompt: "Search title, summary, or transcript")
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
                    if !session.savedAudio.runs(for: record.id).isEmpty {
                        Label("Audio saved", systemImage: "waveform")
                            .font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("history-audio-\(record.id)")
                    }
                    if MobileSession.isFromAppleWatch(record) {
                        Label("From Apple Watch", systemImage: "applewatch")
                            .font(.caption).foregroundStyle(.secondary)
                    }
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

    /// Audio the iPhone could not keep: said once, until dismissed.
    private var watchProblems: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(session.watchInboxProblems.enumerated()), id: \.offset) { _, problem in
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.orange)
            }
            Button("Dismiss") { session.dismissWatchInboxProblems() }
                .font(.footnote).buttonStyle(.borderless)
        }
        .accessibilityIdentifier("history-watch-problems")
    }

    /// A watch recording still being received or transcribed, or one that failed.
    private func watchRow(_ row: WatchInboxRow) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(row.title).font(.headline)
                Text(row.detail).font(.caption)
                    .foregroundStyle(row.failure == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
            }
            Spacer(minLength: 0)
            if row.failure != nil {
                Button("Retry") { session.retryWatchRecording(row.id) }.buttonStyle(.borderless)
            }
            Button("Delete", role: .destructive) {
                pendingWatchDeletion = row
                showWatchDeletion = true
            }.buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("history-watch-\(row.id.uuidString)")
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
