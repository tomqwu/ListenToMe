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
        app.staticTexts["On My iPhone"].tap()
        let folder = app.collectionViews["File View"].staticTexts["ListenToMe"]
        XCTAssertTrue(folder.waitForExistence(timeout: 10), app.debugDescription)
        folder.tap()
        let file = app.cells.matching(NSPredicate(format: "label CONTAINS %@", "meeting")).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 10), app.debugDescription)
        file.tap()
        if app.buttons["Open"].exists { app.buttons["Open"].tap() }
        let attachment = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "attachment-")).firstMatch
        for _ in 0..<5 where !attachment.isHittable { app.swipeUp() }
        XCTAssertTrue(attachment.waitForExistence(timeout: 10), app.debugDescription)
        attachment.tap()
        let preview = XCTAttachment(screenshot: app.screenshot())
        preview.name = "Imported document preview"; preview.lifetime = .keepAlways; add(preview)
        app.buttons.matching(identifier: "Done").allElementsBoundByIndex.first(where: { $0.isHittable })?.tap()
        app.buttons["Attachment actions"].tap()
        app.buttons["Add text to notes"].tap()
        for _ in 0..<5 where !app.textViews["Conversation notes"].isHittable { app.swipeDown() }
        XCTAssertTrue((app.textViews["Conversation notes"].value as? String ?? "").contains("Synthetic import: Alex"))
    }
}
