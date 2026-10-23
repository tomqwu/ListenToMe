import Foundation

/// Pure rules for on-device spoken-language detection on iOS (issue #197; re-checks during a recording
/// are `LanguageRecheckPolicy` and `LanguageTracker`, issue #199).
///
/// Apple's `SpeechTranscriber` needs one locale up front and does not detect or switch languages, so
/// speech in another language comes out as nonsense no text corrector can repair. In Automatic mode
/// the app runs a small multilingual Whisper model over the first stretch of speech of a recording.
/// These rules decide whether that result is good enough to restart transcription in another locale,
/// which supported locale a Whisper language code becomes, and when the first check can listen. They
/// live here so they can be tested without CoreML,
/// a microphone or the Speech framework.
public enum LanguageDetectionPolicy {
    /// Detection and replay audio is 16 kHz mono, the format `SpeakerAudioBuffer` accumulates.
    public static let sampleRate = 16_000
    /// Whisper's probability for its top language must reach this before the app switches. A missed
    /// switch keeps today's behavior; a wrong switch ruins a transcript that was fine.
    public static let minimumConfidence = 0.8
    /// Seconds of speech, from the first speech event, before the language is checked.
    public static let minimumSpeech: TimeInterval = 8
    /// Whisper reads at most 30 s of audio per decision.
    public static let maximumWindow: TimeInterval = 30

    /// Why the current language was kept.
    public enum Reason: Sendable, Equatable {
        /// The user chose a fixed language, which detection never overrides.
        case pinned
        /// This recording already switched `LanguageRecheckPolicy.maximumSwitches` times.
        case switchLimit
        /// Whisper was not sure enough.
        case lowConfidence
        /// The detected language is the one being transcribed (perhaps in another region).
        case sameLanguage
        /// On-device transcription has no locale for the detected language.
        case unsupported
    }

    public enum Decision: Sendable, Equatable {
        case keep(Reason)
        /// Restart transcription in this locale identifier, one of the supported ones.
        case switchTo(String)
    }

    // Every input the issue lists is a parameter, so a test can state each case in one call.
    // swiftlint:disable function_parameter_count
    /// Whether to switch from `current` given Whisper's `detected` language code and its probability.
    /// `supported` lists the locale identifiers on-device transcription accepts; `region` is the
    /// device's region, used to pick among them.
    public static func decide(detected: String, probability: Double, current: String, supported: [String],
                              pinned: Bool, atSwitchLimit: Bool, region: String?) -> Decision {
        if pinned { return .keep(.pinned) }
        if atSwitchLimit { return .keep(.switchLimit) }
        guard probability.isFinite, probability >= minimumConfidence else { return .keep(.lowConfidence) }
        let spoken = languageCode(forWhisper: detected)
        if !spoken.isEmpty, spoken == spokenLanguage(of: current) { return .keep(.sameLanguage) }
        guard let locale = bestLocale(forWhisper: detected, supported: supported, region: region) else {
            return .keep(.unsupported)
        }
        return .switchTo(locale)
    }
    // swiftlint:enable function_parameter_count

    /// The supported locale that best transcribes Whisper language `code`: the one in the device's
    /// region, else the language's home locale, else the alphabetically first, so the choice is
    /// stable. Whisper's "zh" is Mandarin: it never becomes Cantonese (zh-HK), and devices in Taiwan,
    /// Hong Kong and Macao get Traditional Mandarin (zh-TW).
    public static func bestLocale(forWhisper code: String, supported: [String], region: String?) -> String? {
        let spoken = languageCode(forWhisper: code)
        guard !spoken.isEmpty else { return nil }
        let candidates = supported.filter { spokenLanguage(of: $0) == spoken }
        guard !candidates.isEmpty else { return nil }
        let device = region?.uppercased()
        var preferred: [String] = []
        if spoken == "zh" { preferred.append(["TW", "HK", "MO"].contains(device ?? "") ? "TW" : "CN") }
        if let device { preferred.append(device) }
        if let home = homeRegion[spoken] { preferred.append(home) }
        for wanted in preferred {
            if let match = candidates.first(where: { parts(of: $0).region == wanted }) { return match }
        }
        return candidates.min()
    }

    /// Whisper's language code as an ISO 639 code. Whisper writes Javanese as "jw".
    public static func languageCode(forWhisper code: String) -> String {
        let lowered = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowered == "jw" ? "jv" : lowered
    }

    /// Whether the speech heard so far is enough to check: `minimumSpeech` seconds from the first speech
    /// event to the latest, or a whole window of audio since speech began. Times are recording time.
    public static func isReady(speechStart: TimeInterval?, speechEnd: TimeInterval, captured: TimeInterval) -> Bool {
        guard let speechStart else { return false }
        return speechEnd - speechStart >= minimumSpeech || captured - speechStart >= maximumWindow
    }

    /// Undo once the replay audio is gone: the lines a switch replaced (`originals`) take the place of
    /// the switched recording's own lines (`recording`, by id) that start at or after `since` (where
    /// transcribing again began) and ended by the switch (`cut`), both transcript time. Every other line
    /// is untouched: earlier and later recordings, the recording's lines before `since`, and Apple Watch
    /// lines added since. A line spanning the switch stays, since it alone holds the words after it.
    public static func restoring(_ originals: [TranscriptSegment], into segments: [TranscriptSegment],
                                 recording: Set<UUID>, since: TimeInterval = -.infinity,
                                 before cut: TimeInterval) -> [TranscriptSegment] {
        let replaced = { (line: TranscriptSegment) in
            recording.contains(line.id) && line.start >= since - 0.001 && line.end <= cut
        }
        guard let position = segments.firstIndex(where: replaced) else { return segments }
        var restored = segments.filter { !replaced($0) }
        restored.insert(contentsOf: originals, at: position)
        return restored
    }

    /// Commits a replay: the new transcriber's lines for the audio before the switch (`replayed`) take
    /// the place of the recording's earlier lines (`originals`). When the replay finished, they replace
    /// every original; when it stopped part-way, only originals that start before the last replayed
    /// line ends, so no stretch of the recording is left without a line.
    public static func mergingReplay(_ replayed: [TranscriptSegment], over originals: [TranscriptSegment],
                                     complete: Bool) -> [TranscriptSegment] {
        guard !complete else { return replayed }
        guard let covered = replayed.map(\.end).max() else { return originals }
        return replayed + originals.filter { $0.start >= covered }
    }

    // MARK: - Locale parsing

    /// Where a language is mostly spoken, for languages whose supported locales span several regions.
    private static let homeRegion: [String: String] = [
        "en": "US", "es": "ES", "fr": "FR", "de": "DE", "pt": "BR", "it": "IT", "ar": "SA",
        "zh": "CN", "yue": "CN", "ja": "JP", "ko": "KR",
    ]

    /// The language a locale transcribes. Apple's zh-HK model is Cantonese, so it counts as "yue".
    static func spokenLanguage(of identifier: String) -> String {
        let (language, region) = parts(of: identifier)
        return language == "zh" && region == "HK" ? "yue" : language
    }

    /// Language and region subtags of an identifier written with "-" or "_", with or without a script.
    static func parts(of identifier: String) -> (language: String, region: String?) {
        let tags = identifier.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
        guard let language = tags.first?.lowercased() else { return ("", nil) }
        let region = tags.dropFirst().first { tag in
            (tag.count == 2 && tag.allSatisfy(\.isLetter)) || (tag.count == 3 && tag.allSatisfy(\.isNumber))
        }
        return (language, region?.uppercased())
    }
}
