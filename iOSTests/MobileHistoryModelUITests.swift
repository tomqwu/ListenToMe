import XCTest

@MainActor
final class MobileHistoryModelUITests: XCTestCase {
    func testReleaseSettingsDoNotOfferUnacceptedSearchModel() {
        let app = openSettings(model: "absent")
        defer { app.terminate() }
        let form = app.collectionViews["aiSettingsForm"]
        XCTAssertTrue(form.waitForExistence(timeout: 5))
        let explanation = app.staticTexts["recordingExplanation"]
        let forbidden = [app.staticTexts["Additional History languages"],
                         app.buttons["historyModelDownload"], app.switches["historyModelEnabled"],
                         app.buttons["historyModelCancel"], app.buttons["historyModelRemove"]]
        var observed: Set<String> = []
        var captured = false
        for _ in 0..<18 {
            for element in forbidden where element.exists && element.isHittable {
                observed.insert(element.identifier.isEmpty ? element.label : element.identifier)
                if !captured {
                    capture(app, "Release Settings offers unaccepted History model controls")
                    captured = true
                }
            }
            if explanation.exists && explanation.isHittable { break }
            form.swipeUp()
        }
        XCTAssertTrue(explanation.exists && explanation.isHittable,
                      "Inspect Settings through the reachable Recording explanation; absence offscreen is insufficient")
        XCTAssertTrue(observed.isEmpty, "Unaccepted search-model controls were offered: \(observed.sorted())")
        capture(app, "Release Settings through Recording explanation")
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
