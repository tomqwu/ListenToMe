import XCTest

@MainActor
final class MobileSpeakerControlsUITests: XCTestCase {
    func testSpeakerOptOutIsReachableWhileListeningAndOptInWaitsForStop() {
        let app = XCUIApplication()
        app.launchArguments = ["--automatic-summary-fixture", "-autoQuickSummary", "NO",
                               "-mobileAIProvider", "apple", "-mobileIdentifySpeakers", "YES"]
        app.launchPastReleaseNotes()
        app.buttons["Start listening"].tap()
        XCTAssertTrue(app.buttons["Stop listening"].waitForExistence(timeout: 5))
        openSettings(app)
        let row = app.switches["identifySpeakersToggle"].firstMatch
        let toggle = row.switches.firstMatch
        revealSettingsControl(row, in: app.collectionViews["aiSettingsForm"])
        XCTAssertTrue(toggle.exists, "Operate the native switch, rather than tapping its containing label row")
        XCTAssertTrue(toggle.isEnabled, "The user must be able to withdraw speaker consent while recording")
        guard toggle.isEnabled else { return }
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertFalse(toggle.isEnabled, "A new speaker run starts with the next recording, after Stop")
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Speaker opt-out while recording"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Stop listening"].isEnabled, "Optional speaker consent cannot stop transcription")
        app.buttons["Stop listening"].tap()
        XCTAssertTrue(app.buttons["Start listening"].waitForExistence(timeout: 5))
        openSettings(app)
        revealSettingsControl(row, in: app.collectionViews["aiSettingsForm"])
        XCTAssertTrue(toggle.isEnabled)
        XCTAssertEqual(toggle.value as? String, "0", "The off choice must survive Stop and reopening Settings")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1")
    }

    func testLongPressRenamesSpeakerAndCancelPreservesLabels() {
        let app = XCUIApplication()
        app.launchArguments = ["--watch-speakers-fixture", "-autoQuickSummary", "NO"]
        XCUIDevice.shared.orientation = .portrait
        app.launchPastReleaseNotes()
        app.buttons["Expand transcript"].tap()
        let reader = app.scrollViews["expandedTranscriptScroll"]
        let speaker = reader.staticTexts["Speaker 1"].firstMatch
        XCTAssertTrue(speaker.waitForExistence(timeout: 5))
        speaker.press(forDuration: 1)
        let rename = app.buttons["Rename speaker…"]
        guard rename.waitForExistence(timeout: 5) else { XCTFail("Long-press must expose speaker rename"); return }
        rename.tap()
        let name = app.textFields["renameSpeakerName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.press(forDuration: 1)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30))
        XCTAssertFalse(app.buttons["renameSpeakerSave"].isEnabled, "Blank names cannot replace a participant")
        name.typeText("Dana")
        app.buttons["renameSpeakerSave"].tap()
        XCTAssertTrue(reader.staticTexts["Dana"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(reader.staticTexts.matching(identifier: "Dana").count, 2,
                       "Rename every line for the same identity")
        XCTAssertFalse(reader.staticTexts["Speaker 1"].exists)
        XCTAssertTrue(reader.staticTexts["Speaker 2"].firstMatch.exists)
        XCTAssertFalse(app.buttons["Pause"].exists, "Long press must not start saved audio")
        reader.staticTexts["Dana"].firstMatch.press(forDuration: 1)
        rename.tap()
        name.tap()
        name.typeText(" discarded edit")
        app.buttons["renameSpeakerCancel"].tap()
        XCTAssertTrue(reader.staticTexts["Dana"].firstMatch.exists)
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = "Rename speaker from transcript"
        capture.lifetime = .keepAlways
        add(capture)
        app.navigationBars["Transcript"].buttons["Done"].tap()
        app.buttons["Notes"].tap()
        let saved = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH 'speakerName-watch:'")).firstMatch
        for _ in 0..<10 where !saved.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertEqual(saved.value as? String, "Dana",
                       "Transcript and speaker settings share the saved identity")
    }

    func testRenameInDuoSurvivesRotation() {
        let app = XCUIApplication()
        app.launchArguments = ["--watch-speakers-fixture", "-autoQuickSummary", "NO"]
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launchPastReleaseNotes()
        XCUIDevice.shared.orientation = .landscapeLeft
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
        let reader = app.scrollViews["transcriptScroll"]
        let speaker = reader.staticTexts["Speaker 2"].firstMatch
        XCTAssertTrue(speaker.waitForExistence(timeout: 5))
        speaker.press(forDuration: 1)
        app.buttons["Rename speaker…"].tap()
        let name = app.textFields["renameSpeakerName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30) + "Sam")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(name.waitForExistence(timeout: 5), "Rotation must preserve the editor")
        XCTAssertEqual(name.value as? String, "Sam", "Rotation must preserve the unsaved name")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        app.buttons["renameSpeakerSave"].tap()
        XCTAssertTrue(reader.staticTexts["Sam"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["summary-panel-quick"].exists)
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = "Speaker rename in two-pane layout"
        capture.lifetime = .keepAlways
        add(capture)
        XCUIDevice.shared.orientation = .portrait
        app.buttons["Expand transcript"].tap()
        XCTAssertTrue(app.scrollViews["expandedTranscriptScroll"].staticTexts["Sam"].waitForExistence(timeout: 5))
    }

    func testRenameEditorActionsAtLargestTextSize() {
        let app = XCUIApplication()
        app.launchArguments = ["--watch-speakers-fixture", "-autoQuickSummary", "NO",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        XCUIDevice.shared.orientation = .portrait
        app.launchPastReleaseNotes()
        app.buttons["Expand transcript"].tap()
        let reader = app.scrollViews["expandedTranscriptScroll"]
        reader.staticTexts["Speaker 1"].firstMatch.press(forDuration: 1)
        app.buttons["Rename speaker…"].tap()
        let name = app.textFields["renameSpeakerName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        XCTAssertTrue(app.buttons["renameSpeakerCancel"].isHittable,
                      "Cancel remains reachable with large text and keyboard")
        XCTAssertTrue(app.buttons["renameSpeakerSave"].isHittable,
                      "Save remains reachable with large text and keyboard")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        XCTAssertLessThanOrEqual(app.buttons["renameSpeakerCancel"].frame.maxY, app.keyboards.firstMatch.frame.minY,
                                 "The entire Cancel control must be above the keyboard")
        XCTAssertLessThanOrEqual(app.buttons["renameSpeakerSave"].frame.maxY, app.keyboards.firstMatch.frame.minY,
                                 "The entire Save control must be above the keyboard")
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = "Speaker editor largest text with keyboard"
        capture.lifetime = .keepAlways
        add(capture)
        app.buttons["renameSpeakerCancel"].tap()
        XCTAssertTrue(reader.staticTexts["Speaker 1"].firstMatch.exists)
    }

    private func openSettings(_ app: XCUIApplication) {
        app.buttons["More"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }
}
