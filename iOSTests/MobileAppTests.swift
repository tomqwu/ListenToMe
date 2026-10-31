import XCTest

@MainActor
final class MobileAppTests: XCTestCase {
    func testEachSummaryRoleCanChooseAndPersistItsOwnModel() {
        let app = XCUIApplication()
        let catalog = "[{\"name\":\"quick-fixture\"},{\"name\":\"summary-fixture\"}]"
        app.launchArguments = ["-mobileAIProvider", "ollama", "-mobileOllamaCatalog",
                               Data(catalog.utf8).base64EncodedString()]
        app.launchPastReleaseNotes()
        for role in ["quick", "summary"] {
            app.buttons["More"].tap()
            app.buttons["Settings"].tap()
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5),
                          "Reopening Settings must finish before revealing either model role")
            let link = app.buttons["choose-model-\(role)"]
            revealSettingsControl(link, in: app.collectionViews["aiSettingsForm"])
            XCTAssertTrue(link.isHittable)
            XCTAssertTrue(app.navigationBars["Settings"].exists, "Revealing the model must keep Settings open")
            link.tap()
            let model = app.buttons["model-\(role)-fixture"]
            revealSettingsControl(model, in: app.collectionViews["roleModelList"])
            XCTAssertTrue(model.isHittable)
            model.tap()
            let title = role == "quick" ? "Quick Summary" : "Summary"
            app.navigationBars["\(title) model"].buttons.firstMatch.tap()
            XCTAssertTrue(link.label.contains("\(role)-fixture"))
            app.buttons["Done"].tap()
        }
        app.terminate(); app.launchPastReleaseNotes()
        app.buttons["More"].tap(); app.buttons["Settings"].tap()
        for role in ["quick", "summary"] {
            let link = app.buttons["choose-model-\(role)"]
            revealSettingsControl(link, in: app.collectionViews["aiSettingsForm"])
            XCTAssertTrue(link.label.contains("\(role)-fixture"))
        }
        XCTAssertFalse(app.buttons["choose-model-deep"].exists, "iOS has no Deep model (#235)")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Independent model settings"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["Done"].tap()
    }

    /// Issue #235: two pages, Live and Summary; no Deep tab.
    func testLiveLayoutAndSummaryTab() {
        let app = XCUIApplication()
        app.launchPastReleaseNotes()
        XCTAssertTrue(app.staticTexts["Live transcript"].isHittable)
        XCTAssertTrue(app.staticTexts["Quick Summary"].isHittable)
        XCTAssertGreaterThan(app.staticTexts["Quick Summary"].frame.minY, app.staticTexts["Live transcript"].frame.maxY)
        let tabs = app.segmentedControls["workspaceTabs"]
        XCTAssertEqual(tabs.buttons.count, 2)
        XCTAssertFalse(tabs.buttons["Deep"].exists)
        XCTAssertFalse(app.buttons["Generate Deep Summary"].exists)
        tabs.buttons["Summary"].tap()
        XCTAssertTrue(app.buttons["generate-summary"].isHittable)
        XCTAssertFalse(app.staticTexts["Live transcript"].exists)
        XCTAssertTrue(app.buttons["Start listening"].isHittable)
        app.segmentedControls["workspaceTabs"].buttons["Live"].tap()
        XCTAssertTrue(app.staticTexts["Quick Summary"].isHittable)
    }

    func testLandscapeAndLargeTextTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launchPastReleaseNotes()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.scrollViews["dashboardScroll"].exists)
        app.segmentedControls["workspaceTabs"].buttons["Summary"].tap()
        XCTAssertTrue(app.buttons["generate-summary"].exists)
        XCTAssertTrue(app.buttons["Start listening"].isHittable)
        let window = app.windows.firstMatch
        XCTAssertGreaterThan(window.frame.width, window.frame.height)
        let scroll = app.scrollViews["dashboardScroll"]
        let recordingReason = app.staticTexts["recordingSupportReason"]
        XCTAssertTrue(recordingReason.exists, "Unavailable recording still needs an explanation on Summary")
        XCTAssertFalse(app.buttons["Start listening"].isEnabled)
        let model = app.buttons["panel-model-summary"]
        // Large text can put the model above or below the viewport. Avoid swiping past it to the end.
        for _ in 0..<20 {
            let viewport = scroll.frame.intersection(window.frame)
            let center = CGPoint(x: model.frame.midX, y: model.frame.midY)
            if viewport.contains(center) && model.isHittable { break }
            let delta = min(viewport.height * 0.35, max(-viewport.height * 0.35, viewport.midY - center.y))
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: delta)),
                        withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTAssertTrue(model.isHittable)
        XCTAssertTrue(scroll.frame.contains(CGPoint(x: model.frame.midX, y: model.frame.midY)))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Landscape accessibility layout"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    func testAutoSummaryPreferenceSurvivesRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--design-review-fixture"]
        app.launchPastReleaseNotes()
        let toggle = app.switches["Auto summaries"].switches.firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        let original = try XCTUnwrap(toggle.value as? String)
        XCTAssertTrue(["0", "1"].contains(original))
        let selected = original == "1" ? "0" : "1"
        func waitForValue(_ value: String, timeout: TimeInterval) -> Bool {
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: toggle)
            return XCTWaiter.wait(for: [changed], timeout: timeout) == .completed
        }
        func setValue(_ value: String) {
            // A freshly booted CI simulator can drop its first synthesized tap. Confirm the
            // actual setting before testing persistence; retry only while it is still unchanged.
            for _ in 0..<2 {
                if toggle.value as? String == value { return }
                XCTAssertTrue(toggle.isHittable)
                toggle.tap()
                if waitForValue(value, timeout: 5) { return }
            }
            XCTAssertEqual(toggle.value as? String, value)
        }
        setValue(selected)
        app.terminate()
        app.launchPastReleaseNotes()
        // Never tap or repair the value after relaunch: persistence must work on its own.
        XCTAssertTrue(waitForValue(selected, timeout: 15))
        setValue(original)
    }

    func testNotesCameraExplanationAndFilePicker() {
        let app = XCUIApplication()
        app.launchPastReleaseNotes()
        app.buttons["Notes"].tap()
        let camera = app.buttons["Take photo"]
        revealAttachment(camera, in: app)
        camera.tap()
        let explanation = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Camera capture requires")).firstMatch
        for _ in 0..<4 where !explanation.isHittable { app.swipeUp() }
        XCTAssertTrue(explanation.exists)
        for _ in 0..<4 where !app.buttons["Add files"].isHittable { app.swipeDown() }
        app.buttons["Add files"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 30))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Notes"].waitForExistence(timeout: 10))
    }

    func testPhotoLibraryPickerCanBeOpenedAndDismissed() {
        let app = XCUIApplication()
        app.launchPastReleaseNotes()
        app.buttons["Notes"].tap()
        // PhotosPicker is exposed as a pop-up button by newer SDKs.
        let library = app.descendants(matching: .any)["Photo library"].firstMatch
        for _ in 0..<6 where !library.isHittable { app.swipeUp() }
        XCTAssertTrue(library.waitForExistence(timeout: 5), app.debugDescription)
        library.tap()
        _ = app.staticTexts["Loading..."].firstMatch.waitForNonExistence(timeout: 30)
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Notes"].exists)
    }

    func testShareExtensionImportsNotesAndPreservesSource() {
        let app = XCUIApplication()
        app.launchPastReleaseNotes()
        app.buttons["New"].tap()
        app.buttons["Notes"].tap()
        let marker = "Shared note " + UUID().uuidString
        app.textViews["Conversation notes"].tap()
        app.textViews["Conversation notes"].typeText(marker)
        app.buttons["Done"].tap()
        app.buttons["More"].tap()
        app.buttons["Share"].tap()
        // Use the Apps list consistently. The original carousel remains in the accessibility
        // hierarchy underneath it, so selecting its first matching cell can tap the wrong app.
        let more = app.cells["More"].firstMatch
        guard more.waitForExistence(timeout: 15) else {
            XCTFail("Share More activity missing: \(app.debugDescription)"); return
        }
        more.tap()
        let destination = app.cells.containing(.staticText, identifier: "ListenToMe")
            .matching(NSPredicate(format: "identifier != %@", "shareCell")).firstMatch
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"), object: destination
        )
        guard XCTWaiter.wait(for: [ready], timeout: 15) == .completed else {
            XCTFail("Apps list destination missing: \(app.debugDescription)"); return
        }
        destination.tap()
        guard app.buttons["Import"].waitForExistence(timeout: 15) else {
            XCTFail("Share import did not open: \(app.debugDescription)"); return
        }
        app.buttons["Import"].tap()
        XCTAssertTrue(app.buttons["Saved"].waitForExistence(timeout: 10))
        app.buttons["finishSharedImport"].tap()
        app.terminate(); app.launchPastReleaseNotes()
        XCTAssertEqual(app.textFields["conversationTitle"].value as? String, "Imported notes")
        app.buttons["Notes"].tap()
        XCTAssertTrue((app.textViews["Conversation notes"].value as? String ?? "").contains(marker))
        app.buttons["Done"].tap()
        app.buttons["History"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", marker)).count, 2)
    }


    func testPrivacyExplainsEveryOptionalOffDeviceProvider() {
        let app = XCUIApplication()
        app.launchPastReleaseNotes()
        app.buttons["More"].tap()
        app.buttons["Settings"].tap()
        let explanation = app.staticTexts["privacyExplanation"]
        revealSettingsControl(explanation, in: app.collectionViews["aiSettingsForm"])
        XCTAssertTrue(explanation.isHittable)
        for phrase in ["run on-device", "If you choose Ollama", "Cloud AI service", "OpenAI-compatible server",
                       "provider shown in AI settings", "AI speech correction", "Keychain"] {
            XCTAssertTrue(explanation.label.contains(phrase), phrase)
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Privacy provider explanation"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    func testOllamaSettingsKeyPersistenceAndRemoval() {
        let app = XCUIApplication()
        app.launchPastReleaseNotes()
        app.buttons["More"].tap()
        app.buttons["Settings"].tap()
        app.buttons["summaryProvider"].tap()
        app.buttons["Ollama Cloud"].tap()
        let field = app.secureTextFields["ollamaAPIKey"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("synthetic-ui-test-key")
        app.buttons["Save API key"].tap()
        XCTAssertTrue(app.staticTexts["savedAPIKey"].waitForExistence(timeout: 3))
        app.terminate()
        app.launchPastReleaseNotes()
        app.buttons["More"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["savedAPIKey"].waitForExistence(timeout: 3))
        app.secureTextFields["ollamaAPIKey"].tap()
        app.secureTextFields["ollamaAPIKey"].typeText("replacement-ui-key")
        app.secureTextFields["ollamaAPIKey"].typeText("\n")
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)
        waitForExpectations(timeout: 5)
        let form = app.collectionViews["aiSettingsForm"]
        let saveAndTest = app.buttons["Save key and test connection"]
        revealSettingsControl(saveAndTest, in: form)
        XCTAssertTrue(saveAndTest.isHittable)
        revealSettingsControl(app.buttons["Save API key"], in: form, towardTop: true)
        app.buttons["Save API key"].tap()
        revealSettingsControl(app.buttons["Remove API key"], in: form)
        app.buttons["Remove API key"].tap()
        XCTAssertFalse(app.staticTexts["savedAPIKey"].exists)
        // The endpoint is user-entered and defaults to Ollama Cloud; it is never chosen for the user.
        let serverField = app.textFields["ollamaBaseURL"]
        revealSettingsControl(serverField, in: form)
        XCTAssertTrue(serverField.exists)
        XCTAssertTrue(app.staticTexts["ollamaServer"].label.contains("https://ollama.com"))
        // Reopen at the top instead of pulling the sheet down while searching for a lazy picker.
        // Repeated downward drags can dismiss Settings after reaching its scroll boundary.
        app.buttons["Done"].tap()
        app.buttons["More"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["summaryProvider"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["ollamaAPIKey"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["savedAPIKey"].exists, "Removing the key must survive reopening Settings")
        let removal = XCTAttachment(screenshot: app.screenshot())
        removal.name = "API key remains removed after Settings reopens"
        removal.lifetime = .keepAlways
        add(removal)
        app.buttons["summaryProvider"].tap()
        app.buttons["Ollama Cloud"].tap()
    }

    func testDeleteConversationAndSummaryModes() {
        let app = XCUIApplication()
        app.launchPastReleaseNotes()
        app.buttons["New"].tap()
        app.buttons["Notes"].tap()
        let notes = app.textViews["Conversation notes"]
        notes.tap()
        let text = "Delete UI test " + UUID().uuidString
        notes.typeText(text)
        app.buttons["Done"].tap()
        app.buttons["Save"].tap()
        app.buttons["More"].tap()
        app.buttons["Full summary"].tap()
        app.buttons["summaryMode"].tap()
        app.buttons["Quick Summary"].tap()
        XCTAssertTrue(app.buttons["full-generate-quick"].exists)
        app.buttons["summaryMode"].tap()
        XCTAssertFalse(app.buttons["summary-option-deep"].exists, "No Deep output on iOS (#235)")
        app.buttons["summary-option-summary"].tap()
        XCTAssertTrue(app.buttons["full-generate-summary"].exists)
        app.buttons["Done"].tap()
        app.buttons["History"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(row.exists)
        row.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        app.buttons["Delete conversation"].tap()
        XCTAssertFalse(row.exists)
        app.terminate()
        app.launchPastReleaseNotes()
        app.buttons["History"].tap()
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch.exists)
    }

    func testSimulatorExplainsUnavailableSpeechWithoutRequestingMicrophone() {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .microphone)
        app.launchPastReleaseNotes()
        let reason = app.staticTexts["recordingSupportReason"]
        XCTAssertTrue(reason.waitForExistence(timeout: 5))
        XCTAssertTrue(reason.label.lowercased().contains("simulator"))
        let details = app.buttons["recordingSupportDetails"]
        XCTAssertTrue(details.isHittable, "Full support guidance remains reachable before Start")
        guard details.exists else { return }
        details.tap()
        let support = app.alerts["Recording support"]
        XCTAssertTrue(support.waitForExistence(timeout: 5))
        XCTAssertTrue(support.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "physical iPhone or iPad")).firstMatch.exists)
        XCTAssertTrue(support.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Microphone permission will not fix this")).firstMatch.exists)
        support.buttons["OK"].tap()
        XCTAssertFalse(app.buttons["Start listening"].isEnabled)
        XCTAssertFalse(app.buttons["Stop listening"].exists)
        XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Unsupported recording explained before Start"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testNotesSurviveNewConversationAndRelaunch() {
        let app = XCUIApplication()
        app.launchPastReleaseNotes()
        app.buttons["New"].tap()
        app.buttons["Notes"].tap()
        let notes = app.textViews["Conversation notes"]
        notes.tap()
        notes.typeText("Decision: review the mobile release on Friday.")
        app.buttons["Done"].tap()
        app.buttons["Save"].tap()
        app.buttons["New"].tap()
        app.terminate()
        app.launchPastReleaseNotes()
        app.buttons["Notes"].tap()
        XCTAssertEqual(app.textViews["Conversation notes"].value as? String, "")
        app.buttons["Done"].tap()
        app.buttons["History"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Decision: review the mobile release")).firstMatch.tap()
        app.buttons["Notes"].tap()
        XCTAssertTrue((notes.value as? String ?? "").contains("review the mobile release"))
        app.terminate()
        app.launchPastReleaseNotes()
        app.buttons["Notes"].tap()
        XCTAssertTrue((app.textViews["Conversation notes"].value as? String ?? "").contains("review the mobile release"))
        app.buttons["Done"].tap()
        app.buttons["More"].tap()
        app.buttons["Settings"].tap()
        let release = app.staticTexts["iPhone & iPad · iOS 26 or later"]
        for _ in 0..<30 where !release.isHittable { app.collectionViews["aiSettingsForm"].swipeUp() }
        XCTAssertTrue(release.isHittable)
    }
}

private extension MobileAppTests {
    func revealAttachment(_ control: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !control.isHittable { app.swipeUp() }
        XCTAssertTrue(control.isHittable, "Attachment tools remain reachable beneath conversation options")
    }
}
