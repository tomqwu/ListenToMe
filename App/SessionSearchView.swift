import SwiftUI
import UniformTypeIdentifiers
import ListenToMeCore

struct SessionSearchView: View {
    @Environment(\.dismiss) private var dismiss
    let store: SessionStore
    let onClear: () -> Void
    @State private var query = ""
    @State private var records: [SessionRecord] = []
    @State private var selected: SessionRecord?
    @State private var confirmClear = false

    init(store: SessionStore, onClear: @escaping () -> Void = {}) {
        self.store = store; self.onClear = onClear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Conversation history").font(.title2).bold()
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            TextField("Search title, summary, or transcript", text: $query).textFieldStyle(.roundedBorder)
            if let error = store.errorText {
                Text(error).foregroundStyle(.red)
                Button("Retry") { records = store.all() }
            }
            // A damaged file is set aside rather than hiding everything, so this is a warning
            // shown next to the conversations that did load, not a read failure.
            if let warning = store.archiveWarning {
                HStack {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                    Button("Dismiss") { store.dismissArchiveWarning() }.controlSize(.small)
                }
            }
            List(SessionSearch.search(records, query: query)) { record in
                Button { selected = record } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(record.title).font(.headline)
                            Spacer()
                            if record.isComplete == false { Text("Recovered checkpoint").font(.caption) }
                        }
                        Text(record.date.formatted()).font(.caption).foregroundStyle(.secondary)
                        Text(record.summary.isEmpty ? record.transcript : record.summary)
                            .lineLimit(2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 5)
            }
            if records.isEmpty && store.errorText == nil { Text("Saved conversations will appear here.") }
            HStack {
                Button("Refresh") { records = store.all() }
                Spacer()
                Button("Clear history…", role: .destructive) { confirmClear = true }.disabled(records.isEmpty)
            }
        }
        .padding(20).frame(width: 680, height: 540)
        // Loaded here rather than in `init`: this view is constructed inside MeetingView's `.sheet`
        // closure, which re-runs whenever the elapsed timer ticks or a token streams in, so seeding
        // @State in the initializer re-read and re-decoded the whole archive on the main thread
        // once a second and threw the result away (issue #116).
        .task { records = store.all() }
        .confirmationDialog("Delete all saved conversations?", isPresented: $confirmClear) {
            Button("Delete all saved conversations", role: .destructive) {
                if store.clear() { records = []; onClear() }
            }
        } message: { Text("Export any conversations you want to keep first. This cannot be undone in the app.") }
        .sheet(item: $selected) { SessionDetailView(record: $0) }
    }
}

private struct SessionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let record: SessionRecord
    @State private var error: String?

    private var markdown: String { SessionExporter.markdown(for: record) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(record.title).font(.title2).bold()
            Text(record.date.formatted()).foregroundStyle(.secondary)
            if record.isComplete == false {
                Text("Recovered through this checkpoint. Speech after the last save may be missing.")
                    .foregroundStyle(.secondary)
            }
            ScrollView { MarkdownText(text: markdown).frame(maxWidth: .infinity, alignment: .leading) }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Copy conversation") { Clipboard.copy(markdown) }
                Menu("Export") {
                    ConversationExportMenu(record: { record },
                                           hasTimestamps: TranscriptTimestamp.hasTimes(record.segments ?? []),
                                           onError: { error = $0 })
                }.fixedSize()
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 720, height: 580)
    }
}
