import Foundation

extension MeetingSession {
    /// True when the store holds speech the Listener has not summarized yet: finalized utterances
    /// outside its ledger, or unfinalized speech whose wording differs from what the last refresh
    /// already sent as provisional context (issue #113) — a caught-up refresh carries that instead.
    /// A refresh with nothing new is a no-op, so the UI disables Refresh on `!hasUnsummarizedSpeech`
    /// (issue #137).
    public var hasUnsummarizedSpeech: Bool {
        if store.utterances.contains(where: { !summarizedSegmentIDs.contains($0.id) }) { return true }
        guard store.hasProvisionalSpeech else { return false }
        return Self.signature(of: store.provisionalContext(maxChars: Self.listenerTranscriptBudget))
            != summarizedProvisionalText
    }

    /// The provisional lines a refresh sends, as one comparable string.
    static func signature(of segments: [TranscriptSegment]) -> String {
        segments.map { "\($0.speakerLabel): \($0.text)" }.joined(separator: "\n")
    }

}
