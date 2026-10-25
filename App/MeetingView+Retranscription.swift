import SwiftUI
import ListenToMeCore

extension MeetingView {
    var canRetranscribe: Bool {
        _ = MacSavedAudio.shared.revision
        return !wantsCapture && !lifecycleBusy && !isImporting && session.streamingRoles.isEmpty
            && sessionSaveable && ProviderSettings.saveSessionsForSearch
            && MacSavedAudio.shared.library.hasAudio(currentSessionID)
    }

    var retranscriptionSheet: some View {
        RetranscriptionView(original: currentRecord(date: conversationStartedAt ?? Date()),
            library: MacSavedAudio.shared.library,
            recognizers: ["Apple on-device": LocalAudioFileTranscriber.recognize,
                          "WhisperKit on-device": MacFileRetranscriber.recognize],
            terms: { vocabulary.recognitionTerms(for: currentSessionID, localeIdentifier: $0) },
            apply: applyRetranscription)
    }

    func applyRetranscription(_ preview: ConversationRetranscription) throws {
        guard canRetranscribe else { throw ConversationRetranscription.Failure.changed }
        let updated = try preview.applying(to: currentRecord(date: conversationStartedAt ?? Date()))
        try MacSavedAudio.shared.library.commitRetranscription(conversationID: currentSessionID, runs: preview.audioRuns) {
            guard sessionStore.add(updated) else {
                throw LocalAudioFileError.message(sessionStore.errorText ?? "Could not save the new transcript.")
            }
        }
        MacSavedAudio.shared.playback.stop()
        MacSavedAudio.shared.refresh()
        beginDiarizationRunReset()
        guard session.restoreConversation(updated) else { throw ConversationRetranscription.Failure.changed }
        restoredRecord = updated
        conversationLanguages = updated.conversationLanguages
        lastSavedKey = nil
        _ = checkpoint(complete: true, force: true)
        saveMessage = "Transcript replaced. Notes and summaries kept; review summaries for changes."
        saveFailed = false
    }
}
