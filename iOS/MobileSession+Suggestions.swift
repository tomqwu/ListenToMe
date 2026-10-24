import Foundation
import ListenToMeCore

/// Context-aware "Suggested" prompt chips on iOS (#61). The chips ride on passes that already run —
/// the Auto Quick evaluation (inside `QuickSummaryReader.read`) and a manual Quick Summary refresh the
/// user asked for — so no model is ever called just to make them. A tap sends the literal text
/// through the Deep path; nothing is sent by itself.
extension MobileSession {
    /// The chips shown under the Quick Summary.
    var suggestedPrompts: [String] { quickReader.suggestions.prompts }

    /// Why a chip cannot be sent right now (a response is generating, recording is stopping, or the
    /// Deep provider is unavailable), or nil when a tap will be sent.
    var suggestionBlockReason: String? { summaryBlockReason(for: .deep) }

    /// Sends a tapped chip's literal text through Deep, the iOS path that answers a request. The chip
    /// leaves the row and is not suggested again in this conversation. A blocked tap sends nothing,
    /// keeps the chip and says why.
    func askSuggested(_ prompt: String) {
        if let reason = suggestionBlockReason { message = reason; return }
        quickReader.useSuggestion(prompt)
        requestSummary(for: .deep, question: prompt)
    }

    /// Reads a manual Quick Summary answer into the pane's text and offers the suggestions it carries:
    /// the JSON decision's `suggestions` for Ollama, OpenAI-compatible and cloud models, or the strict
    /// "Suggested:" block for Apple Intelligence's prose. Anything unparseable means no chips.
    func manualQuickSummary(_ response: String, prose: Bool) throws -> String {
        guard !prose else {
            quickReader.offerSuggestions(SuggestedPrompts.splitProse(response).suggestions)
            return MobileQuickContext.proseSummary(response) ?? "No key takeaway yet."
        }
        let decision = try QuickSummaryDecision.parse(response)
        quickReader.offerSuggestions(decision.suggestions)
        return decision.summary ?? "No key takeaway yet."
    }

    /// The user message of a manual summary: the fenced transcript, then a tapped chip's request.
    static func userMessage(_ source: String, question: String?) -> String {
        let fenced = PromptData.block("transcript", source)
        guard let question else { return fenced }
        return fenced + "\n\n" + PromptBuilder.askInstruction(question)
    }

    /// A tapped chip's answer keeps its request on top, so the Deep pane — and the saved
    /// conversation — say what was asked.
    static func answer(_ draft: String, question: String?) -> String {
        guard let question else { return draft }
        return "**\(question)**\n\n" + draft
    }
}
