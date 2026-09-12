import SwiftUI

/// Shared iOS identity, surfaces and role accents. The waveform matches the installed app icon.
enum MobileStyle {
    static let accent = adaptive(0x6241BC, 0xB7A4FA)
    static let transcript = adaptive(0x26756D, 0x79D1C2)
    static let quick = adaptive(0x936010, 0xEDC06B)
    static let deep = adaptive(0x8050AD, 0xCFACF1)
    static let canvas = adaptive(0xF5F3FA, 0x11121B)
    static let surface = adaptive(0xFFFFFF, 0x1C1D2A)
    static let line = adaptive(0xE4DFEE, 0x353547)
    static let ink = adaptive(0x252135, 0xF0EDF8)
    static let muted = adaptive(0x6A637A, 0xB6B0C5)
    static let recordGradient = LinearGradient(colors: [Color(red: 0.34, green: 0.22, blue: 0.68),
                                                       Color(red: 0.46, green: 0.28, blue: 0.76)],
                                               startPoint: .leading, endPoint: .trailing)
    static let stopGradient = LinearGradient(colors: [Color(red: 0.78, green: 0.14, blue: 0.23),
                                                     Color(red: 0.66, green: 0.10, blue: 0.20)],
                                             startPoint: .leading, endPoint: .trailing)

    static func tint(for mode: MobileSummaryMode) -> Color {
        switch mode {
        case .quick: quick
        case .summary: accent
        case .deep: deep
        }
    }

    static func symbol(for mode: MobileSummaryMode) -> String {
        switch mode {
        case .quick: "bolt.fill"
        case .summary: "text.alignleft"
        case .deep: "sparkle.magnifyingglass"
        }
    }

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
}

struct MobileBrand: View {
    var compact = false
    var body: some View {
        HStack(spacing: 9) {
            Image("BrandMark").resizable().scaledToFit().frame(width: compact ? 28 : 44, height: compact ? 28 : 44)
                .clipShape(RoundedRectangle(cornerRadius: compact ? 8 : 13, style: .continuous))
                .accessibilityHidden(true)
            Text("Listen to Me").font(compact ? .subheadline.weight(.bold) : .title3.weight(.bold))
                .foregroundStyle(MobileStyle.ink).lineLimit(1)
        }.accessibilityElement(children: .ignore).accessibilityLabel("Listen to Me")
            .accessibilityIdentifier("appBrand")
    }
}

struct MobileRoleIcon: View {
    let symbol: String
    let tint: Color
    var body: some View {
        Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint).frame(width: 30, height: 30)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
    }
}

struct MobileCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(MobileStyle.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(MobileStyle.line, lineWidth: 0.75)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: MobileStyle.accent.opacity(0.035), radius: 12, y: 4)
    }
}

struct MobileRecordStyle: ButtonStyle {
    var recording: Bool
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(recording ? MobileStyle.stopGradient : MobileStyle.recordGradient)
            }
            .shadow(color: (recording ? Color.red : MobileStyle.accent).opacity(enabled ? 0.16 : 0), radius: 10, y: 4)
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
    }
}

struct MobileOutputPlaceholder: View {
    let mode: MobileSummaryMode
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(MobileStyle.tint(for: mode).opacity(0.06))
                HStack(spacing: 14) {
                    Image(systemName: MobileStyle.symbol(for: mode)).font(.title2)
                        .foregroundStyle(MobileStyle.tint(for: mode))
                    VStack(alignment: .leading, spacing: 7) {
                        Capsule().fill(MobileStyle.tint(for: mode).opacity(0.20)).frame(width: 72, height: 5)
                        Capsule().fill(MobileStyle.tint(for: mode).opacity(0.12)).frame(width: 48, height: 5)
                    }
                }
            }.frame(width: 150, height: 66).accessibilityHidden(true)
            Text(mode == .quick ? "Key points, as the conversation unfolds." :
                 (mode == .summary ? "The key points, decisions and next steps." :
                    "A closer look at decisions, risks and open questions."))
                .font(.callout).foregroundStyle(MobileStyle.muted)
        }.padding(.vertical, 8)
    }
}
