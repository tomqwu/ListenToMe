import SwiftUI
import ListenToMeCore

// MARK: - Command-center building blocks
//
// Reusable, state-independent views for the "C · Pro command-center" layout. The pieces that need
// `MeetingView`'s private state (rail, transcript, role column) live in an `extension MeetingView`
// in `CommandCenterPanes.swift`; this file holds the leaf views they compose from.

/// An uppercase, letter-spaced section label used throughout the left status rail.
struct RailLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.4)
            .foregroundStyle(Theme.ink3)
    }
}

/// A monospaced `key  ·······  value` row used for the rail's Models / Session stats.
struct StatRow: View {
    let key: String
    let value: String
    var body: some View {
        HStack {
            Text(key).foregroundStyle(Theme.ink2)
            Spacer(minLength: 8)
            Text(value).foregroundStyle(Theme.ink)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.vertical, 1)
    }
}

/// One keyboard hint in the bottom footer: a `kbd`-styled key + its label.
struct KbdHint: View {
    let key: String
    let label: String
    var body: some View {
        HStack(spacing: 6) {
            Text(key)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(Theme.chip))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.line, lineWidth: 1))
                .foregroundStyle(Theme.ink2)
            Text(label).foregroundStyle(Theme.ink3)
        }
        .font(.system(size: 10.5, design: .monospaced))
    }
}

/// The bottom footer: keyboard hints (labels only; only ⌘⇧Space is an actually-wired hotkey) and an
/// honest privacy line — on-device transcription, but cloud models may send data.
struct CommandCenterFooter: View {
    /// True when an Ollama cloud key routes AI prompts off-device.
    let cloudActive: Bool
    var body: some View {
        HStack(spacing: 18) {
            KbdHint(key: "⌘⇧Space", label: "quick")
            KbdHint(key: "⌘R", label: "recap")
            KbdHint(key: "⌘F", label: "search")
            KbdHint(key: "⌘E", label: "export")
            Spacer()
            Text(cloudActive
                 ? "On-device transcription · cloud model receives transcript & context"
                 : "On-device transcription · local models stay private")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(cloudActive ? Theme.you : Theme.ink3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(Theme.windowBackground)
        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .top)
    }
}

/// A compact "REC mm:ss" pill with a pulsing dot for the rail. Shows nothing while idle.
struct RailRecStatus: View {
    let isRunning: Bool
    let elapsed: String
    var body: some View {
        if isRunning {
            HStack(spacing: 7) {
                RecordingIndicator()
                Text("REC \(elapsed)")
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.red)
            }
        } else {
            HStack(spacing: 7) {
                Circle().fill(Theme.ink3).frame(width: 7, height: 7)
                Text("IDLE")
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.ink3)
            }
        }
    }
}

/// A dense Copilot role box for the right column. Header (colored role name + model name + streaming
/// spinner + Copy), a scrolling Markdown body with sticky auto-scroll, and the role's action buttons.
struct RoleBox<Header: View, Actions: View>: View {
    let title: String
    let accent: Color
    let role: CopilotRole
    let session: MeetingSession
    let outputText: String
    let placeholder: String
    @ViewBuilder let headerExtra: () -> Header
    @ViewBuilder let actions: () -> Actions
    @State private var atBottom = true

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .bold)).tracking(0.5)
                    .foregroundStyle(accent)
                if session.streamingRoles.contains(role) {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Text(session.models[role] ?? "—")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.ink3).lineLimit(1)
                if !outputText.isEmpty {
                    Button { Clipboard.copy(outputText) } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless)
                        .help("Copy this pane's text")
                }
                headerExtra()
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Group {
                            if !outputText.isEmpty {
                                MarkdownText(text: outputText).foregroundStyle(Theme.ink)
                            } else if session.streamingRoles.contains(role) {
                                Text("💭 Thinking…").foregroundStyle(Theme.ink2)
                            } else {
                                PaneEmptyState(
                                    systemImage: "bubble.left.and.text.bubble.right",
                                    text: placeholder)
                            }
                        }
                        Color.clear.frame(height: 1).id(MeetingView.scrollBottomID)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onScrollGeometryChange(for: Bool.self) { geo in
                    geo.contentOffset.y + geo.containerSize.height >= geo.contentSize.height - 24
                } action: { _, isAtBottom in atBottom = isAtBottom }
                .onChange(of: outputText) { _, _ in
                    if atBottom { proxy.scrollTo(MeetingView.scrollBottomID, anchor: .bottom) }
                }
            }
            actions()
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A simple wrapping layout: places subviews left-to-right and flows onto a new row when the next
/// subview would exceed the proposed width. Used for the Quick pane's one-tap action buttons so the
/// growing set wraps instead of overflowing the column.
struct FlowLayout: Layout {
    var spacing: CGFloat = 7

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: maxWidth == .infinity ? totalWidth : maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width - bounds.minX > maxWidth {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                          proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Label helpers (no fabricated data)

enum CommandCenterLabels {
    /// Friendly label for the stored transcription-engine id.
    static func engine(_ id: String) -> String {
        switch id {
        case "speechRecognizer": return "SpeechRecognizer"
        case "whisperKit": return "WhisperKit"
        default: return "SpeechAnalyzer"
        }
    }

    /// mm:ss elapsed since `start`, clamped at 0. Empty string when not recording.
    static func elapsed(since start: Date?, now: Date) -> String {
        guard let start else { return "00:00" }
        let total = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// `mm:ss` for a transcript segment start time, or "" when the start is unknown (zero).
    static func stamp(_ start: TimeInterval) -> String {
        guard start > 0 else { return "" }
        let total = Int(start)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
