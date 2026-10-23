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
    /// Indices below this are already in the conversation: a recording reopened after its audio
    /// and manifest were gone, whose earlier chunks this ledger never saw.
    public private(set) var settledBelow = 0
    /// The conversation holds everything and says so. The manifest is kept as a tombstone, so a
    /// chunk that arrives later (Continue after an interruption, or the watch sending one again) is
    /// recognized instead of starting over; such a chunk reopens the recording.
    public private(set) var completed = false

    public init(recordingID: UUID, startedAt: Date, at time: Date) {
        self.recordingID = recordingID
        self.startedAt = startedAt
        lastActivity = time
    }

    /// Files a delivered chunk. Returns `false`, changing nothing, for a chunk already known, one
    /// already written off or settled, or one whose audio lies wholly inside text already saved.
    @discardableResult
    public mutating func receive(_ chunk: WatchChunkMetadata, at time: Date) -> Bool {
        guard chunk.recordingID == recordingID, self.chunk(chunk.index) == nil, !isNotedGap(chunk.index),
              chunk.index >= settledBelow,
              chunk.startOffset + chunk.duration > transcribedThrough + Self.tolerance else { return false }
        let entry = Chunk(index: chunk.index, startOffset: chunk.startOffset, duration: chunk.duration,
                          state: .received)
        chunks.insert(entry, at: chunks.firstIndex { $0.index > chunk.index } ?? chunks.endIndex)
        // A later chunk (Continue after an interruption) reopens a finished recording; only a last
        // chunk moves its end.
        if chunk.isLast { lastIndex = max(lastIndex ?? chunk.index, chunk.index) }
        lastActivity = time
        completed = false
        return true
    }

    /// The watch's note that a recording ended without a last chunk. One that names nothing beyond
    /// what a completed recording already holds changes nothing visible.
    public mutating func receiveEnd(_ end: WatchRecordingEnd, at time: Date) {
        guard end.recordingID == recordingID else { return }
        if completed, end.lastIndex <= highestIndex { return }
        lastIndex = max(lastIndex ?? end.lastIndex, end.lastIndex)
        endedUnexpectedly = endedUnexpectedly || end.unexpected
        lastActivity = time
        completed = false
    }

    /// The chunks to transcribe now, in order, and the gaps to note before them.
    public func nextBatch(now: Date) -> WatchLedgerBatch {
        let nothing = WatchLedgerBatch(indices: [], newGaps: [], finishes: false)
        guard failure == nil, !completed else { return nothing }
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
        // Every index is accounted for. The recording is over when the watch's last chunk is the
        // highest one received (a chunk after it is Continue, still going), or when the watch has
        // been silent for the whole timeout.
        let finishes = highest >= 0 && ((lastIndex ?? -1) >= highestReceived || timedOut)
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

    /// Every index below `index` is already in the conversation (see `settledBelow`).
    public mutating func settle(below index: Int) {
        settledBelow = max(settledBelow, index)
    }

    /// The conversation now holds the whole recording; nothing is due until another chunk arrives.
    public mutating func markCompleted() { completed = true }

    public mutating func markFailed(_ reason: String) { failure = reason }

    public mutating func clearFailure() { failure = nil }

    /// The watch's last chunk is the highest one received, and every chunk up to it is transcribed
    /// or written off.
    public var isFinished: Bool {
        guard let lastIndex, lastIndex >= highestReceived else { return false }
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

    private var highestReceived: Int { chunks.last?.index ?? -1 }

    private var highestIndex: Int { max(highestReceived, lastIndex ?? -1) }

    private func chunk(_ index: Int) -> Chunk? { chunks.first { $0.index == index } }

    private func isNotedGap(_ index: Int) -> Bool { notedGaps.contains { $0.contains(index) } }

    /// Nothing is left to do for `index`: its chunk is transcribed, it was written off, or it was
    /// already in the conversation when this ledger began.
    private func isSettled(_ index: Int) -> Bool {
        if let chunk = chunk(index) { return chunk.state == .transcribed }
        return index < settledBelow || isNotedGap(index)
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
