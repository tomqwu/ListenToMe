import XCTest
@testable import ListenToMeCore

@MainActor
final class ReferenceContextCoordinatorTests: XCTestCase {
    func testCancelBeforeExecutionReadsNoFiles() async {
        let reader = HeldReferenceRead()
        let coordinator = ReferenceContextCoordinator()
        var publications = 0
        let work = coordinator.load([], maxChars: 500, read: { _ in await reader.immediate() },
                                    apply: { _ in publications += 1 })
        coordinator.cancel()
        await work.value
        let reads = await reader.count
        XCTAssertEqual(reads, 0, "A window closed before execution must not start file I/O")
        XCTAssertEqual(publications, 0)
    }

    func testCancelledRequestCannotPublishALateLocalRead() async {
        let reader = HeldReferenceRead()
        let coordinator = ReferenceContextCoordinator()
        var publications = 0
        let work = coordinator.load([], maxChars: 500, read: { _ in await reader.held() },
                                    apply: { _ in publications += 1 })
        await waitForRead(reader)
        work.cancel()
        await reader.finish("Private obsolete content")
        await work.value
        XCTAssertEqual(publications, 0)
    }

    func testClearOrCloseDiscardsLateContentAndSkippedMessages() async {
        let reader = HeldReferenceRead()
        let coordinator = ReferenceContextCoordinator()
        var context: String? = "Existing selected content"
        var skipped: [TextFileReader.Skipped] = []
        let work = coordinator.load([], maxChars: 500, read: { _ in await reader.held() }, apply: {
            context = $0.context; skipped = $0.skipped
        })
        await waitForRead(reader)
        coordinator.cancel()
        context = nil
        await reader.finish("Cleared content", skipped: [.init(name: "Old file", reason: "unreadable")])
        await work.value
        XCTAssertNil(context)
        XCTAssertTrue(skipped.isEmpty)
    }

    func testNewerSelectionOwnsGroundingEvenWhenOlderReadFinishesLast() async {
        let reader = HeldReferenceRead()
        let coordinator = ReferenceContextCoordinator()
        var context: String?
        let old = coordinator.load([], maxChars: 500, read: { _ in await reader.held() }, apply: { context = $0.context })
        await waitForRead(reader)
        let new = coordinator.load([], maxChars: 500, read: { _ in
            .init(documents: [.init(name: "new.txt", content: "Current selection")])
        }, apply: { context = $0.context })
        await new.value
        await reader.finish("Old selection")
        await old.value
        XCTAssertEqual(context, "### new.txt\nCurrent selection")
    }

    private func waitForRead(_ reader: HeldReferenceRead) async {
        for _ in 0..<200 {
            if await reader.count > 0 { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("The injected local reader did not start")
    }

    func testSelectedLocalTextBecomesBoundedGroundingAndReportsSkippedFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let text = root.appendingPathComponent("selected.txt")
        try String(repeating: "Local selected material. ", count: 100).write(to: text, atomically: true, encoding: .utf8)
        let missing = root.appendingPathComponent("missing.txt")
        let coordinator = ReferenceContextCoordinator()
        var result: ReferenceContextCoordinator.Update?
        await coordinator.load([text, missing], maxChars: 300, apply: { result = $0 }).value
        XCTAssertTrue(result?.context?.hasPrefix("### selected.txt\nLocal selected material.") == true)
        XCTAssertTrue(result?.context?.hasSuffix("[reference material truncated to fit the context budget]") == true)
        XCTAssertLessThan(result?.context?.count ?? .max, 400)
        XCTAssertEqual(result?.skipped.map(\.name), ["missing.txt"])
        XCTAssertEqual(result?.skipped.map(\.reason), ["not found"])
    }

    func testUnreadableSelectionDoesNotInventGrounding() async {
        let coordinator = ReferenceContextCoordinator()
        var result: ReferenceContextCoordinator.Update?
        await coordinator.load([URL(fileURLWithPath: "/missing-\(UUID().uuidString).txt")], maxChars: 500,
                               apply: { result = $0 }).value
        XCTAssertNil(result?.context)
        XCTAssertEqual(result?.skipped.count, 1)
    }
}

private actor HeldReferenceRead {
    private(set) var count = 0
    private var reply: CheckedContinuation<FileContextLoader.Result, Never>?
    func immediate() -> FileContextLoader.Result { count += 1; return .init() }
    func held() async -> FileContextLoader.Result {
        count += 1
        return await withCheckedContinuation { reply = $0 }
    }
    func finish(_ content: String, skipped: [TextFileReader.Skipped] = []) {
        reply?.resume(returning: .init(documents: [.init(name: "old.txt", content: content)], skipped: skipped))
        reply = nil
    }
}
