import Foundation

/// A synthetic check of the evaluator's exact response contract. Transport failures do not
/// condemn a model, and cancellation never produces a result that may be persisted.
public enum OpenAICompatibleContractProbe {
    public enum Outcome: Equatable, Sendable {
        case compatible
        case incompatible(String)
        case unavailable(String)

        public var ledgerResult: Bool? {
            switch self {
            case .compatible: return true
            case .incompatible: return false
            case .unavailable: return nil
            }
        }
    }

    public static func run(provider: any LLMProvider) async throws -> Outcome {
        try Task.checkCancellation()
        let outcome: Outcome
        do {
            let request = try QuickSummaryContext.manualRequest(
                source: "You: Let's move the launch to Friday. Dana will update the rollout checklist.")
            _ = try await QuickSummaryReader.evaluate(request, provider: provider)
            outcome = .compatible
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            outcome = OpenAICompatibleContractLedger.isContractFailure(error)
                ? .incompatible(error.localizedDescription) : .unavailable(error.localizedDescription)
        }
        try Task.checkCancellation()
        return outcome
    }
}
