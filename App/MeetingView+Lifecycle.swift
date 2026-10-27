import SwiftUI
import ListenToMeCore

extension MeetingView {
    /// Window close/teardown: stop the hotkey and any pending restart/import. If recording, mirror
    /// the Stop-button flow so a meeting ended by closing the window is still saved for search
    /// (best-effort: the Task may not finish on a full app quit).
    func tearDownOnDisappear(session: MeetingSession) {
        session.setTranslationSuspended(true)
        captureStartGate.close()
        calendarContext.cancel()
        referenceContext.cancel()
        modelCatalog.cancel()
        capabilityWork.cancel()
        calendarSuggestionWork.cancel()
        speakerModelReset.cancel()
        speakerCheckpoint.cancel()
        transcriptScrollWork.cancel()
        hotkey.stop()
        for role in CopilotRole.allCases { session.cancelResponse(role) }
        speakerWork.cancel()
        diarizationRunToken &+= 1
        let wasCapturing = wantsCapture
        importWork.cancel()    // stop an in-flight file import when the window closes
        if wasCapturing {
            _ = checkpoint()
            captureCoordinator.requestStop(after: {
                _ = checkpoint(complete: true, force: true)
            })
        } else {
            captureCoordinator.requestStop()
            session.stop()
        }
    }

    /// Opens Settings, snapshotting the saving toggle first so an off→on round-trip is still caught
    /// on dismiss (see `markSaveableAfterSettings`).
    func openSettings(_ showSettings: Binding<Bool>) {
        // A catalog begun before editing must not heal choices during the Settings transaction.
        modelCatalog.cancel()
        savingEnabledBeforeSettings = ProviderSettings.saveSessionsForSearch
        showSettings.wrappedValue = true
    }

    /// Settings-dismiss: taint the session only when saving was off at some point during the visit
    /// (off when opened OR off now) AND content was already captured — that content was at risk, so
    /// exclude the whole window-session. Turning saving ON before recording anything leaves it
    /// untainted, so saving works normally for that window.
    func markSaveableAfterSettings() {
        let wasOff = !savingEnabledBeforeSettings || !ProviderSettings.saveSessionsForSearch
        // "Has content" includes an in-progress partial, so audio captured mid-utterance while
        // saving was off still taints the session.
        let hasContent = !store.utterances.isEmpty || store.partial != nil
        if wasOff && hasContent { sessionSaveable = false }
    }

    /// Drops the current in-memory session from future saves after the user clears history, so a
    /// just-deleted transcript can't be re-persisted. A fresh id starts a new (still untainted)
    /// upsert key once this session is sealed.
    func dropCurrentSessionFromSaving() {
        calendarContext.cancel()
        // Only taint when the current window-session has content that was just cleared — clearing
        // old records on a fresh/empty window must not silently disable future saving.
        if hasConversation { sessionSaveable = false }
        currentSessionID = UUID().uuidString
        vocabulary.restore(domainIDs: nil, for: currentSessionID, transcriptLineCount: store.utterances.count)
        applyVocabulary()
        checkpointCoordinator.reset()
    }

    /// On Stop, persist the finished session for cross-meeting search when this window-session is
    /// saveable (saving never observed off), saving is on, and there's new transcript. Reuses
    /// `currentSessionID` so repeated Listen→Stop cycles upsert one growing record. Title = the
    /// active preset's name (or "Session") plus the date.
    func saveSessionIfEnabled(session: MeetingSession, force: Bool = false) {
        _ = checkpoint(complete: !wantsCapture && !lifecycleBusy, force: force)
    }

}
