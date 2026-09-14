import Foundation
import ListenToMeCore
#if canImport(FoundationModels)
import FoundationModels

/// Native transport; scheduling, context and decision validation stay provider-independent.
@available(macOS 26, iOS 26, *)
public struct AppleIntelligenceProvider: LLMProvider {
    public let id = "apple-intelligence"
    public init() {}
    /// Whether the provider can run at all. Deliberately independent of any locale: the device's UI
    /// language says nothing about the language a meeting is held in, and this value decides the
    /// fresh-install default and the macOS status line.
    public static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.deviceNotEligible): return "Apple Intelligence is unavailable on this device. Choose Ollama to use another model."
        case .unavailable(.appleIntelligenceNotEnabled): return "Enable Apple Intelligence in Settings, or choose Ollama."
        case .unavailable(.modelNotReady): return "Apple Intelligence is still preparing its model."
        default: return "Apple Intelligence is unavailable. Choose another provider in Settings."
        }
    }

    /// Why the on-device model cannot work in the language of *this conversation*, or nil when it can.
    /// Only a caller that knows the conversation's language should ask; `isSupported` is injectable so
    /// the gate is testable on a host without Apple Intelligence.
    public static func unsupportedLocaleReason(
        for locale: Locale,
        isSupported: (Locale) -> Bool = { SystemLanguageModel.default.supportsLocale($0) }
    ) -> String? {
        guard !isSupported(locale) else { return nil }
        let language = locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
        return "Apple Intelligence does not support \(language) yet. Choose Ollama to summarize in this language."
    }

    /// FoundationModels reports generation failures as `GenerationError`, whose `localizedDescription`
    /// is developer-facing ("Exceeded context window size"). Every case a meeting can hit gets a
    /// message that says what happened and what to do; nil means "not an Apple generation failure".
    public static func message(for error: Error) -> String? {
        guard let failure = error as? LanguageModelSession.GenerationError else { return nil }
        switch failure {
        case .exceededContextWindowSize:
            return "This conversation is longer than Apple Intelligence's on-device context window. "
                + "Summarize a shorter stretch, or choose Ollama in Settings."
        case .guardrailViolation:
            return "Apple Intelligence declined to process this conversation. Choose Ollama in Settings to summarize it."
        case .unsupportedLanguageOrLocale:
            return "Apple Intelligence does not support this conversation's language yet. Choose Ollama in Settings."
        case .assetsUnavailable:
            return "Apple Intelligence's on-device model is not downloaded yet. Try again once it finishes preparing."
        case .rateLimited:
            return "Apple Intelligence is busy. Wait a moment and generate again."
        case .concurrentRequests:
            return "Another on-device request is still running. Wait for it to finish and generate again."
        case .decodingFailure, .unsupportedGuide:
            return "Apple Intelligence returned an unusable response. Generate again, or choose Ollama in Settings."
        case .refusal:
            return "Apple Intelligence refused to answer for this conversation. Choose Ollama in Settings to summarize it."
        @unknown default:
            return "Apple Intelligence could not complete this summary. Try again, or choose Ollama in Settings."
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
                } catch {
                    // Generation failures reach the UI through this one transport on both platforms,
                    // so they are translated here instead of in each platform's error formatter.
                    if let message = Self.message(for: error) {
                        continuation.finish(throwing: QuickSummaryError.message(message))
                    } else { continuation.finish(throwing: error) }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

#endif
