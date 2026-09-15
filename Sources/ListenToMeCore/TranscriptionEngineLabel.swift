import Foundation

/// Friendly names for the stored transcription-engine ids, plus the rail's live-vs-saved rule.
///
/// The transcriber is built once per run, from the engine setting as it stood at Start; Settings
/// says as much ("takes effect when you next press Start listening"). The rail therefore must show
/// the engine that is *actually* transcribing, not the saved preference — otherwise changing the
/// engine mid-recording makes the UI claim WhisperKit while SpeechAnalyzer is still running, and a
/// support screenshot can't tell which engine produced the transcript (issue #136).
public enum TranscriptionEngineLabel {
    /// Friendly label for a stored engine id. Unknown ids read as SpeechAnalyzer, the default.
    public static func name(_ id: String) -> String {
        switch id {
        case "speechRecognizer": return "SpeechRecognizer"
        case "whisperKit": return "WhisperKit"
        default: return "SpeechAnalyzer"
        }
    }

    /// The rail's Engine line.
    /// - Parameters:
    ///   - active: the engine the live run was started with, or nil when idle.
    ///   - saved: the current `ProviderSettings.transcriptionEngine` value.
    /// - Returns: the saved engine's name when idle; the running engine's name while a run is live,
    ///   suffixed with the pending engine when the user changed the setting mid-run.
    public static func rail(active: String?, saved: String) -> String {
        guard let active else { return name(saved) }
        let running = name(active)
        let pending = name(saved)
        return running == pending ? running : "\(running) · \(pending) next start"
    }
}
