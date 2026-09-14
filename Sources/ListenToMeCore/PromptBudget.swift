import Foundation

/// Splits a provider's prompt window across the transcript and any attached reference material.
///
/// Providers that can take arbitrarily large prompts (Ollama, local or cloud) declare no window and
/// keep the caller's budgets untouched. Providers with a small on-device window (Apple
/// Intelligence's ~4k-token Foundation model) get every prompt clamped, so a long meeting degrades
/// to "the most recent speech" instead of a permanent context-window error (issue #119).
public enum PromptBudget {
    /// Prompt characters the on-device Apple Intelligence model accepts. Matches the cap iOS
    /// already enforces on its Apple summary path.
    public static let appleIntelligenceCharacters = 8_000

    /// Characters held back for the system prompt, action instructions, notes, the rolling summary
    /// and the model's own answer — everything in the prompt that is not transcript or references.
    public static let overheadReserve = 2_400

    /// Reference material may claim at most this fraction of what is left; the transcript is the
    /// reason the user is here, so it must never be crowded out by an attached folder.
    public static let referenceShareDivisor = 3

    /// Shown when material had to be dropped to fit the window.
    public static let truncationNotice =
        "Trimmed to fit this model's context window — only the most recent speech is included."

    public struct Allocation: Sendable, Equatable {
        public let transcript: Int
        public let references: Int
        public init(transcript: Int, references: Int) {
            self.transcript = transcript
            self.references = references
        }
    }

    /// - Parameters:
    ///   - limit: the provider's total prompt window in characters; nil = unlimited.
    ///   - transcript: transcript characters the caller would like to send.
    ///   - references: reference characters available to send.
    public static func allocate(limit: Int?, transcript: Int, references: Int) -> Allocation {
        guard let limit else { return Allocation(transcript: transcript, references: references) }
        // Always leave some room for transcript even if the window is smaller than the reserve.
        let usable = max(limit - overheadReserve, 200)
        let referenceAllowance = min(max(references, 0), usable / referenceShareDivisor)
        let transcriptAllowance = min(max(transcript, 0), usable - referenceAllowance)
        return Allocation(transcript: transcriptAllowance, references: referenceAllowance)
    }
}
