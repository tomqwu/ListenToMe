import SwiftUI

/// App-wide visual design tokens. Keep these in one place so panes, sheets, and onboarding
/// share a single cohesive look. Purely cosmetic — no behavior lives here.
///
/// The palette is Native-Mac (system surfaces, floating cards) defined as dynamic
/// `Color(nsColor:)` values that resolve correctly in both light and dark appearances.
/// The app follows the system appearance by default via `ProviderSettings.appearance`.
enum Theme {
    /// Brand accent (indigo). Applied app-wide via `.tint(Theme.accent)`.
    /// Light `#5b63f0` / dark `#7b82ff` (brighter for contrast on dark surfaces).
    static let accent = dynamic(light: nsColor(0.357, 0.388, 0.941), dark: nsColor(0.482, 0.510, 1.0))
    /// Purple, used sparingly for the Deep role only.
    static let accentDeep = Color(red: 0.486, green: 0.302, blue: 0.859)   // #7c4ddb

    /// Transcript speaker colors (brighter variants in dark mode for legibility).
    static let you = dynamic(light: nsColor(0.184, 0.427, 0.941), dark: nsColor(0.435, 0.627, 1.0))
    static let others = dynamic(light: nsColor(0.122, 0.616, 0.420), dark: nsColor(0.255, 0.780, 0.580))

    // MARK: Surfaces

    /// Window background (behind cards). light `#ebebed` / dark `#1c1c1e`.
    static let windowBackground = dynamic(light: nsColor(0.922, 0.922, 0.929), dark: nsColor(0.110, 0.110, 0.118))
    /// Standard floating-card fill. light `#ffffff` / dark `#2a2a2d`.
    static let cardBackground = dynamic(light: nsColor(1, 1, 1), dark: nsColor(0.165, 0.165, 0.176))
    /// Secondary fill (insets, situation rows, code blocks). light `#f4f4f7` / dark `#202022`.
    static let cardBackground2 = dynamic(light: nsColor(0.957, 0.957, 0.969), dark: nsColor(0.125, 0.125, 0.133))
    /// Hairline / separator. light `#dcdce1` / dark `#3a3a3e`.
    static let line = dynamic(light: nsColor(0.863, 0.863, 0.882), dark: nsColor(0.227, 0.227, 0.243))
    /// Chip / badge background. light `#eeeef2` / dark `#303034`.
    static let chip = dynamic(light: nsColor(0.933, 0.933, 0.949), dark: nsColor(0.188, 0.188, 0.204))
    /// Left transcript sidebar fill (cooler than cards, like a native source list). light `#e4e4ea` / dark `#242427`.
    static let sidebarBackground = dynamic(light: nsColor(0.894, 0.894, 0.918), dark: nsColor(0.141, 0.141, 0.153))

    // MARK: Ink (text)

    /// Primary text. light `#1d1d1f` / dark `#f2f2f4`.
    static let ink = dynamic(light: nsColor(0.114, 0.114, 0.122), dark: nsColor(0.949, 0.949, 0.957))
    /// Secondary text. light `#5f5f67` / dark `#a6a6ae`.
    static let ink2 = dynamic(light: nsColor(0.373, 0.373, 0.404), dark: nsColor(0.651, 0.651, 0.682))
    /// Tertiary / faint text & labels. light `#9a9aa2` / dark `#6e6e76`.
    static let ink3 = dynamic(light: nsColor(0.604, 0.604, 0.635), dark: nsColor(0.431, 0.431, 0.463))

    static let cornerRadius: CGFloat = 12
    static let paneSpacing: CGFloat = 10

    // MARK: Accent tints (suggested-reply box, focal edge)

    /// Soft accent fill for highlighted insets (e.g. the Quick suggested-reply box). light `#eef0fe` / dark `#23243a`.
    static let accentSoft = dynamic(light: nsColor(0.933, 0.941, 0.996), dark: nsColor(0.137, 0.141, 0.227))
    /// Border for accent-soft insets. light `#dde0fb` / dark `#3a3d63`.
    static let accentBorder = dynamic(light: nsColor(0.867, 0.878, 0.984), dark: nsColor(0.227, 0.239, 0.388))
    /// Amber for "open question" / warning labels. light `#c08a1e` / dark `#e0b85f`.
    static let warn = dynamic(light: nsColor(0.753, 0.541, 0.118), dark: nsColor(0.878, 0.722, 0.373))

    // MARK: Helpers

    private static func nsColor(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    /// A `Color` that resolves to `light` in light appearance and `dark` in dark appearance.
    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? dark : light
        })
    }

    /// Rounded-rect card chrome: surface fill, hairline stroke, and padding.
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
                        .stroke(Theme.line, lineWidth: 1)
                )
        }
    }

    /// Native-Mac panel chrome: solid card fill, hairline border, soft drop shadow, rounded corners.
    /// `focal: true` adds a 2pt accent edge along the top — marks the live center pane as the focal
    /// instrument without a glow.
    struct MacCard: ViewModifier {
        var focal: Bool = false
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
                        .stroke(Theme.line, lineWidth: 1)
                )
                .overlay(alignment: .top) {
                    if focal {
                        UnevenRoundedRectangle(
                            topLeadingRadius: Theme.cornerRadius,
                            topTrailingRadius: Theme.cornerRadius,
                            style: .continuous
                        )
                        .fill(Theme.accent)
                        .frame(height: 2)
                    }
                }
                .shadow(color: Color.black.opacity(0.10), radius: focal ? 14 : 8, y: focal ? 6 : 3)
        }
    }
}

extension View {
    /// Wraps the view in the standard `Theme` card chrome (fill + hairline stroke + padding).
    func paneCard(padding: CGFloat = Theme.paneSpacing) -> some View {
        modifier(Theme.PaneCard(padding: padding))
    }

    /// Wraps the view in the Native-Mac card chrome. `focal: true` for the live center pane.
    func macCard(focal: Bool = false, padding: CGFloat = Theme.paneSpacing) -> some View {
        modifier(Theme.MacCard(focal: focal, padding: padding))
    }
}
