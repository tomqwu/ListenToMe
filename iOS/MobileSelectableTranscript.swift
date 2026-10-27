import SwiftUI
import ListenToMeCore

/// Touch-and-hold (and VoiceOver) actions on a final transcript line (issue #234).
struct MobileTranscriptLineActions {
    let summarizeFrom: (UUID) -> Void
    let selectFrom: (UUID) -> Void
    /// Why Summarize from here cannot run, shown under the disabled menu item. One value for every
    /// line (it depends on the provider and on other answers, not on the line), so a long transcript
    /// does not recompute it per row.
    let summarizeBlockReason: String?
}

/// The transcript reader with Select mode (issue #234): tap lines to toggle them, drag down the
/// circles to extend a range, or touch and hold a line for Summarize from here / Select from here.
/// The Live panel shows lines only (`selectable: false`) and hands selecting to the full-height
/// transcript, where the selection bar has room; both share one selection.
///
/// The summary sheet is not presented from here: a view that hosts it is replaced whenever the
/// workspace switches layout (rotation, Dynamic Type), which would close the sheet mid-answer. The
/// owner presents `request` from a view that survives those changes.
struct MobileSelectableTranscript: View {
    let session: MobileSession
    @Binding var selection: TranscriptSelection
    @Binding var selecting: Bool
    @Binding var request: MobileSelectionRequest?
    var scrollIdentifier = "transcriptScroll"
    /// Select mode and its bar are shown here; otherwise `startSelecting` opens the view that has them.
    var selectable = true
    var startSelecting: () -> Void = {}
    /// The saved audio's per-line play controls (issue #55), passed through to the reader.
    var audioTarget: ((TranscriptSegment) -> SavedAudioSeek.Target?)?
    var playAudio: ((SavedAudioSeek.Target) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            MobileTranscriptReader(segments: session.allSegments, scrollIdentifier: scrollIdentifier,
                                   translation: session.liveTranslation.text,
                                   translationProblem: { session.liveTranslation.problems[$0] },
                                   restoreOriginal: session.restoreSpeech, showsSpeakers: session.hasSpeakerLabels,
                                   selection: $selection, selecting: selectable && selecting,
                                   lineActions: MobileTranscriptLineActions(summarizeFrom: { id in
                                       request = MobileSelectionRequest(lines: Self.fromHere(id, in: session.allSegments))
                                   }, selectFrom: { id in
                                       selection.selectFrom(id, in: session.allSegments)
                                       selecting = true
                                       startSelecting()
                                   }, summarizeBlockReason: session.selectionSummaryProviderBlockReason),
                                   audioTarget: audioTarget, playAudio: playAudio, addTerm: session.addToMyTerms)
            if selectable && selecting {
                MobileSelectionBar(session: session, selected: selection.selected(in: session.allSegments),
                                   summarize: {
                                       request = MobileSelectionRequest(lines: selection.selected(in: session.allSegments))
                                   }, done: { selecting = false; selection.clear() })
            }
        }
        // A language Undo or re-transcription replaces lines; what is gone leaves the selection.
        .onChange(of: session.allSegments.map(\.id)) { selection.prune(keeping: session.allSegments) }
    }

    /// The final lines from `id` through the latest.
    static func fromHere(_ id: UUID, in segments: [TranscriptSegment]) -> [TranscriptSegment] {
        var from = TranscriptSelection()
        from.selectFrom(id, in: segments)
        return from.selected(in: segments)
    }
}
