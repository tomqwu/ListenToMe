import XCTest
import UIKit

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
        app.buttons["Settings"].tap()
        app.buttons["summaryProvider"].tap()
        app.buttons["Ollama Cloud"].tap()
        app.secureTextFields["ollamaAPIKey"].tap()
        app.secureTextFields["ollamaAPIKey"].typeText(token)
        app.buttons["Save API key"].tap()
        XCTAssertTrue(app.staticTexts["savedAPIKey"].waitForExistence(timeout: 5))
        reveal(app.buttons["Refresh models from API"], in: app)
        app.buttons["Refresh models from API"].tap()
        let fetched = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Fetched ")).firstMatch
        for _ in 0..<4 where !fetched.exists { app.swipeUp() }
        guard fetched.waitForExistence(timeout: 60) else {
            XCTFail("Catalog refresh failed: \(app.staticTexts["ollamaStatus"].label)"); return
        }
        for role in ["Summary", "Quick Summary", "Deep Think"] {
            if role != "Summary" {
                reveal(app.buttons["modelRole"], in: app, upwards: false)
                app.buttons["modelRole"].tap()
                app.buttons[role].tap()
            }
            reveal(app.buttons["Choose model"], in: app, upwards: false)
            app.buttons["Choose model"].tap()
            let variant = role == "Deep Think" ? "pro" : "flash"
            let preferred = app.buttons.matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND identifier CONTAINS %@", "model-", variant)).firstMatch
            let fallback = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "model-")).firstMatch
            (preferred.exists ? preferred : fallback).tap()
            app.navigationBars.buttons.element(boundBy: 0).tap()
            reveal(app.buttons["Test connection"], in: app)
            app.buttons["Test connection"].tap()
            let verified = app.staticTexts.matching(NSPredicate(
                format: "label BEGINSWITH %@", "Connection verified:")).firstMatch
            for _ in 0..<3 where !app.staticTexts["ollamaStatus"].exists { app.swipeUp() }
            let finished = app.staticTexts.matching(NSPredicate(
                format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Connection verified:", "Connection test failed:")).firstMatch
            _ = finished.waitForExistence(timeout: 120)
            guard verified.exists else {
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "Connection result"; screenshot.lifetime = .keepAlways; add(screenshot)
                XCTFail("\(role) connection failed: \(app.staticTexts["ollamaStatus"].label)"); return
            }
        }
        app.buttons["Done"].tap()
        app.buttons["New"].tap()
        app.segmentedControls.buttons["Notes"].tap()
        let marker = "UI cloud journey " + UUID().uuidString
        app.textViews["Conversation notes"].tap()
        app.textViews["Conversation notes"].typeText(
            marker + ". Decision: review the mobile release on Friday. Alex will prepare the checklist.")
        app.buttons["Save"].tap()
        app.segmentedControls.buttons["Summary"].tap()
        var outputs: [String: String] = [:]
        for role in ["Summary", "Quick Summary", "Deep Think"] {
            if role != "Summary" {
                app.buttons["summaryMode"].tap()
                app.buttons[role].tap()
            }
            app.buttons["Generate \(role)"].tap()
            let output = app.staticTexts["savedSummary"]
            guard output.waitForExistence(timeout: 180) else {
                XCTFail("\(role) generation failed: \(app.staticTexts["sessionMessage"].label)"); return
            }
            XCTAssertFalse(output.label.isEmpty)
            outputs[role] = output.label
        }
        app.terminate()
        app.launch()
        app.segmentedControls.buttons["Summary"].tap()
        for role in ["Summary", "Quick Summary", "Deep Think"] {
            if role != "Summary" {
                app.buttons["summaryMode"].tap()
                app.buttons[role].tap()
            }
            XCTAssertEqual(app.staticTexts["savedSummary"].label, outputs[role])
        }
        shareAndDelete(app, outputs: outputs, marker: marker)
    }

    private func shareAndDelete(_ app: XCUIApplication, outputs: [String: String], marker: String) {
        app.buttons["Share"].tap()
        let copy = app.buttons["Copy"]
        guard copy.waitForExistence(timeout: 10) else { XCTFail("Share sheet did not offer Copy"); return }
        copy.tap()
        let exported = UIPasteboard.general.string ?? ""
        XCTAssertTrue(exported.contains(marker))
        for output in outputs.values { XCTAssertTrue(exported.contains(output)) }
        UIPasteboard.general.items = []
        app.buttons["History"].tap()
        // The test conversation is the newest row; identify it through its saved summary.
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", outputs["Summary"]!)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        app.buttons["Delete conversation"].tap()
        XCTAssertFalse(row.exists)
        app.terminate()
        app.launch()
        app.buttons["History"].tap()
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", outputs["Summary"]!)).firstMatch.exists)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upwards: Bool = true) {
        for _ in 0..<6 where !element.isHittable {
            if upwards { app.swipeUp() } else { app.swipeDown() }
        }
    }

    private func removeTestKey(_ app: XCUIApplication) {
        app.terminate()
        app.launch()
        app.buttons["Settings"].tap()
        let remove = app.buttons["Remove API key"]
        if remove.waitForExistence(timeout: 5) { remove.tap() }
        XCTAssertFalse(app.staticTexts["savedAPIKey"].exists)
    }
}
