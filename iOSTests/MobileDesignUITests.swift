import XCTest

@MainActor
final class MobileDesignUITests: XCTestCase {
    func testBrandAndConversationToolsRemainVisibleAcrossTheWorkspace() {
        let app = XCUIApplication()
        app.launchArguments = ["--design-review-fixture", "-autoQuickSummary", "NO"]
        app.launch()
        let brand = app.descendants(matching: .any).matching(identifier: "appBrand").firstMatch
        XCTAssertTrue(brand.waitForExistence(timeout: 5))
        XCTAssertTrue(app.windows.firstMatch.frame.contains(brand.frame))
        for name in ["History", "New", "Save", "Notes", "Start listening"] {
            XCTAssertTrue(app.buttons[name].isHittable, "\(name) must remain directly available")
        }
        capture(app, "Branded Live workspace")
        if app.segmentedControls["workspaceTabs"].exists {
            for tab in ["Summary", "Deep"] {
                app.segmentedControls["workspaceTabs"].buttons[tab].tap()
                capture(app, "Branded \(tab) workspace")
            }
        } else {
            app.segmentedControls["reviewTabs"].buttons["Summary"].tap()
            capture(app, "Branded iPad Summary")
        }
        app.buttons["Notes"].tap()
        XCTAssertTrue(app.navigationBars["Notes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Import from Calendar"].exists)
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
