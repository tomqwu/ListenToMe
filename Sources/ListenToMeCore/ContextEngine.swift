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
        return Self.context(messages: finals + provisional, notes: notes, summary: summary,
                            responseLanguage: responseLanguage, references: references,
                            personaGuidance: personaGuidance)
    }

    /// A prompt context over lines the caller already chose (`OnDemandGrounding`), with every
    /// optional block trimmed and dropped when blank.
    public static func context(messages: [TranscriptSegment], notes: String?, summary: String? = nil,
                               responseLanguage: String? = nil, references: String? = nil,
                               personaGuidance: String? = nil, transcriptNote: String? = nil) -> PromptContext {
        func kept(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
        return PromptContext(messages: messages, notes: kept(notes), summary: kept(summary),
                             responseLanguage: kept(responseLanguage), references: kept(references),
                             personaGuidance: kept(personaGuidance), transcriptNote: kept(transcriptNote))
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
