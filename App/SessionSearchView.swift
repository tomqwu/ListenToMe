import SwiftUI
import UniformTypeIdentifiers
import ListenToMeCore

struct SessionSearchView: View {
    @Environment(\.dismiss) private var dismiss
    let store: SessionStore
    let onClear: () -> Void
    let onDelete: (String) -> Void
    let onOpen: ((SessionRecord) -> Void)?
    /// Read when the user asks, so a Settings change since the sheet opened is honoured (#57).
    let askRoute: () -> HistoryAskRoute
    @State private var query = ""
    @State private var records: [SessionRecord] = []
    @State private var selected: SessionRecord?
    @State private var confirmClear = false
    @State private var deleting: SessionRecord?

    init(store: SessionStore, onClear: @escaping () -> Void = {}, onDelete: @escaping (String) -> Void = { _ in },
         onOpen: ((SessionRecord) -> Void)? = nil,
         askRoute: @escaping () -> HistoryAskRoute = { .unavailable("Asking is not available here.") }) {
        self.store = store; self.onClear = onClear; self.onDelete = onDelete
        self.onOpen = onOpen; self.askRoute = askRoute
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Keyword plus on-device semantic results with snippets, once the index has answered;
    /// until then (and with no index) the keyword results the sheet always had.
    private var hybrid: [HistorySearchResult]? { store.historySearch?.results(for: query) }
    private var shown: [SessionRecord] { hybrid?.map(\.record) ?? SessionSearch.search(records, query: query) }

    /// Only a conversation the archive still holds, in its current form (never a cleared one).
    private func open(_ id: String) { selected = records.first { $0.id == id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Conversation history").font(.title2).bold()
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            TextField("Search or ask your conversations", text: $query).textFieldStyle(.roundedBorder)
                .onChange(of: query) { store.historySearch?.search(query) }
            if let search = store.historySearch, !trimmedQuery.isEmpty, !records.isEmpty {
                HistoryAskPanel(search: search, question: trimmedQuery, route: askRoute(),
                                ask: { search.ask(trimmedQuery, route: askRoute()) }, open: open)
            }
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
            List(shown) { record in
                Button { open(record.id) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(record.title).font(.headline)
                            Spacer()
                            if record.isComplete == false { Text("Recovered checkpoint").font(.caption) }
                        }
                        Text(record.date.formatted()).font(.caption).foregroundStyle(.secondary)
                        if let result = hybrid?.first(where: { $0.id == record.id }), result.snippet != nil {
                            HistorySnippetText(result: result)
                        } else {
                            Text(record.summary.isEmpty ? record.transcript : record.summary)
                                .lineLimit(2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 5)
                .contextMenu {
                    Button("Delete conversation…", role: .destructive) { deleting = record }
                }
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
        } message: {
            Text("Export any conversations you want to keep first. Saved audio is deleted too. "
                 + "This cannot be undone in the app.")
        }
        .confirmationDialog("Delete this conversation?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), presenting: deleting) { record in
            Button("Delete conversation", role: .destructive) { _ = delete(record) }
        } message: { record in
            Text("Delete “\(record.title)” and its saved audio from this device? "
                 + "Exported copies are kept. This cannot be undone in the app.")
        }
        .sheet(item: $selected) { record in
            SessionDetailView(record: record, onOpen: onOpen.map { action in
                { selected = nil; dismiss(); action(record) }
            }, onDelete: { delete(record) })
        }
    }

    private func delete(_ record: SessionRecord) -> String? {
        guard store.delete(record) else { return store.errorText ?? "Could not delete conversation." }
        records.removeAll { $0.id == record.id }
        onDelete(record.id)
        if selected?.id == record.id { selected = nil }
        deleting = nil
        return nil
    }
}

private struct SessionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let record: SessionRecord
    var onOpen: (() -> Void)?
    let onDelete: () -> String?
    @State private var confirmDelete = false
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
            MacSavedAudioSection(record: record)   // Saved audio, when the conversation has any (#55)
            ScrollView { MarkdownText(text: markdown).frame(maxWidth: .infinity, alignment: .leading) }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                if let onOpen { Button("Open conversation", action: onOpen) }
                Button("Copy conversation") { Clipboard.copy(markdown) }
                Menu("Export") {
                    ConversationExportMenu(record: { record },
                                           hasTimestamps: TranscriptTimestamp.hasTimes(record.segments ?? []),
                                           onError: { error = $0 })
                }.fixedSize()
                Spacer()
                Button("Delete…", role: .destructive) { confirmDelete = true }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 720, height: 580)
        .confirmationDialog("Delete this conversation?", isPresented: $confirmDelete) {
            Button("Delete conversation", role: .destructive) { error = onDelete() }
        } message: {
            Text("The conversation and saved audio will be deleted from this device. "
                 + "Exported copies are kept. This cannot be undone in the app.")
        }
    }
}
