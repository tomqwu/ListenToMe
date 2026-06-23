import Foundation

/// The three AI pane roles, each independently selectable.
public enum CopilotRole: String, Sendable, CaseIterable, Equatable {
    case listener
    case quick
    case deep
}
