import XCTest
@testable import ListenToMeCore

final class MacFeatureReadinessTests: XCTestCase {
    func testUnavailableAppleCannotBeSelectedOrRunAndExplicitAlternativesRemain() {
        let modes = MacFeatureReadiness.selectableAIModes(appleReason: "Device is not eligible.")
        XCTAssertFalse(modes.contains(.apple))
        for mode: AIProcessingMode in [.off, .local, .cloud, .cloudAI, .openAI] {
            XCTAssertTrue(modes.contains(mode))
            XCTAssertEqual(MacFeatureReadiness.selectAI(.apple, current: mode, appleReason: "Not eligible."), mode)
        }
        XCTAssertFalse(MacFeatureReadiness.aiCanRun(mode: .apple, appleReason: "Model not ready."))
        XCTAssertTrue(MacFeatureReadiness.aiCanRun(mode: .apple, appleReason: nil))
        XCTAssertFalse(MacFeatureReadiness.aiCanRun(mode: .off, appleReason: nil))
        XCTAssertTrue(MacFeatureReadiness.selectableAIModes(appleReason: nil).contains(.apple))
        XCTAssertEqual(MacFeatureReadiness.selectAI(.apple, current: .local, appleReason: nil), .apple)
        XCTAssertEqual(MacFeatureReadiness.selectAI(.apple, current: .apple, appleReason: "Unavailable."), .apple,
                       "A saved unavailable choice remains saved until the user explicitly chooses another provider")
    }

    func testUnsupportedSelectedSpeechEngineIsBlockedWithAnAlternativeBeforeCapture() {
        let analyzer = MacFeatureReadiness.recording(engine: "speechAnalyzer", microphone: .authorized,
            advancedSupported: false, legacySupported: true, legacyPermissionDenied: false)
        XCTAssertFalse(analyzer.canRun)
        XCTAssertTrue(analyzer.reason?.contains("Settings") == true)
        let legacy = MacFeatureReadiness.recording(engine: "speechRecognizer", microphone: .authorized,
            advancedSupported: true, legacySupported: false, legacyPermissionDenied: false)
        XCTAssertFalse(legacy.canRun)
        XCTAssertTrue(legacy.reason?.contains("on-device") == true)
        XCTAssertTrue(MacFeatureReadiness.recording(engine: "speechRecognizer", microphone: .authorized,
            advancedSupported: false, legacySupported: true, legacyPermissionDenied: false).canRun)
        XCTAssertTrue(MacFeatureReadiness.recording(engine: "whisperKit", microphone: .authorized,
            advancedSupported: false, legacySupported: false, legacyPermissionDenied: false).canRun)
    }

    func testDeniedPermissionsBlockCaptureButUndeterminedPermissionCanBeRequestedByTap() {
        for microphone: MicrophoneAuthorization in [.denied, .restricted] {
            let result = MacFeatureReadiness.recording(engine: "speechAnalyzer", microphone: microphone,
                advancedSupported: true, legacySupported: true, legacyPermissionDenied: false)
            XCTAssertFalse(result.canRun)
            XCTAssertNotNil(result.reason)
            XCTAssertEqual(result.setupAction != nil, microphone == .denied)
        }
        XCTAssertTrue(MacFeatureReadiness.recording(engine: "speechAnalyzer", microphone: .notDetermined,
            advancedSupported: true, legacySupported: false, legacyPermissionDenied: false).canRun)
        let legacy = MacFeatureReadiness.recording(engine: "speechRecognizer", microphone: .authorized,
            advancedSupported: true, legacySupported: true, legacyPermissionDenied: true)
        XCTAssertFalse(legacy.canRun)
        XCTAssertNotNil(legacy.setupAction)
        XCTAssertTrue(MacFeatureReadiness.recording(engine: "speechAnalyzer", microphone: .authorized,
            advancedSupported: true, legacySupported: true, legacyPermissionDenied: true).canRun,
                      "Legacy Speech permission must not block the independent advanced engine")
    }
}
