import AVFoundation
import Foundation
import ListenToMeCore

/// Receives a copy of captured audio for Save audio recordings (issue #55). `append` is called from the
/// capture path and must return at once; writing happens elsewhere. Nothing is written after `finish`
/// or `cancel`.
protocol SavedAudioWriting: AnyObject, Sendable {
    /// Mono Float samples at `sampleRate`. `timestamp` is the capture time of the chunk when the capture
    /// stamps its audio (the Mac); a gap in those times is filled with silence so the file stays on the
    /// capture's timeline. `nil` means the chunks are contiguous (iPhone: exactly what the transcriber heard).
    func append(samples: [Float], sampleRate: Double, timestamp: TimeInterval?)
    /// Closes the file after everything appended so far is written, then reports the result.
    func finish()
    /// Stops writing without reporting: the audio is being deleted.
    func cancel()
}

/// Streams audio to an AAC `.m4a` at 16 kHz mono with bounded memory: chunks are converted and written on
/// one serial queue, and at most `maximumPending` chunks wait for it. A write error, a full disk or a
/// writer that falls behind stops the file and reports once; the capture and its transcript go on.
final class SavedAudioFileWriter: SavedAudioWriting, @unchecked Sendable {
    /// About 20 seconds of 48 kHz microphone buffers.
    static let maximumPending = 512
    private static let silenceCap: TimeInterval = 600

    private let url: URL
    private let onFailure: @Sendable (String) -> Void
    private let onFinish: @Sendable (SavedAudioRunResult) -> Void
    private let queue = DispatchQueue(label: "com.tomwu.ListenToMe.saved-audio", qos: .utility)
    private let lock = NSLock()
    private var pending = 0           // guarded by `lock`
    private var closed = false        // guarded by `lock`
    private var stopped = false       // guarded by `lock`: failed or cancelled, so writes are skipped
    private var failure: String?      // guarded by `lock`

    // Used only on `queue`.
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var converterRate: Double = 0
    private var frames: AVAudioFramePosition = 0
    private var firstTimestamp: TimeInterval?
    private let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: SavedAudioPolicy.sampleRate,
                                       channels: 1, interleaved: false)!

    init(url: URL, onFailure: @escaping @Sendable (String) -> Void,
         onFinish: @escaping @Sendable (SavedAudioRunResult) -> Void) {
        self.url = url
        self.onFailure = onFailure
        self.onFinish = onFinish
    }

    static var fileSettings: [String: Any] {
        [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: SavedAudioPolicy.sampleRate,
         AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: SavedAudioPolicy.bitRate]
    }

    /// Free space on the volume that holds `url`, for disk-full messages and the start check.
    static func availableBytes(near url: URL) -> Int64? {
        var folder = url
        while !FileManager.default.fileExists(atPath: folder.path), folder.pathComponents.count > 1 {
            folder.deleteLastPathComponent()
        }
        let values = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    func append(samples: [Float], sampleRate: Double, timestamp: TimeInterval?) {
        guard !samples.isEmpty, sampleRate > 0 else { return }
        let accepted: Bool = lock.withLock {
            guard !closed, !stopped else { return false }
            guard pending < Self.maximumPending else { return false }
            pending += 1
            return true
        }
        guard accepted else {
            if lock.withLock({ !closed && !stopped }) { fail(message: SavedAudioPolicy.fellBehindMessage) }
            return
        }
        queue.async { [self] in
            defer { lock.withLock { pending -= 1 } }
            guard !lock.withLock({ stopped }) else { return }
            do { try write(samples, rate: sampleRate, timestamp: timestamp) } catch {
                fail(message: SavedAudioPolicy.failureMessage(error, availableBytes: Self.availableBytes(near: url)))
            }
        }
    }

    func finish() {
        guard lock.withLock({ () -> Bool in
            defer { closed = true }
            return !closed
        }) else { return }
        queue.async { [self] in
            file?.close()
            file = nil
            let reported = lock.withLock { failure }
            onFinish(SavedAudioRunResult(duration: Double(frames) / SavedAudioPolicy.sampleRate,
                                         firstTimestamp: firstTimestamp, failure: reported))
        }
    }

    func cancel() {
        lock.withLock { closed = true; stopped = true }
        queue.async { [self] in
            file?.close()
            file = nil
        }
    }

    /// Stops writing once and says why. The file keeps what was written before.
    private func fail(message: String) {
        let first: Bool = lock.withLock {
            guard !stopped else { return false }
            stopped = true
            failure = message
            return true
        }
        guard first else { return }
        queue.async { [self] in
            file?.close()
            file = nil
        }
        onFailure(message)
    }

    // MARK: Queue only

    private func write(_ samples: [Float], rate: Double, timestamp: TimeInterval?) throws {
        if file == nil {
            file = try AVAudioFile(forWriting: url, settings: Self.fileSettings, commonFormat: .pcmFormatFloat32,
                                   interleaved: false)
        }
        guard let file else { return }
        if let timestamp {
            if let firstTimestamp {
                let gap = timestamp - firstTimestamp - Double(frames) / SavedAudioPolicy.sampleRate
                if gap > 0.25 { try writeSilence(seconds: min(gap, Self.silenceCap), to: file) }
            } else {
                firstTimestamp = timestamp
            }
        }
        guard let buffer = try convert(samples, rate: rate), buffer.frameLength > 0 else { return }
        try file.write(from: buffer)
        frames += AVAudioFramePosition(buffer.frameLength)
    }

    private func writeSilence(seconds: TimeInterval, to file: AVAudioFile) throws {
        var remaining = AVAudioFrameCount(seconds * SavedAudioPolicy.sampleRate)
        while remaining > 0 {
            let count = min(remaining, AVAudioFrameCount(SavedAudioPolicy.sampleRate))
            guard let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else { return }
            silence.frameLength = count   // zero-filled
            try file.write(from: silence)
            frames += AVAudioFramePosition(count)
            remaining -= count
        }
    }

    /// Mono Float at `rate` to 16 kHz. One converter per input rate keeps its filter state between chunks.
    private func convert(_ samples: [Float], rate: Double) throws -> AVAudioPCMBuffer? {
        guard let source = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1,
                                         interleaved: false),
              let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = input.floatChannelData?[0] else { return nil }
        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { values in
            if let base = values.baseAddress { channel.update(from: base, count: values.count) }
        }
        if rate == SavedAudioPolicy.sampleRate { return input }
        if converter == nil || converterRate != rate {
            converter = AVAudioConverter(from: source, to: format)
            converterRate = rate
        }
        guard let converter else { return nil }
        let capacity = AVAudioFrameCount(Double(samples.count) * SavedAudioPolicy.sampleRate / rate) + 1_024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return input
        }
        if let error { throw error }
        return output
    }
}

/// Starts the writers of one recording run and keeps the library's list of runs in step with them. Used
/// from the capture path, so it is safe on any thread. `makeWriter` is replaced in tests.
final class SavedAudioRecorder: @unchecked Sendable {
    typealias WriterFactory = @Sendable (URL, @escaping @Sendable (String) -> Void,
                                         @escaping @Sendable (SavedAudioRunResult) -> Void) -> any SavedAudioWriting

    let library: SavedAudioLibrary
    private let makeWriter: WriterFactory
    private let availableBytes: @Sendable () -> Int64?
    private let lock = NSLock()
    /// Writers still running, by conversation, so deleting that conversation stops them first.
    private var active: [ObjectIdentifier: (conversation: String, writer: any SavedAudioWriting)] = [:]
    /// The latest run started, for `anchor` (the Mac knows the first line only after start returns).
    private var latest: (conversation: String, index: Int)?
    /// Problems to show; called on any thread.
    var onProblem: @Sendable (String) -> Void = { _ in }
    /// A file finished or was deleted; called on any thread.
    var onChange: @Sendable () -> Void = {}

    init(library: SavedAudioLibrary, availableBytes: (@Sendable () -> Int64?)? = nil,
         makeWriter: @escaping WriterFactory = { url, failure, finish in
             SavedAudioFileWriter(url: url, onFailure: failure, onFinish: finish)
         }) {
        self.library = library
        self.makeWriter = makeWriter
        let root = library.root
        self.availableBytes = availableBytes ?? { SavedAudioFileWriter.availableBytes(near: root) }
    }

    /// One writer per source, or none when storage is low or the folder cannot be prepared; the reason
    /// is reported and the recording goes on without saving audio.
    func beginRun(conversationID: String, sources: [SpeakerSource], timelineOffset: TimeInterval,
                  timesMatchAudio: Bool, now: Date = Date()) -> [SpeakerSource: any SavedAudioWriting] {
        forgetLatestRun()
        if let reason = SavedAudioPolicy.startBlockedReason(availableBytes: availableBytes()) {
            onProblem(reason)
            return [:]
        }
        let runs: [SavedAudioRun]
        do {
            runs = try library.beginRun(conversationID: conversationID, sources: sources, startedAt: now,
                                        timelineOffset: timelineOffset, timesMatchAudio: timesMatchAudio)
        } catch {
            onProblem(SavedAudioPolicy.failureMessage(error, availableBytes: availableBytes()))
            return [:]
        }
        var writers: [SpeakerSource: any SavedAudioWriting] = [:]
        for run in runs {
            guard let url = library.url(for: run, conversationID: conversationID) else { continue }
            let box = WriterBox()
            let writer = makeWriter(url, { [weak self] in self?.onProblem($0) }, { [weak self] result in
                guard let self else { return }
                self.library.finishRun(conversationID: conversationID, fileName: run.fileName, result: result)
                if let id = box.id { self.lock.withLock { _ = self.active.removeValue(forKey: id) } }
                self.onChange()
            })
            box.id = ObjectIdentifier(writer)
            lock.withLock { active[ObjectIdentifier(writer)] = (conversationID, writer) }
            writers[run.source] = writer
        }
        if let index = runs.first?.index { lock.withLock { latest = (conversationID, index) } }
        return writers
    }

    /// A capture that saves nothing started, so a later `anchorLatestRun` must not move an older run.
    func forgetLatestRun() { lock.withLock { latest = nil } }

    /// Records the first transcript line of the latest run (the Mac).
    func anchorLatestRun(firstSegment: Int) {
        guard let latest = lock.withLock({ latest }) else { return }
        library.anchor(conversationID: latest.conversation, index: latest.index, firstSegment: firstSegment)
    }

    /// Stops any writer of the conversation, then deletes its audio.
    func delete(conversationID: String) throws {
        cancelWriters { $0 == conversationID }
        try library.delete(conversationID: conversationID)
        onChange()
    }

    func deleteAll() throws {
        cancelWriters { _ in true }
        try library.deleteAll()
        onChange()
    }

    private func cancelWriters(where matches: (String) -> Bool) {
        let cancelled: [any SavedAudioWriting] = lock.withLock {
            let matching = active.filter { matches($0.value.conversation) }
            for key in matching.keys { active.removeValue(forKey: key) }
            return matching.values.map(\.writer)
        }
        cancelled.forEach { $0.cancel() }
    }

    /// The writer's identity, known only after the writer that captures it was made.
    private final class WriterBox: @unchecked Sendable {
        var id: ObjectIdentifier?
    }
}
