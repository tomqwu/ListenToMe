import Foundation
import Observation

/// The single source of truth for transcribed conversation. UI and engines read from it.
@Observable
public final class ConversationStore {
    /// Finalized utterances in arrival order; capture timestamps remain available per engine.
    public private(set) var utterances: [TranscriptSegment] = []
    /// The current in-progress (non-final) segment, if any.
    public private(set) var partials: [SpeakerSource: TranscriptSegment] = [:]
    public var partial: TranscriptSegment? { partials[.others] ?? partials[.you] }
    public private(set) var revision = 0

    public init() {}

    public func apply(_ segment: TranscriptSegment) {
        if segment.isFinal {
            utterances.append(segment)
            partials[segment.source] = nil
            revision += 1
        } else {
            partials[segment.source] = segment.text.isEmpty ? nil : segment
        }
    }

    public func reset() {
        utterances = []; partials = [:]; revision += 1
    }

    public func restore(_ segments: [TranscriptSegment]) {
        utterances = segments; partials = [:]; revision += 1
    }

    /// Apply a complete attribution pass only to the supplied run/channel's lines.
    public func attributeSpeakers(_ assignments: [UUID: SpeakerIdentity], replacing ids: Set<UUID>) {
        utterances = utterances.map { original in
            guard ids.contains(original.id) else { return original }
            var segment = original
            segment.speakerID = assignments[segment.id]?.id
            segment.speakerName = assignments[segment.id]?.name
            return segment
        }
        revision += 1
    }

    public func renameSpeaker(id: String, name: String) {
        utterances = utterances.map { original in
            guard original.speakerID == id else { return original }
            var segment = original
            segment.speakerName = name
            return segment
        }
        revision += 1
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
