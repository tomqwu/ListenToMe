import SwiftUI

/// App-wide visual design tokens. Keep these in one place so panes, sheets, and onboarding
/// share a single cohesive look. Purely cosmetic — no behavior lives here.
///
/// The command-center direction is dark-native, so the palette is defined as dynamic
/// `Color(nsColor:)` values that resolve to the dark "C · Pro" tokens in dark mode and to the
/// original light tokens in light mode. Because they're dynamic, both appearances stay usable;
/// the app merely *defaults* to dark via `ProviderSettings.appearance`.
enum Theme {
    /// Brand accent (indigo). Applied app-wide via `.tint(Theme.accent)`.
    static let accent = Color(red: 0.36, green: 0.40, blue: 0.92)   // #5b63f0
    /// Purple, used sparingly for the Deep role only.
    static let accentDeep = Color(red: 0.486, green: 0.302, blue: 0.859)   // #7c4ddb

    /// Transcript speaker colors (brighter variants in dark mode for legibility).
    static let you = dynamic(light: nsColor(0.184, 0.427, 0.941), dark: nsColor(0.435, 0.627, 1.0))
    static let others = dynamic(light: nsColor(0.122, 0.616, 0.420), dark: nsColor(0.255, 0.780, 0.580))

    // MARK: Surfaces

    /// Window background (behind cards). dark `#17171f` / light `#f6f5fb`.
    static let windowBackground = dynamic(light: nsColor(0.965, 0.961, 0.984), dark: nsColor(0.090, 0.090, 0.122))
    /// Standard pane/card fill. dark `#1d1d27` / light `#ffffff`.
    static let cardBackground = dynamic(light: nsColor(1, 1, 1), dark: nsColor(0.114, 0.114, 0.153))
    /// Secondary card fill (insets, code blocks). dark `#20202b` / light `#fbfaff`.
    static let cardBackground2 = dynamic(light: nsColor(0.984, 0.980, 1), dark: nsColor(0.125, 0.125, 0.169))
    /// Hairline / divider color. dark `#2a2a36` / light `#e7e4f0`.
    static let line = dynamic(light: nsColor(0.906, 0.894, 0.941), dark: nsColor(0.165, 0.165, 0.212))
    /// Chip / inset background. dark `#262633` / light `#efedfa`.
    static let chip = dynamic(light: nsColor(0.937, 0.929, 0.980), dark: nsColor(0.149, 0.149, 0.200))

    // MARK: Ink (text)

    /// Primary text. dark `#f1f0f6` / light `#1c1b22`.
    static let ink = dynamic(light: nsColor(0.110, 0.106, 0.133), dark: nsColor(0.945, 0.941, 0.965))
    /// Secondary text. dark `#a9a7b8` / light `#5b5966`.
    static let ink2 = dynamic(light: nsColor(0.357, 0.349, 0.400), dark: nsColor(0.663, 0.655, 0.722))
    /// Tertiary / faint text & labels. dark `#6f6d80` / light `#9a98a6`.
    static let ink3 = dynamic(light: nsColor(0.604, 0.596, 0.651), dark: nsColor(0.435, 0.427, 0.502))

    static let cornerRadius: CGFloat = 12
    static let paneSpacing: CGFloat = 10

    // MARK: Glass HUD

    /// Translucent panel fill layered over `.ultraThinMaterial` for the "instrument cluster" look.
    /// dark = deep navy at ~55% / light = white at ~60%.
    static let glassPanelFill = dynamicA(light: nsColorA(1, 1, 1, 0.60),
                                         dark: nsColorA(0.075, 0.086, 0.149, 0.55))
    /// HUD panel hairline — a cool indigo so the dark panels read as glowing instruments. ≈ `#2b3a6b`.
    static let glassStroke = dynamic(light: nsColor(0.882, 0.871, 0.933),
                                     dark: nsColor(0.169, 0.227, 0.420))
    /// Brighter stroke for emphasis / hover. ≈ `#3a4a8b`.
    static let glassStrokeStrong = dynamic(light: nsColor(0.804, 0.792, 0.882),
                                           dark: nsColor(0.227, 0.290, 0.545))

    /// Subtle top-to-bottom depth behind the cockpit panels (deep spaceship backdrop).
    static let windowGradient = LinearGradient(
        colors: [
            dynamic(light: nsColor(0.973, 0.969, 0.988), dark: nsColor(0.055, 0.063, 0.110)),
            dynamic(light: nsColor(0.945, 0.941, 0.969), dark: nsColor(0.086, 0.094, 0.157))
        ],
        startPoint: .top, endPoint: .bottom)

    // MARK: Helpers

    private static func nsColor(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    private static func nsColorA(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    /// Alpha-preserving variant of `dynamic(light:dark:)`.
    private static func dynamicA(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? dark : light
        })
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

    /// Glass-HUD panel chrome: translucent fill over `.ultraThinMaterial`, a glowing indigo stroke,
    /// and an outer shadow. `ring: true` is the emphasized treatment for the live center pane
    /// (accent stroke + accent glow), used to mark "where we are right now".
    struct HudPanel: ViewModifier {
        var ring: Bool = false
        var padding: CGFloat = Theme.paneSpacing

        func body(content: Content) -> some View {
            content
                .padding(padding)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                                .fill(Theme.glassPanelFill)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .stroke(ring ? Theme.accent.opacity(0.9) : Theme.glassStroke,
                                lineWidth: ring ? 1.5 : 1)
                )
                .shadow(color: (ring ? Theme.accent : Color.black).opacity(ring ? 0.30 : 0.22),
                        radius: ring ? 22 : 12, y: ring ? 0 : 4)
        }
    }
}

extension View {
    /// Wraps the view in the standard `Theme` card chrome (fill + hairline stroke + padding).
    func paneCard(padding: CGFloat = Theme.paneSpacing) -> some View {
        modifier(Theme.PaneCard(padding: padding))
    }

    /// Wraps the view in the Glass-HUD panel chrome. `ring: true` for the live center pane.
    func hudPanel(ring: Bool = false, padding: CGFloat = Theme.paneSpacing) -> some View {
        modifier(Theme.HudPanel(ring: ring, padding: padding))
    }
}
