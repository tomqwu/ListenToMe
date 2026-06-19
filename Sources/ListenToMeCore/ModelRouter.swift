import Foundation
import Observation

/// Holds the registered providers and routes streaming requests to the active one.
@Observable
public final class ModelRouter {
    private var providers: [String: any LLMProvider] = [:]
    public private(set) var activeID: String

    public init(default provider: any LLMProvider) {
        activeID = provider.id
        providers[provider.id] = provider
    }

    public func register(_ provider: any LLMProvider) {
        providers[provider.id] = provider
    }

    /// Switches the active provider if `id` is registered; otherwise a no-op.
    public func setActive(_ id: String) {
        if providers[id] != nil { activeID = id }
    }

    public func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        guard let provider = providers[activeID] else {
            return AsyncThrowingStream { $0.finish() }
        }
        return provider.stream(request)
    }
}
