import Foundation
import ListenToMeCore

// MARK: - Label helpers (no fabricated data)

enum CommandCenterLabels {
    /// Friendly label for the stored transcription-engine id.
    static func engine(_ id: String) -> String { TranscriptionEngineLabel.name(id) }

    /// The rail's Engine line: the engine the live run actually built, with the saved setting
    /// flagged as pending when the user changed it mid-run (issue #136).
    static func engine(active: String?, saved: String) -> String {
        TranscriptionEngineLabel.rail(active: active, saved: saved)
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
