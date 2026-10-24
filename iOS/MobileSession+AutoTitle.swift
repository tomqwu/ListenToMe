import Foundation
import ListenToMeCore

/// Naming a conversation that still has its default name once it is saved (#221). Runs after Stop,
/// Save, a finished Apple Watch recording and a return to the foreground; never blocks any of them.
/// The rule and the title itself come from `ConversationAutoTitle` in Core.
extension MobileSession {
    static let autoTitleKey = "mobileNameConversationsAutomatically"

    /// Settings → Conversations → Name conversations automatically. On unless turned off.
    static var namesConversationsAutomatically: Bool {
        UserDefaults.standard.object(forKey: autoTitleKey) as? Bool ?? true
    }

    /// The title field's edits. A typed title is the user's from then on, and a naming still under
    /// way for this conversation is cancelled.
    func renameByUser(_ newTitle: String) {
        guard newTitle != title else { return }
        title = newTitle
        titleState = .user
        autoTitleTasks[id]?.cancel()
        autoTitleTasks[id] = nil
    }

    /// The provider the user chose for summaries, when it can answer now: Apple Intelligence on this
    /// device by default, or the Ollama, Cloud AI or OpenAI-compatible service picked in Settings.
    /// Nil means on-device keywords. Never a service the user has not chosen.
    var autoTitleProvider: (any LLMProvider)? {
        // A test session's injected `summaryProvider` counts its own requests; titles leave it alone.
        guard summaryProvider == nil else { return nil }
        if ai.provider == .apple, let onDeviceProviderOverride { return onDeviceProviderOverride }
        // While the app hosts unit tests no real model is asked; tests inject `onDeviceProviderOverride`.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              summaryAvailability(for: .summary) == nil else { return nil }
        return ai.provider == .apple ? AppleIntelligenceProvider() : try? ai.client(for: .summary)
    }

    /// Names `recordID` (the open conversation by default) in the background if it still has its
    /// default name and enough words. `language` defaults to the conversation's.
    func nameConversationIfNeeded(_ recordID: String? = nil, language: String? = nil) {
        guard Self.namesConversationsAutomatically, isForeground else { return }
        let target = recordID ?? id
        guard autoTitleTasks[target] == nil, let snapshot = autoTitleSnapshot(target),
              ConversationAutoTitle.shouldName(state: snapshot.state, title: snapshot.title, words: snapshot.words)
        else { return }
        let provider = autoTitleProvider
        let language = language ?? (target == id ? conversationLanguage : transcriptionLanguage)
        autoTitleTasks[target] = Task { [weak self] in
            let named = await ConversationAutoTitle.title(transcript: snapshot.spoken, summary: snapshot.summary,
                                                          language: language, provider: provider)
            guard let self else { return }
            self.autoTitleTasks[target] = nil
            guard !Task.isCancelled, let named else { return }
            self.applyAutoTitle(named.title, to: target, from: snapshot)
        }
    }

    /// What naming starts from; the title is applied only if it is still exactly this.
    struct AutoTitleSnapshot: Sendable {
        let title: String
        let state: ConversationTitleState
        let spoken: String
        let summary: String
        let words: Int

        init(title: String, state: ConversationTitleState, segments: [TranscriptSegment], summary: String) {
            self.title = title
            self.state = state
            spoken = segments.filter(\.isFinal).map(\.text).joined(separator: "\n")
            self.summary = summary
            words = ConversationAutoTitle.wordCount(spoken)
        }
    }

    private func autoTitleSnapshot(_ target: String) -> AutoTitleSnapshot? {
        if target == id {
            return AutoTitleSnapshot(title: title, state: titleState, segments: segments, summary: summary)
        }
        guard let record = history.first(where: { $0.id == target }) else { return nil }
        return AutoTitleSnapshot(title: record.title, state: record.resolvedTitleState,
                                 segments: record.segments ?? [], summary: record.summary)
    }

    /// Applies the title where the conversation lives now, unless the user renamed it meanwhile.
    /// Saving it also updates the Save to folder note; its file name is keyed by the conversation.
    private func applyAutoTitle(_ named: String, to target: String, from snapshot: AutoTitleSnapshot) {
        let state = ConversationAutoTitle.namedState(after: snapshot.state, words: snapshot.words)
        if target == id {
            guard title == snapshot.title, titleState == snapshot.state else { return }
            title = named
            titleState = state
            save(announce: false)
            return
        }
        guard let record = history.first(where: { $0.id == target }), record.title == snapshot.title,
              record.resolvedTitleState == snapshot.state else { return }
        let updated = record.retitled(named, state: state)
        do {
            try archive.save(updated)
            remember(updated)
            Self.markdownVault.save(updated, language: transcriptionLanguage)
        } catch {
            // The default name stays; the next save tries again.
        }
    }
}
