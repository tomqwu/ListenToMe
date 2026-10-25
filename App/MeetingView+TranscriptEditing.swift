import ListenToMeCore

extension MeetingView {
    func editTranscriptLine(_ segment: TranscriptSegment, text: String) {
        guard session.editTranscript(id: segment.id, text: text) else { return }
        autoTitleTask?.cancel(); autoTitleTask = nil
        _ = checkpoint(complete: !wantsCapture && !lifecycleBusy && !session.isTranscribingFile && importTask == nil, force: true)
    }

    func deleteTranscriptLine(_ segment: TranscriptSegment) {
        guard let index = store.utterances.firstIndex(where: { $0.id == segment.id }),
              session.deleteTranscript(id: segment.id) else { return }
        // The diarizer's capture-run boundary is an array position, not a timestamp.
        if index < diarizationRunStartIndex { diarizationRunStartIndex -= 1 }
        autoTitleTask?.cancel(); autoTitleTask = nil
        _ = checkpoint(complete: !wantsCapture && !lifecycleBusy && !session.isTranscribingFile && importTask == nil, force: true)
    }
}
