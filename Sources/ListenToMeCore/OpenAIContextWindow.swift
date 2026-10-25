import Foundation

/// An explicit server capacity, not a claim about a model's advertised maximum. Local runners
/// often configure a smaller window. Unknown capacity keeps the existing server-managed behavior.
public struct OpenAIContextWindow: Sendable, Equatable {
    public static let choices = [4_096, 8_192, 16_384, 32_768, 65_536, 131_072, 262_144]
    public let tokens: Int

    public init?(tokens: Int) {
        guard Self.choices.contains(tokens) else { return nil }
        self.tokens = tokens
    }

    public func outputTokens(requested: Int?) -> Int {
        min(max(1, requested ?? 4_096), tokens / 4)
    }

    /// A planning hint for existing character-based trimming. The final UTF-8 check below is
    /// authoritative, including for Chinese, emoji and combining characters.
    public var maxPromptCharacters: Int { tokens - outputTokens(requested: nil) - 1_024 - 256 }

    public func validate(_ request: LLMRequest, requestedOutput: Int?) throws {
        let content = [request.system] + request.messages.map(\.content)
        // One byte per token is deliberately conservative without a server-specific tokenizer.
        // Leave room for role delimiters and the server's chat template in addition to the answer.
        var remaining = tokens - outputTokens(requested: requestedOutput) - 1_024
        for text in content {
            remaining -= 128
            guard remaining >= 0, text.utf8.count <= remaining else {
                throw OpenAICompatibleError.server("This request exceeds the configured server context window "
                    + "(\(tokens) tokens). No text was sent. Use a shorter selection or increase the limit "
                    + "only if your server is configured to support it.")
            }
            remaining -= text.utf8.count
        }
    }
}
