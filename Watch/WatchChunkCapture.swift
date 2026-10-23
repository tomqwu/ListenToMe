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

    /// Written when a chunk is opened, so a chunk finished but never handed over (the app was killed)
    /// can still be sent with its place on the timeline; see `WatchOutbox`.
    func pendingMetadataURL(_ index: Int) -> URL { folder.appendingPathComponent("\(index).json") }
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
    /// finished by rotation reaches `onChunk` on the main actor, closed. A write failure ends capture,
    /// keeps what was written, and reaches `onFailure` once. An engine change reaches `onAudioEvent`.
    func start(_ run: WatchCaptureRun, onChunk: @escaping @MainActor @Sendable (WatchFinishedChunk) -> Void,
               onFailure: @escaping @MainActor @Sendable (String) -> Void,
               onAudioEvent: @escaping @MainActor @Sendable (WatchAudioEvent) -> Void) throws
    /// Whether audio is still being captured; the recorder checks it with the limits.
    var isRunning: Bool { get }
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
/// the tap block, which runs on the engine's own (non-realtime) thread, converts and writes under it,
/// so a rotation closes one file and opens the next between two buffers. One converter serves the
/// whole run, so the resampler's history carries across a rotation, and the last chunk gets its tail
/// with an end-of-stream flush.
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
    private var target: AVAudioFormat?
    private var index = 0
    private var chunkOffset: TimeInterval = 0
    private var chunkFrames: AVAudioFramePosition = 0
    private var lastFinished: Int?
    private var onChunk: (@MainActor @Sendable (WatchFinishedChunk) -> Void)?
    private var onFailure: (@MainActor @Sendable (String) -> Void)?
    private var configurationObserver: (any NSObjectProtocol)?

    var isRunning: Bool { engine.isRunning }

    func start(_ run: WatchCaptureRun, onChunk: @escaping @MainActor @Sendable (WatchFinishedChunk) -> Void,
               onFailure: @escaping @MainActor @Sendable (String) -> Void,
               onAudioEvent: @escaping @MainActor @Sendable (WatchAudioEvent) -> Void) throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw WatchCaptureError.noMicrophone }
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1,
                                         interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: target) else {
            throw WatchCaptureError.unsupportedFormat
        }
        try lock.withLock {
            self.run = run
            self.onChunk = onChunk
            self.onFailure = onFailure
            self.target = target
            self.converter = converter
            index = run.firstIndex
            chunkOffset = run.startOffset
            lastFinished = nil
            try openChunk()
        }
        installTap(on: input, format: inputFormat)
        // The engine stops itself when the hardware configuration changes under it.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            let running = self.engine.isRunning
            Task { @MainActor in onAudioEvent(.engineConfigurationChanged(engineRunning: running)) }
        }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            removeObserver()
            _ = lock.withLock { finish() }
            throw error
        }
    }

    func stop() -> WatchCaptureEnding {
        removeObserver()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        return lock.withLock { finish() }
    }

    private func removeObserver() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
    }

    private func installTap(on input: AVAudioInputNode, format: AVAudioFormat) {
        input.installTap(onBus: 0, bufferSize: 4_096, format: format) { [weak self] buffer, _ in
            self?.write(buffer)
        }
    }

    private func write(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            guard run != nil, file != nil, let converter, let target else { return }
            do {
                let converted = try convert(buffer, with: converter, to: target)
                try append(converted)
                if WatchCapturePolicy.shouldRotate(chunkElapsed: Double(chunkFrames) / Self.sampleRate) {
                    if let chunk = closeChunk(isLast: false) { deliver(chunk) }
                    try openChunk()
                }
            } catch {
                // Keep what was written, closed; stop writing. The recorder ends the recording.
                if let chunk = closeChunk(isLast: false) { deliver(chunk) }
                self.converter = nil
                let reason = error.localizedDescription
                if let onFailure { Task { @MainActor in onFailure(reason) } }
            }
        }
    }

    // MARK: Under the lock

    private func append(_ buffer: AVAudioPCMBuffer) throws {
        guard let file, buffer.frameLength > 0 else { return }
        try file.write(from: buffer)
        chunkFrames += AVAudioFramePosition(buffer.frameLength)
    }

    private func openChunk() throws {
        guard let run, let target else { return }
        let file = try AVAudioFile(forWriting: run.url(index), settings: Self.fileSettings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        guard file.processingFormat == target else { throw WatchCaptureError.unsupportedFormat }
        self.file = file
        chunkFrames = 0
        // Its duration is a placeholder until the chunk is closed; only its place on the timeline is used.
        let pending = WatchChunkMetadata(recordingID: run.recordingID, index: index, startOffset: chunkOffset,
                                         duration: WatchCapturePolicy.chunkDuration, isLast: false,
                                         startedAt: run.startedAt, watchBuild: run.watchBuild)
        try? JSONEncoder().encode(pending).write(to: run.pendingMetadataURL(index), options: .atomic)
    }

    /// Closes the open chunk explicitly, so the file is complete before anything reads or sends it.
    /// An empty chunk is deleted.
    private func closeChunk(isLast: Bool) -> WatchFinishedChunk? {
        guard let run, let file else { return nil }
        file.close()
        self.file = nil
        let url = run.url(index)
        let duration = Double(chunkFrames) / Self.sampleRate
        guard chunkFrames > 0 else {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: run.pendingMetadataURL(index))
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
        flushConverter()
        let last = closeChunk(isLast: true)
        let ending = WatchCaptureEnding(last: last, lastIndex: lastFinished)
        run = nil
        converter = nil
        target = nil
        onChunk = nil
        onFailure = nil
        return ending
    }

    /// Writes the resampler's last samples into the final chunk.
    private func flushConverter() {
        guard let converter, let target, file != nil else { return }
        for _ in 0..<4 {
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 4_096) else { return }
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
                inputStatus.pointee = .endOfStream
                return nil
            }
            guard status != .error, output.frameLength > 0 else { return }
            try? append(output)
            if status == .endOfStream { return }
        }
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
        // at a buffer boundary or a rotation.
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
