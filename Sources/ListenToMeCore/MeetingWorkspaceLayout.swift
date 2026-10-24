import Foundation

/// Layout follows the space available to the workspace, including after rotation or window resizing.
/// Accessibility text always gets one outer scroll rather than narrow, nested reading columns.
public enum MeetingWorkspaceLayout: Sendable, Equatable {
    case wide, twoPane, vertical, scrolling

    public static func resolve(width: Double, height: Double, accessibilityText: Bool) -> Self {
        guard !accessibilityText else { return .scrolling }
        if width >= 760, height >= 600 { return .wide }
        if width >= 640, height >= 180 { return .twoPane }
        if height < 360 { return .scrolling }
        return .vertical
    }
}
