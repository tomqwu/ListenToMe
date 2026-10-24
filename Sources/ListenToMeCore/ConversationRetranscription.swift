import Foundation

/// A reviewed replacement is tied to the exact original transcript, not just its conversation ID.
/// Notes and summaries may change while recognition runs; applying uses their latest values.
public struct ConversationRetranscription: Sendable {
    public let conversationID: String
    public let originalTranscript: String
    public let originalSegments: [TranscriptSegment]?
    public let segments: [TranscriptSegment]
    public let language: String
    public let audioRuns: [SavedAudioRun]

    public init(original: SessionRecord, segments: [TranscriptSegment], language: String, audioRuns: [SavedAudioRun] = []) throws {
        guard !segments.isEmpty, segments.allSatisfy({ $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw Failure.noSpeech
        }
        conversationID = original.id
        originalTranscript = original.transcript
        originalSegments = original.segments
        self.segments = segments.sorted { $0.start < $1.start }
        self.language = language
        self.audioRuns = audioRuns
    }

    public func applying(to current: SessionRecord) throws -> SessionRecord {
        guard current.id == conversationID, current.transcript == originalTranscript,
              current.segments == originalSegments else { throw Failure.changed }
        return SessionRecord(id: current.id, title: current.title, date: current.date,
            transcript: segments.map { "\($0.speakerLabel): \($0.text)" }.joined(separator: "\n"),
            summary: current.summary, segments: segments, notes: current.notes,
            quickSuggestion: current.quickSuggestion, deepAnswer: current.deepAnswer,
            isComplete: current.isComplete, attachments: current.attachments, sourceImportID: current.sourceImportID,
            titleState: current.titleState, language: language, languages: [language],
            selectionSummaries: current.selectionSummaries, summaryInstructions: current.summaryInstructions)
    }

    /// File recognition starts at zero. Place each track on the saved recording's timeline and
    /// retain its source; inferred speaker names from the previous transcript cannot be reused.
    public static func placing(_ lines: [TranscriptSegment], run: SavedAudioRun, language: String) throws -> [TranscriptSegment] {
        guard run.timelineOffset.isFinite, run.timelineOffset >= 0 else { throw Failure.invalidTimeline }
        return try lines.filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { line in
            guard line.start.isFinite, line.end.isFinite, line.start >= 0, line.end >= line.start else {
                throw Failure.invalidTimeline
            }
            return TranscriptSegment(source: run.source, text: line.text, isFinal: true,
                start: run.timelineOffset + line.start, end: run.timelineOffset + line.end, language: language)
        }
    }

    /// Earlier Mac recordings may have untimed transcripts, so several runs can share offset zero.
    /// Preserve track offsets within each run, but place later runs after preceding audio ends.
    public static func timeline(for runs: [SavedAudioRun]) -> [SavedAudioRun] {
        var end = 0.0
        var result: [SavedAudioRun] = []
        for index in Set(runs.map(\.index)).sorted() {
            let group = runs.filter { $0.index == index }
            let first = group.map(\.timelineOffset).min() ?? 0
            let base = max(end, first)
            for run in group {
                let offset = base + max(0, run.timelineOffset - first)
                result.append(SavedAudioRun(index: run.index, source: run.source, fileName: run.fileName,
                    startedAt: run.startedAt, timelineOffset: offset, timesMatchAudio: true,
                    duration: run.duration, failure: run.failure))
                end = max(end, offset + (run.duration ?? 0))
            }
        }
        return result
    }

    public enum Failure: LocalizedError {
        case noSpeech, changed, invalidTimeline
        public var errorDescription: String? {
            switch self {
            case .noSpeech: return "No speech was recognized. Your original transcript is unchanged."
            case .changed: return "The conversation changed. Re-transcribe again before replacing its transcript."
            case .invalidTimeline: return "The saved audio has invalid timing. Your original transcript is unchanged."
            }
        }
    }
}
