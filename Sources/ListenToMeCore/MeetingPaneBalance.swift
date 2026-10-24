import Foundation

/// Reading space in the phone's Duo layout. Both panes retain a readable minimum width.
public enum MeetingPaneBalance: String, CaseIterable, Sendable {
    case balanced, transcript, quick

    public func transcriptWidth(available: Double) -> Double {
        let width = max(0, available)
        let minimum = min(280, width / 2)
        let fraction = self == .transcript ? 0.6 : (self == .quick ? 0.4 : 0.5)
        return min(width - minimum, max(minimum, width * fraction))
    }
}
