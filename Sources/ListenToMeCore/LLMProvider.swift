import Foundation

/// A streaming chat model. Implementations yield token/text deltas as they arrive.
public protocol LLMProvider: Sendable {
    var id: String { get }
    /// Total prompt characters this provider can accept, or nil when it has no practical limit.
    /// Callers clamp the prompts they assemble to this window (see `PromptBudget`).
    var maxPromptCharacters: Int? { get }
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error>
}

public extension LLMProvider {
    /// Most providers (Ollama, local or cloud) take prompts far larger than anything we build.
    var maxPromptCharacters: Int? { nil }
}
