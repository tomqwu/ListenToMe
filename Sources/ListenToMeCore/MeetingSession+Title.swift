import Foundation

public extension MeetingSession {
    /// The provider that names a saved conversation automatically (#221): the Summary pane's, which
    /// the user chose. Nil when AI is off or that model is unavailable, so naming falls back to
    /// on-device keywords and never reaches a provider the user has not picked.
    var conversationTitleProvider: (any LLMProvider)? {
        guard aiEnabled, let model = models[.listener], !model.isEmpty,
              providerAvailability(model) == nil else { return nil }
        return providers[.listener]
    }

    /// The last Summary that finished streaming, for naming. `listenerSummary` can be a refresh
    /// still arriving word by word, and half a sentence must not become the title.
    var completedListenerSummary: String { lastCompletedListenerSummary }
}
