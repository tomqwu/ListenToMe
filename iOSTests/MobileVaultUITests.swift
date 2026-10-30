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
        let form = app.collectionViews["aiSettingsForm"]
        let toggle = form.switches["saveToFolderToggle"]
        guard form.waitForExistence(timeout: 5) else {
            XCTFail("Settings must present its form"); return
        }
        guard reveal(toggle, in: form, app: app) else { return }
        XCTAssertEqual(toggle.value as? String, "0")
        let explanation = form.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Obsidian vault'")).firstMatch
        guard reveal(explanation, in: form, app: app) else { return }
        capture(app, "Folder disclosure before enabling saving")
        guard reveal(toggle, in: form, app: app, belowWhenMissing: false) else { return }
        XCTAssertEqual(toggle.value as? String, "0", "Reading the disclosure does not enable saving")

        toggle.switches.firstMatch.tap()
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "the Files folder picker opens")
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5), "Cancelling returns to Settings")
        guard reveal(toggle, in: form, app: app) else { return }
        XCTAssertEqual(toggle.value as? String, "1", "Cancel leaves saving enabled but without a selected folder")
        let choose = form.buttons["chooseSaveFolder"]
        guard reveal(choose, in: form, app: app) else { return }
        XCTAssertEqual(choose.label, "Choose folder…")
        let status = form.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Choose a folder'")).firstMatch
        guard reveal(status, in: form, app: app) else { return }
        XCTAssertTrue(choose.isEnabled && choose.isHittable)
        XCTAssertFalse(app.buttons["Stop listening"].exists)
        capture(app, "Save to folder settings after cancelling picker")
    }

    /// Lazy Settings rows may be absent below the viewport. A partly hittable toggle does not
    /// establish that its disclosure or newly inserted recovery controls have been revealed.
    private func reveal(_ target: XCUIElement, in form: XCUIElement, app: XCUIApplication,
                        belowWhenMissing: Bool = true, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        for _ in 0..<16 {
            let window = app.windows.firstMatch.frame
            var viewport = form.frame.intersection(window).insetBy(dx: 4, dy: 8)
            let top = max(viewport.minY, app.navigationBars["Settings"].frame.maxY + 8)
            let bottom = min(viewport.maxY, window.maxY - 40)
            viewport = CGRect(x: viewport.minX, y: top, width: viewport.width, height: bottom - top)
            let exists = target.exists
            let frame = exists ? target.frame : .zero
            if exists && target.isHittable && frame.height > 0 && viewport.contains(frame) { return true }
            guard viewport.height > 100 else { break }
            let below = exists && frame.height > 0 ? frame.midY > viewport.midY : belowWhenMissing
            let distance = min(viewport.height * 0.35, 240)
            let direction: CGFloat = below ? 1 : -1
            let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            let from = origin.withOffset(CGVector(dx: viewport.midX - window.minX,
                                                  dy: viewport.midY - window.minY + direction * distance / 2))
            let to = origin.withOffset(CGVector(dx: viewport.midX - window.minX,
                                                dy: viewport.midY - window.minY - direction * distance / 2))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        let detail = XCTAttachment(string: "Target: \(target.debugDescription)\n" + app.debugDescription)
        detail.name = "Folder settings reveal failed"; detail.lifetime = .keepAlways; add(detail)
        capture(app, "Folder settings reveal failed")
        XCTFail("The complete folder control or disclosure must be visible", file: file, line: line)
        return false
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
