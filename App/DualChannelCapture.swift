import Foundation
import AppKit
import AVFoundation
import CoreGraphics
import ScreenCaptureKit
import ListenToMeCore

/// Captures the local microphone (source `.you`) and system audio (source `.others`),
/// converting both to mono Float PCM and emitting `AudioChunk`s.
final class DualChannelCapture: NSObject, AudioCapturing, @unchecked Sendable {
    let statusUpdates: AsyncStream<CaptureStatus>
    private let statusContinuation: AsyncStream<CaptureStatus>.Continuation
    private var configurationObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    let chunks: AsyncStream<AudioChunk>
    private let continuation: AsyncStream<AudioChunk>.Continuation

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var stream: SCStream?          // guarded by `lock`
    private var stopped = false            // guarded by `lock`
    private var reportedDrops = Set<SpeakerSource>()   // guarded by `lock`
    /// One restart attempt per channel (re-armed by a successful restart), so a permanently dead
    /// input device can't spin us in a restart loop. Guarded by `lock`.
    private var recovery = CaptureRecovery.Policy()    // guarded by `lock`
    /// True once the system-audio stream has actually been running, so a post-wake restart only
    /// re-arms a channel that worked (and never re-prompts a user who declined Screen Recording).
    private var systemAudioWasActive = false           // guarded by `lock`
    private var systemAudioTask: Task<Void, Never>?
    private let startTime = Date()
    /// Optional sink that accumulates the `.others` channel (resampled to 16 kHz) for speaker
    /// diarization. `nil` (the default) leaves existing callers/tests untouched.
    private let othersSink: SpeakerAudioBuffer?
    private let microphoneSink: SpeakerAudioBuffer?
    private let microphoneGeneration: Int
    /// The sink's generation captured when this capture was built (right after its `reset()`). Passed
    /// to every `othersSink.append` so the buffer rejects this capture's appends once a later run has
    /// reset it. Unused (and irrelevant) when `othersSink` is nil.
    private let sinkGeneration: Int

    init(othersSink: SpeakerAudioBuffer? = nil, sinkGeneration: Int = 0,
         microphoneSink: SpeakerAudioBuffer? = nil, microphoneGeneration: Int = 0) {
        self.microphoneSink = microphoneSink
        self.microphoneGeneration = microphoneGeneration
        self.othersSink = othersSink
        self.sinkGeneration = sinkGeneration
        let statuses = AsyncStream<CaptureStatus>.makeStream()
        statusUpdates = statuses.stream; statusContinuation = statuses.continuation
        var cont: AsyncStream<AudioChunk>.Continuation!
        chunks = AsyncStream(bufferingPolicy: .bufferingNewest(64)) { cont = $0 }
        continuation = cont
        super.init()
    }

    func start() async throws {
        try startMic()
        statusContinuation.yield(CaptureStatus(source: .you, message: "active"))
        // An input-device change (AirPods connect, dock/undock, sleep/wake) stops AVAudioEngine and
        // invalidates the installed tap: recover in place instead of only telling the user, who
        // would otherwise record the rest of the meeting with no "You" channel (issue #107).
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
                self?.restartMicrophone()
            }
        // Sleep/wake doesn't always deliver a configuration change; re-arm whichever channel
        // actually died rather than disturbing healthy ones.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in
                guard let self, !self.lock.withLock({ self.stopped }) else { return }
                if !self.engine.isRunning { self.restartMicrophone() }
                let needsSystemAudio = self.lock.withLock { self.stream == nil && self.systemAudioWasActive }
                if needsSystemAudio { self.restartSystemAudio(reason: "woke from sleep") }
            }
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
                self.statusContinuation.yield(CaptureStatus(source: .others,
                    message: "unavailable — check Permissions, then stop and restart"))
                NSLog("ListenToMe: system audio capture unavailable (\(error.localizedDescription)); " +
                      "continuing with microphone only (grant Screen Recording, then relaunch).")
            }
        }
    }

    func stop() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        statusContinuation.finish()
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
        // A denied microphone does NOT make engine.start() throw on macOS — the input node just
        // delivers silence — so check authorization first and fail loudly instead of recording a
        // whole meeting with no "You" lines (issue #110). The UI pre-flights this too; this guard
        // covers any caller that skips it.
        switch CapturePreflight.decide(microphone: PermissionsModel.currentMicrophoneAuthorization()) {
        case .blocked(let message, _):
            statusContinuation.yield(CapturePreflight.noAccessStatus)
            throw NSError(domain: "ListenToMe.Capture", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: message])
        case .start, .requestAccess:
            break   // .requestAccess: starting the engine raises the one-time system prompt
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw NSError(domain: "ListenToMe.Capture", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No usable microphone. Connect an input and retry."])
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.emit(buffer: buffer, source: .you)
        }
        engine.prepare()
        try engine.start()
    }

    /// Removes the stale tap, re-reads the (possibly new) input format, re-installs the tap and
    /// restarts the engine. Yields "input changed — resumed" on success, and a degraded status the
    /// UI shows as an alert when it fails.
    private func restartMicrophone() {
        if lock.withLock({ stopped }) { return }
        guard lock.withLock({ recovery.shouldAttemptRestart(for: .you) }) else {
            statusContinuation.yield(CaptureRecovery.status(for: .microphoneInputChanged,
                                                            outcome: .notAttempted))
            return
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        do {
            try startMic()   // re-reads inputNode.outputFormat(forBus: 0) for the new device
            lock.withLock { recovery.restartSucceeded(for: .you) }
            statusContinuation.yield(CaptureRecovery.status(for: .microphoneInputChanged,
                                                            outcome: .resumed))
        } catch {
            statusContinuation.yield(CaptureRecovery.status(
                for: .microphoneInputChanged, outcome: .failed(reason: error.localizedDescription)))
        }
    }

    /// One-shot restart of the system-audio stream after ScreenCaptureKit stopped it (or after a
    /// wake). A failure leaves a visible "system audio stopped" status rather than silent loss.
    private func restartSystemAudio(reason: String) {
        if lock.withLock({ stopped }) { return }
        let event = CaptureRecovery.Event.systemAudioStopped(reason: reason)
        guard lock.withLock({ recovery.shouldAttemptRestart(for: .others) }) else {
            statusContinuation.yield(CaptureRecovery.status(for: event, outcome: .notAttempted))
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.startSystemAudio()
                // startSystemAudio returns without a stream when there is no display to capture.
                guard self.lock.withLock({ self.stream != nil }) else {
                    self.statusContinuation.yield(CaptureRecovery.status(
                        for: event, outcome: .failed(reason: "no display available")))
                    return
                }
                self.lock.withLock { self.recovery.restartSucceeded(for: .others) }
                self.statusContinuation.yield(CaptureRecovery.status(for: event, outcome: .resumed))
            } catch {
                self.statusContinuation.yield(CaptureRecovery.status(
                    for: event, outcome: .failed(reason: error.localizedDescription)))
            }
        }
    }

    // MARK: - System audio (.others)

    private func startSystemAudio() async throws {
        if Task.isCancelled || lock.withLock({ stopped }) { return }
        let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                           onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            statusContinuation.yield(CaptureStatus(source: .others, message: "no display available"))
            return
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 1

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio,
                                   sampleHandlerQueue: DispatchQueue(label: "system-audio"))
        try await stream.startCapture()
        statusContinuation.yield(CaptureStatus(source: .others, message: "active"))
        // stop() may have run while we were awaiting the (possibly prompt-bearing) setup above;
        // if so, don't retain a live stream that would never be stopped.
        let keep: Bool = lock.withLock {
            if stopped { return false }
            self.stream = stream
            self.systemAudioWasActive = true
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
        // and `startOffset`. The `stopped` check is a fast pre-filter; the buffer's generation guard
        // (via `sinkGeneration`) is the authoritative cutoff — it rejects an append atomically under
        // the buffer's lock even if this callback was mid-resample when the next run reset the buffer.
        // The continuation.yield below is harmless (the consumer is detached), so only the append is
        // guarded.
        if !lock.withLock({ stopped }) {
            let sink = source == .others ? othersSink : microphoneSink
            let generation = source == .others ? sinkGeneration : microphoneGeneration
            sink?.append(samples: samples, sampleRate: mono.format.sampleRate,
                         timestamp: timestamp, generation: generation)
        }
        let chunk = AudioChunk(samples: samples,
                               sampleRate: mono.format.sampleRate,
                               source: source,
                               timestamp: timestamp)
        if case .dropped(let lost) = continuation.yield(chunk),
           lock.withLock({ reportedDrops.insert(lost.source).inserted }) {
            statusContinuation.yield(CaptureStatus(source: lost.source,
                message: "audio dropped during overload/model setup — stop and restart"))
        }
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

extension DualChannelCapture: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // Drop the dead stream before restarting so stop() can't chase a stale handle, then make
        // one recovery attempt; a failure surfaces as a degraded status (issue #107).
        lock.withLock { if self.stream === stream { self.stream = nil } }
        restartSystemAudio(reason: error.localizedDescription)
    }
}
