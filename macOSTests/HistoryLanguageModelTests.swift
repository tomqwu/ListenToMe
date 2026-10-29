import Foundation
import XCTest

@MainActor
final class HistoryLanguageModelTests: XCTestCase {
    private func make(_ service: HistoryAssetService) -> (HistoryLanguageModel, UserDefaults) {
        let defaults = UserDefaults(suiteName: "history-model-test-" + UUID().uuidString)!
        let model = HistoryLanguageModel(defaults: defaults, lookup: { await service.lookup() },
                                        install: { progress in try await service.install(progress) },
                                        remove: { await service.remove() })
        return (model, defaults)
    }

    func testOpeningSettingsDoesNotDownloadOrEnableAnInstalledModel() async {
        let service = HistoryAssetService(installed: true)
        let (model, defaults) = make(service)
        defer { defaults.removeObject(forKey: HistoryLanguageModel.enabledKey) }
        model.refresh()
        await model.waitForOperation()
        XCTAssertEqual(model.state, .ready)
        XCTAssertFalse(model.enabled)
        XCTAssertNil(model.activeDirectory)
        let downloads = await service.downloads
        XCTAssertEqual(downloads, 0)
        model.setEnabled(true)
        XCTAssertTrue(model.enabled)
        XCTAssertEqual(model.activeDirectory, HistoryAssetService.directory)
        model.setEnabled(false)
        XCTAssertNil(model.activeDirectory)
    }

    func testDownloadEnablesOnlyAfterVerifiedCompletion() async {
        let service = HistoryAssetService()
        let (model, defaults) = make(service)
        defer { defaults.removeObject(forKey: HistoryLanguageModel.enabledKey) }
        model.download()
        await service.waitUntilStarted()
        XCTAssertEqual(model.state, .downloading)
        XCTAssertFalse(model.enabled)
        XCTAssertNil(model.activeDirectory)
        await service.release()
        await model.waitForOperation()
        XCTAssertEqual(model.state, .ready)
        XCTAssertTrue(model.enabled)
        XCTAssertTrue(defaults.bool(forKey: HistoryLanguageModel.enabledKey))
        XCTAssertEqual(model.activeDirectory, HistoryAssetService.directory)
    }

    func testCancelPreventsLateDownloadFromActivatingOrReportingProgress() async {
        let service = HistoryAssetService()
        let (model, defaults) = make(service)
        defer { defaults.removeObject(forKey: HistoryLanguageModel.enabledKey) }
        model.download()
        await service.waitUntilStarted()
        model.cancel()
        await service.release()
        await model.waitForOperation()
        XCTAssertEqual(model.state, .notInstalled)
        XCTAssertFalse(model.enabled)
        XCTAssertNil(model.activeDirectory)
        XCTAssertEqual(model.progress, 0)
        XCTAssertFalse(defaults.bool(forKey: HistoryLanguageModel.enabledKey))
    }

    func testRemovingModelDisablesSearchBeforeStorageFinishes() async {
        let service = HistoryAssetService(installed: true)
        let (model, defaults) = make(service)
        defer { defaults.removeObject(forKey: HistoryLanguageModel.enabledKey) }
        model.refresh()
        await model.waitForOperation()
        model.setEnabled(true)
        var directories: [URL?] = []
        model.didChange = { directories.append($0) }
        model.remove()
        XCTAssertFalse(model.enabled)
        XCTAssertNil(model.activeDirectory)
        XCTAssertEqual(directories.count, 1)
        await model.waitForOperation()
        XCTAssertEqual(model.state, .notInstalled)
        let removed = await service.removed
        XCTAssertTrue(removed)
    }
}

private actor HistoryAssetService {
    nonisolated static let directory = URL(fileURLWithPath: "/synthetic-verified-model")
    var installed: Bool
    var downloads = 0
    var removed = false
    private var started: CheckedContinuation<Void, Never>?
    private var held: CheckedContinuation<Void, Never>?
    init(installed: Bool = false) { self.installed = installed }
    func lookup() -> URL? { installed ? Self.directory : nil }
    func install(_ progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        downloads += 1
        await withCheckedContinuation { continuation in
            held = continuation
            started?.resume(); started = nil
        }
        progress(1) // Deliberately ignores cancellation to exercise the owner fence.
        installed = true
        return Self.directory
    }
    func waitUntilStarted() async {
        if downloads > 0 { return }
        await withCheckedContinuation { started = $0 }
    }
    func release() { held?.resume(); held = nil }
    func remove() { installed = false; removed = true }
}
