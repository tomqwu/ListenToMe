import Foundation

/// The shared "the model stopped at its output limit" signal (issue #215).
///
/// A server that ends a response because it hit the output-token cap — OpenAI-compatible
/// `finish_reason: "length"`, Ollama `done_reason: "length"`, Anthropic `stop_reason: "max_tokens"`
/// (or `"model_context_window_exceeded"`) — has produced a *partial* answer. `streamEvents` reports
/// it as a final `LLMStreamEvent.outputLimitReached` and then finishes normally, so a pane keeps the
/// partial text and shows `notice`. The plain-text `stream(_:)` has no way to say "partial", so it
/// ends with `LLMOutputLimitError` instead of passing a cut-off answer off as whole.
///
/// Apple Intelligence needs no equivalent: its input and output share one window, and running out
/// of it already fails with `exceededContextWindowSize`, which has its own message.
public enum LLMOutputLimit {
    /// The one-line notice shown beside a cut-off answer on both platforms.
    public static let notice = "The answer was cut off at the model's output limit."

    /// True for the OpenAI-compatible `finish_reason` / Ollama `done_reason` that means "out of tokens".
    static func isLengthStop(_ reason: String?) -> Bool { reason == "length" }

    /// Plain-text deltas for `stream(_:)`: answer text only, and `cutOff` once a stream reports that it
    /// stopped at the output limit (after every delta it produced has been passed on).
    static func textStream(_ events: AsyncThrowingStream<LLMStreamEvent, Error>,
                           cutOff: Error = LLMOutputLimitError()) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in events {
                        switch event {
                        case .content(let delta): continuation.yield(delta)
                        case .thinking: break
                        case .outputLimitReached: throw cutOff
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Drains `events` into the answer text, recording whether it was cut off. Thinking is dropped.
    /// `limit` bounds the text, as every caller already bounds what it accepts.
    public static func collect(_ events: AsyncThrowingStream<LLMStreamEvent, Error>, limit: Int,
                               tooLarge: @autoclosure () -> Error) async throws -> (text: String, cutOff: Bool) {
        var text = ""
        var cutOff = false
        for try await event in events {
            try Task.checkCancellation()
            switch event {
            case .content(let delta):
                text += delta
                guard text.count <= limit else { throw tooLarge() }
            case .thinking: break
            case .outputLimitReached: cutOff = true
            }
        }
        return (text, cutOff)
    }
}

/// What `stream(_:)` throws for a response that stopped at the model's output limit. Callers of
/// `streamEvents` never see it: they get `LLMStreamEvent.outputLimitReached` and keep the text.
public struct LLMOutputLimitError: LocalizedError, Equatable {
    public init() {}
    public var errorDescription: String? {
        LLMOutputLimit.notice + " Retry, ask for a shorter answer, or raise the model's output limit."
    }
}
