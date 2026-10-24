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
    /// Writes everything appended so far, closes the file and reports it; returns once that is done.
    func finish() async
    /// Stops writing without reporting: the audio is being deleted.
    func cancel()
}

/// Streams audio to an AAC `.m4a` at 16 kHz mono with bounded memory: chunks are converted and written on
/// one serial queue, and at most `maximumPending` chunks wait for it. The file is a fragmented MPEG-4
/// (`AVAssetWriter.movieFragmentInterval`), so if the app is killed mid-recording everything up to the
/// last fragment, a few seconds back, still plays. A write error, a full disk or a writer that falls
/// behind stops the file and reports once; the capture and its transcript go on.
final class SavedAudioFileWriter: SavedAudioWriting, @unchecked Sendable {
    /// About 20 seconds of 48 kHz microphone buffers.
    static let maximumPending = 512
    /// At most this much silence is inserted into one file for gaps in the capture times, in total.
    static let silenceCap: TimeInterval = 600
    /// A kill loses at most about this much audio.
    static let fragmentInterval = CMTime(seconds: 4, preferredTimescale: 600)

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
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var formatDescription: CMAudioFormatDescription?
    private var converter: AVAudioConverter?
    private var converterRate: Double = 0
    private var frames: Int64 = 0
    private var silence: TimeInterval = 0
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

    /// How long a saved file plays, or `nil` when it cannot be read (`SavedAudioLibrary.repairUnfinished`).
    static func playableDuration(of url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 else { return nil }
        return Double(file.length) / file.fileFormat.sampleRate
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

    func finish() async {
        let first: Bool = lock.withLock {
            defer { closed = true }
            return !closed
        }
        guard first else { return }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                close { [self] in
                    let reported = lock.withLock { failure }
                    onFinish(SavedAudioRunResult(duration: Double(frames) / SavedAudioPolicy.sampleRate,
                                                 firstTimestamp: firstTimestamp, failure: reported))
                    done.resume()
                }
            }
        }
    }

    func cancel() {
        lock.withLock { closed = true; stopped = true }
        queue.async { [self] in close {} }
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
        queue.async { [self] in close {} }
        onFailure(message)
    }

    // MARK: Queue only

    /// Finishes the file (what was written stays playable) and runs `then` once it is closed.
    private func close(then: @escaping @Sendable () -> Void) {
        guard let writer, let input, writer.status == .writing else {
            self.writer = nil; self.input = nil
            then()
            return
        }
        self.writer = nil; self.input = nil
        input.markAsFinished()
        writer.finishWriting { then() }
    }

    private func open() throws -> AVAssetWriterInput {
        if let input { return input }
        let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        writer.movieFragmentInterval = Self.fragmentInterval
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.fileSettings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw CocoaError(.fileWriteUnknown) }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        var formatDescription: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: format.streamDescription, layoutSize: 0, layout: nil,
                                       magicCookieSize: 0, magicCookie: nil, extensions: nil,
                                       formatDescriptionOut: &formatDescription)
        self.writer = writer
        self.input = input
        self.formatDescription = formatDescription
        return input
    }

    private func write(_ samples: [Float], rate: Double, timestamp: TimeInterval?) throws {
        let input = try open()
        if let timestamp {
            if let firstTimestamp {
                let gap = timestamp - firstTimestamp - Double(frames) / SavedAudioPolicy.sampleRate
                let allowed = min(gap, Self.silenceCap - silence)
                if gap > 0.25, allowed > 0 {
                    try writeSilence(seconds: allowed, to: input)
                    silence += allowed
                }
            } else {
                firstTimestamp = timestamp
            }
        }
        guard let converted = try convert(samples, rate: rate), !converted.isEmpty else { return }
        try appendSamples(converted, to: input)
    }

    private func writeSilence(seconds: TimeInterval, to input: AVAssetWriterInput) throws {
        var remaining = Int(seconds * SavedAudioPolicy.sampleRate)
        while remaining > 0 {
            let count = min(remaining, Int(SavedAudioPolicy.sampleRate))
            try appendSamples([Float](repeating: 0, count: count), to: input)
            remaining -= count
        }
    }

    /// Appends 16 kHz mono samples at the next position of the file's timeline.
    private func appendSamples(_ samples: [Float], to input: AVAssetWriterInput) throws {
        guard let writer, let formatDescription else { return }
        var waited = 0
        while !input.isReadyForMoreMediaData {
            if writer.status == .failed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
            guard waited < 2_000 else { throw SavedAudioWriterError.fellBehind }
            Thread.sleep(forTimeInterval: 0.001)
            waited += 1
        }
        let bytes = samples.count * MemoryLayout<Float>.size
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes,
                                                 blockAllocator: nil, customBlockSource: nil, offsetToData: 0,
                                                 dataLength: bytes, flags: 0, blockBufferOut: &block) == noErr,
              let block else { throw CocoaError(.fileWriteUnknown) }
        let copied = samples.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0,
                                          dataLength: bytes)
        }
        var sample: CMSampleBuffer?
        guard copied == noErr,
              CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                allocator: nil, dataBuffer: block, formatDescription: formatDescription, sampleCount: samples.count,
                presentationTimeStamp: CMTime(value: frames, timescale: CMTimeScale(SavedAudioPolicy.sampleRate)),
                packetDescriptions: nil, sampleBufferOut: &sample) == noErr,
              let sample else { throw CocoaError(.fileWriteUnknown) }
        guard input.append(sample) else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        frames += Int64(samples.count)
    }

    /// Mono Float at `rate` to 16 kHz. One converter per input rate keeps its filter state between chunks.
    private func convert(_ samples: [Float], rate: Double) throws -> [Float]? {
        if rate == SavedAudioPolicy.sampleRate { return samples }
        guard let source = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1,
                                         interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { values in
            if let base = values.baseAddress { channel.update(from: base, count: values.count) }
        }
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
            return buffer
        }
        if let error { throw error }
        guard let data = output.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: data, count: Int(output.frameLength)))
    }
}

enum SavedAudioWriterError: LocalizedError {
    case fellBehind
    var errorDescription: String? { "The device could not write audio fast enough." }
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
    /// Callers of `waitForWrites`, resumed once no writer is running.
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
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

    /// The conversation being written, if a writer is running.
    var recordingConversation: String? { lock.withLock { active.values.first?.conversation } }

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
                if let id = box.id { self.release(id) }
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

    /// The setting was turned off mid-recording: every running file stops now and keeps what it has.
    func finishAll() async {
        let running = lock.withLock { active.values.map(\.writer) }
        for writer in running { await writer.finish() }
    }

    /// Waits until every running file is closed, or `timeout` passes.
    func waitForWrites(timeout: Duration) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.idle() }
            group.addTask { try? await Task.sleep(for: timeout) }
            await group.next()
            group.cancelAll()
        }
    }

    private func idle() async {
        let key = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (waiter: CheckedContinuation<Void, Never>) in
                let resumeNow: Bool = lock.withLock {
                    if active.isEmpty || Task.isCancelled { return true }
                    waiters[key] = waiter
                    return false
                }
                if resumeNow { waiter.resume() }
            }
        } onCancel: {
            lock.withLock { waiters.removeValue(forKey: key) }?.resume()
        }
    }

    private func release(_ id: ObjectIdentifier) {
        let resumed: [CheckedContinuation<Void, Never>] = lock.withLock {
            active.removeValue(forKey: id)
            guard active.isEmpty else { return [] }
            defer { waiters = [:] }
            return Array(waiters.values)
        }
        resumed.forEach { $0.resume() }
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
        let cancelled: [(ObjectIdentifier, any SavedAudioWriting)] = lock.withLock {
            active.filter { matches($0.value.conversation) }.map { ($0.key, $0.value.writer) }
        }
        for (id, writer) in cancelled {
            writer.cancel()
            release(id)
        }
    }

    /// The writer's identity, known only after the writer that captures it was made.
    private final class WriterBox: @unchecked Sendable {
        var id: ObjectIdentifier?
    }
}
