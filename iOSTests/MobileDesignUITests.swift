import XCTest

@MainActor
final class MobileDesignUITests: XCTestCase {
    func testReleaseFixtureRepresentsSupportedRecordingWithoutRequestingMicrophone() {
        let app = XCUIApplication()
        app.launchArguments = ["--design-review-fixture", "-autoQuickSummary", "NO", "-mobileAIProvider", "apple"]
        app.launchPastReleaseNotes()
        let start = app.buttons["Start listening"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: start)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        XCTAssertFalse(app.staticTexts["recordingSupportReason"].exists)
        XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists)
        capture(app, "Synthetic supported-device workspace for release capture")
    }

    func testBrandAndConversationToolsRemainVisibleAcrossTheWorkspace() {
        let app = XCUIApplication()
        app.launchArguments = ["--design-review-fixture", "-autoQuickSummary", "NO", "-mobileAIProvider", "apple"]
        app.launchPastReleaseNotes()
        let brand = app.descendants(matching: .any).matching(identifier: "appBrand").firstMatch
        XCTAssertTrue(brand.waitForExistence(timeout: 5))
        XCTAssertTrue(app.windows.firstMatch.frame.contains(brand.frame))
        for name in ["History", "New", "Save", "Notes", "Start listening"] {
            XCTAssertTrue(app.buttons[name].isHittable, "\(name) must remain directly available")
        }
        capture(app, "Branded Live workspace")
        if app.segmentedControls["workspaceTabs"].exists {
            XCTAssertFalse(app.segmentedControls["workspaceTabs"].buttons["Deep"].exists, "No Deep tab on iOS (#235)")
            app.segmentedControls["workspaceTabs"].buttons["Summary"].tap()
            capture(app, "Branded Summary workspace")
        } else {
            capture(app, "Branded iPad Summary")
        }
        // The fixture conversation was saved with a Deep analysis by an older version: read-only.
        let earlier = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Earlier deep analysis")).firstMatch
        for _ in 0..<5 where !earlier.isHittable { app.swipeUp() }
        XCTAssertTrue(earlier.isHittable)
        earlier.tap()
        let earlierText = app.staticTexts["earlierDeepAnalysisText"]
        XCTAssertTrue(earlierText.waitForExistence(timeout: 5))
        for _ in 0..<5 where !earlierText.isHittable { app.swipeUp() }
        XCTAssertTrue(earlierText.label.contains("Which feedback would change"))
        XCTAssertFalse(app.buttons["Generate Deep Summary"].exists, "Nothing new is generated as Deep")
        capture(app, "Earlier deep analysis, read-only")
        for _ in 0..<5 where !app.buttons["Notes"].isHittable { app.swipeDown() }
        app.buttons["Notes"].tap()
        XCTAssertTrue(app.navigationBars["Notes"].waitForExistence(timeout: 5))
        let calendar = app.buttons["Import from Calendar"]
        for _ in 0..<5 where !calendar.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(calendar.isHittable, "Imports remain reachable below Notes and Prompt")
        capture(app, "Notes and imports")
        app.buttons["Done"].tap()
        app.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        capture(app, "Conversation history")
        app.buttons["Done"].tap()
        app.buttons["More"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(brand.exists)
        capture(app, "Branded settings")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
