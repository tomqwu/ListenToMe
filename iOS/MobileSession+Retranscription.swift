import Foundation
import ListenToMeCore

extension MobileSession {
    var canRetranscribe: Bool { !busy && canPlaySavedAudio }

    func applyRetranscription(_ preview: ConversationRetranscription) throws {
        guard !busy else { throw ConversationRetranscription.Failure.changed }
        let updated = try preview.applying(to: currentRecord)
        // Write History before replacing visible text. A storage failure leaves the original in place.
        try savedAudio.library.commitRetranscription(conversationID: id, runs: preview.audioRuns) {
            try archive.save(updated)
        }
        languageDetection.languageChanges[id] = [preview.language]
        if languageDetection.notice?.conversation == id { languageDetection.clearNotice() }
        savedAudio.playback.stop()
        savedAudio.refresh()
        restore(updated)
        remember(updated)
        if save(announce: false) { message = "Transcript replaced. Notes and summaries kept; review summaries for changes." }
    }
}
