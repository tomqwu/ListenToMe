import SwiftUI
import ListenToMeCore

/// A sheet for searching across locally-persisted past sessions. Lists matches ranked by
/// `SessionSearch`, and lets the user clear everything that's stored.
struct SessionSearchView: View {
    @Environment(\.dismiss) private var dismiss
    let store: SessionStore

    @State private var query = ""
    @State private var records: [SessionRecord]

    init(store: SessionStore) {
        self.store = store
        _records = State(initialValue: store.all())
    }

    private var results: [SessionRecord] {
        SessionSearch.search(records, query: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Search past meetings").font(.title2).bold()
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            TextField("Search title, summary, or transcript", text: $query)
                .textFieldStyle(.roundedBorder)

            if results.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
                    Text(records.isEmpty
                         ? "No saved sessions yet. Finished sessions are saved automatically."
                         : "No sessions match your search.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(results) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(record.title).font(.headline)
                            Spacer()
                            Text(record.date, format: .relative(presentation: .named))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let snippet = snippet(for: record) {
                            Text(snippet).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            HStack {
                Spacer()
                Button("Clear saved sessions", role: .destructive) {
                    store.clear()
                    records = []
                }
                .disabled(records.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520, height: 520)
    }

    /// A short summary/snippet for a result row: the summary if present, else the transcript start.
    private func snippet(for record: SessionRecord) -> String? {
        let summary = record.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = summary.isEmpty ? record.transcript : summary
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
