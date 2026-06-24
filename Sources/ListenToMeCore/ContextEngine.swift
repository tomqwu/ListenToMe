import Foundation

/// Assembles prompt context and decides when to fire a proactive suggestion.
public struct ContextEngine {
    public let debounce: TimeInterval
    private var lastFire: TimeInterval = -.greatestFiniteMagnitude

    public init(debounce: TimeInterval = 8) {
        self.debounce = debounce
    }

    public func buildContext(from store: ConversationStore, notes: String?, maxChars: Int = 4000,
                             summary: String? = nil) -> PromptContext {
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSummary = summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        return PromptContext(
            messages: store.recentContext(maxChars: maxChars),
            notes: (trimmed?.isEmpty == false) ? trimmed : nil,
            summary: (trimmedSummary?.isEmpty == false) ? trimmedSummary : nil
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
