import Foundation

/// A streaming chat model. Implementations yield token/text deltas as they arrive.
public protocol LLMProvider: Sendable {
    var id: String { get }
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error>
}
