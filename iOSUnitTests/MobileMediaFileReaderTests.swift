import AVFoundation
import XCTest
@testable import ListenToMeIOS

final class MobileMediaFileReaderTests: XCTestCase {
    private func fixture(_ name: String, extension suffix: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: suffix))
    }
    func testMP4AndMOVDecodeAudioWithChosenSourceAndProgress() async throws {
        for suffix in ["mp4", "mov"] {
            let url = try fixture("import-tone", extension: suffix)
            let reader = try await MediaFileChunkProducer.open(url: url, source: .you)
            var count = 0
            var energy = 0.0
            var lastTime = 0.0
            var lastProgress = 0.0
            while let chunk = try await reader.next() {
                XCTAssertEqual(chunk.source, .you)
                XCTAssertEqual(chunk.sampleRate, 16_000)
                XCTAssertGreaterThanOrEqual(chunk.timestamp, lastTime)
                lastTime = chunk.timestamp
                count += chunk.samples.count
                energy += chunk.samples.reduce(0) { $0 + Double($1 * $1) }
                let progress = await reader.progress()
                XCTAssertGreaterThanOrEqual(progress, lastProgress)
                XCTAssertLessThanOrEqual(progress, 1)
                lastProgress = progress
            }
            XCTAssertGreaterThan(count, 15_000)
            XCTAssertLessThan(count, 18_000)
            XCTAssertGreaterThan(energy, 1)
            let finished = await reader.progress()
            XCTAssertEqual(finished, 1)
            let repeatedEOF = try await reader.next()
            XCTAssertNil(repeatedEOF)
        }
    }
    func testAudioFileKeepsExistingDecoderAndSourceSelection() async throws {
        let url = try fixture("watch-chunk-0", extension: "m4a")
        let reader = try await MediaFileChunkProducer.open(url: url, source: .others)
        var count = 0
        while let chunk = try await reader.next() {
            XCTAssertEqual(chunk.source, .others)
            count += chunk.samples.count
        }
        XCTAssertGreaterThan(count, 0)
        let progress = await reader.progress()
        XCTAssertEqual(progress, 1)
    }
    func testSilentMovieReportsNoAudioTrack() async throws {
        let url = try fixture("import-silent", extension: "mp4")
        do {
            _ = try await MediaFileChunkProducer.open(url: url, source: .others)
            XCTFail("Expected no-audio error")
        } catch { XCTAssertTrue(error.localizedDescription.contains("no audio track"), error.localizedDescription) }
    }
    func testCancelledMovieReadStopsWithoutConsumingTheRest() async throws {
        let url = try fixture("import-tone", extension: "mov")
        let reader = try await MediaFileChunkProducer.open(url: url, source: .others)
        let first = try await reader.next()
        XCTAssertEqual(first?.source, .others)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await reader.next()
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
