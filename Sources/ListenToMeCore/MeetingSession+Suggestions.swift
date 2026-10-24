import Foundation

// Context-aware "Suggested" prompt chips on macOS (#61). The chips come from the Quick evaluator's
// decision (see `SuggestedPrompts`), so they exist only while Auto is on and AI is on: no model is
// ever called to make them. A tap sends the literal text through the ordinary Quick or Deep pane.

extension MeetingSession {
    /// The chips to show above the fixed Quick actions; empty while AI is off.
    public var suggestedPrompts: [String] { aiEnabled ? quickReader.suggestions.prompts : [] }

    /// Sends a tapped chip's literal text through the normal Quick path (or Deep when `deep`), with
    /// the same grounding, budget and manual-answer rules as the fixed actions. The chip leaves the
    /// row and is not suggested again in this conversation. Nothing happens while AI is off.
    public func askSuggested(_ prompt: String, deep: Bool = false) async {
        guard aiEnabled else { return }
        quickReader.useSuggestion(prompt)
        if deep { await respondDeep(.ask(prompt)) } else { await respondQuick(.ask(prompt)) }
    }
}
