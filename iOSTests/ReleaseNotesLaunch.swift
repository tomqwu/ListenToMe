import XCTest

extension XCUIApplication {
    @MainActor func launchPastReleaseNotes() {
        launch()
        let button = buttons["releaseNotesContinue"]
        if button.waitForExistence(timeout: 2) { button.tap() }
    }
}
