import Foundation

/// Pure rules for on-device spoken-language detection on iOS (issue #197).
///
/// Apple's `SpeechTranscriber` needs one locale up front and does not detect or switch languages, so
/// speech in another language comes out as nonsense no text corrector can repair. In Automatic mode
/// the app runs a small multilingual Whisper model over the first stretch of speech of a recording.
/// These rules decide whether that result is good enough to restart transcription in another locale,
/// which supported locale a Whisper language code becomes, when to listen, and how much audio to keep
/// for re-transcribing what was already heard. They live here so they can be tested without CoreML,
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
    /// Audio kept to re-transcribe a recording from its start after a switch. Past this the check is
    /// abandoned for the recording and the audio released, so a phone never holds more than about
    /// 7.7 MB for it.
    public static let maximumBuffered: TimeInterval = 120

    /// Why the current language was kept.
    public enum Reason: Sendable, Equatable {
        /// The user chose a fixed language, which detection never overrides.
        case pinned
        /// This recording already switched once; mid-recording code-switching is out of scope.
        case alreadySwitched
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
                              pinned: Bool, alreadySwitched: Bool, region: String?) -> Decision {
        if pinned { return .keep(.pinned) }
        if alreadySwitched { return .keep(.alreadySwitched) }
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

    /// The samples to detect on: from just before the first speech, at most `maximumWindow` long.
    public static func window(speechStart: TimeInterval, totalSamples: Int) -> Range<Int> {
        let total = max(0, totalSamples)
        let start = min(total, max(0, Int((speechStart - 0.5) * Double(sampleRate))))
        return start..<min(total, start + Int(maximumWindow) * sampleRate)
    }

    /// Whether more audio is buffered than a switch may replay.
    public static func shouldRelease(totalSamples: Int) -> Bool {
        totalSamples > Int(maximumBuffered) * sampleRate
    }

    /// Undo after the replayed audio is gone: the lines a switch replaced (`originals`) go back in front
    /// of this recording's lines heard after the switch (`cut`, transcript time). Lines before
    /// `firstLine` belong to earlier recordings and are untouched.
    public static func restoring(_ originals: [TranscriptSegment], into segments: [TranscriptSegment],
                                 firstLine: Int, before cut: TimeInterval) -> [TranscriptSegment] {
        guard firstLine <= segments.count else { return segments }
        let later = segments[firstLine...].filter { $0.start >= cut }
        return Array(segments[..<firstLine]) + originals + later
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
