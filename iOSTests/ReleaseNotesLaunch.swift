import XCTest

extension XCUIApplication {
    /// UI tests never download the real speaker models: Identify speakers is on by default (#195), so
    /// the app substitutes models that load at once and hear no voices (DEBUG simulator builds only).
    @MainActor func useSpeakerModelsFixture() {
        launchEnvironment["LISTENTOME_SPEAKER_MODELS_FIXTURE"] = "1"
    }

    @MainActor func launchPastReleaseNotes() {
        useSpeakerModelsFixture()
        launch()
        let button = buttons["releaseNotesContinue"]
        if button.waitForExistence(timeout: 2) { button.tap() }
    }
}
