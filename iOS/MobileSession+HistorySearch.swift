import Foundation
import ListenToMeCore

/// History search (issue #57): keyword matching plus the on-device semantic index, and "Ask your
/// history". Kept out of the class body; the index lives beside the archive in `Search Index/`.
extension MobileSession {
    var historySearch: HistorySearchModel { HistorySearchModel.shared(besideArchive: archive.directoryURL) }

    /// Records matching `query`, newest first; an empty query is the full history. This is the
    /// keyword search the semantic results start from and fall back to.
    func historyMatching(_ query: String) -> [SessionRecord] {
        SessionSearch.search(history, query: query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Reconciles the index with the archive (after a reload or a deletion). Searches and questions
    /// read `history` itself, so they never see a conversation History no longer lists.
    func indexHistory() {
        historySearch.records = { [weak self] in self?.history ?? [] }
        historySearch.sync(history)
    }

    /// Embeds a conversation that was just saved.
    func indexSaved(_ record: SessionRecord) { historySearch.update(record) }

    /// A deleted conversation's vectors are removed with it. The single removal path every deletion
    /// goes through: one conversation, several, or `everything` (Delete all, which wipes the index).
    /// Shaped to plug into a deletion-owner list as one entry (#220).
    func forgetSearchIndex(ids: [String], everything: Bool = false) {
        if everything { historySearch.forgetAll(); return }
        for id in ids { historySearch.forget(id: id) }
    }

    /// Where a question goes: the selected summary provider, as the Summary role is configured. Apple
    /// Intelligence answers on this device; every other provider is named in the disclosure.
    var historyAskRoute: HistoryAskRoute {
        if ai.provider == .apple {
            if onDeviceProviderOverride == nil, let reason = AppleIntelligenceProvider.unavailableReason {
                return .unavailable(reason)
            }
            let override = onDeviceProviderOverride
            return HistoryAskRoute(unavailable: nil, destination: nil, responseLanguage: nil,
                                   makeProvider: { override ?? AppleIntelligenceProvider() })
        }
        if let reason = ai.availability(for: .summary) { return .unavailable(reason) }
        let ai = ai
        return HistoryAskRoute(unavailable: nil, destination: ai.summaryEndpointLabel, responseLanguage: nil,
                               makeProvider: { try ai.client(for: .summary) })
    }

    func askHistory(_ question: String) {
        historySearch.ask(question, route: historyAskRoute, describe: MobileAISettings.errorMessage)
    }
}
