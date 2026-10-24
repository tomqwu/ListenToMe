import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ListenToMeCore

extension MeetingView {
    var hasConversation: Bool {
        !session.summaryInstructions.isEmpty || !store.utterances.isEmpty
            || !session.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @discardableResult
    func checkpoint(complete: Bool = false, force: Bool = false) -> Bool {
        guard ProviderSettings.saveSessionsForSearch, sessionSaveable else { return false }
        guard hasConversation else { return true }
        // Compare a cheap dirty key BEFORE building anything: the timer fires once a second for the
        // whole meeting, and rebuilding the joined transcript first made every idle tick
        // O(transcript) on the main actor (issue #116). `store.revision` stands in for the
        // transcript; Date is intentionally excluded so ticks do not rewrite unchanged content.
        let key = SessionCheckpointKey(
            revision: store.revision, title: conversationTitle, summary: session.listenerSummary,
            notes: session.notes, quickSuggestion: session.quickSuggestion,
            deepAnswer: session.deepAnswer, complete: complete, summaryInstructions: session.summaryInstructions,
            vocabularyDomainIDs: vocabulary.domainIDs(for: currentSessionID).sorted())
        guard force || key != lastSavedKey else { return true }
        // The record keeps the conversation's start (its first checkpoint), so History, its exports
        // and the Save to folder note all carry the same date and file name as the live export.
        let started = conversationStartedAt ?? Date()
        let record = currentRecord(date: started, complete: complete)
        guard sessionStore.add(record) else {
            saveMessage = sessionStore.errorText ?? "Save failed. Retry or Export to keep this conversation."
            saveFailed = true
            return false
        }
        lastSavedKey = key
        conversationStartedAt = started
        // Save to folder (issue #53): written once capture has stopped, then on each later change.
        let vault = MarkdownVaultSync.shared
        vault.activeRecordingID = complete ? nil : currentSessionID
        if complete {
            vault.save(record, startedAt: started)
        }
        saveMessage = "Saved at " + Date().formatted(date: .omitted, time: .standard)
        saveFailed = false
        return true
    }

    func saveConversation() {
        if ProviderSettings.saveSessionsForSearch && sessionSaveable {
            if checkpoint(complete: !session.isRunning && !lifecycleBusy, force: true) { nameConversationIfNeeded() }
        } else {
            _ = saveConversationAs()
        }
    }

    @discardableResult
    func saveConversationAs() -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = SessionExporter.fileName(title: conversationTitle,
                                                              date: conversationStartedAt ?? Date(), fileExtension: "md")
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try sessionMarkdown().write(to: url, atomically: true, encoding: .utf8)
            saveMessage = "Exported to \(url.lastPathComponent)"; saveFailed = false
            return true
        } catch {
            saveMessage = "Export failed: \(error.localizedDescription)"; saveFailed = true
            return false
        }
    }

    func newConversation() {
        guard !lifecycleBusy, !session.isTranscribingFile else { return }
        lifecycleBusy = true
        Task {
            defer { lifecycleBusy = false }
            wantsCapture = false
            recordingStartedAt = nil
            restartTask?.cancel()
            // A checkpoint is independent of transcription/model completion.
            _ = checkpoint()
            await session.stopAndWait()
            let persisted = !hasConversation || (ProviderSettings.saveSessionsForSearch && sessionSaveable
                                                 && checkpoint(complete: true, force: true))
            if !persisted {
                let alert = NSAlert()
                alert.messageText = saveFailed ? "Keep this conversation before starting a new one" : "Save this conversation?"
                alert.informativeText = "Save As keeps a Markdown copy. Cancel keeps this conversation open."
                alert.addButton(withTitle: "Save As…")
                alert.addButton(withTitle: "Cancel")
                alert.addButton(withTitle: "Discard and start new")
                switch alert.runModal() {
                case .alertFirstButtonReturn: guard saveConversationAs() else { return }
                case .alertThirdButtonReturn: MacSavedAudio.shared.discard(conversationID: currentSessionID)
                default: return
                }
            }
            discardAudioIfNotInHistory()
            if persisted { nameConversationIfNeeded() }   // the saved one, in the background (#221)
            autoTitleTask = nil   // it renames the saved record; typing the new title must not cancel it
            beginDiarizationRunReset()
            restoredRecord = nil
            session.resetConversation()
            currentSessionID = UUID().uuidString; conversationStartedAt = nil
            vocabulary.restore(domainIDs: nil, for: currentSessionID)
            applyVocabulary()
            conversationLanguages = ConversationLanguages()
            conversationTitle = ConversationTitle.generated(Date().formatted(date: .abbreviated, time: .shortened))
            conversationTitleState = .placeholder
            sessionSaveable = ProviderSettings.saveSessionsForSearch
            othersAudioSink.reset(); microphoneAudioSink.reset()
            lastSavedKey = nil
            saveMessage = "New conversation"; saveFailed = false
            clearReferences(session: session)
            transcriptAtBottom = true
        }
    }

    func openConversation(_ record: SessionRecord) {
        guard record.id != currentSessionID else { return }
        guard !lifecycleBusy, !session.isRunning, !session.isTranscribingFile else {
            saveMessage = "Stop recording or importing before opening another conversation."
            saveFailed = true
            return
        }
        guard record.segments != nil || record.transcript.isEmpty else {
            saveMessage = "This older conversation can be read and exported in History. It cannot be reopened yet."
            saveFailed = true
            return
        }
        if hasConversation {
            guard ProviderSettings.saveSessionsForSearch, sessionSaveable,
                  checkpoint(complete: true, force: true) else {
                saveMessage = "Save or start a new conversation before opening History."
                saveFailed = true
                return
            }
        }
        autoTitleTask?.cancel(); autoTitleTask = nil
        beginDiarizationRunReset()
        clearReferences(session: session)
        othersAudioSink.reset(); microphoneAudioSink.reset()
        restoredRecord = record
        guard session.restoreConversation(record) else { return }
        currentSessionID = record.id; conversationStartedAt = record.date
        conversationTitle = record.title; conversationTitleState = record.resolvedTitleState
        conversationLanguages = record.conversationLanguages
        vocabulary.restore(domainIDs: record.vocabularyDomainIDs, for: currentSessionID,
                           transcriptLineCount: store.utterances.count)
        applyVocabulary()
        lastSavedKey = nil; sessionSaveable = ProviderSettings.saveSessionsForSearch
        saveMessage = "Opened conversation"; saveFailed = false
    }

    var conversationStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Conversation title", text: conversationTitleBinding)
                    .focused($titleFieldFocused)
                    .textFieldStyle(.plain).fontWeight(.semibold)
                    .accessibilityLabel("Conversation title")
                Spacer()
                Text(lifecycleBusy ? "Finalizing…" : (wantsCapture
                    ? (session.isPreparing ? "Preparing…"
                       : (recordingStartedAt == nil ? "Starting…" : "Recording \(elapsedLabel)"))
                    : "Ready"))
                Text(ProviderSettings.aiModeLabel)
            }
            HStack(alignment: .top, spacing: 16) {
                // A dead channel must be visible: the rail still says REC and the elapsed timer
                // keeps counting, so a grey caption hid the failure entirely (issue #107).
                Text(session.captureDegraded ? "⚠️ \(session.captureStatus)" : session.captureStatus)
                    .foregroundStyle(session.captureDegraded ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                    .fontWeight(session.captureDegraded ? .semibold : .regular)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(session.transcriptionStatus).frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(saveMessage).foregroundStyle(saveFailed ? .red : .secondary)
                    if saveFailed {
                        HStack {
                            Button("Retry save") { saveConversation() }
                            Button("Save As…") { _ = saveConversationAs() }
                        }
                    }
                    if let problem = MacSavedAudio.shared.problem {
                        Text("⚠️ \(problem)").foregroundStyle(.orange).multilineTextAlignment(.trailing)
                        Button("Dismiss") { MacSavedAudio.shared.dismissProblem() }
                    }
                    let vault = MarkdownVaultSync.shared
                    if vault.needsAttention {
                        Text("⚠️ Save to folder: \(vault.statusText)").foregroundStyle(.orange)
                            .multilineTextAlignment(.trailing)
                        Button("Retry folder save") {
                            vault.retry(history: sessionStore.all(), excluding: wantsCapture ? currentSessionID : nil)
                        }.disabled(!vault.hasFolder)
                    }
                }.frame(maxWidth: .infinity, alignment: .trailing)
            }
            if store.partial != nil {
                Text("Saving keeps finalized text; the current spoken phrase is still being transcribed.")
                    .foregroundStyle(.secondary)
            }
            // Apple Intelligence has a small on-device context window; say so when a prompt had to
            // be trimmed instead of silently answering from a partial transcript (issue #119).
            if let notice = session.promptTruncationNotice {
                Text(notice).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Theme.cardBackground2)
    }

    var conversationCommands: ConversationCommands {
        ConversationCommands(canSave: hasConversation, canStartNew: !lifecycleBusy && !session.isTranscribingFile,
            isCapturing: wantsCapture,
            canToggleCapture: !lifecycleBusy && !session.isTranscribingFile,
            canUseAI: session.aiEnabled,
            save: saveConversation, new: newConversation, history: { showSearch = true },
            export: exportSession, settings: { openSettings($showSettings) },
            toggleCapture: { toggleCapture(session: session) },
            deepAnswer: { Task { await session.respondDeep(.answerQuestion) } },
            recap: { Task { await session.respondQuick(.recap) } },
            refreshSummary: { Task { await session.refreshListener() } })
    }

    /// App/window close waits for final text, but never for optional AI or speaker analysis.
    func prepareToClose() async -> Bool {
        guard !lifecycleBusy else { return false }
        lifecycleBusy = true
        defer { lifecycleBusy = false }
        wantsCapture = false; recordingStartedAt = nil; activeEngine = nil
        restartTask?.cancel(); importTask?.cancel()
        _ = checkpoint()
        await session.stopAndWait()
        await MacSavedAudio.shared.waitForWrites()
        await importTask?.value
        if !hasConversation { discardAudioIfNotInHistory(); return true }
        if ProviderSettings.saveSessionsForSearch && sessionSaveable && checkpoint(complete: true, force: true) {
            // The final Save to folder note is queued by that checkpoint; let it land before quitting.
            await MarkdownVaultSync.shared.waitForWrites(timeout: .seconds(5))
            return true
        }
        let alert = NSAlert()
        alert.messageText = "Save this conversation before closing?"
        alert.informativeText = saveFailed ? saveMessage : "Automatic history saving is off for this conversation."
        alert.addButton(withTitle: "Save As…")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Close without saving")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            guard saveConversationAs() else { return false }
            discardAudioIfNotInHistory()
            return true
        case .alertThirdButtonReturn:
            MacSavedAudio.shared.discard(conversationID: currentSessionID)
            return true
        default: return false
        }
    }

    /// Saved audio belongs to a conversation in History (#55): a conversation that is not there — empty,
    /// autosave off, or exported with Save As only — keeps no audio.
    func discardAudioIfNotInHistory() {
        if !sessionStore.contains(currentSessionID) { MacSavedAudio.shared.discard(conversationID: currentSessionID) }
    }
}
