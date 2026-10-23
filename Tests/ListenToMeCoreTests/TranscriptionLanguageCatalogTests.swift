import XCTest
@testable import ListenToMeCore

/// Issue #172: the language pickers list every locale the OS can transcribe, installed first, with the
/// common languages leading each group.
final class TranscriptionLanguageCatalogTests: XCTestCase {
    /// English names, as the pickers would show them on an English device.
    private let names = ["en-US": "English (US)", "en-GB": "English (UK)", "zh-CN": "Chinese (China)",
                         "zh-TW": "Chinese (Taiwan)", "zh-HK": "Chinese (Hong Kong)", "yue-CN": "Cantonese",
                         "ja-JP": "Japanese", "ko-KR": "Korean", "es-ES": "Spanish (Spain)",
                         "es-MX": "Spanish (Mexico)", "fr-FR": "French", "de-DE": "German",
                         "pt-BR": "Portuguese (Brazil)", "pt-PT": "Portuguese (Portugal)", "it-IT": "Italian",
                         "ar-SA": "Arabic", "hi-IN": "Hindi", "da-DK": "Danish"]
    private func label(_ id: String) -> String { names[id] ?? id }

    /// Apple's list in no particular order, as `SpeechTranscriber.supportedLocales` returns it.
    private let apple = ["pt-BR", "it-IT", "en-US", "ar-SA", "zh-HK", "de-DE", "es-MX", "ja-JP", "hi-IN",
                         "en-GB", "zh-CN", "fr-FR", "es-ES", "zh-TW", "ko-KR", "yue-CN", "pt-PT", "da-DK"]

    func testEverySupportedLocaleIsOfferedEvenOnesTheCuratedListLacks() {
        let groups = TranscriptionLanguageCatalog.groups(supported: apple, installed: [], label: label)
        XCTAssertEqual(Set(groups.all), Set(apple))
        for missing in ["pt-BR", "it-IT", "hi-IN", "ar-SA"] {
            XCTAssertTrue(groups.all.contains(missing), "\(missing) must be selectable")
        }
    }

    func testCommonLanguagesLeadInCuratedOrderAndTheRestFollowByName() {
        let groups = TranscriptionLanguageCatalog.groups(supported: apple, installed: [], label: label)
        XCTAssertEqual(groups.downloadable, [
            "en-US", "en-GB", "zh-CN", "zh-TW", "yue-CN", "ja-JP", "ko-KR", "es-ES", "fr-FR", "de-DE",
            "ar-SA", "zh-HK", "da-DK", "hi-IN", "it-IT", "pt-BR", "pt-PT", "es-MX",
        ])
        XCTAssertEqual(groups.installed, [])
    }

    func testInstalledLanguagesFormTheirOwnGroupWithTheSameOrder() {
        let groups = TranscriptionLanguageCatalog.groups(supported: apple, installed: ["it_IT", "en-US", "ja-JP"],
                                                         label: label)
        XCTAssertEqual(groups.installed, ["en-US", "ja-JP", "it-IT"], "Installed written either way still counts")
        XCTAssertFalse(groups.downloadable.contains("en-US"))
        XCTAssertEqual(groups.all.count, apple.count, "Each language appears once, in one group")
        XCTAssertEqual(TranscriptionLanguageGroups(installed: ["a"], downloadable: ["b"]).all, ["a", "b"])
    }

    func testIdentifiersAreDeduplicatedAndReturnedInBCP47Form() {
        let groups = TranscriptionLanguageCatalog.groups(supported: ["en_US", "en-US", " fr_FR ", "EN-us", ""],
                                                         installed: [], label: label)
        XCTAssertEqual(groups.all, ["en-US", "fr-FR"])
        XCTAssertEqual(TranscriptionLanguageCatalog.bcp47("zh_Hant_TW"), "zh-Hant-TW")
        XCTAssertTrue(TranscriptionLanguageCatalog.same("en_us", "en-US"))
        XCTAssertFalse(TranscriptionLanguageCatalog.same("en-US", "en-GB"))
    }

    func testExcludedLanguagesAreLeftOutHoweverTheyAreWritten() {
        let groups = TranscriptionLanguageCatalog.groups(supported: apple, installed: ["en-US"],
                                                         excluding: ["en_US"], label: label)
        XCTAssertFalse(groups.all.contains("en-US"), "The device language already has its own System entry")
        XCTAssertTrue(groups.all.contains("en-GB"))
    }

    func testTheStoredChoiceStaysSelectableWhenTheOSNoLongerListsIt() {
        let groups = TranscriptionLanguageCatalog.groups(supported: ["en-US", "fr-FR"], installed: [],
                                                         selected: "sv-SE", label: label)
        XCTAssertEqual(groups.downloadable, ["en-US", "fr-FR", "sv-SE"])
        let listed = TranscriptionLanguageCatalog.groups(supported: ["en-US", "fr-FR"], installed: ["fr-FR"],
                                                         selected: "fr_FR", label: label)
        XCTAssertEqual(listed.all, ["fr-FR", "en-US"], "A listed choice is not added twice")
        let empty = TranscriptionLanguageCatalog.groups(supported: ["en-US"], installed: [], selected: "",
                                                        label: label)
        XCTAssertEqual(empty.all, ["en-US"], "No stored choice (macOS Auto) adds nothing")
    }

    func testAnUnavailableOSListFallsBackToTheCommonLanguages() {
        let groups = TranscriptionLanguageCatalog.groups(supported: [], installed: [], label: label)
        XCTAssertEqual(groups.downloadable, TranscriptionLanguageCatalog.common)
    }

    func testEqualLabelsFallBackToTheIdentifierSoTheOrderIsStable() {
        let sorted = TranscriptionLanguageCatalog.ordered(["xx-B", "xx-A", "en-US"], label: { _ in "Same" })
        XCTAssertEqual(sorted, ["en-US", "xx-A", "xx-B"])
    }

    /// Automatic (`LanguageDetectionPolicy`) switches among the same supported list the picker shows,
    /// so the picker's normalising, ordering and grouping must not change where a detection lands, and
    /// every language Automatic can switch to must be one the user can also pick.
    func testAutomaticSwitchTargetsAreAlwaysPickerOptions() {
        let groups = TranscriptionLanguageCatalog.groups(supported: apple, installed: ["fr-FR"], label: label)
        for whisper in ["en", "zh", "yue", "es", "fr", "de", "ja", "ko", "pt", "it", "ar", "hi", "da", "sv"] {
            for region in ["US", "GB", "TW", "HK", "MX", "BR", nil] as [String?] {
                let fromOS = LanguageDetectionPolicy.bestLocale(forWhisper: whisper, supported: apple, region: region)
                let fromPicker = LanguageDetectionPolicy.bestLocale(forWhisper: whisper, supported: groups.all,
                                                                    region: region)
                XCTAssertEqual(fromPicker, fromOS, "\(whisper) in \(region ?? "no region")")
                if let fromPicker { XCTAssertTrue(groups.all.contains(fromPicker)) }
            }
        }
        XCTAssertEqual(LanguageDetectionPolicy.bestLocale(forWhisper: "pt", supported: groups.all, region: "US"),
                       "pt-BR", "Portuguese, absent from the old curated lists, is now a switch target and an option")
    }
}
