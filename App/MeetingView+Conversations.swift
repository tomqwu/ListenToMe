import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ListenToMeCore

extension MeetingView {
    var hasConversation: Bool { !store.utterances.isEmpty || !session.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    @discardableResult
    func checkpoint(complete: Bool = false, force: Bool = false) -> Bool {
        guard ProviderSettings.saveSessionsForSearch, sessionSaveable else { return false }
        guard hasConversation else { return true }
        let record = SessionRecord(
            id: currentSessionID, title: conversationTitle, date: Date(),
            transcript: store.utterances.map { "\($0.speakerLabel): \($0.text)" }.joined(separator: "\n"),
            summary: session.listenerSummary, segments: store.utterances, notes: session.notes,
            quickSuggestion: session.quickSuggestion, deepAnswer: session.deepAnswer, isComplete: complete)
        // Date is intentionally excluded so repeated timer ticks do not rewrite unchanged content.
        let signature = String(store.revision) + record.title + record.transcript + record.summary + (record.notes ?? "")
            + (record.quickSuggestion ?? "") + (record.deepAnswer ?? "") + String(complete)
        guard force || signature != lastSavedSignature else { return true }
        guard sessionStore.add(record) else {
            saveMessage = sessionStore.errorText ?? "Save failed. Retry or Export to keep this conversation."
            saveFailed = true
            return false
        }
        lastSavedSignature = signature
        saveMessage = "Saved at " + Date().formatted(date: .omitted, time: .standard)
        saveFailed = false
        return true
    }

    func saveConversation() {
        if ProviderSettings.saveSessionsForSearch && sessionSaveable {
            _ = checkpoint(complete: !session.isRunning && !lifecycleBusy, force: true)
        } else {
            _ = saveConversationAs()
        }
    }

    @discardableResult
    func saveConversationAs() -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "ListenToMe-Conversation.md"
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
                case .alertThirdButtonReturn: break
                default: return
                }
            }
            beginDiarizationRunReset()
            session.resetConversation()
            currentSessionID = UUID().uuidString
            conversationTitle = "Conversation — " + Date().formatted(date: .abbreviated, time: .shortened)
            sessionSaveable = ProviderSettings.saveSessionsForSearch
            othersAudioSink.reset(); microphoneAudioSink.reset()
            lastSavedSignature = ""
            saveMessage = "New conversation"; saveFailed = false
            clearReferences(session: session)
            transcriptAtBottom = true
        }
    }

    var conversationStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Conversation title", text: $conversationTitle)
                    .textFieldStyle(.plain).fontWeight(.semibold)
                    .accessibilityLabel("Conversation title")
                Spacer()
                Text(lifecycleBusy ? "Finalizing…" : (wantsCapture
                    ? (recordingStartedAt == nil ? "Starting…" : "Recording \(elapsedLabel)") : "Ready"))
                Text(ProviderSettings.aiMode.label)
            }
            HStack(alignment: .top, spacing: 16) {
                Text(session.captureStatus).frame(maxWidth: .infinity, alignment: .leading)
                Text(session.transcriptionStatus).frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(saveMessage).foregroundStyle(saveFailed ? .red : .secondary)
                    if saveFailed {
                        HStack {
                            Button("Retry save") { saveConversation() }
                            Button("Save As…") { _ = saveConversationAs() }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .trailing)
            }
            if store.partial != nil {
                Text("Saving keeps finalized text; the current spoken phrase is still being transcribed.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Theme.cardBackground2)
    }

    var conversationCommands: ConversationCommands {
        ConversationCommands(canSave: hasConversation, canStartNew: !lifecycleBusy && !session.isTranscribingFile,
            save: saveConversation, new: newConversation, history: { showSearch = true },
            export: exportSession, settings: { openSettings($showSettings) })
    }

    /// App/window close waits for final text, but never for optional AI or speaker analysis.
    func prepareToClose() async -> Bool {
        guard !lifecycleBusy else { return false }
        lifecycleBusy = true
        defer { lifecycleBusy = false }
        wantsCapture = false; recordingStartedAt = nil
        restartTask?.cancel(); importTask?.cancel()
        _ = checkpoint()
        await session.stopAndWait()
        await importTask?.value
        if !hasConversation { return true }
        if ProviderSettings.saveSessionsForSearch && sessionSaveable && checkpoint(complete: true, force: true) {
            return true
        }
        let alert = NSAlert()
        alert.messageText = "Save this conversation before closing?"
        alert.informativeText = saveFailed ? saveMessage : "Automatic history saving is off for this conversation."
        alert.addButton(withTitle: "Save As…")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Close without saving")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return saveConversationAs()
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }
}
