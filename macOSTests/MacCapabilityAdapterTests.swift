import XCTest
import ListenToMeCore

/// Baseline adoption of existing outcomes through the production framework adapter's metadata seam.
@MainActor
final class MacCapabilityAdapterTests: XCTestCase {
    func testDeniedMicrophoneBlocksCaptureButStillAllowsEngineConfiguration() async {
        var microphoneReads = 0
        var environment = metadata()
        environment.microphone = { microphoneReads += 1; return .denied }
        let locale = Locale(identifier: "en-US")
        let capture = await MacDeviceCapabilities.recording(engine: "speechAnalyzer", locale: locale, environment: environment)
        XCTAssertFalse(capture.canRun)
        XCTAssertEqual(capture.setupAction, "Open microphone settings")
        XCTAssertEqual(microphoneReads, 1)
        let choice = await MacDeviceCapabilities.recording(engine: "speechAnalyzer", locale: locale,
                                                           checkMicrophone: false, environment: environment)
        XCTAssertTrue(choice.canRun)
        XCTAssertEqual(microphoneReads, 1, "Choosing an engine must not require capture permission")
    }

    func testUnavailableAdvancedFrameworkDoesNotClaimItsLanguageWorks() async {
        var environment = metadata()
        var localeQueries = 0
        environment.advancedAvailable = { false }
        environment.advancedLocale = { _ in localeQueries += 1; return true }
        let result = await MacDeviceCapabilities.recording(engine: "speechAnalyzer", locale: .current,
                                                          environment: environment)
        XCTAssertFalse(result.canRun)
        XCTAssertTrue(result.reason?.contains("Settings") == true)
        XCTAssertEqual(localeQueries, 0)
    }

    func testActualSelectedLocaleReachesTheNativeAdapterAndLegacyPermissionIsIndependent() async {
        var environment = metadata()
        let unsupported = Locale(identifier: "xx-XX")
        var checked: Locale?
        environment.advancedLocale = { locale in checked = locale; return locale != unsupported }
        environment.legacyPermissionDenied = { true }
        let blocked = await MacDeviceCapabilities.recording(engine: "speechAnalyzer", locale: unsupported,
                                                           environment: environment)
        XCTAssertEqual(checked, unsupported)
        XCTAssertFalse(blocked.canRun)
        let supported = await MacDeviceCapabilities.recording(engine: "speechAnalyzer", locale: Locale(identifier: "en-US"),
                                                             environment: environment)
        XCTAssertTrue(supported.canRun, "Legacy Speech permission does not block the advanced module")
        let legacy = await MacDeviceCapabilities.recording(engine: "speechRecognizer", locale: .current,
                                                          environment: environment)
        XCTAssertFalse(legacy.canRun)
        XCTAssertEqual(legacy.setupAction, "Open speech recognition settings")
    }

    private func metadata() -> MacDeviceCapabilities.Environment {
        .init(microphone: { .authorized }, advancedAvailable: { true }, advancedLocale: { _ in true },
              legacySupported: { _ in true }, legacyPermissionDenied: { false })
    }
}
