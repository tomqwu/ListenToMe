import FoundationModels
import XCTest

@MainActor
final class MobileAICapabilityUITests: XCTestCase {
    func testSettingsMarksUnavailableAppleChoiceAndExplainsRecovery() {
        let app = XCUIApplication(bundleIdentifier: "com.tomwu.ListenToMe.ios")
        if ProcessInfo.processInfo.environment["LISTENTOME_EXISTING_PHYSICAL_APP"] == "1" {
            app.activate()
        } else {
            app.launchArguments = ["-mobileAIProvider", "apple", "-autoQuickSummary", "NO",
                                   "-mobileIdentifySpeakers", "NO", "-mobileCorrectTranscript", "NO"]
            app.launchPastReleaseNotes()
        }
        app.buttons["More"].tap()
        app.buttons["Settings"].tap()
        let provider = app.buttons["summaryProvider"]
        XCTAssertTrue(provider.waitForExistence(timeout: 10))
        let available: Bool
        if case .available = SystemLanguageModel.default.availability { available = true } else { available = false }
        let explanation = app.staticTexts["appleIntelligenceUnavailable"]
        if !available {
            XCTAssertTrue(explanation.exists, "An unavailable saved choice needs an explicit recovery explanation")
            XCTAssertTrue(explanation.label.contains("Choose a supported provider"), explanation.label)
            XCTAssertTrue(explanation.label.contains("recording"), explanation.label)
        }
        provider.tap()
        let choice = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@",
            "Apple Intelligence · on-device", "Apple Intelligence · unavailable")).firstMatch
        print("APPLE_PROVIDER_LABEL:", provider.label)
        print("APPLE_MENU_MATCHES:", app.buttons.matching(NSPredicate(format: "label CONTAINS 'Apple Intelligence'")).allElementsBoundByIndex.map { $0.label })
        let alternative = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Ollama'")).firstMatch
        XCTAssertTrue(alternative.waitForExistence(timeout: 5), "Supported alternatives remain an explicit choice")
        if available {
            XCTAssertTrue(choice.exists)
            XCTAssertTrue(choice.isEnabled)
        } else {
            XCTAssertTrue(provider.label.contains("unavailable"), provider.label)
            XCTAssertFalse(choice.exists, "Unavailable Apple must not be offered as a provider action")
        }
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Summary AI capability choice"; image.lifetime = .keepAlways; add(image)
        app.navigationBars["Settings"].tap() // dismiss outside the menu without changing the provider
        app.buttons["Done"].tap()
    }
}
