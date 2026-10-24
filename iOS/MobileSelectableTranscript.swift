import SwiftUI
import ListenToMeCore

/// Touch-and-hold actions on a final transcript line (issue #234).
struct MobileTranscriptLineActions {
    let summarizeFrom: (UUID) -> Void
    let selectFrom: (UUID) -> Void
}

/// A request to summarize these lines, shown as a sheet.
struct MobileSelectionRequest: Identifiable {
    let id = UUID()
    let lines: [TranscriptSegment]
}

/// The transcript reader with Select mode (issue #234): tap lines to toggle them, drag down the
/// circles to extend a range, or touch and hold a line for Summarize from here / Select from here.
/// The Live panel shows lines only (`selectable: false`) and hands selecting to the full-height
/// transcript, where the selection bar has room; both share one selection.
struct MobileSelectableTranscript: View {
    let session: MobileSession
    @Binding var selection: TranscriptSelection
    @Binding var selecting: Bool
    var scrollIdentifier = "transcriptScroll"
    /// Select mode and its bar are shown here; otherwise `startSelecting` opens the view that has them.
    var selectable = true
    var startSelecting: () -> Void = {}
    @State private var request: MobileSelectionRequest?

    var body: some View {
        VStack(spacing: 0) {
            MobileTranscriptReader(segments: session.allSegments, scrollIdentifier: scrollIdentifier,
                                   restoreOriginal: session.restoreSpeech, showsSpeakers: session.hasSpeakerLabels,
                                   selection: $selection, selecting: selectable && selecting,
                                   lineActions: MobileTranscriptLineActions(summarizeFrom: { id in
                                       var from = TranscriptSelection()
                                       from.selectFrom(id, in: session.allSegments)
                                       request = MobileSelectionRequest(lines: from.selected(in: session.allSegments))
                                   }, selectFrom: { id in
                                       selection.selectFrom(id, in: session.allSegments)
                                       selecting = true
                                       startSelecting()
                                   }))
            if selectable && selecting {
                MobileSelectionBar(session: session, selected: selection.selected(in: session.allSegments),
                                   summarize: {
                                       request = MobileSelectionRequest(lines: selection.selected(in: session.allSegments))
                                   }, done: { selecting = false; selection.clear() })
            }
        }
        .sheet(item: $request) { request in
            MobileSelectionSummarySheet(session: session, selected: request.lines)
                .presentationDetents([.medium, .large])
        }
    }
}
