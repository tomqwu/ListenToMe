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

    /// The summary provider as a privacy mode: Ollama on the user's own server counts as local.
    var autoTitleMode: AIProcessingMode {
        switch ai.provider {
        case .apple: return .apple
        case .ollama: return ai.usesCustomEndpoint ? .local : .cloud
        case .openAI: return .openAI
        case .cloud: return .cloudAI
        }
    }

    /// The provider the user chose for summaries, when naming may ask it: Apple Intelligence on this
    /// device (the default) or the user's own Ollama server, and only when it can answer now. With
    /// Ollama Cloud, a Cloud AI service or an OpenAI-compatible server this is nil, so a title comes
    /// from the summary or on-device keywords and Stop sends nothing anywhere.
    var autoTitleProvider: (any LLMProvider)? {
        // A test session's injected `summaryProvider` counts its own requests; titles leave it alone.
        guard summaryProvider == nil, ConversationAutoTitle.mayAskModel(autoTitleMode) else { return nil }
        if ai.provider == .apple, let onDeviceProviderOverride { return onDeviceProviderOverride }
        // While the app hosts unit tests no real model is asked; tests inject `onDeviceProviderOverride`.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              summaryAvailability(for: .summary) == nil else { return nil }
        return ai.provider == .apple ? AppleIntelligenceProvider() : try? ai.client(for: .summary)
    }

    /// Names `recordID` (the open conversation by default) in the background if it still has its
    /// default name and enough words. `language` defaults to the conversation's. Never while
    /// recording: a return from Control Center mid-recording must not name half a transcript.
    func nameConversationIfNeeded(_ recordID: String? = nil, language: String? = nil) {
        guard Self.namesConversationsAutomatically, isForeground, state == .idle else { return }
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
            guard !Task.isCancelled else { return }
            self.applyAutoTitle(named?.title, to: target, from: snapshot)
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
    /// `nil` (nothing usable) keeps the name and records the attempt, so naming is not tried again
    /// on every Save or return to the app until the transcript has grown.
    private func applyAutoTitle(_ named: String?, to target: String, from snapshot: AutoTitleSnapshot) {
        let state = named == nil ? ConversationAutoTitle.attemptedState(after: snapshot.state, words: snapshot.words)
            : ConversationAutoTitle.namedState(after: snapshot.state, words: snapshot.words)
        if target == id {
            guard title == snapshot.title, titleState == snapshot.state else { return }
            if let named { title = named }
            titleState = state
            save(announce: false)
            return
        }
        guard let record = history.first(where: { $0.id == target }), record.title == snapshot.title,
              record.resolvedTitleState == snapshot.state else { return }
        let updated = record.retitled(named ?? record.title, state: state)
        do {
            try archive.save(updated)
            remember(updated)
            if named != nil { Self.markdownVault.save(updated) }   // the record's own language (#206)
        } catch {
            // The default name stays; the next save tries again.
        }
    }
}
