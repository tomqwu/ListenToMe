import AVFoundation
import ListenToMeCore
import Speech
import XCTest
@testable import ListenToMeIOS

@MainActor
final class MobileSpeechCatalogTests: XCTestCase {
    private func fallbackEnvironment() -> SpeechLanguageCatalog.Environment {
        var environment = SpeechLanguageCatalog.Environment()
        environment.speechAvailable = { false }
        environment.speechLocales = { XCTFail("Unsupported advanced speech must not supply the language list"); return [] }
        environment.dictationLocales = { [Locale(identifier: "en-US"), Locale(identifier: "zh-CN")] }
        environment.speechLocale = { _ in nil }
        environment.dictationLocale = { $0 }
        environment.installed = { module in
            guard let dictation = module as? DictationTranscriber else { XCTFail("Expected local dictation assets"); return false }
            return dictation.selectedLocales.first?.identifier(.bcp47) == "en-US"
        }
        return environment
    }

    func testFallbackLanguagesAreOfferedWithTheCorrectInstalledStatus() async {
        let catalog = SpeechLanguageCatalog(environment: fallbackEnvironment())
        await catalog.load()
        XCTAssertEqual(catalog.supported, ["en-US", "zh-CN"])
        let groups = catalog.groups(selected: nil, label: { $0 })
        XCTAssertEqual(groups.installed, ["en-US"])
        XCTAssertEqual(groups.downloadable, ["zh-CN"])
    }

    func testMixedLanguageCatalogPrefersAdvancedAndKeepsDictationOnlyLanguages() async {
        var environment = fallbackEnvironment()
        environment.speechAvailable = { true }
        environment.speechLocales = { [Locale(identifier: "en-US")] }
        environment.speechLocale = { $0.identifier(.bcp47) == "en-US" ? $0 : nil }
        var modules: [String] = []
        environment.installed = { module in
            modules.append(module is SpeechTranscriber ? "advanced" : "dictation")
            return module is SpeechTranscriber
        }
        let catalog = SpeechLanguageCatalog(environment: environment)
        await catalog.load()
        XCTAssertEqual(catalog.supported, ["en-US", "zh-CN"])
        XCTAssertEqual(catalog.installed, ["en-US"])
        XCTAssertEqual(modules, ["advanced", "dictation"])
    }

    func testAutomaticLanguageFilterUsesTheSameCatalogWithoutLoadingWhisper() async {
        let catalog = SpeechLanguageCatalog(environment: fallbackEnvironment())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let identifier = WhisperLanguageIdentifier(directory: root, catalogLocales: {
            await catalog.load()
            return await catalog.supported
        })
        let languages = await identifier.supportedLocales()
        XCTAssertEqual(languages, ["en-US", "zh-CN"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path), "Reading capability lists must not download a detector model")
    }
}
