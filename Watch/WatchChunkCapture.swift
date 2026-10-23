import AVFoundation
import Foundation

/// One run of a watch recording: from Start (or Continue) to the next stop (issue #181).
struct WatchCaptureRun: Sendable {
    let recordingID: UUID
    let startedAt: Date
    /// The index of the run's first chunk; a Continue run picks up after the previous run's last.
    let firstIndex: Int
    /// Seconds from the recording's start to the run's first sample: wall-clock time for a Continue.
    let startOffset: TimeInterval
    /// `Application Support/Recording/<recordingID>/`, where chunks are written before they are final.
    let folder: URL
    let watchBuild: String

    func url(_ index: Int) -> URL { folder.appendingPathComponent("\(index).m4a") }
}

/// A chunk file that is complete and ready to send.
struct WatchFinishedChunk: Sendable {
    let url: URL
    let metadata: WatchChunkMetadata
}

/// What a run left when it stopped.
struct WatchCaptureEnding: Sendable {
    /// The run's final chunk, marked `isLast`, or `nil` when it held no audio (or writing had failed).
    let last: WatchFinishedChunk?
    /// The index of the run's last finished chunk, `last` included; `nil` when the run finished none.
    let lastIndex: Int?
}

/// Captures the microphone into consecutive chunk files, one run at a time.
///
/// The go path of the Task 15 device spike (still pending on `spike/181-watch-audio`) is
/// `WatchEngineCapture`: an `AVAudioEngine` input tap written into `AVAudioFile` AAC with no gap at
/// a rotation. The no-go fallback is an `AVAudioRecorder` with the same settings that accepts a short
/// gap at each rotation; it would be a second type conforming to this protocol, and nothing else in
/// the recorder changes.
protocol WatchChunkCapturing: AnyObject {
    /// Starts capturing. Called on the main actor with the audio session already active. A chunk
    /// finished by rotation reaches `onChunk` on the main actor. A write failure ends capture, keeps
    /// what was written, and reaches `onFailure` once.
    func start(_ run: WatchCaptureRun, onChunk: @escaping @MainActor @Sendable (WatchFinishedChunk) -> Void,
               onFailure: @escaping @MainActor @Sendable (String) -> Void) throws
    /// Stops capturing and finishes the run's last chunk. Called on the main actor.
    func stop() -> WatchCaptureEnding
}

enum WatchCaptureError: LocalizedError {
    case noMicrophone
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .noMicrophone: "The Apple Watch microphone is not available."
        case .unsupportedFormat: "The Apple Watch microphone audio cannot be converted for recording."
        }
    }
}

/// The engine-tap capture: converts the input to 16 kHz mono and writes AAC-LC at about 32 kbps
/// (`WatchCapturePolicy.chunkDuration` per file). Every piece of mutable state is guarded by `lock`;
/// the tap block, which runs off the main thread, converts and writes under it, so a rotation closes
/// one file and opens the next between two buffers.
final class WatchEngineCapture: WatchChunkCapturing, @unchecked Sendable {
    static let sampleRate: Double = 16_000
    /// AAC-LC, mono, 16 kHz, about 32 kbps: about 14 MB an hour.
    static var fileSettings: [String: Any] {
        [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
         AVEncoderBitRateKey: 32_000]
    }

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var run: WatchCaptureRun?
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var index = 0
    private var chunkOffset: TimeInterval = 0
    private var chunkFrames: AVAudioFramePosition = 0
    private var lastFinished: Int?
    private var onChunk: (@MainActor @Sendable (WatchFinishedChunk) -> Void)?
    private var onFailure: (@MainActor @Sendable (String) -> Void)?

    func start(_ run: WatchCaptureRun, onChunk: @escaping @MainActor @Sendable (WatchFinishedChunk) -> Void,
               onFailure: @escaping @MainActor @Sendable (String) -> Void) throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw WatchCaptureError.noMicrophone }
        try lock.withLock {
            self.run = run
            self.onChunk = onChunk
            self.onFailure = onFailure
            index = run.firstIndex
            chunkOffset = run.startOffset
            lastFinished = nil
            try openChunk(inputFormat: inputFormat)
        }
        installTap(on: input, format: inputFormat)
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            _ = lock.withLock { finish() }
            throw error
        }
    }

    func stop() -> WatchCaptureEnding {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        return lock.withLock { finish() }
    }

    /// Not main-actor isolated: the tap block runs on the engine's own thread.
    private func installTap(on input: AVAudioInputNode, format: AVAudioFormat) {
        input.installTap(onBus: 0, bufferSize: 4_096, format: format) { [weak self] buffer, _ in
            self?.write(buffer)
        }
    }

    private func write(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            guard run != nil, let file, let converter else { return }
            do {
                let converted = try convert(buffer, with: converter, to: file.processingFormat)
                guard converted.frameLength > 0 else { return }
                try file.write(from: converted)
                chunkFrames += AVAudioFramePosition(converted.frameLength)
                if WatchCapturePolicy.shouldRotate(chunkElapsed: Double(chunkFrames) / Self.sampleRate) {
                    let inputFormat = converter.inputFormat
                    if let chunk = closeChunk(isLast: false) { deliver(chunk) }
                    try openChunk(inputFormat: inputFormat)
                }
            } catch {
                // Keep what was written; stop writing. The recorder ends the recording with the reason.
                if let chunk = closeChunk(isLast: false) { deliver(chunk) }
                self.file = nil
                self.converter = nil
                let reason = error.localizedDescription
                if let onFailure { Task { @MainActor in onFailure(reason) } }
            }
        }
    }

    // MARK: Under the lock

    private func openChunk(inputFormat: AVAudioFormat) throws {
        guard let run else { return }
        let file = try AVAudioFile(forWriting: run.url(index), settings: Self.fileSettings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let converter = AVAudioConverter(from: inputFormat, to: file.processingFormat) else {
            throw WatchCaptureError.unsupportedFormat
        }
        self.file = file
        self.converter = converter
        chunkFrames = 0
    }

    /// Closes the open chunk (dropping the `AVAudioFile` finishes the file). An empty chunk is deleted.
    private func closeChunk(isLast: Bool) -> WatchFinishedChunk? {
        guard let run, file != nil else { return nil }
        file = nil
        let url = run.url(index)
        let duration = Double(chunkFrames) / Self.sampleRate
        guard chunkFrames > 0 else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        let metadata = WatchChunkMetadata(recordingID: run.recordingID, index: index, startOffset: chunkOffset,
                                          duration: duration, isLast: isLast, startedAt: run.startedAt,
                                          watchBuild: run.watchBuild)
        lastFinished = index
        index += 1
        chunkOffset += duration
        chunkFrames = 0
        return WatchFinishedChunk(url: url, metadata: metadata)
    }

    private func finish() -> WatchCaptureEnding {
        let last = closeChunk(isLast: true)
        let ending = WatchCaptureEnding(last: last, lastIndex: lastFinished)
        run = nil
        converter = nil
        onChunk = nil
        onFailure = nil
        return ending
    }

    private func deliver(_ chunk: WatchFinishedChunk) {
        guard let onChunk else { return }
        Task { @MainActor in onChunk(chunk) }
    }

    private func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter,
                         to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw WatchCaptureError.unsupportedFormat
        }
        var supplied = false
        var conversionError: NSError?
        // `.noDataNow` keeps the sample-rate converter's history between buffers, so there is no click
        // at a buffer boundary.
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        if status == .error { throw conversionError ?? WatchCaptureError.unsupportedFormat }
        return output
    }
}
