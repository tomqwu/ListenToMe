import XCTest

/// Opt-in physical acceptance. Uses the real microphone and speech engine; never a transcript fixture.
@MainActor
final class MobilePhysicalCaptureUITests: XCTestCase {
    func testPhysicalMicrophoneTranscriptionAndSavedAudioPlayback() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires a physical device and audible synthetic speech beside its microphone")
        #else
        guard ProcessInfo.processInfo.environment["LISTENTOME_PHYSICAL_AUDIO_ACCEPTANCE"] == "1" else {
            throw XCTSkip("Enable only for an attended physical microphone acceptance run")
        }
        let app = XCUIApplication(bundleIdentifier: "com.tomwu.ListenToMe.ios")
        // Argument-domain values affect this test launch; no existing provider/key is changed.
        app.launchArguments = ["-saveRawAudio", "YES", "-autoQuickSummary", "NO",
                               "-mobileIdentifySpeakers", "NO", "-mobileCorrectTranscript", "NO",
                               "-mobileTranscriptionLanguageAutomatic",
                               ProcessInfo.processInfo.environment["LISTENTOME_PHYSICAL_AUTOMATIC"] == "1" ? "YES" : "NO",
                               "-mobileTranscriptionLanguage", "en-US"]
        if ProcessInfo.processInfo.environment["LISTENTOME_EXISTING_PHYSICAL_APP"] == "1" {
            // The attended runner launches the existing installation with the same arguments.
            // Activate avoids Xcode attempting to reinstall it while diagnosing a reported build.
            app.activate()
        } else {
            app.launch()
        }
        let continueButton = app.buttons["releaseNotesContinue"]
        if continueButton.waitForExistence(timeout: 10) { continueButton.tap() }
        let newConversation = app.buttons["New"]
        XCTAssertTrue(newConversation.waitForExistence(timeout: 20))
        XCTAssertTrue(newConversation.isEnabled)
        newConversation.tap() // saves the previous conversation; never deletes history
        let phrase = app.staticTexts.containing(NSPredicate(
            format: "label CONTAINS[c] 'physical recording' OR label CONTAINS[c] 'microphone test'"))
        XCTAssertEqual(phrase.count, 0, "Old text must not satisfy this capture run")
        let start = app.buttons["Start listening"]
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        addUIInterruptionMonitor(withDescription: "Microphone access for physical recording") { alert in
            if alert.buttons["Allow"].exists { alert.buttons["Allow"].tap(); return true }
            if alert.buttons["OK"].exists { alert.buttons["OK"].tap(); return true }
            return false
        }
        let supported = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: start)
        let supportResult = XCTWaiter.wait(for: [supported], timeout: 30)
        capture(app, "Physical recording capability before Start")
        XCTAssertEqual(supportResult, .completed, app.staticTexts["recordingSupportReason"].debugDescription)
        guard supportResult == .completed else { return }
        start.tap()
        app.tap()  // permits the interruption monitor to handle the OS microphone prompt
        let status = app.staticTexts["captureStatus"]
        let failure = app.alerts["Couldn’t start listening"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            status.label.hasPrefix("Listening") || failure.exists || start.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 120), .completed)
        capture(app, "Physical listening startup")
        XCTAssertFalse(failure.exists, failure.debugDescription)
        XCTAssertTrue(status.label.hasPrefix("Listening"), "Recording did not start: \(status.label)")
        guard status.label.hasPrefix("Listening") else { return }
        print("LTM_PHYSICAL_LISTENING_CONFIRMED")
        // The attended runner plays a public synthetic phrase through the Mac speaker.
        let heard = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            if !status.label.hasPrefix("Listening") {
                print("LTM_PHYSICAL_RECORDING_STOPPED")
                return true
            }
            return phrase.count > 0
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [heard], timeout: 90), .completed,
                       "The real microphone must produce current synthetic-speech text")
        XCTAssertGreaterThan(phrase.count, 0, "Recording must produce current speech before it stops")
        capture(app, "Physical live microphone transcript")
        print("LTM_PHYSICAL_RECORDING_STOPPED")
        app.buttons["Stop listening"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        let play = app.buttons["playSavedAudio"]
        XCTAssertTrue(play.waitForExistence(timeout: 10), "Opt-in real capture must retain playable audio")
        guard play.exists else { return }
        play.tap()
        XCTAssertTrue(app.otherElements["savedAudioPlayer"].waitForExistence(timeout: 5))
        app.buttons["Play"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
        capture(app, "Physical retained audio playback")
        app.buttons["Pause"].tap()
        #endif
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
