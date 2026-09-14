import Foundation
import ListenToMeCore
#if canImport(FoundationModels)
import FoundationModels

/// Native transport; scheduling, context and decision validation stay provider-independent.
@available(macOS 26, iOS 26, *)
public struct AppleIntelligenceProvider: LLMProvider {
    public let id = "apple-intelligence"
    /// The on-device Foundation model has a ~4k-token window shared by input and output, so the
    /// prompt is capped at the same character budget iOS already enforces (issue #119).
    public let maxPromptCharacters: Int? = PromptBudget.appleIntelligenceCharacters
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
                    let prompt = request.messages.map(\.content).joined(separator: "\n")
                    // Callers bound the assembled prompt with PromptBudget before it gets here.
                    // If one did not, say so rather than silently answering from a prompt whose
                    // front — including the transcript header — was cut away (issue #119).
                    guard request.system.count + prompt.count
                            <= PromptBudget.appleIntelligenceCharacters - PromptBudget.answerReserve else {
                        throw QuickSummaryError.message(
                            "This request is too long for Apple Intelligence's on-device context " +
                            "window. Shorten your notes or attached reference material, or choose Ollama.")
                    }
                    let session = LanguageModelSession(instructions: request.system)
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
