import XCTest
@testable import ListenToMeCore

/// Issue #197: when the spoken language differs from the transcription language, switch once.
final class LanguageDetectionPolicyTests: XCTestCase {
    private let apple = ["en-US", "en-GB", "en-AU", "zh-CN", "zh-TW", "zh-HK", "yue-CN", "es-ES", "es-MX",
                         "es-US", "fr-FR", "fr-CA", "de-DE", "ja-JP", "pt-BR", "pt-PT", "ko-KR", "it-IT"]

    private func decide(_ language: String, _ probability: Double, current: String = "en_US",
                        supported: [String]? = nil, pinned: Bool = false, switched: Bool = false,
                        region: String? = "US") -> LanguageDetectionPolicy.Decision {
        LanguageDetectionPolicy.decide(detected: language, probability: probability, current: current,
                                       supported: supported ?? apple, pinned: pinned, alreadySwitched: switched,
                                       region: region)
    }

    // MARK: Decision

    func testConfidentOtherSupportedLanguageSwitches() {
        XCTAssertEqual(decide("zh", 0.97), .switchTo("zh-CN"))
        XCTAssertEqual(decide("es", 0.9), .switchTo("es-US"), "The device region picks among Spanish locales")
        XCTAssertEqual(decide("ja", LanguageDetectionPolicy.minimumConfidence), .switchTo("ja-JP"),
                       "The threshold itself is confident enough")
    }

    func testLowConfidenceKeepsTheCurrentLanguage() {
        XCTAssertEqual(decide("zh", 0.79), .keep(.lowConfidence))
        XCTAssertEqual(decide("zh", .nan), .keep(.lowConfidence), "A broken probability never switches")
    }

    func testSameLanguageInAnotherRegionKeepsTheChosenLocale() {
        XCTAssertEqual(decide("en", 0.99, current: "en_GB"), .keep(.sameLanguage))
        XCTAssertEqual(decide("zh", 0.99, current: "zh-Hant-TW"), .keep(.sameLanguage))
    }

    func testUnsupportedLanguageKeepsTheCurrentLanguage() {
        XCTAssertEqual(decide("sw", 0.95), .keep(.unsupported))
        XCTAssertEqual(decide("zh", 0.95, supported: ["en-US"]), .keep(.unsupported))
        XCTAssertEqual(decide("", 0.95), .keep(.unsupported))
    }

    func testAFixedLanguageIsNeverOverridden() {
        XCTAssertEqual(decide("zh", 0.99, pinned: true), .keep(.pinned))
    }

    func testARecordingSwitchesOnlyOnce() {
        XCTAssertEqual(decide("fr", 0.99, current: "zh-CN", switched: true), .keep(.alreadySwitched))
    }

    func testPinnedOutranksEveryOtherReason() {
        XCTAssertEqual(decide("en", 0.1, pinned: true, switched: true), .keep(.pinned))
        XCTAssertEqual(decide("en", 0.1, switched: true), .keep(.alreadySwitched))
    }

    // MARK: Whisper code → supported locale

    func testChineseFollowsTheDeviceRegion() {
        let best = { LanguageDetectionPolicy.bestLocale(forWhisper: "zh", supported: self.apple, region: $0) }
        XCTAssertEqual(best("CN"), "zh-CN")
        XCTAssertEqual(best("TW"), "zh-TW")
        XCTAssertEqual(best("HK"), "zh-TW", "Mandarin in Hong Kong is Traditional Mandarin, not Cantonese")
        XCTAssertEqual(best("MO"), "zh-TW")
        XCTAssertEqual(best("SG"), "zh-CN")
        XCTAssertEqual(best("US"), "zh-CN")
        XCTAssertEqual(best(nil), "zh-CN")
    }

    func testMandarinNeverResolvesToCantonese() {
        XCTAssertNil(LanguageDetectionPolicy.bestLocale(forWhisper: "zh", supported: ["zh-HK", "en-US"], region: "HK"))
    }

    func testCantoneseResolvesToACantoneseLocale() {
        XCTAssertEqual(LanguageDetectionPolicy.bestLocale(forWhisper: "yue", supported: apple, region: "HK"), "zh-HK")
        XCTAssertEqual(LanguageDetectionPolicy.bestLocale(forWhisper: "yue", supported: apple, region: "US"), "yue-CN")
        XCTAssertEqual(LanguageDetectionPolicy.bestLocale(forWhisper: "yue", supported: ["zh-HK"], region: "US"),
                       "zh-HK")
        XCTAssertEqual(decide("zh", 0.99, current: "zh-HK"), .switchTo("zh-CN"), "zh-HK transcribes Cantonese")
        XCTAssertEqual(decide("yue", 0.99, current: "zh_HK"), .keep(.sameLanguage))
    }

    func testDeviceRegionWinsThenTheLanguagesHomeThenAStableChoice() {
        XCTAssertEqual(LanguageDetectionPolicy.bestLocale(forWhisper: "fr", supported: apple, region: "CA"), "fr-CA")
        XCTAssertEqual(LanguageDetectionPolicy.bestLocale(forWhisper: "fr", supported: apple, region: "US"), "fr-FR")
        XCTAssertEqual(LanguageDetectionPolicy.bestLocale(forWhisper: "pt", supported: apple, region: "GB"), "pt-BR")
        XCTAssertEqual(LanguageDetectionPolicy.bestLocale(forWhisper: "en", supported: apple, region: "DE"), "en-US")
        XCTAssertEqual(LanguageDetectionPolicy.bestLocale(forWhisper: "nl", supported: ["nl-NL", "nl-BE"],
                                                          region: "US"),
                       "nl-BE", "Without a home region the alphabetically first locale keeps the choice stable")
    }

    func testUnderscoredAndScriptTaggedLocalesAreUnderstood() {
        XCTAssertEqual(LanguageDetectionPolicy.bestLocale(forWhisper: "zh", supported: ["zh_Hans_CN", "zh_Hant_TW"],
                                                          region: "TW"), "zh_Hant_TW")
        XCTAssertEqual(LanguageDetectionPolicy.bestLocale(forWhisper: "de", supported: ["de"], region: "AT"), "de")
    }

    func testNumericRegionsAndEmptyIdentifiersAreHandled() {
        XCTAssertEqual(LanguageDetectionPolicy.bestLocale(forWhisper: "es", supported: ["", "es-419", "es-ES"],
                                                          region: "419"), "es-419")
        XCTAssertEqual(LanguageDetectionPolicy.bestLocale(forWhisper: "es", supported: ["es-419", "es-ES"],
                                                          region: "MX"), "es-ES")
    }

    func testWhisperOnlyCodesMapToIsoCodes() {
        XCTAssertEqual(LanguageDetectionPolicy.languageCode(forWhisper: "jw"), "jv")
        XCTAssertEqual(LanguageDetectionPolicy.languageCode(forWhisper: " ES "), "es")
        XCTAssertEqual(LanguageDetectionPolicy.bestLocale(forWhisper: "jw", supported: ["jv-ID"], region: nil), "jv-ID")
    }

    // MARK: When to listen, and how much to keep

    func testDetectionWaitsForEnoughSpeech() {
        XCTAssertFalse(LanguageDetectionPolicy.isReady(speechStart: nil, speechEnd: 0, captured: 60))
        XCTAssertFalse(LanguageDetectionPolicy.isReady(speechStart: 2, speechEnd: 9, captured: 9))
        XCTAssertTrue(LanguageDetectionPolicy.isReady(speechStart: 2, speechEnd: 10, captured: 10))
        XCTAssertTrue(LanguageDetectionPolicy.isReady(speechStart: 2, speechEnd: 3, captured: 32),
                      "Sparse speech is checked once a whole window has passed since it began")
    }

    func testTheWindowStartsJustBeforeTheFirstSpeechAndIsCapped() {
        let rate = LanguageDetectionPolicy.sampleRate
        XCTAssertEqual(LanguageDetectionPolicy.window(speechStart: 0.2, totalSamples: 10 * rate), 0..<(10 * rate))
        XCTAssertEqual(LanguageDetectionPolicy.window(speechStart: 5, totalSamples: 60 * rate),
                       Int(4.5 * Double(rate))..<Int(34.5 * Double(rate)))
        XCTAssertEqual(LanguageDetectionPolicy.window(speechStart: 50, totalSamples: 10 * rate),
                       (10 * rate)..<(10 * rate),
                       "A stale speech time never reaches past the audio")
    }

    // MARK: Undo without replay

    private func line(_ text: String, _ start: TimeInterval, _ end: TimeInterval? = nil) -> TranscriptSegment {
        TranscriptSegment(source: .you, text: text, isFinal: true, start: start, end: end ?? start + 1)
    }

    func testRestoringPutsTheOriginalLinesBackBeforeTheSwitch() {
        let earlier = line("earlier recording", 0)
        let switched = [line("重新", 10), line("转写", 12), line("after", 20)]
        let current = [earlier] + switched
        let originals = [line("chong xin", 10), line("zhuan xie", 12)]
        let restored = LanguageDetectionPolicy.restoring(originals, into: current, recording: Set(switched.map(\.id)),
                                                         before: 15)
        XCTAssertEqual(restored.map(\.text), ["earlier recording", "chong xin", "zhuan xie", "after"])
        XCTAssertEqual(LanguageDetectionPolicy.restoring(originals, into: current, recording: [], before: 15), current,
                       "A conversation that no longer holds the recording is left alone")
    }

    /// Review of #201, findings 5 and 6.
    func testRestoringKeepsTheLineSpanningTheSwitchAndEveryOtherRecordingsLines() {
        let switched = [line("我们", 2, 6), line("今天开会讨论", 9, 14)]
        let watch = line("Apple Watch line", 3, 5)
        let later = line("a later recording", 40)
        let current = switched + [watch, later]
        let originals = [line("wo men", 2, 6), line("jin tian (unfinished)", 9, 12)]
        let restored = LanguageDetectionPolicy.restoring(originals, into: current, recording: Set(switched.map(\.id)),
                                                         before: 12)
        XCTAssertEqual(restored.map(\.text),
                       ["wo men", "jin tian (unfinished)", "今天开会讨论", "Apple Watch line", "a later recording"],
                       "Only the switched recording's lines that ended by the switch are replaced")
    }

    // MARK: Replay commit

    func testACompleteReplayReplacesEveryOriginal() {
        let originals = [line("garbage one", 1, 4), line("garbage two", 5, 9), line("partial", 9.5, 10)]
        let replayed = [line("第一句", 1, 6)]
        XCTAssertEqual(LanguageDetectionPolicy.mergingReplay(replayed, over: originals, complete: true).map(\.text),
                       ["第一句"])
    }

    func testAReplayStoppedPartWayKeepsTheOriginalsItDidNotReach() {
        let originals = [line("garbage one", 1, 4), line("garbage two", 5, 9), line("partial", 9.5, 10)]
        let merged = LanguageDetectionPolicy.mergingReplay([line("第一句", 1, 6)], over: originals, complete: false)
        XCTAssertEqual(merged.map(\.text), ["第一句", "partial"])
        XCTAssertEqual(LanguageDetectionPolicy.mergingReplay([], over: originals, complete: false), originals,
                       "A replay that produced nothing keeps every original")
    }
}
