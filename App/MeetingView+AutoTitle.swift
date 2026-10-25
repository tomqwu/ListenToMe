import SwiftUI
import ListenToMeCore

/// Naming a conversation that still has its "Conversation — <date>" title once it is saved (#221).
/// Runs after Stop, Save and New conversation; never blocks them. The rule and the title come from
/// `ConversationAutoTitle` in Core.
extension MeetingView {
    /// The title field's edits: a typed title is the user's from then on, and a naming under way
    /// for this conversation is cancelled.
    var conversationTitleBinding: Binding<String> {
        Binding(get: { conversationTitle }, set: { newValue in
            guard newValue != conversationTitle else { return }
            conversationTitle = newValue
            conversationTitleState = .user
            titleCoordinator.cancel(currentSessionID)
        })
    }

    /// Names the open conversation in the background if it still has its default title and enough
    /// final words. The source is the last completed Summary; otherwise the Summary pane's model,
    /// only with Apple Intelligence or local Ollama; otherwise on-device keywords.
    func nameConversationIfNeeded() {
        guard ProviderSettings.autoNameConversations, ProviderSettings.saveSessionsForSearch, sessionSaveable else { return }
        let spoken = store.utterances.filter(\.isFinal).map(\.text).joined(separator: "\n")
        let words = ConversationAutoTitle.wordCount(spoken)
        let target = currentSessionID, title = conversationTitle, state = conversationTitleState
        guard ConversationAutoTitle.shouldName(state: state, title: title, words: words) else { return }
        let provider = ConversationAutoTitle.mayAskModel(ProviderSettings.aiMode) ? session.conversationTitleProvider : nil
        // Never a refresh still streaming in: half a sentence must not become the title.
        let summary = session.completedListenerSummary
        let language = ProviderSettings.transcriptionLocale().identifier
        let startedAt = conversationStartedAt
        let snapshot = ConversationTitleCoordinator.Snapshot(title: title, state: state, spoken: spoken, summary: summary)
        titleCoordinator.name(target, snapshot: snapshot, language: language, provider: provider) { result in
            let named = result.title, newState = result.state
            if target == currentSessionID {
                // A title field being edited would write its own text back when editing ends.
                guard conversationTitle == title, conversationTitleState == state, !titleFieldFocused else { return }
                if let named { conversationTitle = named }
                conversationTitleState = newState
                _ = checkpoint(complete: !wantsCapture && !lifecycleBusy, force: true)
                return
            }
            // A New conversation started meanwhile: rename the saved record, unless renamed since.
            guard let record = sessionStore.all().first(where: { $0.id == target }), record.title == title,
                  record.resolvedTitleState == state else { return }
            let updated = record.retitled(named ?? title, state: newState)
            if sessionStore.add(updated), named != nil {
                MarkdownVaultSync.shared.save(updated, startedAt: startedAt)   // the record's own language (#206)
            }
        }
    }
}
