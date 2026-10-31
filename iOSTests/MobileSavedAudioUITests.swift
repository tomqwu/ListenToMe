import UIKit
import XCTest

/// Settings → Save audio recordings (issue #55): off by default, explains that audio stays on the device
/// and what it costs, and offers automatic deletion once on. Nothing is recorded in this test.
@MainActor
final class MobileSavedAudioUITests: XCTestCase {
    func testSaveAudioRecordingsIsOffByDefaultAndExplainsItself() {
        let app = XCUIApplication()
        app.launchArguments = ["-saveRawAudio", "NO", "-savedAudioRetentionDays", "0"]
        app.launchPastReleaseNotes()
        app.buttons["More"].tap()
        app.buttons["Settings"].tap()
        let form = app.collectionViews["aiSettingsForm"]
        let toggle = app.switches["saveAudioToggle"]
        XCTAssertTrue(form.waitForExistence(timeout: 5))
        revealSettingsControl(toggle, in: form)
        XCTAssertEqual(toggle.value as? String, "0", "Saving audio is opt-in")
        let retention = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Keep audio'")).firstMatch
        XCTAssertFalse(retention.exists)

        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        XCTAssertTrue(retention.waitForExistence(timeout: 5), "Automatic deletion is offered once it is on")
        let explanation = app.staticTexts["savedAudioExplanation"]
        revealSettingsControl(explanation, in: form)
        XCTAssertTrue((explanation.label as NSString).contains("never uploaded"), explanation.label)
        XCTAssertTrue((explanation.label as NSString).contains("per hour"), explanation.label)
        XCTAssertTrue(app.buttons["deleteAllSavedAudio"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Save audio recordings settings"; screenshot.lifetime = .keepAlways; add(screenshot)
        revealSettingsControl(toggle, in: form)
        toggle.switches.firstMatch.tap()   // leave the simulator's setting off
    }

    func testNotesOnlySavedRecordingStillOffersPlaybackInPortrait() {
        let app = XCUIApplication()
        app.launchArguments = ["--saved-audio-fixture", "--saved-audio-without-speech", "-mobileCorrectTranscript", "NO"]
        app.launchPastReleaseNotes()
        let actions = app.buttons["transcriptOptions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 10), "Saved audio without recognized speech still needs its playback action")
        guard actions.exists else { return }
        actions.tap()
        let play = app.buttons["playSavedAudio"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        XCTAssertTrue(app.otherElements["savedAudioPlayer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["shareSavedAudio"].exists)
        XCTAssertTrue(app.buttons["Play"].isHittable)
        app.buttons["Done"].tap()
        XCTAssertFalse(app.buttons["Stop listening"].exists)
    }

    /// The fixture's audio is a synthetic tone written by the real writer; the microphone is never used.
    func testSavedAudioPlaysFromATappedLineAndCanBeShared() {
        let app = XCUIApplication()
        app.launchArguments = ["--saved-audio-fixture", "-mobileCorrectTranscript", "NO"]
        app.launchPastReleaseNotes()
        app.buttons["transcriptOptions"].tap()
        let open = app.buttons["playSavedAudio"]
        XCTAssertTrue(open.waitForExistence(timeout: 10), "A conversation with saved audio offers Play recording")
        open.tap()
        let player = app.otherElements["savedAudioPlayer"]
        XCTAssertTrue(player.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["shareSavedAudio"].exists, "The audio can be exported from the share sheet")
        let line = app.buttons["Play from 0:03"]
        XCTAssertTrue(line.waitForExistence(timeout: 5), "Lines with trustworthy times can seek")
        line.tap()
        let pause = app.buttons["Pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5), "Tapping a line plays from its time")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Saved audio player"; screenshot.lifetime = .keepAlways; add(screenshot)
        pause.tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
    }

    func testSavedAudioHeaderAtDefaultTextKeepsTranscriptUsable() {
        checkPlayerLayout(category: .large, launchCategory: "UICTContentSizeCategoryL")
    }

    func testSavedAudioHeaderAtLargestTextKeepsTranscriptUsable() {
        checkPlayerLayout(category: .accessibilityExtraExtraExtraLarge,
                          launchCategory: "UICTContentSizeCategoryAccessibilityXXXL")
    }

    /// Native text metrics catch word splitting/truncation that an intact AX label does not expose.
    /// This fixture never plays its tone: these checks prove layout, not audible playback or VoiceOver.
    private func checkPlayerLayout(category: UIContentSizeCategory, launchCategory: String) {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait; app.terminate() }
        app.launchArguments = ["--watch-speakers-fixture", "-autoQuickSummary", "NO",
                               "-UIPreferredContentSizeCategoryName", launchCategory]
        app.launchPastReleaseNotes()
        let expand = app.buttons["Expand transcript"]
        guard expand.waitForExistence(timeout: 5), expand.isHittable else {
            XCTFail("The saved conversation must open its actual transcript reader"); return
        }
        expand.tap()
        let player = app.otherElements["savedAudioPlayer"]
        let reader = app.scrollViews["expandedTranscriptScroll"]
        let title = player.staticTexts["Saved audio"]
        let share = app.buttons["shareSavedAudio"]
        let shareText = share.staticTexts["Share audio"]
        let time = player.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "[0-9]+:[0-9]{2} / [0-9]+:[0-9]{2}"))
            .firstMatch
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            player.exists && reader.exists && title.exists && shareText.exists && time.exists
                && reader.frame.height > 0 && app.frame.height > app.frame.width
        }, object: nil)
        guard XCTWaiter.wait(for: [ready], timeout: 5) == .completed else {
            capturePlayerLayout(app, name: "Missing saved audio header at \(launchCategory)")
            XCTFail("Saved audio, Share audio, time and transcript must all render"); return
        }
        capturePlayerLayout(app, name: "Saved audio header before scrolling \(launchCategory)")
        let traits = UITraitCollection(preferredContentSizeCategory: category)
        let titleFont = UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traits)
        let semibold = UIFont(descriptor: titleFont.fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.semibold]
        ]), size: titleFont.pointSize)
        let body = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits)
        assertCompleteWords(title, text: "Saved audio", font: semibold, icon: player.images["waveform"])
        assertCompleteWords(shareText, text: "Share audio", font: body, icon: share.images["square.and.arrow.up"])
        let caption = UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: traits)
        let digits = UIFont.monospacedDigitSystemFont(ofSize: caption.pointSize, weight: .regular)
        let timeWidth = (time.label as NSString).size(withAttributes: [.font: digits]).width
        XCTAssertGreaterThanOrEqual(time.frame.width + 2, timeWidth, "The complete elapsed/duration text must fit")
        XCTAssertLessThanOrEqual(time.frame.height, digits.lineHeight * 1.3, "Elapsed/duration must stay on one line")
        for control in [app.buttons["savedAudioPlay"], player.sliders["Playback position"], share, time] {
            assertWholePlayerControl(control, inside: player.frame.intersection(app.frame))
        }
        XCTAssertGreaterThanOrEqual(player.sliders["Playback position"].frame.width, 44)
        // iPad presents this reader in a sheet; the background app is not available reading space.
        let readerSurface = player.frame.union(reader.frame).intersection(app.frame)
        XCTAssertGreaterThanOrEqual(reader.frame.intersection(app.frame).height,
                                    max(body.lineHeight * 3, readerSurface.height * 0.25),
                                    "The fixed player must leave useful transcript space")
        revealFirstSavedSpeaker(in: reader, app: app)
        XCTAssertEqual(app.buttons["savedAudioPlay"].label, "Play", "Reader scrolling must never start playback")
        XCTAssertFalse(app.buttons["Pause"].exists)
        XCTAssertEqual(player.sliders["Playback position"].value as? String, "0:00")
        capturePlayerLayout(app, name: "Saved audio header and first speaker \(launchCategory)")
    }

    private func assertCompleteWords(_ text: XCUIElement, text expected: String, font: UIFont, icon: XCUIElement) {
        XCTAssertEqual(text.label, expected)
        let longest = expected.split(separator: " ").map {
            (String($0) as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? 0
        // SwiftUI's Label AX text frame can include its image. Remove only measured image overlap;
        // otherwise a full container frame could conceal a too-narrow word column.
        let overlap = icon.exists ? text.frame.intersection(icon.frame) : .null
        let width = text.frame.width - (overlap.isNull ? 0 : overlap.width)
        XCTAssertGreaterThanOrEqual(width + 2, longest, "A complete word in \(expected) must fit beside its symbol")
        let fullWidth = (expected as NSString).size(withAttributes: [.font: font]).width
        if text.frame.height <= font.lineHeight * 1.3 {
            XCTAssertGreaterThanOrEqual(width + 2, fullWidth,
                                        "One visible line must fit the entire phrase, even when AX keeps a truncated label")
        } else {
            let complete = (expected as NSString).boundingRect(
                with: CGSize(width: max(1, width), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil)
            XCTAssertGreaterThanOrEqual(text.frame.height + 2, ceil(complete.height),
                                        "Wrapped text must have room for the complete phrase without an ellipsis")
        }
        XCTAssertGreaterThanOrEqual(text.frame.height, font.lineHeight * 0.75,
                                    "The requested Dynamic Type size must not silently collapse")
        XCTAssertLessThanOrEqual(text.frame.height, font.lineHeight * 2 + 2,
                                 "Two words may wrap at a word boundary, not split or truncate into three lines")
    }

    private func assertWholePlayerControl(_ control: XCUIElement, inside bounds: CGRect) {
        XCTAssertTrue(control.exists && control.isHittable, "Every saved-audio control must be usable")
        XCTAssertTrue(control.isEnabled)
        XCTAssertGreaterThan(control.frame.width, 0)
        XCTAssertGreaterThan(control.frame.height, 0)
        XCTAssertTrue(bounds.insetBy(dx: -1, dy: -1).contains(control.frame),
                      "Entire control \(control.label) must be visible, frame=\(control.frame), viewport=\(bounds)")
    }

    private func revealFirstSavedSpeaker(in reader: XCUIElement, app: XCUIApplication) {
        let firstTime = reader.buttons["Play from 0:01"] // Inspect identity only; never tap audio.
        var identity: String?
        for attempt in 0...8 {
            let viewport = reader.frame.intersection(app.frame).insetBy(dx: 2, dy: 2)
            guard viewport.width > 44, viewport.height > 44 else {
                XCTFail("Transcript needs an unobscured scroll viewport"); return
            }
            if identity == nil, firstTime.exists, firstTime.identifier.hasPrefix("transcript-play-") {
                identity = "transcript-speaker-" + firstTime.identifier.dropFirst("transcript-play-".count)
            }
            let speaker = reader.staticTexts[identity ?? "unresolved-first-speaker"]
            if speaker.exists && speaker.isHittable && viewport.contains(speaker.frame) {
                XCTAssertEqual(speaker.label, "Speaker 1")
                return
            }
            guard attempt < 8 else { break }
            let earlier = !speaker.exists || speaker.frame.minY < viewport.minY
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let x = viewport.minX + viewport.width * 0.94 - app.frame.minX
            let low = viewport.minY + viewport.height * 0.30 - app.frame.minY
            let high = viewport.minY + viewport.height * 0.75 - app.frame.minY
            origin.withOffset(CGVector(dx: x, dy: earlier ? low : high)).press(forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: x, dy: earlier ? high : low)))
        }
        XCTFail("The exact first identified speaker must be reachable by ordinary bounded reader scrolling")
    }

    private func capturePlayerLayout(_ app: XCUIApplication, name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + " AX"; tree.lifetime = .keepAlways; add(tree)
    }

}
