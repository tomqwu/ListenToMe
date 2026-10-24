import Foundation
import ListenToMeCore

/// Context-aware "Suggested" prompt chips on iOS (#61). The chips ride on passes that already run —
/// the Auto Quick evaluation (inside `QuickSummaryReader.read`) and a manual Quick Summary refresh the
/// user asked for — so no model is ever called just to make them. A tap sends the literal text to the
/// Deep model as a separate ask (`MobileSuggestedAsk`); nothing is sent by itself.
extension MobileSession {
    /// The chips shown under the Quick Summary.
    var suggestedPrompts: [String] { quickReader.suggestions.prompts }

    /// Why no chip can be sent right now (an answer or a summary is generating, recording is stopping,
    /// nothing has been said, or the Deep provider is unavailable), or nil.
    var suggestionBlockReason: String? { suggestionBlockReason(for: nil) }

    /// As `suggestionBlockReason`, plus the provider's size limit for this particular request.
    func suggestionBlockReason(for prompt: String?) -> String? {
        if suggestedAsk.isAnswering { return "Wait for the current answer, or cancel it." }
        if let reason = summaryBlockReason(for: .deep) { return reason }
        guard let prompt else { return nil }
        let request = Self.askRequest(source: summarySource, prompt: prompt)
        let size = request.system.count + request.messages.reduce(0) { $0 + $1.content.count }
        let limit = askUsesCloud ? 60_000 : PromptBudget.appleIntelligenceCharacters
        guard size <= limit else {
            return "This conversation exceeds the selected provider's summary limit. Export it or shorten your notes."
        }
        return nil
    }

    /// Sends a tapped chip's literal text to the Deep model as a separate ask: the answer appears under
    /// the question in the Deep tab and leaves Deep Summary, its saved text and Auto's review state
    /// untouched. A blocked tap sends nothing, says why and keeps the chip; the chip is used up only
    /// once its answer has arrived, so a failed or cancelled ask can be tapped again.
    /// - Returns: true when the request was sent.
    @discardableResult
    func askSuggested(_ prompt: String) -> Bool {
        if let reason = suggestionBlockReason(for: prompt) { message = reason; return false }
        let client: any LLMProvider
        do {
            client = try summaryProvider
                ?? (askUsesCloud ? ai.client(for: .deep) : (onDeviceProviderOverride ?? AppleIntelligenceProvider()))
        } catch {
            message = "Could not ask: \(MobileAISettings.errorMessage(error))"
            return false
        }
        message = nil
        suggestedAsk.start(question: prompt, request: Self.askRequest(source: summarySource, prompt: prompt),
                           client: client) { [weak self] in self?.quickReader.useSuggestion(prompt) }
        return true
    }

    private var askUsesCloud: Bool { summaryProvider != nil || ai.provider != .apple }

    /// The Deep model's instructions over the fenced transcript, then the tapped request.
    static func askRequest(source: String, prompt: String) -> LLMRequest {
        LLMRequest(system: MobileSummaryMode.deep.instructions, messages: [ChatMessage(role: "user",
            content: PromptData.block("transcript", source) + "\n\n" + PromptBuilder.askInstruction(prompt))])
    }

    /// Reads a manual Quick Summary answer into the pane's text and offers the suggestions it carries:
    /// the JSON decision's `suggestions` for Ollama, OpenAI-compatible and cloud models, or the strict
    /// "Suggested:" block for Apple Intelligence's prose. Anything unparseable means no chips, and
    /// chips from a refresh that started before a provider or model change are dropped by the reader.
    func manualQuickSummary(_ response: String, prose: Bool) throws -> String {
        guard !prose else {
            quickReader.offerSuggestions(SuggestedPrompts.splitProse(response).suggestions)
            return MobileQuickContext.proseSummary(response) ?? "No key takeaway yet."
        }
        let decision = try QuickSummaryDecision.parse(response)
        quickReader.offerSuggestions(decision.suggestions)
        return decision.summary ?? "No key takeaway yet."
    }

    /// A new or reopened conversation: no chips, no used-chip memory and no open ask.
    func resetSuggestions() {
        quickReader.reset()
        suggestedAsk.reset()
    }

    /// The provider or a model changed: the old model's chips and any ask still streaming from it go.
    func suggestionsProviderChanged() {
        quickReader.providerChanged()
        suggestedAsk.cancel()
    }
}
