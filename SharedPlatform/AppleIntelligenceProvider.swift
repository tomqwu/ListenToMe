import Foundation
import ListenToMeCore
#if canImport(FoundationModels)
import FoundationModels

/// Native transport; scheduling, context and decision validation stay provider-independent.
@available(macOS 26, iOS 26, *)
public struct AppleIntelligenceProvider: LLMProvider {
    public let id = "apple-intelligence"
    public init() {}
    public static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.deviceNotEligible): return "Apple Intelligence is unavailable on this device. Choose Ollama to use another model."
        case .unavailable(.appleIntelligenceNotEnabled): return "Enable Apple Intelligence in Settings, or choose Ollama."
        case .unavailable(.modelNotReady): return "Apple Intelligence is still preparing its model."
        default: return "Apple Intelligence is unavailable. Choose another provider in Settings."
        }
    }
    public static let automaticQuickUnavailableReason = "Auto Quick Summary requires Ollama. Apple Intelligence is available for manual summaries."

    public func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard request.purpose != .quickEvaluation else {
                        throw QuickSummaryError.message(Self.automaticQuickUnavailableReason)
                    }
                    if let reason = Self.unavailableReason { throw QuickSummaryError.message(reason) }
                    let session = LanguageModelSession(instructions: request.system)
                    let prompt = request.messages.map(\.content).joined(separator: "\n")
                    let response = try await session.respond(to: prompt).content
                    try Task.checkCancellation()
                    continuation.yield(response); continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

#endif
