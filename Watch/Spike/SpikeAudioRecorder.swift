import AVFoundation
import Foundation

/// SPIKE ONLY: issue #181, plan Task 15. Lives on `spike/181-watch-audio` and is never merged.
///
/// Records the watch microphone exactly as Task 15 Step 1 says: a `.record` session, an
/// `AVAudioEngine` input tap, and `AVAudioFile(forWriting:settings:)` with AAC, 16 kHz, mono,
/// 32 kbps, rotating to a new file every 300 s of audio. The tap's hardware format is converted to
/// 16 kHz mono Float32 because `AVAudioFile.write(from:)` needs the file's processing format.
final class SpikeAudioRecorder: @unchecked Sendable {
    struct Chunk: Sendable {
        let url: URL
        let index: Int
        let seconds: Double
        let bytes: Int64
        /// Read back right after `setAttributes` on the freshly created file.
        let protectionAtCreate: String
        /// Read back after `AVAudioFile.close()` finalized the file (the U4 answer).
        let protectionAfterClose: String
    }

    static let chunkSeconds: Double = 300
    static let sampleRate: Double = 16_000
    static let requestedProtection = FileProtectionType.completeUntilFirstUserAuthentication

    /// Task 15 Step 1 settings, verbatim.
    static var fileSettings: [String: Any] {
        [AVFormatIDKey: kAudioFormatMPEG4AAC,
         AVSampleRateKey: 16_000,
         AVNumberOfChannelsKey: 1,
         AVEncoderBitRateKey: 32_000]
    }

    /// Called on the tap thread or the caller's thread; hop to the main actor before touching UI.
    var onChunkFinalized: (@Sendable (Chunk) -> Void)?
    var onEvent: (@Sendable (String) -> Void)?

    let directory: URL
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                          channels: 1, interleaved: false)!
    private var converter: AVAudioConverter?
    private var file: AVAudioFile?
    private var fileURL: URL?
    private var protectionAtCreate = "?"
    private var chunkIndex = 0
    private var framesInChunk: AVAudioFramePosition = 0
    private var sessionStamp = ""
    private var observers: [NSObjectProtocol] = []

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = documents.appendingPathComponent("SpikeChunks", isDirectory: true)
    }

    struct SpikeError: LocalizedError {
        let errorDescription: String?
    }

    func start() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)

        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
            throw SpikeError(errorDescription: "Input format is empty: \(inFormat)")
        }
        guard let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw SpikeError(errorDescription: "No converter from \(inFormat) to 16 kHz mono")
        }
        onEvent?("input format \(Int(inFormat.sampleRate)) Hz, \(inFormat.channelCount) ch")

        lock.lock()
        self.converter = converter
        chunkIndex = 0
        sessionStamp = Self.stamp(Date())
        let opened = Result { try openNextChunkLocked() }
        lock.unlock()
        try opened.get()

        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        observeInterruptions()
        engine.prepare()
        try engine.start()
    }

    /// Removes the tap, stops the engine and finalizes the open chunk.
    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        lock.lock()
        let chunk = finalizeLocked()
        converter = nil
        lock.unlock()
        if let chunk { onChunkFinalized?(chunk) }
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    // MARK: Tap

    private func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        var finalized: Chunk?
        var failure: String?
        defer {
            lock.unlock()
            if let finalized { onChunkFinalized?(finalized) }
            if let failure { onEvent?(failure) }
        }
        guard let converter, let file else { return }
        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error else {
            failure = "convert error: \(error?.localizedDescription ?? "unknown")"
            return
        }
        guard out.frameLength > 0 else { return }
        do {
            try file.write(from: out)
        } catch {
            failure = "write error: \(error.localizedDescription)"
            return
        }
        framesInChunk += AVAudioFramePosition(out.frameLength)
        if Double(framesInChunk) >= Self.chunkSeconds * Self.sampleRate {
            finalized = finalizeLocked()
            do { try openNextChunkLocked() } catch { failure = "rotate error: \(error.localizedDescription)" }
        }
    }

    // MARK: Files (call with the lock held)

    private func openNextChunkLocked() throws {
        chunkIndex += 1
        let name = String(format: "chunk-%@-%03d.m4a", sessionStamp, chunkIndex)
        let url = directory.appendingPathComponent(name)
        let newFile = try AVAudioFile(forWriting: url, settings: Self.fileSettings,
                                      commonFormat: .pcmFormatFloat32, interleaved: false)
        do {
            try FileManager.default.setAttributes([.protectionKey: Self.requestedProtection],
                                                  ofItemAtPath: url.path)
            protectionAtCreate = Self.protection(of: url)
        } catch {
            protectionAtCreate = "set failed: \(error.localizedDescription)"
        }
        file = newFile
        fileURL = url
        framesInChunk = 0
    }

    private func finalizeLocked() -> Chunk? {
        guard let file, let fileURL else { return nil }
        file.close()
        self.file = nil
        self.fileURL = nil
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? NSNumber
        return Chunk(url: fileURL, index: chunkIndex, seconds: Double(framesInChunk) / Self.sampleRate,
                     bytes: size?.int64Value ?? -1, protectionAtCreate: protectionAtCreate,
                     protectionAfterClose: Self.protection(of: fileURL))
    }

    // MARK: Interruptions (F5: recording cannot resume from the background; the spike only logs them)

    private func observeInterruptions() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                                            queue: nil) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let began = raw == AVAudioSession.InterruptionType.began.rawValue
            self?.onEvent?(began ? "INTERRUPTION began" : "INTERRUPTION ended")
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                            queue: nil) { [weak self] _ in
            self?.onEvent?("ENGINE configuration change, running: \(self?.engine.isRunning ?? false)")
        })
    }

    // MARK: Helpers

    static func protection(of url: URL) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return "unreadable"
        }
        guard let value = attributes[.protectionKey] as? FileProtectionType else { return "none" }
        return short(value)
    }

    static func short(_ value: FileProtectionType) -> String {
        value.rawValue.replacingOccurrences(of: "NSFileProtection", with: "")
    }

    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
