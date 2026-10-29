import XCTest

@MainActor
final class MobileHistoryModelUITests: XCTestCase {
    func testExplicitDownloadCanBeCancelledFromSettings() {
        let app = openSettings(model: "absent")
        defer { app.terminate() }
        let form = app.collectionViews["aiSettingsForm"]
        let download = app.buttons["historyModelDownload"]
        revealSettingsControl(download, in: form)
        XCTAssertTrue(download.isHittable)
        XCTAssertFalse(app.buttons["historyModelCancel"].exists, "Opening Settings cannot start a download")
        capture(app, "History model explicit download disclosure")
        download.tap()
        let cancel = app.buttons["historyModelCancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        revealSettingsControl(cancel, in: form)
        XCTAssertFalse(app.switches["historyModelEnabled"].exists, "Incomplete files cannot be enabled")
        capture(app, "History model download progress and cancel")
        cancel.tap()
        XCTAssertTrue(download.waitForExistence(timeout: 5))
        XCTAssertFalse(cancel.exists)
        XCTAssertFalse(app.switches["historyModelEnabled"].exists)
    }

    func testInstalledModelRequiresOptInAndCanBeRemoved() {
        let app = openSettings(model: "installed")
        defer { app.terminate() }
        let form = app.collectionViews["aiSettingsForm"]
        let enabled = app.switches["historyModelEnabled"]
        revealSettingsControl(enabled, in: form)
        XCTAssertEqual(enabled.value as? String, "0", "Existing files do not grant opt-in")
        // A tap on the containing label row must never invoke the neighboring destructive action.
        enabled.tap()
        XCTAssertTrue(enabled.exists)
        XCTAssertTrue(app.buttons["historyModelRemove"].exists)
        // SwiftUI exposes the row and its actual native switch separately, as in the speaker tests.
        let control = enabled.switches.firstMatch
        XCTAssertTrue(control.isHittable)
        let wasOn = control.value as? String == "1"
        control.tap()
        XCTAssertEqual(control.value as? String, wasOn ? "0" : "1")
        if wasOn { control.tap() }
        XCTAssertEqual(enabled.value as? String, "1")
        capture(app, "History model enabled with removal control")
        let remove = app.buttons["historyModelRemove"]
        revealSettingsControl(remove, in: form)
        remove.tap()
        XCTAssertTrue(app.buttons["historyModelDownload"].waitForExistence(timeout: 5))
        XCTAssertFalse(enabled.exists)
        XCTAssertFalse(remove.exists)
    }

    private func openSettings(model: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LISTENTOME_HISTORY_MODEL_FIXTURE"] = model
        app.launchArguments = ["-mobileAIProvider", "apple", "-autoQuickSummary", "NO"]
        XCUIDevice.shared.orientation = .portrait
        app.launchPastReleaseNotes()
        app.buttons["More"].tap()
        app.buttons["Settings"].tap()
        return app
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
