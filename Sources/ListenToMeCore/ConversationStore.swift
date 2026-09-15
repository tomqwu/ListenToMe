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

    /// Rail statistics, maintained as utterances arrive instead of rescanning the whole transcript
    /// on every render (issue #116): a multi-hour meeting re-filtered the full array once a second.
    public private(set) var youCount = 0
    public private(set) var othersCount = 0
    /// Total characters of finalized speech, for the rail's explicit ~chars/4 token estimate.
    public private(set) var transcriptCharacterCount = 0

    public init() {}

    public func apply(_ segment: TranscriptSegment) {
        if segment.isFinal {
            utterances.append(segment)
            count(segment, by: 1)
            partials[segment.source] = nil
            revision += 1
        } else {
            partials[segment.source] = segment.text.isEmpty ? nil : segment
        }
    }

    public func reset() {
        utterances = []; partials = [:]; revision += 1
        youCount = 0; othersCount = 0; transcriptCharacterCount = 0
    }

    public func restore(_ segments: [TranscriptSegment]) {
        utterances = segments; partials = [:]; revision += 1
        youCount = 0; othersCount = 0; transcriptCharacterCount = 0
        for segment in segments { count(segment, by: 1) }
    }

    private func count(_ segment: TranscriptSegment, by delta: Int) {
        if segment.source == .you { youCount += delta } else { othersCount += delta }
        transcriptCharacterCount += delta * segment.text.count
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
    /// The budget charges each segment what it actually costs in the prompt — the speaker label,
    /// the `": "` separator and the joining newline as well as the text — so a window sized to a
    /// provider's context limit cannot be blown by hundreds of short, heavily labeled lines.
    public func recentContext(maxChars: Int) -> [TranscriptSegment] {
        var total = 0
        var collected: [TranscriptSegment] = []
        for segment in utterances.reversed() {
            let cost = TranscriptSegment.promptCharacterCost(segment)
            // Always include the most recent; otherwise stop before exceeding the budget.
            if !collected.isEmpty && total + cost > maxChars { break }
            total += cost
            collected.append(segment)
        }
        return collected.reversed()
    }

    /// Trimmed characters a non-final hypothesis needs before it is worth sending to a model. The
    /// same threshold the live evaluator applies in `QuickSummaryContext.pieces`, so both pipelines
    /// agree on what counts as meaningful provisional speech.
    public static let provisionalMinimumCharacters = 24

    /// Marks a line the recognizer has not finalized, so the model can weigh it as unconfirmed
    /// wording rather than a quotation. Placed in the text, which every prompt builder renders.
    public static let provisionalTag = "(provisional) "

    /// The current non-final speech, per channel, as prompt lines tagged `(provisional)` and kept
    /// within `maxChars` of assembled prompt cost (issue #113).
    ///
    /// Apple's SpeechAnalyzer can keep a hypothesis volatile for an entire recording, so a prompt
    /// built from `utterances` alone may omit the very question the user pressed the hotkey about.
    /// Segments stay non-final, so they never advance a summarized/acknowledged ledger. When the
    /// budget cannot hold the whole hypothesis the most recent speech (its tail) is kept.
    public func provisionalContext(maxChars: Int) -> [TranscriptSegment] {
        var remaining = maxChars
        var collected: [TranscriptSegment] = []
        for source in [SpeakerSource.you, .others] {
            guard let segment = partials[source] else { continue }
            let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= Self.provisionalMinimumCharacters else { continue }
            // Everything the line costs besides its own words: label, ": ", joining newline, tag.
            let overhead = segment.speakerLabel.count + 3 + Self.provisionalTag.count
            let allowance = remaining - overhead
            guard allowance >= Self.provisionalMinimumCharacters else { continue }
            let kept = trimmed.count <= allowance ? trimmed : String(trimmed.suffix(allowance))
            collected.append(TranscriptSegment(
                id: segment.id, source: segment.source, text: Self.provisionalTag + kept,
                isFinal: false, start: segment.start, end: segment.end,
                speakerID: segment.speakerID, speakerName: segment.speakerName))
            remaining -= overhead + kept.count
        }
        return collected
    }
}
