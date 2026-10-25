import AVFoundation
import ListenToMeCore
import XCTest
@testable import ListenToMeIOS

@MainActor
final class MobileRecordingCapabilityTests: XCTestCase {
    func testUnsupportedLanguageBlocksStartBeforeCreatingRecorder() async {
        var created = 0
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = MobileSession(storageDirectory: root, makeRecorder: {
            created += 1; return MobileRecorder()
        }, recordingSupport: { _ in .unsupported(reason: "Choose a supported transcription language.") })
        await session.refreshRecordingSupport()
        session.start()
        XCTAssertEqual(created, 0)
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.recordingAvailability.reason, "Choose a supported transcription language.")
        XCTAssertFalse(session.recordingAvailability.canRun)
    }

    func testDictationSupportIsReadyWithoutInstallingOrOpeningMicrophone() async {
        var environment = MobileSpeechModel.Environment()
        environment.speechAvailable = { false }
        environment.dictationLocale = { _ in Locale(identifier: "en-US") }
        environment.install = { _ in XCTFail("Checking support must not download assets") }
        environment.format = { _ in XCTFail("Checking support must not prepare capture"); return nil }
        let availability = await MobileSpeechModel.availability(locale: Locale(identifier: "en-US"),
            environment: environment, simulator: false, microphoneDenied: false)
        XCTAssertEqual(availability, .ready)
    }

    func testDeniedMicrophoneRequiresSettingsWithoutClaimingHardwareUnsupported() async {
        let availability = await MobileSpeechModel.availability(locale: Locale(identifier: "en-US"),
            simulator: false, microphoneDenied: true)
        XCTAssertFalse(availability.canRun)
        XCTAssertTrue(availability.canConfigure)
        XCTAssertEqual(availability.setupAction, "Open microphone settings")
        XCTAssertTrue(availability.reason?.contains("Microphone") == true)
    }

    func testSimulatorIsExplainedBeforeRequestingPermissionOrPreparingAssets() async {
        var environment = MobileSpeechModel.Environment()
        environment.speechAvailable = { XCTFail("Simulator must not probe an unusable capture engine"); return true }
        let availability = await MobileSpeechModel.availability(locale: .current, environment: environment,
            simulator: true, microphoneDenied: false)
        XCTAssertFalse(availability.canRun)
        XCTAssertEqual(availability.reason, MobileSpeechModel.simulatorUnavailable)
    }

    func testLatePreviousLanguageCheckCannotEnableUnsupportedCurrentLanguage() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var pending: CheckedContinuation<FeatureAvailability, Never>?
        var calls = 0
        let session = MobileSession(storageDirectory: root, recordingSupport: { _ in
            calls += 1
            if calls == 1 { return await withCheckedContinuation { pending = $0 } }
            return .unsupported(reason: "Current language is unavailable.")
        })
        let oldCheck = Task { await session.refreshRecordingSupport() }
        for _ in 0..<400 where pending == nil { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(pending)
        await session.refreshRecordingSupport()
        pending?.resume(returning: .ready)
        await oldCheck.value
        XCTAssertFalse(session.recordingAvailability.canRun)
        XCTAssertEqual(session.recordingAvailability.reason, "Current language is unavailable.")
    }
}
