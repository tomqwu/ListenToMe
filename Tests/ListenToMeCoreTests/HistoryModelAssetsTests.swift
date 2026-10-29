import Foundation
import CryptoKit
import XCTest
@testable import ListenToMeCore

private final class AssetProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var updates: [Double] = []
    func append(_ value: Double) { lock.lock(); defer { lock.unlock() }; updates.append(value) }
    var values: [Double] { lock.lock(); defer { lock.unlock() }; return updates }
}

private actor AssetDownloads {
    var calls = 0
    var held = false
    var started = false
    var lastDestination: URL?
    var skipWriting = false
    private var continuation: CheckedContinuation<Void, Never>?
    func hold() { held = true }
    func omitWrite() { skipWriting = true }
    func release() { held = false; continuation?.resume(); continuation = nil }
    func download(_ url: URL, _ destination: URL, _ progress: @Sendable (Double) -> Void) async throws {
        calls += 1; started = true; lastDestination = destination
        if held { await withCheckedContinuation { continuation = $0 } }
        // Deliberately uncooperative: removal/cancellation must fence this late file.
        if !skipWriting { try Data(url.lastPathComponent.utf8).write(to: destination) }
        progress(1)
    }
}

final class HistoryModelAssetsTests: XCTestCase, @unchecked Sendable {
    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HistoryAssets-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func asset(_ name: String) -> HistoryModelAssets.Asset {
        let bytes = Data(name.utf8)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return .init(name: name, bytes: Int64(bytes.count), sha256: digest)
    }
    private func make(_ root: URL, _ downloads: AssetDownloads) -> HistoryModelAssets {
        HistoryModelAssets(directory: root, assets: [asset("config.json"), asset("model.safetensors")],
            downloader: { try await downloads.download($0, $1, $2) })
    }
    private func waitStarted(_ downloads: AssetDownloads) async throws {
        for _ in 0..<100 {
            if await downloads.started { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Downloader did not start"); throw CancellationError()
    }
    func testReadinessNeverDownloadsAndProductionManifestIsPinned() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let downloads = AssetDownloads(); let store = make(root, downloads)
        let absent = await store.installedDirectory(); XCTAssertNil(absent)
        let calls = await downloads.calls; XCTAssertEqual(calls, 0)
        XCTAssertEqual(HistoryModelAssets.revision, "4328cf26390c98c5e3c738b4460a05b95f4911f5")
        XCTAssertEqual(HistoryModelAssets.assets.count, 6)
        XCTAssertEqual(HistoryModelAssets.totalBytes, 1_126_353_221)
        XCTAssertTrue(HistoryModelAssets.assets.allSatisfy {
            $0.url.path.contains("/resolve/" + HistoryModelAssets.revision + "/") && $0.url.scheme == "https"
        })
    }
    func testExplicitInstallPublishesOnlyVerifiedFilesAndReopensOffline() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let downloads = AssetDownloads(); let store = make(root, downloads)
        try await store.install()
        let value = await store.installedDirectory(); let installed = try XCTUnwrap(value)
        XCTAssertEqual(try Data(contentsOf: installed.appendingPathComponent("config.json")), Data("config.json".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: installed.path).sorted(),
                       ["config.json", "model.safetensors"])
        XCTAssertTrue(PrivateStorage.isExcludedFromBackup(installed))
        let reopened = make(root, downloads); let found = await reopened.installedDirectory()
        XCTAssertEqual(found, installed)
        let calls = await downloads.calls; XCTAssertEqual(calls, 2)
    }
    func testBadHashOrSizeNeverPublishesAndCleansOnlyOwnedStaging() async throws {
        for wrongSize in [false, true] {
            let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
            let sentinel = root.appendingPathComponent("unrelated.txt"); try Data("keep".utf8).write(to: sentinel)
            let good = asset("config.json")
            let bad = HistoryModelAssets.Asset(name: good.name, bytes: good.bytes + (wrongSize ? 1 : 0),
                sha256: wrongSize ? good.sha256 : String(repeating: "0", count: 64))
            let store = HistoryModelAssets(directory: root, assets: [bad], downloader: { url, output, _ in
                try Data(url.lastPathComponent.utf8).write(to: output)
            })
            do { try await store.install(); XCTFail("Invalid asset installed") } catch {}
            let installed = await store.installedDirectory(); XCTAssertNil(installed)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["unrelated.txt"])
            XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep".utf8))
        }
    }
    func testCancelledInstallCannotPublishLateDownload() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let downloads = AssetDownloads(); await downloads.hold(); let store = make(root, downloads)
        let work = Task { try await store.install() }; try await waitStarted(downloads)
        work.cancel(); await downloads.release()
        do { try await work.value; XCTFail("Cancelled installation succeeded") } catch {}
        let installed = await store.installedDirectory(); XCTAssertNil(installed)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
    func testRemoveWaitsForOwnedDownloadAndPreventsLateReappearance() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let downloads = AssetDownloads(); await downloads.hold(); let store = make(root, downloads)
        let progress = AssetProgress()
        let work = Task { try await store.install(progress: { progress.append($0) }) }; try await waitStarted(downloads)
        let removal = Task { try await store.remove() }
        // Observing not-installed before releasing the producer establishes the removal fence.
        for _ in 0..<100 {
            if await store.status == .notInstalled { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let state = await store.status; XCTAssertEqual(state, .notInstalled)
        let countAtRemoval = progress.values.count
        await downloads.release(); try await removal.value
        do { try await work.value; XCTFail("Removed installation succeeded") } catch {}
        XCTAssertEqual(progress.values.count, countAtRemoval, "A removed producer must not emit late progress")
        let installed = await store.installedDirectory(); XCTAssertNil(installed)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        try await store.install(); let reinstalled = await store.installedDirectory(); XCTAssertNotNil(reinstalled)
    }
    func testCorruptMissingAndSymlinkAssetsAreNotReady() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let downloads = AssetDownloads(); let store = make(root, downloads); try await store.install()
        let found = await store.installedDirectory(); let installed = try XCTUnwrap(found)
        let file = installed.appendingPathComponent("config.json")
        try Data("corrupt".utf8).write(to: file)
        let corrupt = await store.installedDirectory(); XCTAssertNil(corrupt)
        try FileManager.default.removeItem(at: file)
        let missing = await store.installedDirectory(); XCTAssertNil(missing)
        let external = root.appendingPathComponent("external"); try Data("config.json".utf8).write(to: external)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: external)
        let linked = await store.installedDirectory(); XCTAssertNil(linked)
        try await store.remove(); XCTAssertEqual(try Data(contentsOf: external), Data("config.json".utf8))
        let calls = await downloads.calls; XCTAssertEqual(calls, 2)
    }
    func testSymlinkedOwnerOrAncestorCannotReadInstallOrRemoveExternalModel() async throws {
        for ancestor in [false, true] {
            let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
            let external = root.appendingPathComponent("external")
            let realOwner = ancestor ? external.appendingPathComponent("owner") : external
            let downloads = AssetDownloads(); let original = make(realOwner, downloads)
            try await original.install()
            let ready = await original.installedDirectory(); let installed = try XCTUnwrap(ready)
            let originalBytes = try Data(contentsOf: installed.appendingPathComponent("config.json"))
            let link = root.appendingPathComponent("linked")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)
            let unsafe = make(ancestor ? link.appendingPathComponent("owner") : link, downloads)
            let found = await unsafe.installedDirectory(); XCTAssertNil(found)
            do { try await unsafe.install(); XCTFail("Linked owner must not install") } catch {}
            do { try await unsafe.remove(); XCTFail("Linked owner must not remove external model") } catch {}
            XCTAssertEqual(try? Data(contentsOf: installed.appendingPathComponent("config.json")), originalBytes)
            let calls = await downloads.calls; XCTAssertEqual(calls, 2, "Unsafe owner must not download")
        }
    }

    func testDownloadedSymlinkIsRejectedBeforeChangingExternalPermissions() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let external = root.appendingPathComponent("outside")
        try Data("config.json".utf8).write(to: external)
        try FileManager.default.setAttributes([.posixPermissions: 0o604], ofItemAtPath: external.path)
        let store = HistoryModelAssets(directory: root.appendingPathComponent("owner"), assets: [asset("config.json")],
            downloader: { _, output, _ in
                try FileManager.default.createSymbolicLink(at: output, withDestinationURL: external)
            })
        do { try await store.install(); XCTFail("Linked asset must not install") } catch {}
        let attributes = try FileManager.default.attributesOfItem(atPath: external.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o604)
        XCTAssertEqual(try Data(contentsOf: external), Data("config.json".utf8))
        let installed = await store.installedDirectory(); XCTAssertNil(installed)
    }

    func testChangedOwnerPreservesExternalStageAndQuarantinesOriginal() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let owner = root.appendingPathComponent("owner")
        let parked = root.appendingPathComponent("preserved-owner")
        let external = root.appendingPathComponent("external")
        let downloads = AssetDownloads(); await downloads.hold(); await downloads.omitWrite()
        let store = make(owner, downloads)
        let work = Task { try await store.install() }; try await waitStarted(downloads)
        let output = await downloads.lastDestination
        let stageName = try XCTUnwrap(output).deletingLastPathComponent().lastPathComponent
        try FileManager.default.moveItem(at: owner, to: parked)
        let externalStage = external.appendingPathComponent(stageName)
        try FileManager.default.createDirectory(at: externalStage, withIntermediateDirectories: true)
        let sentinel = externalStage.appendingPathComponent("keep.txt")
        try Data("external sentinel".utf8).write(to: sentinel)
        try FileManager.default.createSymbolicLink(at: owner, withDestinationURL: external)
        await downloads.release()
        do { try await work.value; XCTFail("Changed owner must refuse publication") } catch {}
        XCTAssertEqual(try? Data(contentsOf: sentinel), Data("external sentinel".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: parked.appendingPathComponent(stageName).path),
                      "Unsafe staging stays preserved rather than being removed through a changed owner")
        let installed = await store.installedDirectory(); XCTAssertNil(installed)
    }

}
