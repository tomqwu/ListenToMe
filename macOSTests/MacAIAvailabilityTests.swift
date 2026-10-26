import XCTest
import ListenToMeCore

/// Baseline adoption: the native view consumes these same choices and selection actions.
@MainActor
final class MacAIAvailabilityTests: XCTestCase {
    func testUnavailableNativeAppleChoicePreservesEveryExplicitProvider() {
        let menu = MacAIAvailability { "Apple Intelligence is unavailable on this Mac." }
        XCTAssertFalse(menu.choices.contains(.apple))
        for provider: AIProcessingMode in [.off, .local, .cloud, .cloudAI, .openAI] {
            XCTAssertTrue(menu.choices.contains(provider))
            XCTAssertEqual(menu.select(.apple, current: provider), provider)
        }
        XCTAssertNotNil(menu.reason)
    }

    func testRetainedAppleMenuActionRechecksReadinessAndForegroundCanRecover() {
        var reason: String?
        let menu = MacAIAvailability { reason }
        XCTAssertTrue(menu.choices.contains(.apple))
        reason = "The model is preparing."
        XCTAssertEqual(menu.select(.apple, current: .local), .local)
        XCTAssertFalse(menu.choices.contains(.apple))
        XCTAssertEqual(menu.reason, reason)
        reason = nil
        menu.refresh()
        XCTAssertTrue(menu.choices.contains(.apple))
        XCTAssertEqual(menu.select(.apple, current: .local), .apple)
    }

    func testSavedUnavailableAppleChoiceRemainsSavedUntilExplicitAlternativeSelection() {
        let menu = MacAIAvailability { "Apple Intelligence was turned off." }
        XCTAssertEqual(menu.select(.apple, current: .apple), .apple)
        XCTAssertFalse(menu.choices.contains(.apple))
        XCTAssertEqual(menu.select(.local, current: .apple), .local)
        XCTAssertNotNil(menu.reason)
    }
}
