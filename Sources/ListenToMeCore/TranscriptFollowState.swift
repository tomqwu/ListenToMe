/// Content growth and programmatic scrolling cannot disengage follow-latest. Only a user's scroll
/// gesture may do so; touching Latest or reaching the end resumes it.
public struct TranscriptFollowState: Equatable, Sendable {
    public private(set) var following = true
    public private(set) var userScrolling = false
    public var shouldScroll: Bool { following && !userScrolling }
    public init() {}
    public mutating func beginUserScroll() { userScrolling = true }
    public mutating func geometryChanged(atEnd: Bool) {
        if userScrolling { following = atEnd }
    }
    public mutating func endUserScroll(atEnd: Bool) { following = atEnd; userScrolling = false }
    public mutating func latest() { following = true; userScrolling = false }
}
