import Foundation
import Observation

/// The single source of truth for transcribed conversation. UI and engines read from it.
@Observable
public final class ConversationStore {
    /// Finalized utterances in chronological order.
    public private(set) var utterances: [TranscriptSegment] = []
    /// The current in-progress (non-final) segment, if any.
    public private(set) var partial: TranscriptSegment?

    public init() {}

    public func apply(_ segment: TranscriptSegment) {
        if segment.isFinal {
            utterances.append(segment)
            partial = nil
        } else {
            partial = segment
        }
    }

    /// Most-recent finalized utterances kept within `maxChars` (always at least the latest).
    public func recentContext(maxChars: Int) -> [TranscriptSegment] {
        var total = 0
        var collected: [TranscriptSegment] = []
        for segment in utterances.reversed() {
            // Always include the most recent; otherwise stop before exceeding the budget.
            if !collected.isEmpty && total + segment.text.count > maxChars { break }
            total += segment.text.count
            collected.append(segment)
        }
        return collected.reversed()
    }
}
