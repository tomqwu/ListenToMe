import Foundation
import ListenToMeCore

extension MobileSession {
    var speechCorrectionStatus: String {
        guard ai.correctTranscript else { return "Speech correction off" }
        if correctionProvider == nil, let reason = ai.correctionAvailability { return "Correction paused · " + reason }
        return speechCorrection.status
    }

    func checkSpeech(_ segment: TranscriptSegment) {
        guard ai.correctTranscript, acceptsSpeechCorrection else { return }
        let sessionID = id
        // Only nearby recognized speech is sent. Notes, attachments and audio are excluded.
        let context = segments.dropLast().suffix(4).map { $0.originalText ?? $0.text }.joined(separator: "\n")
        do {
            let provider = try correctionProvider ?? ai.correctionClient()
            speechCorrection.submit(segment, context: context, model: ai.correctionModel, provider: provider) { [weak self] result in
                guard let self, self.id == sessionID, self.ai.correctTranscript,
                      let index = self.segments.firstIndex(where: { $0.id == segment.id && $0.text == segment.text }) else { return }
                self.segments[index] = result
                self.save(announce: false)
                Task { await self.updateQuickAutomatically() }
            }
        } catch {
            speechCorrection.reportFailure(error)
        }
    }

    func restoreSpeech(_ segmentID: UUID) {
        guard let index = segments.firstIndex(where: { $0.id == segmentID }), segments[index].originalText != nil else { return }
        segments[index] = segments[index].restoringOriginal
        save(announce: false)
        Task { await updateQuickAutomatically() }
    }
}
