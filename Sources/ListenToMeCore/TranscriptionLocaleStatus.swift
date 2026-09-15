import Foundation

/// Status text for the transcription locale actually in use.
///
/// Apple's `SpeechTranscriber` silently resolves an unsupported locale to en-US. Without a distinct
/// status the only trace was "Transcription: on-device · en-US", so a pt-BR meeting filled the
/// transcript with English-looking nonsense and nothing on screen explained why (issue #136).
public enum TranscriptionLocaleStatus {
    /// The normal line: the language the engine resolved the request to.
    public static func running(_ resolved: String) -> String {
        "Transcription: on-device · \(resolved)"
    }

    /// The line shown when the requested language is not supported at all and the transcript will
    /// come out in another one.
    public static func fallback(requested: String, resolved: String) -> String {
        "Transcription: \(requested) isn't supported on this Mac — transcribing in \(resolved)"
    }
}
