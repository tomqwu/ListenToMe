import AVFoundation
import Foundation
import XCTest
#if os(iOS)
@testable import ListenToMeIOS
#endif

/// Generated PCM only: no SpeechAnalyzer, model, microphone, playback or external audio.
enum AudioChunkFeedAssertions {
    static let rate = 16_000.0
    static func format(_ common: AVAudioCommonFormat) throws -> AVAudioFormat {
        try XCTUnwrap(AVAudioFormat(commonFormat: common, sampleRate: rate, channels: 1, interleaved: false))
    }
    static func folder(_ test: XCTestCase) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AudioChunkFeed-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        test.addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    static func sample(_ index: Int, count: Int, marker: Float) -> Float {
        // The final 64 samples cannot be replaced by padding or the repeating ordinary prefix.
        index >= count - 64 ? marker + Float(index % 16) / 1_024 : Float(index % 251 - 125) / 1_024
    }
    static func wave(_ root: URL, name: String, frames: Int, marker: Float = 0.5, diskFormat: AVAudioCommonFormat = .pcmFormatFloat32) throws -> URL {
        let url = root.appendingPathComponent(name + ".wav")
        let source = try format(.pcmFormatFloat32)
        let disk = try format(diskFormat)
        let file = try AVAudioFile(forWriting: url, settings: disk.settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        if frames > 0 {
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(frames)))
            buffer.frameLength = AVAudioFrameCount(frames)
            let values = try XCTUnwrap(buffer.floatChannelData?[0])
            for index in 0..<frames { values[index] = sample(index, count: frames, marker: marker) }
            try file.write(from: buffer)
        }
        return url
    }
    static func chunk(_ url: URL, index: Int = 0, start: Double = 0, frames: Int) -> LocalAudioChunk {
        LocalAudioChunk(index: index, url: url, startOffset: start, duration: Double(frames) / rate)
    }
    struct Output {
        var samples: [Int16] = []
        var anchors: [(frame: Int, seconds: Double)] = []
        var bufferCount = 0
    }
    static func consume(_ feed: ChunkFeed, limit: Int = 128) throws -> Output {
        var result = Output()
        for _ in 0..<limit {
            guard let pcm = feed.nextPCM() else { return result }
            XCTAssertGreaterThan(pcm.buffer.frameLength, 0, "Do not emit empty conversion buffers")
            XCTAssertEqual(pcm.buffer.format.commonFormat, .pcmFormatInt16)
            XCTAssertEqual(pcm.buffer.format.sampleRate, rate)
            if let start = pcm.bufferStartTime { result.anchors.append((result.samples.count, start.seconds)) }
            let values = try XCTUnwrap(pcm.buffer.int16ChannelData?[0])
            result.samples.append(contentsOf: UnsafeBufferPointer(start: values, count: Int(pcm.buffer.frameLength)))
            result.bufferCount += 1
        }
        XCTFail("Feed did not reach EOF within the bounded generated-fixture pull count")
        return result
    }
    static func tail(_ samples: [Int16], sourceFrames: Int, marker: Float) {
        XCTAssertGreaterThanOrEqual(samples.count, 64)
        guard samples.count >= 64 else { return }
        for (offset, actual) in samples.suffix(64).enumerated() {
            let index = sourceFrames - 64 + offset
            let expected = Double(sample(index, count: sourceFrames, marker: marker) * 32_768)
            XCTAssertEqual(Double(actual), expected, accuracy: 2, "Distinctive final sample \(offset) was lost, replaced or reordered")
        }
    }
    static func conservation(_ test: XCTestCase) throws {
        let root = try folder(test)
        for (frames, diskFormat) in [(16_037, AVAudioCommonFormat.pcmFormatFloat32),
                                     (500_900, .pcmFormatFloat32), (500_900, .pcmFormatInt16)] {
            let url = try wave(root, name: "tail-\(frames)-\(diskFormat.rawValue)", frames: frames, diskFormat: diskFormat)
            let original = try Data(contentsOf: url)
            let file = try AVAudioFile(forReading: url)
            XCTAssertEqual(file.length, AVAudioFramePosition(frames))
            XCTAssertEqual(file.processingFormat.commonFormat, .pcmFormatFloat32)
            XCTAssertEqual(file.fileFormat.commonFormat, diskFormat)
            try diagnoseFileReads(file, expected: frames)
            let feed = ChunkFeed(chunks: [chunk(url, frames: frames)], format: try format(.pcmFormatInt16))
            let output = try consume(feed)
            XCTAssertEqual(output.samples.count, frames, "Same-rate representation conversion must retain every PCM frame")
            tail(output.samples, sourceFrames: frames, marker: 0.5)
            XCTAssertEqual(output.anchors.count, 1)
            XCTAssertEqual(output.anchors.first?.frame, 0)
            XCTAssertEqual(output.anchors.first?.seconds ?? -1, 0, accuracy: 1 / rate)
            XCTAssertNil(feed.nextPCM()); XCTAssertNil(feed.nextPCM()); XCTAssertNil(feed.failure)
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
        try sameFormatPreservation(test)
    }
    static func sameFormatPreservation(_ test: XCTestCase) throws {
        let root = try folder(test); let frames = 16_037
        let url = try wave(root, name: "same-format", frames: frames)
        let original = try Data(contentsOf: url)
        let source = try AVAudioFile(forReading: url)
        let target = try format(.pcmFormatFloat32)
        XCTAssertEqual(source.processingFormat, target, "This control must exercise the no-converter path")
        let feed = ChunkFeed(chunks: [chunk(url, frames: frames)], format: target)
        var count = 0; var anchors = 0
        for _ in 0..<128 {
            guard let pcm = feed.nextPCM() else { break }
            XCTAssertGreaterThan(pcm.buffer.frameLength, 0)
            XCTAssertEqual(pcm.buffer.format, target)
            if let start = pcm.bufferStartTime {
                anchors += 1
                XCTAssertEqual(count, 0)
                XCTAssertEqual(start.seconds, 0, accuracy: 1 / rate)
            }
            let values = try XCTUnwrap(pcm.buffer.floatChannelData?[0])
            for index in 0..<Int(pcm.buffer.frameLength) {
                XCTAssertEqual(values[index], sample(count + index, count: frames, marker: 0.5))
            }
            count += Int(pcm.buffer.frameLength)
        }
        XCTAssertEqual(count, frames); XCTAssertEqual(anchors, 1)
        XCTAssertNil(feed.nextPCM()); XCTAssertNil(feed.failure)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
    static func diagnoseFileReads(_ file: AVAudioFile, expected: Int) throws {
        var total = 0
        var reads: [String] = []
        for _ in 0..<128 {
            if file.framePosition >= file.length { break }
            let before = file.framePosition
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                       frameCapacity: AVAudioFrameCount(rate)))
            try file.read(into: buffer)
            total += Int(buffer.frameLength)
            reads.append("\(before)->\(file.framePosition):\(buffer.frameLength)")
            if buffer.frameLength == 0 { break }
        }
        print("PCM diagnostic disk=\(file.fileFormat) processing=\(file.processingFormat) declared=\(expected) read=\(total) positions=\(reads)")
        XCTAssertEqual(total, expected, "Direct AVAudioFile reads must preserve source frames before explicit conversion")
    }
    static func timelines(_ test: XCTestCase) throws {
        for diskFormat in [AVAudioCommonFormat.pcmFormatFloat32, .pcmFormatInt16] {
            let root = try folder(test); let frames = [16_037, 16_123, 16_071]
            let markers: [Float] = [0.25, 0.5, -0.5]
            let urls = try frames.enumerated().map { try wave(root, name: "part\($0.offset)", frames: $0.element, marker: markers[$0.offset], diskFormat: diskFormat) }
            let originals = try urls.map { try Data(contentsOf: $0) }
            let chunks = urls.enumerated().map { chunk($0.element, index: $0.offset,
                                                       start: [3.0, 3.1, 10.0][$0.offset], frames: frames[$0.offset]) }
            let feed = ChunkFeed(chunks: chunks, format: try format(.pcmFormatInt16)); let output = try consume(feed)
            XCTAssertEqual(output.samples.count, frames.reduce(0, +))
            XCTAssertEqual(output.anchors.map(\.frame), [0, frames[0], frames[0] + frames[1]], "Next chunk cannot begin before the prior tail drains")
            XCTAssertEqual(output.anchors.count, 3)
            if output.anchors.count == 3 {
                XCTAssertEqual(output.anchors[0].seconds, 3, accuracy: 1 / rate)
                XCTAssertEqual(output.anchors[1].seconds, 3 + Double(frames[0]) / rate, accuracy: 1 / rate)
                XCTAssertEqual(output.anchors[2].seconds, 10, accuracy: 1 / rate)
            }
            var offset = 0
            for index in frames.indices {
                let end = offset + frames[index]
                if output.samples.count >= end { tail(Array(output.samples[offset..<end]), sourceFrames: frames[index], marker: markers[index]) }
                offset = end
            }
            XCTAssertNil(feed.failure)
            XCTAssertEqual(try urls.map { try Data(contentsOf: $0) }, originals)
        }
    }
    static func cancellation(_ test: XCTestCase) throws {
        for diskFormat in [AVAudioCommonFormat.pcmFormatFloat32, .pcmFormatInt16] {
            let root = try folder(test); let frames = 500_900
            let url = try wave(root, name: "cancel-tail", frames: frames, diskFormat: diskFormat); let original = try Data(contentsOf: url)
            let feed = ChunkFeed(chunks: [chunk(url, frames: frames), chunk(url, index: 1, start: 60, frames: frames)],
                                 format: try format(.pcmFormatInt16))
            var received = 0
            // Stop with observable final audio still undelivered; do not depend on buffer cadence.
            for _ in 0..<128 {
                if received >= frames - Int(rate) { break }
                let pcm = try XCTUnwrap(feed.nextPCM()); received += Int(pcm.buffer.frameLength)
            }
            XCTAssertGreaterThanOrEqual(received, frames - Int(rate))
            XCTAssertLessThan(received, frames, "This case must reach an observable undelivered-audio state")
            feed.stop(failing: nil)
            XCTAssertTrue(feed.isStopped); XCTAssertNil(feed.nextPCM()); XCTAssertNil(feed.nextPCM()); XCTAssertNil(feed.failure)
            XCTAssertEqual(try Data(contentsOf: url), original)
            let stopped = ChunkFeed(chunks: [chunk(url, frames: frames)], format: try format(.pcmFormatInt16))
            stopped.stop(failing: NSError(domain: "SyntheticCancellation", code: 7))
            stopped.stop(failing: NSError(domain: "SyntheticCancellation", code: 9))
            XCTAssertNil(stopped.nextPCM()); XCTAssertEqual((stopped.failure as NSError?)?.code, 7)
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
    }
    static func emptyAndErrors(_ test: XCTestCase) throws {
        let root = try folder(test); let target = try format(.pcmFormatInt16)
        let empty = ChunkFeed(chunks: [], format: target)
        XCTAssertNil(empty.nextPCM()); XCTAssertNil(empty.failure)
        let zeroURL = try wave(root, name: "empty", frames: 0); let zeroBytes = try Data(contentsOf: zeroURL)
        let zero = ChunkFeed(chunks: [chunk(zeroURL, frames: 0)], format: target)
        XCTAssertNil(zero.nextPCM()); XCTAssertNil(zero.nextPCM()); XCTAssertNil(zero.failure)
        XCTAssertEqual(try Data(contentsOf: zeroURL), zeroBytes)
        let valid = try wave(root, name: "later-valid", frames: 100)
        let invalid = root.appendingPathComponent("invalid.wav"); let bytes = Data("not an audio file".utf8)
        try bytes.write(to: invalid)
        for bad in [root.appendingPathComponent("missing.wav"), invalid] {
            let feed = ChunkFeed(chunks: [chunk(bad, frames: 100), chunk(valid, index: 1, frames: 100)], format: target)
            XCTAssertNil(feed.nextPCM()); XCTAssertTrue(feed.isStopped); XCTAssertNotNil(feed.failure)
            XCTAssertNil(feed.nextPCM(), "An unreadable chunk must not silently continue into later audio")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("missing.wav").path))
        XCTAssertEqual(try Data(contentsOf: invalid), bytes)
    }
}
