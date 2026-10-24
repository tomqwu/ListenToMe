import Foundation
import ListenToMeCore

/// Context-aware "Suggested" prompt chips on iOS (#61). The chips ride on passes that already run —
/// the Auto Quick evaluation (inside `QuickSummaryReader.read`) and a manual Quick Summary refresh the
/// user asked for — so no model is ever called just to make them. A tap sends the literal text to the
/// Quick model as a separate ask (`MobileSuggestedAsk`), answered in a small card under Quick Summary;
/// nothing is sent by itself.
extension MobileSession {
    /// The chips shown under the Quick Summary.
    var suggestedPrompts: [String] { quickReader.suggestions.prompts }

    /// Why no chip can be sent right now (an answer or a summary is generating, recording is stopping,
    /// nothing has been said, or the Quick provider is unavailable), or nil.
    var suggestionBlockReason: String? {
        if suggestedAsk.isAnswering { return "Wait for the current answer, or cancel it." }
        return summaryBlockReason(for: .quick)
    }

    /// Sends a tapped chip's literal text to the Quick model as a separate ask. Its answer appears in
    /// the Ask card under Quick Summary; Quick Summary, Summary, the saved conversation and Auto's review
    /// state are untouched. A long conversation is answered from what fits, exactly like an on-demand
    /// Quick answer (`OnDemandGrounding`). A blocked tap sends nothing, says why and keeps the
    /// chip; the chip is used up only once its answer has arrived, so a failed or cancelled ask can be
    /// tapped again.
    /// - Returns: true when the request was sent.
    @discardableResult
    func askSuggested(_ prompt: String) -> Bool {
        if let reason = suggestionBlockReason { message = reason; return false }
        let client: any LLMProvider
        do {
            client = try summaryProvider
                ?? (askUsesCloud ? ai.client(for: .quick) : (onDeviceProviderOverride ?? AppleIntelligenceProvider()))
        } catch {
            message = "Could not ask: \(MobileAISettings.errorMessage(error))"
            return false
        }
        message = nil
        let (request, grounding) = askRequest(prompt)
        suggestedAsk.start(question: prompt, request: request, grounding: grounding,
                           client: client) { [weak self] in self?.quickReader.useSuggestion(prompt) }
        return true
    }

    private var askUsesCloud: Bool { summaryProvider != nil || ai.provider != .apple }

    /// The copilot's answer prompt over the notes and the speech that fits the provider (fenced as
    /// data), then the tapped request; plus the card's line saying which part of the conversation was read.
    func askRequest(_ prompt: String) -> (LLMRequest, String?) {
        let system = Self.askSystem
        let instruction = "\n\n" + PromptBuilder.askInstruction(prompt) + " Answer briefly."
        let window: Int? = askUsesCloud ? nil : PromptBudget.appleIntelligenceCharacters
        let excerpt = OnDemandGrounding.excerpt(
            notes: notes, segments: allSegments.map(Self.promptSegment), summary: summary,
            summaryCoveredIDs: answerNotices.summaryCoverage(showing: summary),
            budget: OnDemandGrounding.oneShotBudget(window: window, system: system) - instruction.count)
        let request = LLMRequest(system: system,
                                 messages: [ChatMessage(role: "user", content: excerpt.userMessage + instruction)])
        return (request, excerpt.notice(summaryName: "your Summary"))
    }

    /// The macOS Quick copilot prompt with the data-not-instructions notice, so a chip is answered the
    /// way a fixed Quick action is.
    static var askSystem: String {
        PromptBuilder.systemWithDirectives(PromptBuilder.systemPrompt, PromptContext(messages: [], notes: nil))
    }

    /// The manual Quick Summary's text (`quickOutput`), offering the suggestions the answer carries:
    /// the JSON decision's `suggestions` for Ollama, OpenAI-compatible and cloud models, or the strict
    /// final "Suggested:" block for Apple Intelligence's prose. Anything unparseable means no chips, and
    /// chips from a refresh that started before a provider or model change are dropped by the reader.
    func quickOutputOfferingChips(_ response: String, prose: Bool, cutOff: Bool) throws -> String {
        let output = try Self.quickOutput(response, prose: prose, cutOff: cutOff)
        let suggestions = prose ? SuggestedPrompts.splitProse(response).suggestions
            : ((try? QuickSummaryDecision.parse(response))?.suggestions ?? [])
        quickReader.offerSuggestions(suggestions)
        return output
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
