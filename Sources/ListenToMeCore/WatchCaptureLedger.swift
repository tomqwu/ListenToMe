import Foundation

/// The iPhone's manifest for one Apple Watch recording (issue #181): which chunks arrived, which are
/// transcribed, and whether the recording is over. It decides what the foreground drain transcribes
/// next; the audio files themselves live beside it in the watch inbox.
///
/// Chunks can arrive out of order, twice, or never. Transcription only moves forward through a
/// contiguous run of chunks. A missing chunk holds it back until `gapTimeout` has passed with no
/// news from the watch; the run is then written off as a gap the conversation notes visibly.
public struct WatchCaptureLedger: Codable, Equatable, Sendable {
    public enum ChunkState: String, Codable, Sendable { case received, transcribed }

    public struct Chunk: Codable, Equatable, Sendable {
        public let index: Int
        public let startOffset: TimeInterval
        public let duration: TimeInterval
        public var state: ChunkState
        public var end: TimeInterval { startOffset + duration }
    }

    /// How long a missing chunk is waited for after the last delivery, and how long a recording with
    /// no end is kept open.
    public static let gapTimeout: TimeInterval = 86_400
    /// Final results and chunk ends are compared with this slack: analyzer times are not exact.
    static let tolerance: TimeInterval = 0.05

    public let recordingID: UUID
    public let startedAt: Date
    /// Sorted by index.
    public private(set) var chunks: [Chunk] = []
    /// The index of the recording's last chunk, once the watch has said which one it is.
    public private(set) var lastIndex: Int?
    public private(set) var endedUnexpectedly = false
    /// Recording time up to which text is saved. Never moves back.
    public private(set) var transcribedThrough: TimeInterval = 0
    public private(set) var lastActivity: Date
    /// Why transcription failed; the drain skips the recording until the user retries.
    public private(set) var failure: String?
    /// Runs of chunks written off as missing; the conversation already carries their note.
    public private(set) var notedGaps: [ClosedRange<Int>] = []

    public init(recordingID: UUID, startedAt: Date, at time: Date) {
        self.recordingID = recordingID
        self.startedAt = startedAt
        lastActivity = time
    }

    /// Files a delivered chunk. Returns `false`, changing nothing, for a chunk already known, one
    /// already written off as missing, or one whose audio lies wholly inside text already saved.
    @discardableResult
    public mutating func receive(_ chunk: WatchChunkMetadata, at time: Date) -> Bool {
        guard chunk.recordingID == recordingID, self.chunk(chunk.index) == nil, !isNotedGap(chunk.index),
              chunk.startOffset + chunk.duration > transcribedThrough + Self.tolerance else { return false }
        let entry = Chunk(index: chunk.index, startOffset: chunk.startOffset, duration: chunk.duration, state: .received)
        chunks.insert(entry, at: chunks.firstIndex { $0.index > chunk.index } ?? chunks.endIndex)
        // A later chunk (Continue after an interruption) reopens a finished recording; only a last
        // chunk moves its end.
        if chunk.isLast { lastIndex = max(lastIndex ?? chunk.index, chunk.index) }
        lastActivity = time
        return true
    }

    /// The watch's note that a recording ended without a last chunk.
    public mutating func receiveEnd(_ end: WatchRecordingEnd, at time: Date) {
        guard end.recordingID == recordingID else { return }
        lastIndex = max(lastIndex ?? end.lastIndex, end.lastIndex)
        endedUnexpectedly = endedUnexpectedly || end.unexpected
        lastActivity = time
    }

    /// The chunks to transcribe now, in order, and the gaps to note before them.
    public func nextBatch(now: Date) -> WatchLedgerBatch {
        let nothing = WatchLedgerBatch(indices: [], newGaps: [], finishes: false)
        guard failure == nil else { return nothing }
        let timedOut = now.timeIntervalSince(lastActivity) >= Self.gapTimeout
        let highest = highestIndex
        var indices: [Int] = []
        var gaps: [ClosedRange<Int>] = []
        var index = 0
        while index <= highest {
            if isSettled(index) {
                index += 1
            } else if chunk(index) != nil {
                indices.append(index)
                index += 1
            } else {
                // Missing: wait for it, or after the timeout write the whole missing run off.
                guard timedOut else { return WatchLedgerBatch(indices: indices, newGaps: gaps, finishes: false) }
                var last = index
                while last < highest, chunk(last + 1) == nil, !isSettled(last + 1) { last += 1 }
                gaps.append(index...last)
                index = last + 1
            }
        }
        // Every index is accounted for. The recording is over when the watch named its last chunk,
        // or when it has been silent for the whole timeout.
        let finishes = highest >= 0 && (lastIndex != nil || timedOut)
        return WatchLedgerBatch(indices: indices, newGaps: gaps, finishes: finishes)
    }

    /// Records gaps whose note has been added to the conversation.
    public mutating func noteGaps(_ gaps: [ClosedRange<Int>]) {
        for gap in gaps where !notedGaps.contains(gap) { notedGaps.append(gap) }
    }

    /// Text is saved through `time`. Returns the indices of the chunks this newly covers wholly,
    /// whose audio may now be deleted.
    @discardableResult
    public mutating func markTranscribed(through time: TimeInterval) -> [Int] {
        transcribedThrough = max(transcribedThrough, time)
        var covered: [Int] = []
        for position in chunks.indices where chunks[position].state == .received
            && chunks[position].end <= transcribedThrough + Self.tolerance {
            chunks[position].state = .transcribed
            covered.append(chunks[position].index)
        }
        return covered
    }

    public mutating func markFailed(_ reason: String) { failure = reason }

    public mutating func clearFailure() { failure = nil }

    /// The watch named the last chunk and every chunk up to it (and any after it) is transcribed or
    /// written off.
    public var isFinished: Bool {
        guard lastIndex != nil else { return false }
        return (0...highestIndex).allSatisfy(isSettled)
    }

    /// About how many minutes of audio a gap lost: the time between its neighbours, or five minutes
    /// a chunk when a neighbour is unknown.
    public func gapMinutes(_ gap: ClosedRange<Int>) -> Int {
        guard let previous = chunk(gap.lowerBound - 1), let next = chunk(gap.upperBound + 1) else {
            return gap.count * 5
        }
        return max(1, Int(((next.startOffset - previous.end) / 60).rounded()))
    }

    // MARK: Helpers

    private var highestIndex: Int { max(chunks.last?.index ?? -1, lastIndex ?? -1) }

    private func chunk(_ index: Int) -> Chunk? { chunks.first { $0.index == index } }

    private func isNotedGap(_ index: Int) -> Bool { notedGaps.contains { $0.contains(index) } }

    /// Nothing is left to do for `index`: its chunk is transcribed, it was written off, or it is
    /// missing but the next chunk that did arrive starts within text already saved (a recording
    /// reopened after it finished, whose earlier audio is long gone).
    private func isSettled(_ index: Int) -> Bool {
        if let chunk = chunk(index) { return chunk.state == .transcribed }
        if isNotedGap(index) { return true }
        guard let next = chunks.first(where: { $0.index > index }) else { return false }
        return next.startOffset <= transcribedThrough + Self.tolerance
    }
}

/// What the drain transcribes next for one recording.
public struct WatchLedgerBatch: Equatable, Sendable {
    /// Chunks to feed, in order.
    public let indices: [Int]
    /// Missing runs to note in the conversation before these chunks' text.
    public let newGaps: [ClosedRange<Int>]
    /// Once these chunks are transcribed, the recording is complete.
    public let finishes: Bool

    public init(indices: [Int], newGaps: [ClosedRange<Int>], finishes: Bool) {
        self.indices = indices
        self.newGaps = newGaps
        self.finishes = finishes
    }
}
