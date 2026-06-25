import SwiftUI

/// App-wide visual design tokens. Keep these in one place so panes, sheets, and onboarding
/// share a single cohesive look. Purely cosmetic — no behavior lives here.
enum Theme {
    /// Brand accent (indigo). Applied app-wide via `.tint(Theme.accent)`.
    static let accent = Color(red: 0.36, green: 0.40, blue: 0.92)

    /// Standard pane/card fill that adapts to light/dark.
    static let cardBackground = Color(nsColor: .controlBackgroundColor)

    static let cornerRadius: CGFloat = 12
    static let paneSpacing: CGFloat = 10

    /// Rounded-rect card chrome: subtle fill, hairline `.quaternary` stroke, and padding.
    /// Use on each pane/section so the layout reads as a set of cohesive cards.
    struct PaneCard: ViewModifier {
        var padding: CGFloat = Theme.paneSpacing

        func body(content: Content) -> some View {
            content
                .padding(padding)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .fill(Theme.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .stroke(.quaternary, lineWidth: 1)
                )
        }
    }
}

extension View {
    /// Wraps the view in the standard `Theme` card chrome (fill + hairline stroke + padding).
    func paneCard(padding: CGFloat = Theme.paneSpacing) -> some View {
        modifier(Theme.PaneCard(padding: padding))
    }
}
