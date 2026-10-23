import Foundation

/// Which models on which OpenAI-compatible servers failed the Quick Summary JSON contract, so Auto
/// can pause with a reason instead of retrying a known-bad model every few seconds (issue #52).
///
/// Results are keyed by server origin and model ID, so testing one model never clears or condemns
/// another, and the list is bounded: the oldest entries go first.
public struct OpenAICompatibleContractLedger: Equatable, Sendable {
    public static let capacity = 32
    public private(set) var failures: [String]

    public init(failures: [String] = []) {
        self.failures = Array(failures.suffix(Self.capacity))
    }

    public static func key(_ endpoint: URL, model: String) -> String {
        OpenAICompatibleEndpoint.origin(of: endpoint) + "|" + model
    }

    public func hasFailed(_ endpoint: URL, model: String) -> Bool {
        !model.isEmpty && failures.contains(Self.key(endpoint, model: model))
    }

    public mutating func record(_ endpoint: URL, model: String, passed: Bool) {
        guard !model.isEmpty else { return }
        let key = Self.key(endpoint, model: model)
        failures.removeAll { $0 == key }
        if !passed { failures.append(key) }
        if failures.count > Self.capacity { failures.removeFirst(failures.count - Self.capacity) }
    }

    /// True for outcomes that show the model cannot hold the contract, as opposed to a network or
    /// server failure: an unusable decision, or an answer that was empty or only reasoning.
    public static func isContractFailure(_ error: Error) -> Bool {
        if error is QuickSummaryError { return true }
        switch error as? OpenAICompatibleError {
        case .thinkingOnly?, .empty?: return true
        default: return false
        }
    }
}
