import Foundation

/// How one OpenAI-compatible vendor differs from the plain `/v1/chat/completions` shape (issue #214).
///
/// The generic custom server (#52) uses `.standard`. The cloud presets (`CloudAIPreset`) each pick
/// a dialect so a request never carries a field that vendor is documented to reject, and Auto Quick's
/// evaluator asks that vendor to skip reasoning in the way it understands. A vendor that still
/// refuses the hint with 400/422 gets the request once more without it (`OpenAICompatibleProvider`).
public struct OpenAICompatibleDialect: Sendable, Equatable {
    /// How the Quick evaluator asks a model not to reason before answering.
    public enum QuickReasoning: Sendable, Equatable {
        /// `reasoning_effort: "none"` plus `chat_template_kwargs.enable_thinking: false`: Ollama's
        /// `/v1`, vLLM and llama.cpp ignore what they do not know.
        case generic
        /// Only `reasoning_effort: <value>` (OpenAI, Gemini, Groq).
        case effort(String)
        /// `thinking: {"type": "disabled"}` (DeepSeek).
        case thinkingDisabled
        /// `reasoning: {"effort": "none"}` (OpenRouter).
        case openRouter
        /// No hint: the vendor rejects unknown fields or cannot turn reasoning off (Mistral, xAI).
        case none
    }

    /// `max_tokens`, or `max_completion_tokens` for OpenAI, whose newer models reject `max_tokens`.
    public let maximumTokensField: String
    /// False where reasoning models accept only the default temperature (OpenAI's GPT-5 family).
    public let sendsTemperature: Bool
    public let quickReasoning: QuickReasoning
    /// Extra request headers, such as OpenRouter's optional app attribution. Never credentials.
    public let headers: [String: String]

    public init(maximumTokensField: String = "max_tokens", sendsTemperature: Bool = true,
                quickReasoning: QuickReasoning = .generic, headers: [String: String] = [:]) {
        self.maximumTokensField = maximumTokensField
        self.sendsTemperature = sendsTemperature
        self.quickReasoning = quickReasoning
        self.headers = headers
    }

    /// A custom server the user typed (#52).
    public static let standard = OpenAICompatibleDialect()

    /// Adds the Quick evaluator's reasoning hint to a request body.
    func addQuickReasoningHints(to body: inout [String: Any]) {
        switch quickReasoning {
        case .generic:
            body["reasoning_effort"] = "none"
            body["chat_template_kwargs"] = ["enable_thinking": false]
        case .effort(let value): body["reasoning_effort"] = value
        case .thinkingDisabled: body["thinking"] = ["type": "disabled"]
        case .openRouter: body["reasoning"] = ["effort": "none"]
        case .none: break
        }
    }
}
