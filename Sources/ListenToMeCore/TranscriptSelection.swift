import Foundation

/// Which transcript lines the user picked for a selection summary (issue #234). Only final lines
/// can be selected: a live hypothesis may still be rewritten, so it is never part of a selection.
public struct TranscriptSelection: Sendable, Equatable {
    public private(set) var ids: Set<UUID> = []
    /// The line a drag or "Select from here" started at; a later drag extends from it.
    public private(set) var anchor: UUID?

    public init() {}

    public var isEmpty: Bool { ids.isEmpty }

    /// Tap: add or remove one final line, and make it the anchor.
    public mutating func toggle(_ id: UUID, in segments: [TranscriptSegment]) {
        guard segments.contains(where: { $0.id == id && $0.isFinal }) else { return }
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        anchor = id
    }

    /// Drag: select every final line from the anchor (or `from`) through `id`, in either direction.
    /// Lines selected outside that range stay selected.
    public mutating func extend(from start: UUID? = nil, to id: UUID, in segments: [TranscriptSegment]) {
        let origin = start ?? anchor ?? id
        guard let first = segments.firstIndex(where: { $0.id == origin }),
              let last = segments.firstIndex(where: { $0.id == id }) else { return }
        for segment in segments[min(first, last)...max(first, last)] where segment.isFinal { ids.insert(segment.id) }
        anchor = origin
    }

    /// "Select from here": that line through the latest final line, replacing any earlier choice.
    public mutating func selectFrom(_ id: UUID, in segments: [TranscriptSegment]) {
        guard let first = segments.firstIndex(where: { $0.id == id }) else { return }
        ids = Set(segments[first...].filter(\.isFinal).map(\.id))
        anchor = id
    }

    public mutating func clear() { ids = []; anchor = nil }

    /// Forgets lines that are no longer in `segments` (a language Undo or re-transcription replaces
    /// lines with new IDs), so nothing stays selected that the user cannot see.
    public mutating func prune(keeping segments: [TranscriptSegment]) {
        let present = Set(segments.lazy.filter(\.isFinal).map(\.id))
        ids.formIntersection(present)
        if let anchor, !present.contains(anchor) { self.anchor = nil }
    }

    /// The selected lines that still exist, in transcript order. A line removed or re-transcribed
    /// since it was picked simply drops out.
    public func selected(in segments: [TranscriptSegment]) -> [TranscriptSegment] {
        segments.filter { $0.isFinal && ids.contains($0.id) }
    }
}
