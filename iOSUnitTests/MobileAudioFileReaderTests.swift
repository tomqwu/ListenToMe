import AVFoundation
import XCTest
@testable import ListenToMeIOS

final class MobileAudioFileReaderTests: XCTestCase {
    func testCompressedAACEndsNormallyAndRepeatedEOFIsHarmless() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let writer = try AVAudioFile(forWriting: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000
            ])
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: writer.processingFormat, frameCapacity: 12_000))
            buffer.frameLength = 12_000
            let channel = try XCTUnwrap(buffer.floatChannelData?[0])
            for index in 0..<12_000 { channel[index] = Float(sin(Double(index) * 0.1)) * 0.1 }
            try writer.write(from: buffer)
        }
        let expectedFrames = try AVAudioFile(forReading: url).length
        let reader = try XCTUnwrap(AudioFileChunkProducer(url: url, source: .others))
        let initialProgress = await reader.progress()
        XCTAssertEqual(initialProgress, 0)
        var frames = 0
        var previousProgress = 0.0
        while let chunk = try await reader.next() {
            frames += chunk.samples.count
            let progress = await reader.progress()
            XCTAssertGreaterThanOrEqual(progress, previousProgress)
            XCTAssertLessThanOrEqual(progress, 1)
            previousProgress = progress
        }
        XCTAssertEqual(previousProgress, 1)
        XCTAssertEqual(Int64(frames), expectedFrames)
        XCTAssertGreaterThan(frames, 0)
        let eof = try await reader.next()
        XCTAssertNil(eof)
    }
}
