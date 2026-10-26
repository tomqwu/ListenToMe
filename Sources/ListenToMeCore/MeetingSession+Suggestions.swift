import Foundation

// Context-aware "Suggested" prompt chips on macOS (#61). The chips come from the Quick evaluator's
// decision (see `SuggestedPrompts`), so they exist only while Auto is on and AI is on: no model is
// ever called to make them. A tap sends the literal text through the ordinary Quick or Deep pane.

extension MeetingSession {
    /// The chips to show above the fixed Quick actions; empty while AI or Auto is off, because on
    /// macOS only the Auto evaluator makes them.
    public var suggestedPrompts: [String] {
        aiEnabled && autoSummaryEnabled ? quickReader.suggestions.prompts : []
    }

    @discardableResult
    public func requestSuggested(_ prompt: String, deep: Bool = false) -> Task<Void, Never>? {
        guard aiEnabled else { return nil }
        quickReader.useSuggestion(prompt)
        return deep ? requestDeep(.ask(prompt)) : requestQuick(.ask(prompt))
    }

    /// Sends a tapped chip's literal text through the normal Quick path (or Deep when `deep`), with
    /// the same grounding, budget and manual-answer rules as the fixed actions: on macOS a Deep chip
    /// behaves exactly like the **Deep answer** button, replacing the Deep pane and counting as a
    /// manual Deep answer, because the macOS Deep pane is an answer pane rather than a saved review.
    /// The chip leaves the row and is not suggested again in this conversation. Nothing happens while
    /// AI is off.
    public func askSuggested(_ prompt: String, deep: Bool = false) async {
        await requestSuggested(prompt, deep: deep)?.value
    }
}
