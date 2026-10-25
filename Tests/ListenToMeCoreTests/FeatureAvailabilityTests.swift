import XCTest
@testable import ListenToMeCore

final class FeatureAvailabilityTests: XCTestCase {
    func testUnsupportedFeaturesHaveNoSelectableOrRunnableAction() {
        let unsupported = FeatureAvailability.unsupported(reason: "This OS or hardware does not support the feature.")
        XCTAssertFalse(unsupported.canConfigure)
        XCTAssertFalse(unsupported.canRun)
        XCTAssertEqual(unsupported.reason, "This OS or hardware does not support the feature.")
        XCTAssertNil(unsupported.setupAction)
    }

    func testSetupRequiredFeaturesExplainConfigurationButCannotExecute() {
        let permission = FeatureAvailability.setupRequired(reason: "Microphone access is off.", action: "Open microphone settings")
        XCTAssertTrue(permission.canConfigure)
        XCTAssertFalse(permission.canRun)
        XCTAssertEqual(permission.reason, "Microphone access is off.")
        XCTAssertEqual(permission.setupAction, "Open microphone settings")
    }

    func testTemporaryUnavailabilityDoesNotAdvertiseWorkingExecution() {
        let disconnected = FeatureAvailability.temporarilyUnavailable(reason: "Connect the paired iPhone.")
        XCTAssertTrue(disconnected.canConfigure)
        XCTAssertFalse(disconnected.canRun)
        XCTAssertEqual(disconnected.reason, "Connect the paired iPhone.")
        XCTAssertNil(disconnected.setupAction)
    }

    func testReadinessTransitionEnablesExecutionAndClearsSetupReason() {
        var availability = FeatureAvailability.setupRequired(reason: "Model not ready.", action: "Prepare local model")
        XCTAssertFalse(availability.canRun)
        availability = .ready
        XCTAssertTrue(availability.canConfigure)
        XCTAssertTrue(availability.canRun)
        XCTAssertNil(availability.reason)
        XCTAssertNil(availability.setupAction)
    }
}
