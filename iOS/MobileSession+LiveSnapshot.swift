import Foundation
import ListenToMeCore

extension MobileSession {
    struct LiveKey: Equatable {
        let revision: Int
        let partial: TranscriptSegment?
        let notes: String
    }

    struct LiveSnapshot {
        let pieces: [MobileQuickContext.Piece]
        let source: String
        let manualSegments: [TranscriptSegment]
        let manualSource: String
        let provisionalNotice: String?
    }

    /// Finalized edits (including labels/language) increment revision. The complete partial and
    /// notes form the rest of the key, so repeated reads never scan the finalized transcript.
    func liveSnapshot() -> LiveSnapshot {
        let key = LiveKey(revision: liveRevision, partial: partial, notes: notes)
        if let liveCache, liveCacheKey == key { return liveCache }
        let finals = segments.map(Self.promptSegment)
        let live = partial.map(Self.promptSegment)
        let notesLine = MobileQuickContext.attributedNotes(notes)
        let source = ([notesLine] + (finals + (live.map { [$0] } ?? [])).map(MobileQuickContext.attributed))
            .filter { !$0.isEmpty }.joined(separator: "\n")
        let manual = (finals + (live.map { [$0] } ?? [])).compactMap { segment -> TranscriptSegment? in
            guard !segment.isFinal else { return segment }
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= ConversationStore.provisionalMinimumCharacters else { return nil }
            return TranscriptSegment(id: segment.id, source: segment.source,
                text: ConversationStore.provisionalTag + text, isFinal: false, start: segment.start, end: segment.end,
                speakerID: segment.speakerID, speakerName: segment.speakerName,
                originalText: segment.originalText, correctionModel: segment.correctionModel, language: segment.language)
        }
        let snapshot = LiveSnapshot(
            pieces: MobileQuickContext.pieces(notes: notes, segments: finals, liveSegments: live.map { [$0] } ?? []),
            source: source, manualSegments: manual,
            manualSource: ([notesLine] + manual.map(MobileQuickContext.attributed))
                .filter { !$0.isEmpty }.joined(separator: "\n"),
            provisionalNotice: manual.contains { !$0.isFinal } ? PromptBuilder.provisionalNotice : nil)
        liveCacheKey = key
        liveCache = snapshot
        liveSnapshotComputations += 1
        return snapshot
    }
}
