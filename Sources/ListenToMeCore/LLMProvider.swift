import Foundation

/// One piece of a streamed response. Reasoning models ("thinking" models such as `deepseek-r1` or
/// `qwen3`) emit reasoning deltas before — sometimes instead of — the answer. They are carried
/// separately so a pane can show "Thinking…" instead of staying blank for a minute, and so the
/// reasoning is never persisted into the answer text (issue #137).
public enum LLMStreamEvent: Sendable, Equatable {
    case content(String)
    case thinking(String)
}

/// A streaming chat model. Implementations yield token/text deltas as they arrive.
public protocol LLMProvider: Sendable {
    var id: String { get }
    /// Total prompt characters this provider can accept, or nil when it has no practical limit.
    /// Callers clamp the prompts they assemble to this window (see `PromptBudget`).
    var maxPromptCharacters: Int? { get }
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error>
    /// The answer *and* any reasoning the model reports. Providers that cannot distinguish the two
    /// inherit the default, which labels everything `stream` yields as content.
    func streamEvents(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error>
}

public extension LLMProvider {
    /// Most providers (Ollama, local or cloud) take prompts far larger than anything we build.
    var maxPromptCharacters: Int? { nil }

    func streamEvents(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        let deltas = stream(request)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await delta in deltas { continuation.yield(.content(delta)) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
