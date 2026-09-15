import Foundation

/// Assembles prompt context and decides when to fire a proactive suggestion.
public struct ContextEngine {
    public let debounce: TimeInterval
    private var lastFire: TimeInterval = -.greatestFiniteMagnitude

    public init(debounce: TimeInterval = 8) {
        self.debounce = debounce
    }

    public func buildContext(from store: ConversationStore, notes: String?, maxChars: Int = 4000,
                             summary: String? = nil, responseLanguage: String? = nil,
                             references: String? = nil, personaGuidance: String? = nil) -> PromptContext {
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSummary = summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLang = responseLanguage?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRefs = references?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPersona = personaGuidance?.trimmingCharacters(in: .whitespacesAndNewlines)
        // Non-final speech is appended after the finalized window, tagged "(provisional)", and is
        // charged to the same budget so a provider's context window still holds (issue #113). It may
        // reserve at most half the transcript allowance, so it can never crowd out the history — and
        // it is then sized by what the finalized window *actually* spent: `recentContext` always
        // keeps the latest utterance even when that one line already exceeds the budget, so reading
        // the reservation alone could push the assembled prompt past a provider's cap.
        let reserved = max(0, maxChars / 2)
        let finals = store.recentContext(maxChars: max(0, maxChars - reserved))
        let spent = finals.reduce(0) { $0 + TranscriptSegment.promptCharacterCost($1) }
        let provisional = store.provisionalContext(maxChars: min(reserved, max(0, maxChars - spent)))
        return PromptContext(
            messages: finals + provisional,
            notes: (trimmed?.isEmpty == false) ? trimmed : nil,
            summary: (trimmedSummary?.isEmpty == false) ? trimmedSummary : nil,
            responseLanguage: (trimmedLang?.isEmpty == false) ? trimmedLang : nil,
            references: (trimmedRefs?.isEmpty == false) ? trimmedRefs : nil,
            personaGuidance: (trimmedPersona?.isEmpty == false) ? trimmedPersona : nil
        )
    }

    /// True when a finalized remote question arrives and the debounce window has elapsed.
    public mutating func shouldFireProactive(for segment: TranscriptSegment, now: TimeInterval) -> Bool {
        guard segment.isFinal,
              segment.source == .others,
              QuestionDetector.isQuestion(segment.text),
              now - lastFire >= debounce else {
            return false
        }
        lastFire = now
        return true
    }
}
