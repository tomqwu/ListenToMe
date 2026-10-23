import Foundation
import ListenToMeCore
import UIKit

/// What Automatic transcription language says (issues #197 and #199): the status line, the notice
/// beside Undo and Status details' wording, and the device conditions that pause re-checks.
extension MobileLanguageDetection {
    static func describe(_ guess: LanguageGuess) -> String {
        "\(guess.language) \(Int((guess.probability * 100).rounded()))%"
    }

    static func describe(_ skip: LanguageRecheckPolicy.Skip) -> String {
        switch skip {
        case .lowPower: return "Low Power Mode"
        case .background: return "app in the background"
        case .thermal: return "device is hot"
        case .silence: return "too little speech"
        }
    }

    /// Low Power Mode, a backgrounded app and a hot device pause re-checks (issue #199).
    static func deviceConditions() -> LanguageRecheckPolicy.Conditions {
        let info = ProcessInfo.processInfo
        return .init(lowPower: info.isLowPowerModeEnabled,
                     background: UIApplication.shared.applicationState == .background,
                     thermal: info.thermalState == .serious || info.thermalState == .critical)
    }

    static func displayName(_ identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }

    static func languageName(_ whisperCode: String) -> String {
        let code = LanguageDetectionPolicy.languageCode(forWhisper: whisperCode)
        return Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    /// "2:05" or "1:02:05", for a transcript time.
    static func clock(_ time: TimeInterval) -> String {
        let seconds = max(0, Int(time.rounded(.down)))
        let (hours, minutes) = (seconds / 3_600, seconds / 60 % 60)
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds % 60)
            : String(format: "%d:%02d", minutes, seconds % 60)
    }

    /// One line for the meeting status area, or `nil` when there is nothing to say.
    var statusLine: String? {
        switch status {
        case .preparing where run != nil:
            return "Getting language detection ready on this device (one-time download, " +
                "\(WhisperLanguageIdentifier.downloadDescription))…"
        case .checking: return "Checking the spoken language on this device…"
        case .switching(let locale): return "Switching transcription to \(Self.displayName(locale))…"
        case .unavailable(let reason):
            var trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            while trimmed.hasSuffix(".") { trimmed.removeLast() }
            let detail = trimmed.isEmpty ? "the language model could not be loaded" : trimmed
            return "Language detection paused: \(detail). Transcribing in " +
                "\(Self.displayName(run?.locale ?? Locale.current.identifier)); the next recording tries again."
        case .idle, .preparing: return lastError
        }
    }

    /// "Detected Chinese · switched", for the notice beside Undo, or "Detected French from 2:05 ·
    /// switched" when a re-check found the change part-way through. A switch that could not transcribe
    /// the recording so far again says that only new speech is in the new language.
    var noticeText: String? {
        notice.map {
            guard $0.replayed else { return "Detected \(Self.languageName($0.detected)) · switched for new speech" }
            let from = $0.fromRecordingStart ? "" : " from \(Self.clock($0.since))"
            return "Detected \(Self.languageName($0.detected))\(from) · switched"
        }
    }
}

extension SpeakerAudioBuffer {
    /// Releases language audio older than `LanguageRecheckPolicy.retained` (issue #199), in whole
    /// 10-second blocks, so a recording of any length holds about two minutes for checks and replays.
    func keepTrailingLanguageAudio() {
        discardAudio(before: sampleCount - LanguageRecheckPolicy.retainedSamples)
    }

    /// Recording time of the earliest language audio still held.
    var heldFrom: TimeInterval {
        TimeInterval(sampleCount - retainedSampleCount) / TimeInterval(LanguageDetectionPolicy.sampleRate)
    }

    /// Recording time from which a replay can safely start (`LanguageRecheckPolicy.replayFloor`).
    var replayFloor: TimeInterval {
        LanguageRecheckPolicy.replayFloor(
            captured: TimeInterval(sampleCount) / TimeInterval(LanguageDetectionPolicy.sampleRate), heldFrom: heldFrom)
    }
}
