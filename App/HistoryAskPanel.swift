import SwiftUI
import ListenToMeCore

/// "Ask your history" in the Mac History sheet (issue #57): answers the search text as a question
/// from the best matching excerpts and lists the conversations the answer cites.
struct HistoryAskPanel: View {
    let search: HistorySearchModel
    let question: String
    let route: HistoryAskRoute
    let ask: () -> Void
    let open: (String) -> Void

    private var showsAnswer: Bool {
        search.answerQuestion == question && (search.isAsking || !search.answer.isEmpty || search.askError != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button("Ask your history", systemImage: "sparkle.magnifyingglass", action: ask)
                    .disabled(search.isAsking || route.unavailable != nil)
                    .help("Answer “\(question)” from the matching excerpts of your saved conversations")
                if search.isAsking {
                    ProgressView().controlSize(.small)
                    Button("Stop") { search.cancelAsk() }.controlSize(.small)
                }
                Text(route.unavailable ?? route.disclosure
                     ?? "Answered on this Mac from the matching excerpts; nothing leaves the device.")
                    .font(.caption)
                    .foregroundStyle(route.disclosure == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsAnswer {
                VStack(alignment: .leading, spacing: 6) {
                    if !search.answer.isEmpty {
                        ScrollView { MarkdownText(text: search.answer).frame(maxWidth: .infinity, alignment: .leading) }
                            .frame(maxHeight: 140)
                    }
                    if let error = search.askError {
                        Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                    }
                    if !search.citations.isEmpty {
                        HStack(spacing: 8) {
                            Text("Sources").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(search.citations) { citation in
                                Button("\(citation.numbers.map { "[\($0)]" }.joined()) \(citation.title)") {
                                    open(citation.recordID)
                                }
                                .controlSize(.small)
                                .help(citation.date.formatted())
                            }
                        }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
            }
        }
    }
}

/// The excerpt under a search result, labelled with where it came from.
struct HistorySnippetText: View {
    let result: HistorySearchResult

    var body: some View {
        if let snippet = result.snippet {
            (Text(snippet.source.label + (result.isRelated && !result.matchesWords ? " · Related" : "") + "  ")
                .font(.caption.weight(.semibold))
             + Text(snippet.text))
                .lineLimit(3).foregroundStyle(.secondary)
        }
    }
}
