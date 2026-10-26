import SwiftUI
import ListenToMeCore

struct AudioLevelMeters: View {
    let session: MeetingSession
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            VStack(alignment: .leading, spacing: 5) {
                ForEach([SpeakerSource.you, .others], id: \.self) { source in
                    let sample = session.audioLevels.sample(for: source, now: ProcessInfo.processInfo.systemUptime)
                    let available = session.isRunning && !session.isPreparing && !session.captureUnavailable(source)
                    let label = source == .you ? "Microphone" : "System audio"
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(label)
                            Spacer()
                            Text(status(source, sample: sample))
                        }
                        ProgressView(value: available ? sample?.fraction ?? 0 : 0)
                            .accessibilityLabel("\(label) level")
                            .accessibilityValue(status(source, sample: sample))
                    }
                }
            }.font(.caption2).foregroundStyle(.secondary)
        }
        .help("RMS of captured audio, in dBFS. Silence is different from a channel with no recent audio.")
    }

    private func status(_ source: SpeakerSource, sample: LiveAudioLevels.Sample?) -> String {
        if session.isPreparing { return "Preparing" }
        if !session.isRunning { return "Stopped" }
        if session.captureUnavailable(source) { return "Unavailable" }
        guard let sample else { return "No recent audio" }
        return sample.decibels <= -60 ? "Silence" : String(format: "%.0f dBFS", sample.decibels)
    }
}

struct ResponseTimingBadge: View {
    let timings: ResponseTimings
    let role: CopilotRole
    var body: some View {
        if let measurement = timings.measurements[role] {
            TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                let elapsed = measurement.elapsed ?? max(0, ProcessInfo.processInfo.systemUptime - measurement.startedAt)
                let first = measurement.firstContent.map { String(format: "%.2fs", $0) } ?? "—"
                Text("First content \(first) · \(String(format: "%.2fs", elapsed)) · \(measurement.outcome.rawValue.capitalized)")
                    .font(.caption2).foregroundStyle(.secondary)
                    .help("Time from request start to first answer content and stream end. Thinking is not answer content. "
                          + "Times describe the latest request, including automatic reviews.")
            }
        }
    }
}
