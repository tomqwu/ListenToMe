import XCTest
import Foundation
import ListenToMeCore

/// Baseline adoption: executes production framework mapping without a microphone request.
@MainActor
final class MacCapabilityNativeBaselineTests: XCTestCase {
    func testUnsupportedNativeLocaleExplainsRecoveryBeforeCapture() async {
        let unavailable = await MacDeviceCapabilities.recording(engine: "speechAnalyzer",
            locale: Locale(identifier: "xx-XX"), checkMicrophone: false)
        XCTAssertFalse(unavailable.canRun)
        XCTAssertTrue(unavailable.reason?.contains("Settings") == true)
        XCTAssertTrue(unavailable.reason?.contains("language") == true)
    }

    func testNativeAppleSummaryChecksHardwareOrConversationLanguage() {
        XCTAssertNotNil(MacDeviceCapabilities.appleReason(locale: Locale(identifier: "xx-XX")))
    }
}
