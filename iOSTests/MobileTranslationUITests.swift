import XCTest
import UIKit

@MainActor
final class MobileTranslationUITests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--design-review-fixture", "--translation-fixture", "-autoQuickSummary", "NO"] + extra
        app.launchPastReleaseNotes()
        return app
    }
    private func openOptions(_ app: XCUIApplication) -> Bool {
        app.buttons["More"].tap()
        let options = app.buttons["Live translation"]
        guard options.waitForExistence(timeout: 5) else {
            XCTFail("Translation and summary language must have a reachable native control"); return false
        }
        options.tap()
        return app.switches["liveTranslationToggle"].waitForExistence(timeout: 5)
    }
    private func choose(_ identifier: String, _ language: String, in app: XCUIApplication) {
        let picker = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        for _ in 0..<5 where !picker.isHittable { app.swipeUp() }
        XCTAssertTrue(picker.isHittable); picker.tap()
        app.buttons[language].tap()
        // iOS may keep a picker menu presented after selection. Dismiss that menu before the
        // next control rather than treating the first background tap as a toggle/Done action.
        if app.buttons[language].exists {
            if app.navigationBars["Live translation"].exists {
                app.navigationBars["Live translation"].staticTexts["Live translation"].tap()
            } else { app.staticTexts["On-device translation keeps the original below. Check translated wording before sharing."].tap() }
        }
        XCTAssertTrue(picker.label.contains(language))
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
    func testLanguageControlsTranslateFinalSpeechInPortraitAndDuoWithoutChangingOriginal() {
        let app = launch(); guard openOptions(app) else { return }
        choose("translationTargetPicker", "French", in: app)
        let toggle = app.switches["liveTranslationToggle"]
        for _ in 0..<5 where !toggle.isHittable { app.swipeDown() }
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1")
        capture(app, "Live translation options")
        XCTAssertTrue(app.buttons["Done"].isHittable)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Live translation"].waitForNonExistence(timeout: 5))
        let translated = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "translated-line-")).firstMatch
        XCTAssertTrue(translated.waitForExistence(timeout: 5))
        let originals = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "transcript-text-"))
        XCTAssertGreaterThan(originals.count, 0, "Original speech stays alongside its translation")
        XCTAssertFalse(app.buttons["Stop listening"].exists, "Translation never starts the microphone")
        capture(app, "Original transcript and on-device translation portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
        let duo = app.otherElements["twoPaneMeetingWorkspace"]
        let wide = app.otherElements["wideMeetingWorkspace"]
        XCTAssertTrue(duo.waitForExistence(timeout: 3) || wide.exists)
        XCTAssertTrue(translated.waitForExistence(timeout: 5))
        capture(app, "Original transcript and translation in Duo or iPad wide layout")
    }
    func testSummaryPageOffersExplicitTranslationAndKeepsOriginal() {
        let app = launch()
        if app.buttons["Summary"].firstMatch.exists { app.buttons["Summary"].firstMatch.tap() }
        let option = app.buttons["summaryTranslationOptions"]
        XCTAssertTrue(option.waitForExistence(timeout: 5), "Translation must be available on the Summary page")
        guard option.exists else { return }
        option.tap()
        choose("summaryTranslationTargetPicker", "French", in: app)
        XCTAssertFalse(app.staticTexts["translatedSummary"].exists)
        app.buttons["translateSummary"].tap()
        XCTAssertTrue(app.staticTexts["translatedSummary"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["output-summary"].exists, "The original summary remains available")
        XCTAssertFalse(app.buttons["Stop listening"].exists)
        capture(app, "Summary page French translation beside original")
        app.buttons["closeSummaryTranslation"].tap()
        XCTAssertFalse(app.staticTexts["translatedSummary"].exists)
        XCTAssertTrue(app.staticTexts["output-summary"].isHittable)
    }
    func testSummaryMissingPacksAndLargestTextKeepOriginalReachable() {
        let app = launch(["--translation-needs-packs", "-UIPreferredContentSizeCategoryName",
                          "UICTContentSizeCategoryAccessibilityXXXL"])
        if app.buttons["Summary"].firstMatch.exists { app.buttons["Summary"].firstMatch.tap() }
        let option = app.buttons["summaryTranslationOptions"]
        for _ in 0..<8 where !option.isHittable { app.swipeUp() }
        XCTAssertTrue(option.isHittable); option.tap()
        choose("summaryTranslationTargetPicker", "French", in: app)
        let translate = app.buttons["translateSummary"]
        for _ in 0..<8 where !translate.isHittable { app.swipeUp() }
        XCTAssertTrue(translate.isHittable); translate.tap()
        let prepare = app.buttons["prepareTranslationLanguages"]
        XCTAssertTrue(prepare.waitForExistence(timeout: 5))
        for _ in 0..<8 where !prepare.isHittable { app.swipeUp() }
        XCTAssertTrue(prepare.isHittable)
        XCTAssertFalse(app.staticTexts["Preparing translation languages…"].exists)
        XCTAssertFalse(app.staticTexts["translatedSummary"].exists)
        capture(app, "Summary language setup at largest accessibility text")
        let close = app.buttons["closeSummaryTranslation"]
        for _ in 0..<8 where !close.isHittable { app.swipeDown() }
        XCTAssertTrue(close.isHittable); close.tap()
        let original = app.staticTexts["output-summary"]
        for _ in 0..<8 where !original.isHittable { app.swipeUp() }
        XCTAssertTrue(original.isHittable)
        XCTAssertTrue(app.buttons["Start listening"].isHittable)
        XCTAssertFalse(app.buttons["Stop listening"].exists)
        capture(app, "Original summary remains readable at largest accessibility text")
    }
    func testMissingPacksExplainSetupWithoutStartingDownloadOrRecording() {
        let app = launch(["--translation-needs-packs"]); guard openOptions(app) else { return }
        choose("translationTargetPicker", "French", in: app)
        let toggle = app.switches["liveTranslationToggle"]
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1")
        XCTAssertTrue(app.buttons["prepareTranslationLanguages"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Preparing translation languages…"].exists)
        XCTAssertFalse(app.buttons["Stop listening"].exists)
        capture(app, "On-device translation setup required without automatic download")
    }
}
