import XCTest

@MainActor
final class MobileWorkspaceUITests: XCTestCase {
    /// Issue #235: a Deep model an older build saved is harmless; there is no Deep pane to use it.
    func testAnOldDeepModelSettingIsHarmlessAndNoDeepPaneExists() {
        let app = XCUIApplication()
        let catalog = "[{\"name\":\"glm-5.3-flash\"},{\"name\":\"glm-5.3\"},{\"name\":\"deepseek-v4-pro:0813\"}]"
        app.launchArguments = ["-mobileAIProvider", "ollama", "-mobileOllamaCatalog", Data(catalog.utf8).base64EncodedString(),
                               "-mobileOllamaDeepModel", "glm-5.3-flash", "-mobileOllamaQuickModel", "glm-5.3-flash",
                               "-mobileOllamaModel", "glm-5.3"]
        app.launchPastReleaseNotes()
        if app.segmentedControls["workspaceTabs"].exists {
            XCTAssertFalse(app.segmentedControls["workspaceTabs"].buttons["Deep"].exists)
            app.segmentedControls["workspaceTabs"].buttons["Summary"].tap()
        }
        XCTAssertFalse(app.segmentedControls["reviewTabs"].exists)
        XCTAssertFalse(app.buttons["panel-model-deep"].exists)
        let model = app.buttons["panel-model-summary"]
        XCTAssertTrue(model.waitForExistence(timeout: 5))
        XCTAssertTrue(model.label.contains("glm-5.3"))
        model.tap()
        XCTAssertTrue(app.navigationBars["Summary model"].waitForExistence(timeout: 5))
        let pro = app.buttons["model-deepseek-v4-pro:0813"].firstMatch
        let list = app.collectionViews["roleModelList"]
        for _ in 0..<5 where !pro.isHittable { list.swipeUp() }
        XCTAssertTrue(pro.isHittable)
        pro.tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(model.label.contains("deepseek-v4-pro:0813"))
        capture(app, "Summary model with an old Deep setting")
    }

    func testReviewModesAndRecordingControlsStayAccessible() {
        let app = XCUIApplication(); app.launchPastReleaseNotes()
        if app.segmentedControls["workspaceTabs"].exists {
            for (tab, role) in [("Live", "quick"), ("Summary", "summary")] {
                app.segmentedControls["workspaceTabs"].buttons[tab].tap()
                XCTAssertTrue(app.buttons["panel-model-\(role)"].isHittable)
                XCTAssertTrue(app.buttons["Start listening"].isHittable)
                XCTAssertTrue(app.buttons["Notes"].isHittable)
                capture(app, "Phone \(tab)")
            }
        } else {
            XCTAssertTrue(app.otherElements["wideMeetingWorkspace"].exists)
            XCTAssertTrue(app.staticTexts["Live transcript"].isHittable)
            XCTAssertTrue(app.staticTexts["Quick Summary"].isHittable)
            // Summary sits beside Live; there is no Deep pane to switch to (#235).
            XCTAssertFalse(app.segmentedControls["reviewTabs"].exists)
            XCTAssertTrue(app.buttons["panel-model-summary"].isHittable)
            XCTAssertGreaterThan(app.buttons["panel-model-summary"].frame.minX,
                                 app.buttons["panel-model-quick"].frame.maxX)
            capture(app, "iPad Summary")
        }
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
