import XCTest

@MainActor
final class MobileWorkspaceUITests: XCTestCase {
    func testDeepModelMigrationIsVisibleAndChooserExcludesFlash() {
        let app = XCUIApplication()
        let catalog = "[{\"name\":\"glm-5.3-flash\"},{\"name\":\"glm-5.3\"},{\"name\":\"deepseek-v4-pro:0813\"}]"
        app.launchArguments = ["-mobileAIProvider", "ollama", "-mobileOllamaCatalog", Data(catalog.utf8).base64EncodedString(),
                               "-mobileOllamaDeepModel", "glm-5.3-flash", "-mobileOllamaQuickModel", "glm-5.3-flash"]
        app.launch()
        if app.segmentedControls["workspaceTabs"].exists {
            app.segmentedControls["workspaceTabs"].buttons["Deep"].tap()
        }
        let model = app.buttons["panel-model-deep"]
        XCTAssertTrue(model.waitForExistence(timeout: 5))
        XCTAssertTrue(model.label.contains("glm-5.3"))
        XCTAssertFalse(model.label.lowercased().contains("flash"))
        model.tap()
        XCTAssertTrue(app.navigationBars["Deep Summary model"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["model-glm-5.3-flash"].exists)
        let pro = app.buttons["model-deepseek-v4-pro:0813"].firstMatch
        let list = app.collectionViews["roleModelList"]
        for _ in 0..<5 where !pro.isHittable { list.swipeUp() }
        XCTAssertTrue(pro.isHittable)
        pro.tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(model.label.contains("deepseek-v4-pro:0813"))
        capture(app, "Deep Summary full model")
    }

    func testReviewModesAndRecordingControlsStayAccessible() {
        let app = XCUIApplication(); app.launch()
        if app.segmentedControls["workspaceTabs"].exists {
            for (tab, role) in [("Live", "quick"), ("Summary", "summary"), ("Deep", "deep")] {
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
            for (tab, role) in [("Summary", "summary"), ("Deep Summary", "deep")] {
                app.segmentedControls["reviewTabs"].buttons[tab].tap()
                XCTAssertTrue(app.buttons["panel-model-\(role)"].isHittable)
                XCTAssertGreaterThan(app.buttons["panel-model-\(role)"].frame.minX,
                                     app.buttons["panel-model-quick"].frame.maxX)
                capture(app, "iPad \(tab)")
            }
        }
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
