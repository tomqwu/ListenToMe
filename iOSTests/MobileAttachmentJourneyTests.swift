import XCTest

@MainActor
final class MobileAttachmentJourneyTests: XCTestCase {
    func testPhotoImportPersistsAndCanBeRemoved() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["New"].tap()
        app.buttons["Notes"].tap()
        app.buttons["Photo library"].tap()
        let photo = app.images["PXGGridLayout-Info"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 30), "Requires the simulator's sample photos")
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let attachment = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "attachment-")).firstMatch
        for _ in 0..<5 where !attachment.isHittable { app.swipeUp() }
        XCTAssertTrue(attachment.waitForExistence(timeout: 10))
        let name = attachment.label
        app.terminate(); app.launch()
        app.buttons["Notes"].tap()
        for _ in 0..<5 where !attachment.isHittable { app.swipeUp() }
        XCTAssertEqual(attachment.label, name)
        app.buttons["Attachment actions"].tap()
        app.buttons["Remove attachment"].tap()
        XCTAssertFalse(attachment.exists)
        app.terminate(); app.launch()
        app.buttons["Notes"].tap()
        for _ in 0..<3 { app.swipeUp() }
        XCTAssertFalse(attachment.exists)
    }

    /// Local fixture: place a synthetic meeting.txt in the app's Documents folder, then stage this marker in the runner.
    func testLocalFileImportPreviewAndExtractText() throws {
        let marker = URL.applicationSupportDirectory.appendingPathComponent("AttachmentUIFixture")
        guard FileManager.default.fileExists(atPath: marker.path) else {
            throw XCTSkip("Requires the locally staged synthetic Files fixture.")
        }
        let app = XCUIApplication()
        app.launch()
        app.buttons["New"].tap()
        app.buttons["Notes"].tap()
        app.buttons["Add files"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Browse"].tap()
        let file = app.cells.matching(NSPredicate(format: "label CONTAINS %@", "meeting")).firstMatch
        if !file.waitForExistence(timeout: 5) {
            app.staticTexts["On My iPhone"].tap()
            let folder = app.collectionViews["File View"].staticTexts["ListenToMe"]
            XCTAssertTrue(folder.waitForExistence(timeout: 10), app.debugDescription)
            folder.tap()
        }
        XCTAssertTrue(file.waitForExistence(timeout: 10), app.debugDescription)
        file.tap()
        if app.buttons["Open"].exists { app.buttons["Open"].tap() }
        let attachment = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "attachment-")).firstMatch
        for _ in 0..<5 where !attachment.isHittable { app.swipeUp() }
        XCTAssertTrue(attachment.waitForExistence(timeout: 10), app.debugDescription)
        attachment.tap()
        let renderedText = app.textViews.matching(NSPredicate(
            format: "label BEGINSWITH %@", "Synthetic import: Alex")).firstMatch
        XCTAssertTrue(renderedText.waitForExistence(timeout: 10))
        let preview = XCTAttachment(screenshot: app.screenshot())
        preview.name = "Imported document preview"; preview.lifetime = .keepAlways; add(preview)
        let closePreview = app.buttons["QLOverlayDoneButtonAccessibilityIdentifier"]
        XCTAssertTrue(closePreview.waitForExistence(timeout: 5))
        closePreview.tap()
        for _ in 0..<3 where !app.buttons["Attachment actions"].isHittable { app.swipeUp() }
        app.buttons["Attachment actions"].tap()
        app.buttons["Add text to notes"].tap()
        for _ in 0..<5 where !app.textViews["Conversation notes"].isHittable { app.swipeDown() }
        XCTAssertTrue((app.textViews["Conversation notes"].value as? String ?? "").contains("Synthetic import: Alex"))
        for _ in 0..<5 where !app.buttons["Attachment actions"].isHittable { app.swipeUp() }
        app.buttons["Attachment actions"].tap()
        app.buttons["Share original"].tap()
        XCTAssertTrue(app.cells["ListenToMe"].waitForExistence(timeout: 10))
        app.cells["ListenToMe"].tap()
        XCTAssertTrue(app.buttons["Import"].waitForExistence(timeout: 10))
        app.buttons["Import"].tap()
        XCTAssertTrue(app.buttons["Saved"].waitForExistence(timeout: 10))
        app.buttons["finishSharedImport"].tap()
        app.terminate(); app.launch()
        XCTAssertEqual(app.textFields["conversationTitle"].value as? String, "Imported notes")
        app.buttons["Notes"].tap()
        for _ in 0..<5 where !app.buttons["Attachment actions"].isHittable { app.swipeUp() }
        app.buttons["Attachment actions"].tap()
        app.buttons["Add text to notes"].tap()
        for _ in 0..<5 where !app.textViews["Conversation notes"].isHittable { app.swipeDown() }
        XCTAssertTrue((app.textViews["Conversation notes"].value as? String ?? "").contains("Synthetic import: Alex"))
    }
}
