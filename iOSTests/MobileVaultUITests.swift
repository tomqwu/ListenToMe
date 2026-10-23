import XCTest

/// Settings → Save to folder (issue #53): off by default, explains itself, and turning it on opens
/// the Files folder picker. Cancelling leaves it asking for a folder instead of failing silently.
@MainActor
final class MobileVaultUITests: XCTestCase {
    func testSaveToFolderIsOffByDefaultAndAsksForAFolder() {
        let app = XCUIApplication()
        app.launchArguments = ["-markdownVaultEnabled", "NO"]
        app.launchPastReleaseNotes()
        app.buttons["More"].tap()
        app.buttons["Settings"].tap()
        let toggle = app.switches["saveToFolderToggle"]
        XCTAssertTrue(app.collectionViews["aiSettingsForm"].waitForExistence(timeout: 5))
        for _ in 0..<8 where !(toggle.exists && toggle.isHittable) { app.swipeUp() }
        XCTAssertTrue(toggle.isHittable)
        XCTAssertEqual(toggle.value as? String, "0")
        let explanation = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Obsidian vault'"))
        XCTAssertTrue(explanation.firstMatch.exists)

        toggle.switches.firstMatch.tap()
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "the Files folder picker opens")
        cancel.tap()
        let status = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Choose a folder'")).firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["chooseSaveFolder"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Save to folder settings"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
