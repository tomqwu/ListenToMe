import AVFoundation
import FoundationModels
import Speech
import XCTest
@testable import ListenToMeIOS

@MainActor
final class MobileSpeechFallbackTests: XCTestCase {
    func testUnsupportedAdvancedSpeechPreparesSupportedOnDeviceDictation() async throws {
        var installed: [any SpeechModule] = []
        var environment = MobileSpeechModel.Environment()
        environment.speechAvailable = { false }
        environment.speechLocale = { _ in XCTFail("Unavailable advanced engine must not prepare a model"); return nil }
        environment.dictationLocale = { _ in Locale(identifier: "en-US") }
        environment.install = { installed.append($0) }
        environment.format = { _ in AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1) }
        let (prepared, format) = try await MobileSpeechModel.prepare(
            locale: Locale(identifier: "en-US"), volatileResults: true, environment: environment)
        XCTAssertTrue(prepared.module is DictationTranscriber)
        XCTAssertEqual(installed.count, 1)
        XCTAssertTrue(installed.first is DictationTranscriber)
        XCTAssertEqual(format.sampleRate, 16_000)
    }

    func testSharedFileRetranscriptionPreservesOlderDeviceDictationFallback() async throws {
        var installed: [any SpeechModule] = []
        var environment = MobileSpeechModel.Environment()
        environment.speechAvailable = { false }
        environment.speechLocale = { _ in XCTFail("Unavailable advanced module must not be prepared"); return nil }
        environment.dictationLocale = { _ in Locale(identifier: "en-US") }
        environment.install = { installed.append($0) }
        environment.format = { _ in AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1) }
        let (prepared, format) = try await LocalAudioFileTranscriber.prepare(
            locale: Locale(identifier: "en-US"), environment: environment)
        XCTAssertTrue(prepared.module is DictationTranscriber)
        XCTAssertEqual(installed.count, 1)
        XCTAssertTrue(installed.first is DictationTranscriber)
        XCTAssertEqual(format.sampleRate, 16_000)
    }

    func testSupportedAdvancedEngineRemainsPreferred() async throws {
        var environment = MobileSpeechModel.Environment()
        environment.speechAvailable = { true }
        environment.speechLocale = { _ in Locale(identifier: "en-US") }
        environment.dictationLocale = { _ in XCTFail("Do not choose another module for supported advanced speech"); return nil }
        environment.install = { XCTAssertTrue($0 is SpeechTranscriber) }
        environment.format = { _ in AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1) }
        let (prepared, _) = try await MobileSpeechModel.prepare(
            locale: Locale(identifier: "en-US"), volatileResults: false, environment: environment)
        XCTAssertTrue(prepared.module is SpeechTranscriber)
    }

    func testUnsupportedLanguageDoesNotInstallAModelOrReturnARecordingFormat() async throws {
        var environment = MobileSpeechModel.Environment()
        environment.speechAvailable = { false }
        environment.speechLocale = { _ in nil }
        environment.dictationLocale = { _ in nil }
        environment.install = { _ in XCTFail("No supported local module must not install anything") }
        environment.format = { _ in XCTFail("No supported local module must not start audio"); return nil }
        do {
            _ = try await MobileSpeechModel.prepare(locale: Locale(identifier: "xx"), volatileResults: true,
                                                   environment: environment)
            XCTFail("Unsupported speech must fail clearly")
        } catch { XCTAssertTrue(error.localizedDescription.contains("unavailable")) }
    }

    func testCancelledDictationAssetPreparationDoesNotReturnReadyToRecord() async throws {
        var environment = MobileSpeechModel.Environment()
        environment.speechAvailable = { false }
        environment.dictationLocale = { _ in Locale(identifier: "en-US") }
        environment.install = { _ in throw CancellationError() }
        environment.format = { _ in XCTFail("Cancelled assets must not begin audio"); return nil }
        do {
            _ = try await MobileSpeechModel.prepare(locale: Locale(identifier: "en-US"), volatileResults: true,
                                                   environment: environment)
            XCTFail("Cancelled preparation must not return a ready module")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testPhysicalSpeechCapabilityReport() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Physical hardware report; not a simulator capability assertion")
        #else
        let locale = Locale(identifier: "en-US")
        let speechLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
        let dictationLocale = await DictationTranscriber.supportedLocale(equivalentTo: locale)
        let report = "SpeechTranscriber available: \(SpeechTranscriber.isAvailable)\n"
            + "Advanced English: \(speechLocale?.identifier ?? "unavailable")\n"
            + "Dictation English: \(dictationLocale?.identifier ?? "unavailable")\n"
            + "Summary model: \(SystemLanguageModel.default.availability)"
        print(report)
        let attachment = XCTAttachment(string: report)
        attachment.name = "Physical speech and summary capabilities"; attachment.lifetime = .keepAlways; add(attachment)
        #endif
    }
}
