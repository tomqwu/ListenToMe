import XCTest

/// Opt-in, synthetic-data UI journey. Stage the token in the runner's Application Support directory.
/// The token is consumed immediately, typed only into SecureField and removed through Settings afterward.
@MainActor
final class MobileLiveCloudTests: XCTestCase {
    private var usedCredential = false

    override func tearDown() async throws {
        if usedCredential { removeTestKey(XCUIApplication()) }
        try await super.tearDown()
    }

    func testUserCloudJourney() throws {
        let file = URL.applicationSupportDirectory.appendingPathComponent("OllamaUITestKey")
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw XCTSkip("Requires a locally staged UI test credential.")
        }
        let token = try String(contentsOf: file, encoding: .utf8)
        try FileManager.default.removeItem(at: file)
        let app = XCUIApplication()
        app.launch()
        usedCredential = true
        app.buttons["More"].tap()
        app.buttons["Settings"].tap()
        app.buttons["summaryProvider"].tap()
        app.buttons["Ollama Cloud"].tap()
        app.secureTextFields["ollamaAPIKey"].tap()
        app.secureTextFields["ollamaAPIKey"].typeText(token)
        app.buttons["Save API key"].tap()
        XCTAssertTrue(app.staticTexts["savedAPIKey"].waitForExistence(timeout: 5))
        reveal(app.buttons["Refresh models from API"], in: app)
        app.buttons["Refresh models from API"].tap()
        let fetched = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@ OR label BEGINSWITH %@",
            "Fetched ", "Your selected model is no longer listed")).firstMatch
        for _ in 0..<4 where !fetched.exists { app.swipeUp() }
        guard fetched.waitForExistence(timeout: 60) else {
            XCTFail("Catalog refresh failed: \(app.staticTexts["ollamaStatus"].label)"); return
        }
        for role in ["Summary", "Quick Summary", "Deep Summary"] {
            let roleID = role == "Summary" ? "summary" : (role == "Quick Summary" ? "quick" : "deep")
            let choose = app.buttons["choose-model-\(roleID)"]
            reveal(choose, in: app, upwards: false)
            choose.tap()
            let variant = role == "Deep Summary" ? "pro" : "flash"
            let preferred = app.buttons.matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND identifier CONTAINS %@", "model-", variant)).firstMatch
            let fallback = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "model-")).firstMatch
            (preferred.exists ? preferred : fallback).tap()
            let navigation = app.navigationBars["\(role) model"]
            reveal(app.buttons["Test this model"], in: app)
            app.buttons["Test this model"].tap()
            let verified = app.staticTexts.matching(NSPredicate(
                format: "label BEGINSWITH %@", "Connection verified:")).firstMatch
            for _ in 0..<3 where !app.staticTexts["ollamaStatus"].exists { app.swipeUp() }
            let finished = app.staticTexts.matching(NSPredicate(
                format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Connection verified:", "Connection test failed:")).firstMatch
            _ = app.buttons["Test this model"].waitForExistence(timeout: 120)
            _ = finished.waitForExistence(timeout: 5)
            guard verified.exists else {
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "Connection result"; screenshot.lifetime = .keepAlways; add(screenshot)
                XCTFail("\(role) connection failed: \(app.staticTexts["ollamaStatus"].label)"); return
            }
            navigation.buttons.firstMatch.tap()
        }
        app.buttons["Done"].tap()
        app.buttons["New"].tap()
        let marker = "UI cloud journey " + UUID().uuidString
        app.textFields["conversationTitle"].tap()
        app.textFields["conversationTitle"].typeText(" " + marker)
        app.buttons["Notes"].tap()
        app.textViews["Conversation notes"].tap()
        app.textViews["Conversation notes"].typeText(
            marker + ". Decision: review the mobile release on Friday. Alex will prepare the checklist.")
        app.buttons["Done"].tap()
        app.buttons["Save"].tap()
        app.buttons["More"].tap()
        app.buttons["Full summary"].tap()
        var outputs: [String: String] = [:]
        app.buttons["Generate Summary"].tap()
        let full = app.staticTexts["savedSummary"]
        XCTAssertTrue(full.waitForExistence(timeout: 180))
        outputs["Summary"] = full.label
        app.buttons["Done"].tap()
        for mode in [("Quick Summary", "quick"), ("Deep Summary", "deep")] {
            app.segmentedControls["workspaceTabs"].buttons[mode.1 == "quick" ? "Live" : "Deep"].tap()
            app.buttons["Generate \(mode.0)"].tap()
            let output = app.staticTexts["output-\(mode.1)"]
            let completed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "NOT label BEGINSWITH %@", "Your "), object: output)
            XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 180), .completed)
            XCTAssertFalse(output.label.isEmpty)
            outputs[mode.0] = output.label
        }
        let dashboard = XCTAttachment(screenshot: app.screenshot())
        dashboard.name = "Live cloud dashboard outputs"; dashboard.lifetime = .keepAlways; add(dashboard)
        app.terminate(); app.launch()
        XCTAssertEqual(app.staticTexts["output-quick"].label, outputs["Quick Summary"])
        app.segmentedControls["workspaceTabs"].buttons["Deep"].tap()
        XCTAssertEqual(app.staticTexts["output-deep"].label, outputs["Deep Summary"])
        app.buttons["More"].tap()
        app.buttons["Full summary"].tap()
        XCTAssertEqual(app.staticTexts["savedSummary"].label, outputs["Summary"])
        app.buttons["Done"].tap()
        shareAndDelete(app, outputs: outputs, marker: marker)
    }

    private func shareAndDelete(_ app: XCUIApplication, outputs: [String: String], marker: String) {
        app.buttons["More"].tap()
        app.buttons["Share"].tap()
        let copy = app.cells["Copy"]
        guard copy.waitForExistence(timeout: 10) else { XCTFail("Share sheet did not offer Copy"); return }
        copy.tap()
        app.buttons["New"].tap()
        app.buttons["Notes"].tap()
        app.buttons["Paste"].tap()
        let exported = app.textViews["Conversation notes"].value as? String ?? ""
        XCTAssertTrue(exported.contains(marker))
        // Displayed summaries are formatted; exported output intentionally retains Markdown.
        for heading in ["## Listener", "## Quick", "## Deep"] {
            XCTAssertTrue(exported.contains(heading), "Missing exported section: \(heading)")
        }
        app.buttons["Done"].tap()
        app.buttons["History"].tap()
        // Both this run's source and pasted copy carry the unique marker.
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", marker)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        for _ in 0..<2 {
            row.swipeLeft()
            app.buttons["Delete"].firstMatch.tap()
            app.buttons["Delete conversation"].tap()
        }
        XCTAssertFalse(row.exists)
        app.terminate()
        app.launch()
        app.buttons["History"].tap()
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", marker)).firstMatch.exists)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upwards: Bool = true) {
        for _ in 0..<8 {
            let top = app.navigationBars["Settings"].frame.maxY + 20
            let bottom = app.frame.maxY - 100
            if element.exists, element.frame.minY >= top, element.frame.maxY <= bottom, element.isHittable { return }
            if element.exists, element.frame.minY < top { app.swipeDown() }
            else if element.exists, element.frame.maxY > bottom { app.swipeUp() }
            else if upwards { app.swipeUp() } else { app.swipeDown() }
        }
    }

    private func removeTestKey(_ app: XCUIApplication) {
        app.terminate()
        app.launch()
        app.buttons["More"].tap()
        app.buttons["Settings"].tap()
        let remove = app.buttons["Remove API key"]
        if remove.waitForExistence(timeout: 5) { remove.tap() }
        XCTAssertFalse(app.staticTexts["savedAPIKey"].exists)
    }
}
