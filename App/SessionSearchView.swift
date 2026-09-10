import SwiftUI
import UniformTypeIdentifiers
import ListenToMeCore

struct SessionSearchView: View {
    @Environment(\.dismiss) private var dismiss
    let store: SessionStore
    let onClear: () -> Void
    @State private var query = ""
    @State private var records: [SessionRecord]
    @State private var selected: SessionRecord?
    @State private var confirmClear = false

    init(store: SessionStore, onClear: @escaping () -> Void = {}) {
        self.store = store; self.onClear = onClear
        _records = State(initialValue: store.all())
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

    private var markdown: String {
        if let segments = record.segments {
            return SessionExporter.markdown(title: record.title, transcript: segments, notes: record.notes ?? "",
                                            listenerSummary: record.summary,
                                            quickSuggestion: record.quickSuggestion ?? "", deepAnswer: record.deepAnswer ?? "")
        }
        return "# \(record.title)\n\n## Transcript\n\n\(record.transcript)\n\n## Summary\n\n\(record.summary)"
    }

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
                Button("Export Markdown…") { export() }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 720, height: 580)
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "Conversation.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try markdown.write(to: url, atomically: true, encoding: .utf8) }
        catch { self.error = error.localizedDescription }
    }
}
