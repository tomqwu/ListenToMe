import SwiftUI
import ListenToMeCore

/// "Ask your history" (issue #57): answers the search text as a question from the best matching
/// excerpts, citing the conversations it used. Says where the excerpts go before anything is sent.
struct MobileHistoryAskSection: View {
    @Bindable var session: MobileSession
    let question: String
    let open: (String) -> Void

    private var search: HistorySearchModel { session.historySearch }
    private var route: HistoryAskRoute { session.historyAskRoute }
    private var showsAnswer: Bool {
        search.answerQuestion == question && (search.isAsking || !search.answer.isEmpty || search.askError != nil)
    }

    var body: some View {
        Section {
            Button {
                session.askHistory(question)
            } label: {
                Label("Ask your history about “\(question)”", systemImage: "sparkle.magnifyingglass")
            }
            .disabled(search.isAsking || route.unavailable != nil)
            .accessibilityIdentifier("history-ask")
            if showsAnswer { answer }
        } footer: {
            Text(route.unavailable ?? route.disclosure
                 ?? "Answered on this iPhone by Apple Intelligence from the matching excerpts.")
                .accessibilityIdentifier("history-ask-disclosure")
        }
    }

    @ViewBuilder private var answer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if search.isAsking && search.answer.isEmpty {
                ProgressView("Reading \(search.sentPassages > 0 ? "\(search.sentPassages) excerpts" : "your history")…")
            }
            if !search.answer.isEmpty {
                MarkdownText(text: search.answer).accessibilityIdentifier("history-ask-answer")
            }
            if let error = search.askError {
                Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
            }
            if !search.citations.isEmpty {
                Text("Sources").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(search.citations) { citation in
                    Button {
                        open(citation.recordID)
                    } label: {
                        Label("\(citation.numbers.map { "[\($0)]" }.joined()) \(citation.title) · "
                              + citation.date.formatted(date: .abbreviated, time: .omitted),
                              systemImage: "text.bubble")
                            .font(.footnote)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("history-citation-\(citation.recordID)")
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// The excerpt under a search result, labelled with where it came from.
struct MobileHistorySnippet: View {
    let result: HistorySearchResult

    var body: some View {
        if let snippet = result.snippet {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(snippet.source.label)
                    if result.isRelated && !result.matchesWords {
                        Text("· Related").foregroundStyle(MobileStyle.accent)
                    }
                }
                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(snippet.text).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
