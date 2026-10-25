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
        // The Save to folder journey intentionally leaves an unconfigured destination. Its warning
        // consumes workspace height, so unrelated journeys must start with this opt-in feature off.
        if !launchArguments.contains("-markdownVaultEnabled") {
            launchArguments += ["-markdownVaultEnabled", "NO"]
        }
        // UIKit can retain the previous launch's accessibility-size override in a long UI run.
        // Give ordinary journeys an explicit baseline while preserving large-text test overrides.
        if !launchArguments.contains("-UIPreferredContentSizeCategoryName") {
            launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        }
        launch()
        let button = buttons["releaseNotesContinue"]
        if button.waitForExistence(timeout: 2) { button.tap() }
    }
}
