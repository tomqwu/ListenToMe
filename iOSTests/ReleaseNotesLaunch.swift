import XCTest

extension XCUIApplication {
    /// UI tests never download the real speaker or language models: Identify speakers is on by default
    /// (#195) and the transcription language is Automatic by default (#197), so the app substitutes
    /// models that load at once, hear no voices and never switch (DEBUG simulator builds only).
    @MainActor func useModelFixtures() {
        launchEnvironment["LISTENTOME_SPEAKER_MODELS_FIXTURE"] = "1"
        launchEnvironment["LISTENTOME_LANGUAGE_MODEL_FIXTURE"] = "1"
    }

    @MainActor func launchPastReleaseNotes() {
        useModelFixtures()
        launch()
        let button = buttons["releaseNotesContinue"]
        if button.waitForExistence(timeout: 2) { button.tap() }
    }
}
