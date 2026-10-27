import AVFoundation
import XCTest
@testable import ListenToMeWatch

enum WatchAudioFixture {
    /// Real AAC encode/decode on watchOS, without a microphone, audible playback or paired transport.
    static func write(to url: URL) throws -> Data {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                                channels: 1, interleaved: false))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
        buffer.frameLength = 16_000
        let samples = try XCTUnwrap(buffer.floatChannelData)[0]
        for frame in 0..<16_000 { samples[frame] = Float(sin(Double(frame) * 2 * .pi * 220 / 16_000)) * 0.1 }
        do {
            let writer = try AVAudioFile(forWriting: url, settings: WatchEngineCapture.fileSettings,
                                         commonFormat: .pcmFormatFloat32, interleaved: false)
            try writer.write(from: buffer)
        }
        XCTAssertGreaterThan(try AVAudioFile(forReading: url).length, 0)
        return try Data(contentsOf: url)
    }
}
