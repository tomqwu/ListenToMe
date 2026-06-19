import Foundation
@testable import ListenToMeCore

/// Yields a fixed list of deltas, then finishes.
struct MockLLMProvider: LLMProvider {
    let id: String
    let deltas: [String]
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            for delta in deltas { continuation.yield(delta) }
            continuation.finish()
        }
    }
}
