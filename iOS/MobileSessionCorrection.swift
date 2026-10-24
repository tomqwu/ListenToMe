import Foundation
import ListenToMeCore

extension MobileSession {
    var speechCorrectionStatus: String {
        guard ai.correctTranscript else { return "Speech correction off" }
        if correctionProvider == nil, let reason = ai.correctionAvailability { return "Correction paused · " + reason }
        return speechCorrection.status
    }

    /// Runs on every finalized microphone line: the on-device vocabulary suggestion check, then the
    /// opt-in AI correction.
    func checkSpeech(_ segment: TranscriptSegment) {
        considerVocabularySuggestion(segment)
        guard ai.correctTranscript, acceptsSpeechCorrection else { return }
        let sessionID = id
        // Only nearby recognized speech is sent. Notes, attachments and audio are excluded.
        let context = segments.dropLast().suffix(4).map { $0.originalText ?? $0.text }.joined(separator: "\n")
        do {
            let provider = try correctionProvider ?? ai.correctionClient()
            // The glossary is built by the corrector off the main actor, from a prepared index.
            let lookup = vocabulary.correctionLookup(for: id), phrase = segment.text
            speechCorrection.submit(segment, context: context, glossary: { lookup.glossary(for: phrase) },
                                    model: ai.correctionModel, provider: provider) { [weak self] result in
                guard let self, self.id == sessionID, self.ai.correctTranscript,
                      let index = self.segments.firstIndex(where: { $0.id == segment.id && $0.text == segment.text }) else { return }
                // Speaker identification may have labeled or renamed the line while it was corrected.
                var corrected = result
                corrected.speakerID = self.segments[index].speakerID
                corrected.speakerName = self.segments[index].speakerName
                self.segments[index] = corrected
                self.save(announce: false)
                self.scheduleAutoQuick()
            }
        } catch {
            speechCorrection.reportFailure(error)
        }
    }

    func restoreSpeech(_ segmentID: UUID) {
        guard let index = segments.firstIndex(where: { $0.id == segmentID }), segments[index].originalText != nil else { return }
        segments[index] = segments[index].restoringOriginal
        save(announce: false)
        scheduleAutoQuick()
    }
}
