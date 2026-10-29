import XCTest

@MainActor
final class MobileSpeakerControlsUITests: XCTestCase {
    func testColdLaunchReadinessKeepsDuoRenameControlsVisible() {
        let app = XCUIApplication()
        app.launchArguments = ["--watch-speakers-fixture", "-autoQuickSummary", "NO",
                               "-mobileIdentifySpeakers", "YES", "-mobileCorrectTranscript", "NO"]
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launchPastReleaseNotes()
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Speaker labels on"),
                                             object: app.staticTexts["captureStatus"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed,
                       "Cold launch must synchronize real scene readiness before offering the rename workspace")
        XCTAssertFalse(app.staticTexts["Speaker labels: models not loaded"].exists)
        XCTAssertFalse(app.buttons["Stop listening"].exists, "Readiness must not begin recording")
        attachRenameReadiness(app, name: "Cold launch speaker rename readiness")

        XCUIDevice.shared.orientation = .landscapeLeft
        guard assertSpeakerDuoWorkspaceVisible(app) else { return }
        attachRenameReadiness(app, name: "Landscape speaker rename readiness")
        let reader = app.scrollViews["transcriptScroll"]
        XCTAssertGreaterThan(reader.frame.height, 70, "Keep readable transcript space below the header")
        let speaker = reader.staticTexts["Speaker 2"].firstMatch
        XCTAssertTrue(speaker.waitForExistence(timeout: 5))
        XCTAssertTrue(speaker.isHittable)
        assertWholeRenameControl(speaker, inside: reader.frame)
        speaker.press(forDuration: 1)
        let rename = app.buttons["Rename speaker…"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        XCTAssertTrue(rename.isEnabled)
        assertWholeRenameControl(rename, inside: app.frame)
        rename.tap()
        let name = app.textFields["renameSpeakerName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30) + "Sam")
        let save = app.buttons["renameSpeakerSave"]
        let cancel = app.buttons["renameSpeakerCancel"]
        XCTAssertTrue(save.isHittable)
        XCTAssertTrue(cancel.isHittable)
        assertWholeRenameControl(save, inside: app.frame)
        assertWholeRenameControl(cancel, inside: app.frame)
        if app.keyboards.firstMatch.exists {
            XCTAssertLessThanOrEqual(save.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
            XCTAssertLessThanOrEqual(cancel.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
        }
        save.tap()
        XCTAssertTrue(reader.staticTexts["Sam"].waitForExistence(timeout: 5))
        XCTAssertFalse(reader.staticTexts["Speaker 2"].exists)
        guard assertSpeakerDuoWorkspaceVisible(app) else { return }
        XCTAssertTrue(app.buttons["Start listening"].isEnabled)
        XCTAssertFalse(app.buttons["Stop listening"].exists)
        XCUIDevice.shared.orientation = .portrait
        app.buttons["Expand transcript"].tap()
        assertExpandedRenameIsolation(app)
    }

    private func assertWholeRenameControl(_ control: XCUIElement, inside viewport: CGRect,
                                          file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(control.frame.width, 0, file: file, line: line)
        XCTAssertGreaterThan(control.frame.height, 0, file: file, line: line)
        XCTAssertGreaterThanOrEqual(control.frame.minX, viewport.minX - 1, file: file, line: line)
        XCTAssertGreaterThanOrEqual(control.frame.minY, viewport.minY - 1, file: file, line: line)
        XCTAssertLessThanOrEqual(control.frame.maxX, viewport.maxX + 1, file: file, line: line)
        XCTAssertLessThanOrEqual(control.frame.maxY, viewport.maxY + 1, file: file, line: line)
    }

    private func attachRenameReadiness(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name + " accessibility"; hierarchy.lifetime = .keepAlways; add(hierarchy)
    }

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
        guard assertSpeakerDuoWorkspaceVisible(app) else { return }
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
        guard assertSpeakerDuoWorkspaceVisible(app) else { return }
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = "Speaker rename in two-pane layout"
        capture.lifetime = .keepAlways
        add(capture)
        XCUIDevice.shared.orientation = .portrait
        app.buttons["Expand transcript"].tap()
        assertExpandedRenameIsolation(app)
    }

    private func assertExpandedRenameIsolation(_ app: XCUIApplication,
                                                file: StaticString = #filePath, line: UInt = #line) {
        let reader = app.scrollViews["expandedTranscriptScroll"]
        XCTAssertTrue(reader.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(reader.staticTexts["Sam"].firstMatch.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertEqual(reader.staticTexts.matching(identifier: "Speaker 1").count, 2,
                       "Both lines of the other identity must keep their name", file: file, line: line)
        XCTAssertEqual(reader.staticTexts.matching(identifier: "Sam").count, 1,
                       "Only the selected identity's line is renamed", file: file, line: line)
        XCTAssertFalse(reader.staticTexts["Speaker 2"].exists, file: file, line: line)
    }

    private func assertSpeakerDuoWorkspaceVisible(_ app: XCUIApplication,
                                                  file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let duo = app.otherElements["twoPaneMeetingWorkspace"]
        XCTAssertTrue(duo.waitForExistence(timeout: 5), "Rename must use actual Duo, not a stacked fallback",
                      file: file, line: line)
        guard duo.exists else {
            attachRenameReadiness(app, name: "Missing Duo during speaker rename rotation")
            return false
        }
        XCTAssertFalse(app.buttons["retrySpeakers"].exists,
                       "Ready speaker labels must not leave a stale Retry control", file: file, line: line)
        let transcript = app.otherElements["transcriptPanel"]
        let quick = app.otherElements["summary-panel-quick"]
        XCTAssertTrue(transcript.exists, file: file, line: line)
        XCTAssertTrue(quick.exists, file: file, line: line)
        assertWholeRenameControl(transcript, inside: app.frame, file: file, line: line)
        assertWholeRenameControl(quick, inside: app.frame, file: file, line: line)
        XCTAssertGreaterThanOrEqual(quick.frame.minX, transcript.frame.maxX - 1, file: file, line: line)
        XCTAssertEqual(quick.frame.minY, transcript.frame.minY, accuracy: 2, file: file, line: line)
        XCTAssertGreaterThan(app.scrollViews["transcriptScroll"].frame.height, 70, file: file, line: line)
        XCTAssertTrue(app.scrollViews["transcriptScroll"].isHittable, file: file, line: line)
        XCTAssertTrue(app.buttons["panel-model-quick"].isHittable, file: file, line: line)
        return true
    }

    func testRenameEditorActionsAtLargestTextSize() {
        let app = XCUIApplication()
        app.launchArguments = ["--watch-speakers-fixture", "-autoQuickSummary", "NO",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        XCUIDevice.shared.orientation = .portrait
        app.launchPastReleaseNotes()
        app.buttons["Expand transcript"].tap()
        let reader = app.scrollViews["expandedTranscriptScroll"]
        guard let speaker = revealExactFirstSpeakerOne(in: reader, app: app) else { return }
        speaker.press(forDuration: 1)
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
        XCTAssertTrue(speaker.exists, "Cancel preserves the exact original speaker row")
        XCTAssertEqual(speaker.label, "Speaker 1")
    }

    private func revealExactFirstSpeakerOne(in reader: XCUIElement, app: XCUIApplication,
                                             file: StaticString = #filePath, line: UInt = #line) -> XCUIElement? {
        guard reader.waitForExistence(timeout: 5) else {
            XCTFail("Expanded transcript reader is missing", file: file, line: line)
            attachRenameReadiness(app, name: "Missing expanded speaker reader")
            return nil
        }
        let first = reader.staticTexts["Speaker 1"].firstMatch
        guard first.waitForExistence(timeout: 5), first.identifier.hasPrefix("transcript-speaker-") else {
            XCTFail("The original first Speaker 1 needs a stable transcript identity", file: file, line: line)
            attachRenameReadiness(app, name: "Missing first speaker identity")
            return nil
        }
        // Freeze the original row identity before scrolling; never substitute a later Speaker 1.
        let speaker = reader.staticTexts.matching(identifier: first.identifier).firstMatch
        var scrollTowardEarlierText = true
        for attempt in 0...12 {
            let viewport = reader.frame.intersection(app.frame).insetBy(dx: 2, dy: 2)
            guard !viewport.isNull, viewport.width > 20, viewport.height > 60 else {
                XCTFail("Expanded reader has no usable visible viewport", file: file, line: line)
                break
            }
            if speaker.exists {
                let frame = speaker.frame
                if speaker.isHittable, frame.width > 0, frame.height > 0, viewport.contains(frame) {
                    assertWholeRenameControl(speaker, inside: viewport, file: file, line: line)
                    attachRenameReadiness(app, name: "Exact first speaker revealed at largest text")
                    return speaker
                }
                if frame.minY < viewport.minY { scrollTowardEarlierText = true }
                else if frame.maxY > viewport.maxY { scrollTowardEarlierText = false }
                else {
                    XCTFail("Speaker is inside the reader but blocked; scrolling must not hide that defect",
                            file: file, line: line)
                    break
                }
            }
            guard attempt < 12 else { break }
            // Stay inside the reader content; its rightmost strip belongs to the scroll indicator.
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let x = viewport.minX + viewport.width * 0.85 - app.frame.minX
            let low = viewport.minY + viewport.height * 0.30 - app.frame.minY
            let high = viewport.minY + viewport.height * 0.75 - app.frame.minY
            let from = origin.withOffset(CGVector(dx: x, dy: scrollTowardEarlierText ? low : high))
            let to = origin.withOffset(CGVector(dx: x, dy: scrollTowardEarlierText ? high : low))
            from.press(forDuration: 0.05, thenDragTo: to)
        }
        attachRenameReadiness(app, name: "Exact first speaker could not be revealed")
        XCTFail("The same first Speaker 1 was not fully visible/hittable after bounded reader scrolling",
                file: file, line: line)
        return nil
    }

    private func openSettings(_ app: XCUIApplication) {
        app.buttons["More"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }
}
