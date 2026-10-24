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

    func testPhoneTwoPaneLayoutAndPageSelectionSurviveRotation() {
        let app = XCUIApplication()
        app.launchArguments = ["--transcript-scroll-fixture", "--two-pane-layout-fixture",
                               "-mobileCorrectTranscript", "NO", "-autoQuickSummary", "NO"]
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launchPastReleaseNotes()
        XCTAssertTrue(app.otherElements["transcriptPanel"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["twoPaneMeetingWorkspace"].exists)
        let title = app.textFields["conversationTitle"].value as? String
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.otherElements["twoPaneMeetingWorkspace"].waitForExistence(timeout: 5))
        let transcript = app.otherElements["transcriptPanel"]
        let quick = app.otherElements["summary-panel-quick"]
        XCTAssertGreaterThanOrEqual(quick.frame.minX, transcript.frame.maxX)
        XCTAssertEqual(quick.frame.minY, transcript.frame.minY, accuracy: 2)
        XCTAssertGreaterThan(app.scrollViews["transcriptScroll"].frame.height, 70, "leave readable space below the header")
        XCTAssertTrue(app.buttons["Start listening"].isHittable)
        XCTAssertTrue(app.buttons["Expand transcript"].isHittable)
        XCTAssertTrue(app.buttons["panel-model-quick"].isHittable)
        XCTAssertTrue(app.staticTexts["output-quick"].isHittable, "show the answer before status details")
        capture(app, "iPhone two-pane Live workspace")
        let latest = transcript.staticTexts["The latest phrase."]
        let latestY = latest.frame.minY
        let auto = quick.switches["Auto summaries"].firstMatch
        for _ in 0..<3 where !auto.isHittable { quick.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(auto.isHittable, "Auto remains reachable below the answer")
        XCTAssertEqual(latest.frame.minY, latestY, accuracy: 2, "Quick scrolling must not move the transcript")
        app.buttons["Expand transcript"].tap()
        XCTAssertTrue(app.navigationBars["Transcript"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.navigationBars["Transcript"].exists, "the reader survives a layout change")
        app.buttons["Done"].tap()
        app.segmentedControls["workspaceTabs"].buttons["Summary"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["panel-model-summary"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["twoPaneMeetingWorkspace"].exists)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.otherElements["summary-panel-summary"].exists)
        XCTAssertFalse(app.otherElements["summary-panel-quick"].exists)
        XCTAssertEqual(app.textFields["conversationTitle"].value as? String, title)
        app.segmentedControls["workspaceTabs"].buttons["Live"].tap()
        XCTAssertTrue(app.staticTexts["output-quick"].label.contains("Next steps"), "the answer survives rotation")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
