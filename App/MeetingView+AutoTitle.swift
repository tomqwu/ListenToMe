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
            autoTitleTask?.cancel()
            autoTitleTask = nil
        })
    }

    /// Names the open conversation in the background if it still has its default title and enough
    /// final words. The Summary pane's provider names it when AI is on and that model is available;
    /// otherwise the summary or on-device keywords do.
    func nameConversationIfNeeded() {
        guard ProviderSettings.autoNameConversations, ProviderSettings.saveSessionsForSearch, sessionSaveable else { return }
        let spoken = store.utterances.filter(\.isFinal).map(\.text).joined(separator: "\n")
        let words = ConversationAutoTitle.wordCount(spoken)
        let target = currentSessionID, title = conversationTitle, state = conversationTitleState
        guard ConversationAutoTitle.shouldName(state: state, title: title, words: words) else { return }
        let provider = session.conversationTitleProvider
        let summary = session.listenerSummary
        let language = ProviderSettings.transcriptionLocale().identifier
        let startedAt = conversationStartedAt
        autoTitleTask = Task {
            guard let named = await ConversationAutoTitle.title(transcript: spoken, summary: summary,
                                                                language: language, provider: provider),
                  !Task.isCancelled else { return }
            let newState = ConversationAutoTitle.namedState(after: state, words: words)
            if target == currentSessionID {
                guard conversationTitle == title, conversationTitleState == state else { return }
                conversationTitle = named.title
                conversationTitleState = newState
                _ = checkpoint(complete: !wantsCapture && !lifecycleBusy, force: true)
                return
            }
            // A New conversation started meanwhile: rename the saved record, unless renamed since.
            guard let record = sessionStore.all().first(where: { $0.id == target }), record.title == title,
                  record.resolvedTitleState == state else { return }
            let updated = record.retitled(named.title, state: newState)
            if sessionStore.add(updated) {
                MarkdownVaultSync.shared.save(updated, language: language, startedAt: startedAt)
            }
        }
    }
}
