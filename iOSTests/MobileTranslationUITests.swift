import XCTest
import UIKit

@MainActor
final class MobileTranslationUITests: XCTestCase {
    override func tearDown() async throws {
        XCUIDevice.shared.orientation = .portrait
        try await super.tearDown()
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--design-review-fixture", "--translation-fixture", "-autoQuickSummary", "NO"] + extra
        app.launchPastReleaseNotes()
        return app
    }
    private func openOptions(_ app: XCUIApplication) -> Bool {
        app.buttons["More"].tap()
        let options = app.buttons["Live translation"]
        guard options.waitForExistence(timeout: 5) else {
            XCTFail("Translation and summary language must have a reachable native control"); return false
        }
        options.tap()
        return app.switches["liveTranslationToggle"].waitForExistence(timeout: 5)
    }
    private func choose(_ identifier: String, _ language: String, in app: XCUIApplication) {
        let picker = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        for _ in 0..<5 where !picker.isHittable { app.swipeUp() }
        XCTAssertTrue(picker.isHittable); picker.tap()
        let choice = app.buttons[language]
        if !choice.isHittable {
            capture(app, "Language picker before scrolling at accessibility size")
            // The observed native picker menu is a CollectionView. Its virtualized rows may
            // exist outside its clipped viewport; scroll the menu until the target is hittable.
            let menus = app.collectionViews
            XCTAssertGreaterThan(menus.count, 0)
            let menu = menus.element(boundBy: max(0, menus.count - 1))
            for _ in 0..<8 where !choice.isHittable { menu.swipeUp() }
        }
        XCTAssertTrue(choice.isHittable); choice.tap()
        // iOS may keep a picker menu presented after selection. Dismiss that menu before the
        // next control rather than treating the first background tap as a toggle/Done action.
        if app.buttons[language].exists {
            if app.navigationBars["Live translation"].exists {
                app.navigationBars["Live translation"].staticTexts["Live translation"].tap()
            } else { app.staticTexts["On-device translation keeps the original below. Check translated wording before sharing."].tap() }
        }
        XCTAssertTrue(picker.label.contains(language))
    }
    /// App-wide swipes can fling a large-text control past the opposite edge. Reveal inside
    /// the owning scroll view, rechecking direction and full bounds before any action tap.
    private func revealSummary(_ target: XCUIElement, in app: XCUIApplication,
                               entirely: Bool = true, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let scroll = app.scrollViews["dashboardScroll"]
        guard target.waitForExistence(timeout: 5), scroll.waitForExistence(timeout: 5) else {
            XCTFail("Summary target and scroll view must exist", file: file, line: line); return false
        }
        for _ in 0..<20 {
            let viewport = scroll.frame.intersection(app.windows.firstMatch.frame).insetBy(dx: 2, dy: 2)
            let frame = target.frame
            let visible = viewport.intersection(frame)
            let enoughVisible = entirely ? viewport.contains(frame)
                : !visible.isNull && visible.height >= min(frame.height, viewport.height * 0.5)
            if target.isEnabled && target.isHittable && enoughVisible { return true }
            guard viewport.height > 100, target.isEnabled else { break }
            let below = frame.midY > viewport.midY
            let distance = min(viewport.height * 0.4, max(44, abs(frame.midY - viewport.midY)))
            let direction: CGFloat = below ? 1 : -1
            let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            let window = app.windows.firstMatch.frame
            let from = origin.withOffset(CGVector(dx: viewport.midX - window.minX,
                                                  dy: viewport.midY - window.minY + direction * distance / 2))
            let to = origin.withOffset(CGVector(dx: viewport.midX - window.minX,
                                                dy: viewport.midY - window.minY - direction * distance / 2))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        let detail = XCTAttachment(string: "Target \(target.frame); scroll \(scroll.frame)\n" + app.debugDescription)
        detail.name = "Summary reveal failed"; detail.lifetime = .keepAlways; add(detail)
        capture(app, "Summary reveal failed")
        XCTFail("Summary control must be visibly reachable before tapping", file: file, line: line)
        return false
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
    func testLanguageControlsTranslateFinalSpeechInPortraitAndDuoWithoutChangingOriginal() {
        let app = launch(); guard openOptions(app) else { return }
        choose("translationTargetPicker", "French", in: app)
        let toggle = app.switches["liveTranslationToggle"]
        for _ in 0..<5 where !toggle.isHittable { app.swipeDown() }
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1")
        capture(app, "Live translation options")
        XCTAssertTrue(app.buttons["Done"].isHittable)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Live translation"].waitForNonExistence(timeout: 5))
        let translated = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "translated-line-")).firstMatch
        XCTAssertTrue(translated.waitForExistence(timeout: 5))
        let originals = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "transcript-text-"))
        XCTAssertGreaterThan(originals.count, 0, "Original speech stays alongside its translation")
        XCTAssertFalse(app.buttons["Stop listening"].exists, "Translation never starts the microphone")
        capture(app, "Original transcript and on-device translation portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
        let duo = app.otherElements["twoPaneMeetingWorkspace"]
        let wide = app.otherElements["wideMeetingWorkspace"]
        XCTAssertTrue(duo.waitForExistence(timeout: 3) || wide.exists)
        XCTAssertTrue(translated.waitForExistence(timeout: 5))
        capture(app, "Original transcript and translation in Duo or iPad wide layout")
    }
    func testSummaryPageOffersExplicitTranslationAndKeepsOriginal() {
        let app = launch()
        if app.buttons["Summary"].firstMatch.exists { app.buttons["Summary"].firstMatch.tap() }
        let option = app.buttons["summaryTranslationOptions"]
        XCTAssertTrue(option.waitForExistence(timeout: 5), "Translation must be available on the Summary page")
        guard option.exists else { return }
        option.tap()
        choose("summaryTranslationTargetPicker", "French", in: app)
        XCTAssertFalse(app.staticTexts["translatedSummary"].exists)
        app.buttons["translateSummary"].tap()
        XCTAssertTrue(app.staticTexts["translatedSummary"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["output-summary"].exists, "The original summary remains available")
        XCTAssertFalse(app.buttons["Stop listening"].exists)
        capture(app, "Summary page French translation beside original")
        app.buttons["closeSummaryTranslation"].tap()
        XCTAssertFalse(app.staticTexts["translatedSummary"].exists)
        XCTAssertTrue(app.staticTexts["output-summary"].isHittable)
    }
    func testSummaryMissingPacksAndLargestTextKeepOriginalReachable() {
        let app = launch(["--translation-needs-packs", "-UIPreferredContentSizeCategoryName",
                          "UICTContentSizeCategoryAccessibilityXXXL"])
        if app.buttons["Summary"].firstMatch.exists { app.buttons["Summary"].firstMatch.tap() }
        let option = app.buttons["summaryTranslationOptions"]
        guard revealSummary(option, in: app) else { return }
        option.tap()
        choose("summaryTranslationTargetPicker", "French", in: app)
        let translate = app.buttons["translateSummary"]
        guard revealSummary(translate, in: app) else { return }
        let scroll = app.scrollViews["dashboardScroll"]
        XCTAssertTrue(scroll.frame.contains(translate.frame), "The whole Translate button must be visible before tapping")
        capture(app, "Translate fully visible at largest accessibility text")
        // Reproduce the original harness's overshoot deliberately, then prove the user can
        // scroll back to the same whole control without relying on tap's auto-scroll behavior.
        if UIDevice.current.userInterfaceIdiom == .phone {
            for _ in 0..<8 where translate.frame.maxY >= scroll.frame.minY { scroll.swipeUp(velocity: .slow) }
            XCTAssertLessThan(translate.frame.maxY, scroll.frame.minY, "Phone fixture must place Translate above the viewport")
            guard revealSummary(translate, in: app) else { return }
        }
        XCTAssertTrue(translate.isHittable)
        XCTAssertTrue(scroll.frame.contains(translate.frame))
        translate.tap()
        let prepare = app.buttons["prepareTranslationLanguages"]
        XCTAssertTrue(prepare.waitForExistence(timeout: 5))
        guard revealSummary(prepare, in: app) else { return }
        XCTAssertTrue(prepare.isHittable)
        XCTAssertFalse(app.staticTexts["Preparing translation languages…"].exists)
        XCTAssertFalse(app.staticTexts["translatedSummary"].exists)
        capture(app, "Summary language setup at largest accessibility text")
        let close = app.buttons["closeSummaryTranslation"]
        guard revealSummary(close, in: app) else { return }
        XCTAssertTrue(close.isHittable); close.tap()
        let original = app.staticTexts["output-summary"]
        guard revealSummary(original, in: app, entirely: false) else { return }
        XCTAssertTrue(original.isHittable)
        XCTAssertTrue(app.buttons["Start listening"].isHittable)
        XCTAssertFalse(app.buttons["Stop listening"].exists)
        capture(app, "Original summary remains readable at largest accessibility text")
    }
    func testMissingPacksExplainSetupWithoutStartingDownloadOrRecording() {
        let app = launch(["--translation-needs-packs"]); guard openOptions(app) else { return }
        choose("translationTargetPicker", "French", in: app)
        let toggle = app.switches["liveTranslationToggle"]
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1")
        XCTAssertTrue(app.buttons["prepareTranslationLanguages"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Preparing translation languages…"].exists)
        XCTAssertFalse(app.buttons["Stop listening"].exists)
        capture(app, "On-device translation setup required without automatic download")
    }
}
