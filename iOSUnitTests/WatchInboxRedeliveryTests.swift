import Foundation
import ListenToMeCore
@testable import ListenToMeIOS
import XCTest

/// Real temporary files exercise the receive boundary; the only injected failure is the audio move.
/// Opaque bytes deliberately prove that receiving does not require audio decoding or transcription.
final class WatchInboxRedeliveryTests: XCTestCase {
    func testMissingLedgerRedeliveryMoveFailureKeepsFirstAudioAndSidecar() throws {
        try checkRedelivery(corruptLedger: false)
    }

    func testCorruptLedgerRedeliveryMoveFailureKeepsFirstAudioAndSidecar() throws {
        try checkRedelivery(corruptLedger: true)
    }

    private func checkRedelivery(corruptLedger: Bool) throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchInboxRedelivery-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("WatchInbox")
        let delivered = base.appendingPathComponent("Delivered")
        try FileManager.default.createDirectory(at: delivered, withIntermediateDirectories: true)
        let id = UUID(), started = Date(timeIntervalSince1970: 1_700_000_000)
        let metadata = WatchChunkMetadata(recordingID: id, index: 2, startOffset: 660.25, duration: 117.5,
                                          isLast: true, startedAt: started, watchBuild: "43")
        let first = WatchInbox(root: root, writeFile: { data, url in
            if !corruptLedger && url.lastPathComponent == "manifest.json" {
                throw CocoaError(.fileWriteOutOfSpace)
            }
            try data.write(to: url, options: PrivateStorage.writingOptions)
        })
        let originalBytes = Data(repeating: 11, count: 64)
        let initialDelivery = delivered.appendingPathComponent("first.m4a")
        try originalBytes.write(to: initialDelivery)
        XCTAssertEqual(first.accept(fileAt: initialDelivery, metadata: metadata.transferMetadata, now: started),
                       .stored)
        let audio = first.chunkURL(recordingID: id, index: metadata.index)
        let sidecar = audio.deletingPathExtension().appendingPathExtension("json")
        let originalSidecar = try Data(contentsOf: sidecar)
        XCTAssertEqual(try Data(contentsOf: audio), originalBytes)
        let manifest = audio.deletingLastPathComponent().appendingPathComponent("manifest.json")
        let corruptBytes = Data("interrupted ledger write".utf8)
        if corruptLedger { try corruptBytes.write(to: manifest) }
        XCTAssertTrue(first.ledgers().isEmpty, "The next delivery must arrive before tidy adopts the orphan")

        let incoming = delivered.appendingPathComponent("retry.m4a")
        let retryBytes = Data(repeating: 22, count: 80)
        let retryMetadata = WatchChunkMetadata(recordingID: id, index: 2, startOffset: 600, duration: 120,
                                               isLast: false, startedAt: started, watchBuild: "43")
        try retryBytes.write(to: incoming)
        XCTAssertNotEqual(incoming, audio)
        XCTAssertEqual(try incoming.resourceValues(forKeys: [.fileSizeKey]).fileSize, retryBytes.count)
        XCTAssertLessThan(retryBytes.count, WatchChunkMetadata.maximumFileBytes)
        let receiver = WatchInbox(root: root, moveFile: { source, destination in
            XCTAssertEqual(source, incoming)
            XCTAssertEqual(destination, audio)
            throw CocoaError(.fileWriteOutOfSpace)
        })
        defer { receiver.clearProblems() } // Only this UUID-root's receive-problem key, never user choices.
        let result = receiver.accept(fileAt: incoming, metadata: retryMetadata.transferMetadata,
                                     now: started.addingTimeInterval(60))
        XCTAssertEqual(result, .duplicate, "The first durable copy is already ours despite a missing ledger")
        XCTAssertEqual(try? Data(contentsOf: audio), originalBytes, "A failed retry must not delete earlier audio")
        XCTAssertEqual(try Data(contentsOf: sidecar), originalSidecar, "Keep the first chunk's exact metadata bytes")
        XCTAssertTrue(FileManager.default.fileExists(atPath: incoming.path), "The callback does not own duplicates")
        try FileManager.default.removeItem(at: incoming) // WatchConnectivity removes its temporary delivery on return.

        let healthy = WatchInbox(root: root)
        healthy.tidy(now: started.addingTimeInterval(120))
        let ledger = healthy.ledger(id)
        XCTAssertEqual(ledger?.recordingID, id)
        XCTAssertEqual(ledger?.startedAt, started)
        XCTAssertEqual(ledger?.chunks.map(\.index), [metadata.index], "Recovery must not duplicate the chunk")
        XCTAssertEqual(ledger?.chunks.first?.startOffset, metadata.startOffset)
        XCTAssertEqual(ledger?.chunks.first?.duration, metadata.duration)
        XCTAssertEqual(ledger?.lastIndex, metadata.index)
        XCTAssertEqual(try? Data(contentsOf: audio), originalBytes)
        XCTAssertEqual(try Data(contentsOf: sidecar), originalSidecar)
        if corruptLedger {
            let files = try FileManager.default.contentsOfDirectory(at: manifest.deletingLastPathComponent(),
                                                                    includingPropertiesForKeys: nil)
            let setAside = files.filter { $0.lastPathComponent.hasPrefix("manifest.json.corrupt-") }
            XCTAssertEqual(setAside.count, 1)
            XCTAssertEqual(try setAside.first.map { try Data(contentsOf: $0) }, corruptBytes)
        }
    }
}
