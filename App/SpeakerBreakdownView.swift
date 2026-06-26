import SwiftUI
import ListenToMeCore

/// The experimental "Speaker breakdown" sheet. Renders, from `MeetingView`'s state, one of four
/// states over the system-audio ("Others") channel: loading (preparing model / analyzing), error,
/// "need more audio" (empty/short buffer, surfaced as the diarizer's not-enough-audio error or an
/// empty result), and results — "N speakers detected" with one talk-time bar per speaker. Honest
/// throughout: on-device, voices grouped (not named), accuracy varies.
struct SpeakerBreakdownView: View {
    @Environment(\.dismiss) private var dismiss
    let loading: Bool
    let summary: SpeakerSummary?
    let errorText: String?
    /// Whether the capture buffer hit its ~2 h cap (later audio was dropped) — noted if results show.
    let didTruncate: Bool
    /// True when the active transcription engine isn't WhisperKit, so per-line "Speaker N" labels in
    /// the transcript can't be produced (only WhisperKit emits real per-line timestamps). Noted if
    /// results show, so the breakdown is honest about what changed.
    let perLineLabelsUnavailable: Bool
    /// Canonical diarized-speakerId → "Speaker N" map from `SpeakerLabeling` (the same numbering the
    /// transcript uses). When non-empty, each bar's LABEL text comes from here so the sheet and the
    /// transcript agree on which number is which speaker; bars stay sorted by talk time. Empty on the
    /// non-WhisperKit path, where we fall back to sequential numbering.
    var speakerOrder: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Speaker breakdown").font(.title2).bold()

            content

            Text("Experimental \u{00b7} on-device \u{00b7} groups voices in the system-audio channel; " +
                 "accuracy varies.")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Preparing model\u{2026} / Analyzing\u{2026}").foregroundStyle(Theme.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let errorText {
            Label(errorText, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let summary, summary.speakerCount > 0 {
            results(summary)
        } else {
            Label("Need more system audio. Start a session and let the \u{201C}Others\u{201D} channel " +
                  "play for a while, then try again.", systemImage: "waveform.slash")
                .foregroundStyle(Theme.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func results(_ summary: SpeakerSummary) -> some View {
        Text("\(summary.speakerCount) \(summary.speakerCount == 1 ? "speaker" : "speakers") detected")
            .font(.headline).foregroundStyle(Theme.ink)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(summary.speakers.enumerated()), id: \.element.id) { index, speaker in
                // Take the LABEL from the canonical, TOTAL order map (it covers every diarized
                // speaker) so the number matches the transcript; keep the talk-time SORT (the
                // enumeration order). The fallback fires only on the non-WhisperKit path where
                // `order` is empty for all rows — so it can never collide with a mapped number.
                SpeakerBar(label: speakerOrder[speaker.id] ?? "Speaker \(index + 1)",
                           fraction: speaker.fraction)
            }
        }
        if didTruncate {
            Text("Note: only the first ~2 hours of audio were analyzed.")
                .font(.caption).foregroundStyle(Theme.ink3)
        }
        if perLineLabelsUnavailable {
            Text("Per-line \u{201C}Speaker N\u{201D} labels in the transcript require the WhisperKit " +
                 "engine (it provides per-line timestamps). Switch engines in Settings to enable them.")
                .font(.caption).foregroundStyle(Theme.ink3)
        }
    }
}

/// A single labeled talk-time bar: speaker name, a proportional fill, and the percentage.
private struct SpeakerBar: View {
    let label: String
    let fraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.system(size: 12.5)).foregroundStyle(Theme.ink)
                Spacer()
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Theme.ink2)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Theme.chip)
                    RoundedRectangle(cornerRadius: 4).fill(Theme.others)
                        .frame(width: max(2, geo.size.width * fraction))
                }
            }
            .frame(height: 8)
        }
    }
}
