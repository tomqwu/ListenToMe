import Foundation
import AVFoundation
import CoreGraphics
import ScreenCaptureKit
import ListenToMeCore

/// Captures the local microphone (source `.you`) and system audio (source `.others`),
/// converting both to mono Float PCM and emitting `AudioChunk`s.
final class DualChannelCapture: NSObject, AudioCapturing, @unchecked Sendable {
    let chunks: AsyncStream<AudioChunk>
    private let continuation: AsyncStream<AudioChunk>.Continuation

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var stream: SCStream?          // guarded by `lock`
    private var stopped = false            // guarded by `lock`
    private var systemAudioTask: Task<Void, Never>?
    private let startTime = Date()
    /// Optional sink that accumulates the `.others` channel (resampled to 16 kHz) for speaker
    /// diarization. `nil` (the default) leaves existing callers/tests untouched.
    private let othersSink: SpeakerAudioBuffer?

    init(othersSink: SpeakerAudioBuffer? = nil) {
        self.othersSink = othersSink
        var cont: AsyncStream<AudioChunk>.Continuation!
        chunks = AsyncStream(bufferingPolicy: .bufferingNewest(64)) { cont = $0 }
        continuation = cont
        super.init()
    }

    func start() async throws {
        try startMic()                     // essential "You" channel — propagate if this fails
        // Start system audio OFF the start() path so a Screen Recording prompt (when not yet
        // granted) can't suspend here and stall mic transcription — the caller attaches the mic
        // pump as soon as start() returns. We no longer gate on CGPreflightScreenCaptureAccess():
        // it is cached for the process lifetime and returns a stale `false` even after the user
        // grants access. SCShareableContent reflects the real grant — it succeeds (no prompt) when
        // granted and prompts once when genuinely not granted; stable signing keeps the grant.
        systemAudioTask = Task { [weak self] in
            guard let self else { return }
            // stop() may have run before this task was even assigned (so its cancel couldn't reach
            // us); don't enter the prompt-bearing ScreenCaptureKit path if we're already stopped.
            if Task.isCancelled || self.lock.withLock({ self.stopped }) { return }
            do {
                try await self.startSystemAudio()   // "Others" channel — best-effort
            } catch {
                NSLog("ListenToMe: system audio capture unavailable (\(error.localizedDescription)); " +
                      "continuing with microphone only (grant Screen Recording, then relaunch).")
            }
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        systemAudioTask?.cancel()
        let toStop: SCStream? = lock.withLock {
            stopped = true
            let current = stream
            stream = nil
            return current
        }
        toStop?.stopCapture { _ in }
        continuation.finish()
    }

    // MARK: - Microphone (.you)

    private func startMic() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.emit(buffer: buffer, source: .you)
        }
        engine.prepare()
        try engine.start()
    }

    // MARK: - System audio (.others)

    private func startSystemAudio() async throws {
        if Task.isCancelled || lock.withLock({ stopped }) { return }
        let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                           onScreenWindowsOnly: true)
        guard let display = content.displays.first else { return }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 1

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .audio,
                                   sampleHandlerQueue: DispatchQueue(label: "system-audio"))
        try await stream.startCapture()
        // stop() may have run while we were awaiting the (possibly prompt-bearing) setup above;
        // if so, don't retain a live stream that would never be stopped.
        let keep: Bool = lock.withLock {
            if stopped { return false }
            self.stream = stream
            return true
        }
        if !keep { stream.stopCapture { _ in } }
    }

    // MARK: - Emit helpers

    private func emit(buffer: AVAudioPCMBuffer, source: SpeakerSource) {
        guard let mono = Self.convertToMonoFloat(buffer),
              let channel = mono.floatChannelData?[0] else { return }
        let count = Int(mono.frameLength)
        guard count > 0 else { return }
        let samples = Array(UnsafeBufferPointer(start: channel, count: count))
        let timestamp = Date().timeIntervalSince(startTime)
        // Feed the same mono samples to the diarization sink (it handles the 16 kHz resample). The
        // chunk's capture-time `timestamp` is passed through so the buffer can record its sample-0
        // offset for later alignment against the transcript's capture-time stamps.
        //
        // Skip the sink append once we're stopped: a quick (or locale) restart spins up a NEW capture
        // sharing the SAME buffer, while this OLD SCStream can still deliver queued `.others`
        // callbacks. Appending that stale, old-timeline audio would contaminate the new run's samples
        // and `startOffset`. The continuation.yield below is harmless (the consumer is detached), so
        // only the sink append is guarded. `stop()` sets `stopped = true` under the lock before any
        // new capture resets the buffer, so this is a reliable cutoff.
        if source == .others, !lock.withLock({ stopped }) {
            othersSink?.append(samples: samples, sampleRate: mono.format.sampleRate, timestamp: timestamp)
        }
        let chunk = AudioChunk(samples: samples,
                               sampleRate: mono.format.sampleRate,
                               source: source,
                               timestamp: timestamp)
        continuation.yield(chunk)
    }

    /// Downmixes/converts any PCM buffer to non-interleaved mono Float32 at the same sample rate.
    /// Returns the input unchanged when it is already in that format.
    private static func convertToMonoFloat(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let inFormat = input.format
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: inFormat.sampleRate,
                                            channels: 1,
                                            interleaved: false) else { return nil }
        if inFormat == outFormat { return input }
        guard input.frameLength > 0,
              let converter = AVAudioConverter(from: inFormat, to: outFormat),
              let output = AVAudioPCMBuffer(pcmFormat: outFormat,
                                            frameCapacity: input.frameLength) else { return nil }
        var consumed = false
        var convError: NSError?
        let status = converter.convert(to: output, error: &convError) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return input
        }
        if status == .error || convError != nil { return nil }
        return output
    }
}

extension DualChannelCapture: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .audio,
              let pcm = sampleBuffer.toMonoFloatBuffer() else { return }
        emit(buffer: pcm, source: .others)
    }
}

private extension CMSampleBuffer {
    /// Converts a CoreMedia audio sample buffer to a mono Float `AVAudioPCMBuffer`.
    func toMonoFloatBuffer() -> AVAudioPCMBuffer? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(self),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee
        else { return nil }
        var settings = asbd
        guard let format = AVAudioFormat(streamDescription: &settings) else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(self))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
        else { return nil }
        buffer.frameLength = frames
        CMSampleBufferCopyPCMDataIntoAudioBufferList(
            self, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList)
        // If not already mono Float32, return as-is; the recognizer adapts to buffer.format.
        return buffer
    }
}
