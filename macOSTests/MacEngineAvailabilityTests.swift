import XCTest
import ListenToMeCore

@MainActor
final class MacEngineAvailabilityTests: XCTestCase {
    func testLateLanguageCheckCannotRestoreAnUnsupportedMenuChoice() async {
        let oldLocale = Locale(identifier: "en-US"), currentLocale = Locale(identifier: "xx-XX")
        var pending: CheckedContinuation<FeatureAvailability, Never>?
        let menu = MacEngineAvailability { engine, locale in
            if engine == "speechAnalyzer", locale == oldLocale {
                return await withCheckedContinuation { pending = $0 }
            }
            if engine == "speechAnalyzer" { return .unsupported(reason: "Choose a supported language in Settings.") }
            return .ready
        }
        let oldCheck = Task { await menu.refresh(locale: oldLocale) }
        for _ in 0..<200 where pending == nil { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(pending)
        await menu.refresh(locale: currentLocale)
        XCTAssertFalse(menu.choices.contains("speechAnalyzer"))
        pending?.resume(returning: .ready)
        await oldCheck.value
        XCTAssertFalse(menu.choices.contains("speechAnalyzer"), "The previous language cannot restore this menu choice")
        XCTAssertTrue(menu.status(for: "speechAnalyzer").reason?.contains("supported language") == true)
        XCTAssertEqual(menu.select("speechAnalyzer", current: "whisperKit"), "whisperKit")
    }

    func testCheckingClearsChoicesAndRefusesAnOldOpenMenuAction() async {
        var hold = false
        var pending: CheckedContinuation<FeatureAvailability, Never>?
        let menu = MacEngineAvailability { engine, _ in
            if hold, engine == "speechAnalyzer" { return await withCheckedContinuation { pending = $0 } }
            return .ready
        }
        await menu.refresh(locale: Locale(identifier: "en-US"))
        XCTAssertTrue(menu.choices.contains("speechAnalyzer"))
        hold = true
        let refresh = Task { await menu.refresh(locale: Locale(identifier: "xx-XX")) }
        for _ in 0..<200 where pending == nil { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(pending)
        XCTAssertTrue(menu.choices.isEmpty, "A pending check must not advertise old verified choices")
        XCTAssertFalse(menu.status(for: "speechAnalyzer").canRun)
        XCTAssertEqual(menu.select("speechAnalyzer", current: "whisperKit"), "whisperKit",
                       "An action retained by an open menu must recheck current readiness")
        pending?.resume(returning: .unsupported(reason: "Unavailable for this language."))
        await refresh.value
        XCTAssertFalse(menu.choices.contains("speechAnalyzer"))
        XCTAssertEqual(menu.select("speechAnalyzer", current: "whisperKit"), "whisperKit")
    }

    func testLanguageChangeRefusesOldActionsBeforeTheNextCheckStarts() async {
        let menu = MacEngineAvailability { _, _ in .ready }
        let checked = Locale(identifier: "en-US"), changed = Locale(identifier: "xx-XX")
        await menu.refresh(locale: checked)
        XCTAssertTrue(menu.choices(for: checked).contains("speechAnalyzer"))
        XCTAssertTrue(menu.choices(for: changed).isEmpty)
        XCTAssertFalse(menu.status(for: "speechAnalyzer", locale: changed).canRun)
        XCTAssertEqual(menu.select("speechAnalyzer", current: "whisperKit", locale: changed), "whisperKit")
    }

    func testCancelledCheckCannotReplaceNewChoices() async {
        var pending: CheckedContinuation<FeatureAvailability, Never>?
        let oldLocale = Locale(identifier: "en-US")
        let menu = MacEngineAvailability { engine, locale in
            if engine == "speechAnalyzer", locale == oldLocale {
                return await withCheckedContinuation { pending = $0 }
            }
            return engine == "speechAnalyzer" ? .unsupported(reason: "Current language unavailable.") : .ready
        }
        let cancelled = Task { await menu.refresh(locale: oldLocale) }
        for _ in 0..<200 where pending == nil { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(pending)
        cancelled.cancel()
        await menu.refresh(locale: Locale(identifier: "xx-XX"))
        pending?.resume(returning: .ready)
        await cancelled.value
        XCTAssertFalse(menu.choices.contains("speechAnalyzer"))
        XCTAssertTrue(menu.choices.contains("whisperKit"))
    }
}
