import Foundation

/// Shared ownership of optional naming tasks. Adapters retain privacy/provider selection and apply
/// results only while the saved/open title still matches the snapshot supplied here.
@MainActor
public final class ConversationTitleCoordinator {
    public struct Snapshot: Sendable {
        public let title: String
        public let state: ConversationTitleState
        public let spoken: String
        public let summary: String
        public let words: Int

        public init(title: String, state: ConversationTitleState, spoken: String, summary: String) {
            self.title = title; self.state = state; self.spoken = spoken; self.summary = summary
            words = ConversationAutoTitle.wordCount(spoken)
        }

        public init(title: String, state: ConversationTitleState, segments: [TranscriptSegment], summary: String) {
            self.init(title: title, state: state,
                      spoken: segments.filter(\.isFinal).map(\.text).joined(separator: "\n"), summary: summary)
        }
    }

    public struct Result: Sendable {
        public let title: String?
        public let state: ConversationTitleState
    }

    public typealias Generator = @Sendable (Snapshot, String?, (any LLMProvider)?) async -> String?
    private struct Entry { let generation: UUID; let task: Task<Void, Never> }
    private var entries: [String: Entry] = [:]
    private let generate: Generator

    public init(generate: @escaping Generator = { snapshot, language, provider in
        await ConversationAutoTitle.title(transcript: snapshot.spoken, summary: snapshot.summary,
                                          language: language, provider: provider)?.title
    }) { self.generate = generate }

    public func isNaming(_ id: String) -> Bool { entries[id] != nil }
    public func wait(for id: String) async { await entries[id]?.task.value }

    /// Returns the existing task for a repeated request. Different conversations may finish independently.
    @discardableResult
    public func name(_ id: String, snapshot: Snapshot, language: String?, provider: (any LLMProvider)?,
                     apply: @escaping @MainActor (Result) -> Void) -> Task<Void, Never>? {
        guard ConversationAutoTitle.shouldName(state: snapshot.state, title: snapshot.title, words: snapshot.words)
        else { return nil }
        if let entry = entries[id] { return entry.task }
        let generation = UUID(), generate = generate
        let task = Task { [weak self] in
            let named = await generate(snapshot, language, provider)
            guard let self, self.entries[id]?.generation == generation else { return }
            self.entries[id] = nil
            guard !Task.isCancelled else { return }
            let state = named == nil ? ConversationAutoTitle.attemptedState(after: snapshot.state, words: snapshot.words)
                : ConversationAutoTitle.namedState(after: snapshot.state, words: snapshot.words)
            apply(Result(title: named, state: state))
        }
        entries[id] = Entry(generation: generation, task: task)
        return task
    }

    public func cancel(_ id: String) {
        let entry = entries.removeValue(forKey: id)
        entry?.task.cancel()
    }
}
