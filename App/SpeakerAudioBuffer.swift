import Foundation
import AVFoundation

/// Thread-safe accumulator for the `.others` (system-audio) channel, resampled to 16 kHz mono Float
/// — the format FluidAudio's Pyannote diarizer expects. `append` is called from the audio callback
/// thread; `snapshot`/`reset` from the main actor. Accumulation is capped (~2 h @16 kHz) so a long
/// session can never grow unbounded; once full it stops appending and flags `didTruncate`.
final class SpeakerAudioBuffer: @unchecked Sendable {
    /// Target rate for the diarizer (16 kHz mono).
    private static let targetSampleRate: Double = 16_000
    /// ~2 hours of 16 kHz mono audio; appends stop once the buffer reaches this size.
    private static let maxSamples = 115_200_000
    /// Storage block size: 10 s of 16 kHz mono (640 KB). Audio is accumulated as a list of fixed-size
    /// blocks rather than one giant `[Float]` (issue #109), so an append only ever touches the last
    /// block and a snapshot copies block REFERENCES under the lock — O(blocks), not O(samples).
    static let blockSize = 160_000

    private let lock = NSLock()
    /// Every block but the last holds exactly `blockSize` samples. Guarded by `lock`.
    private var blocks: [[Float]] = []         // guarded by `lock`
    private var total = 0                      // guarded by `lock`
    private var truncated = false              // guarded by `lock`
    /// Bumped on every `reset()`. Each capture captures the generation for ITS run; an append whose
    /// generation no longer matches is from a superseded capture and is rejected under the lock — even
    /// if it was mid-resample when the next run reset the buffer. Closes the TOCTOU window that the
    /// `stopped`-flag check in `DualChannelCapture.emit` alone cannot. Guarded by `lock`.
    private var generation = 0
    /// Capture-time of the buffer's sample 0 — the timestamp of the first `.others` chunk after a
    /// reset. System audio starts asynchronously after capture begins, so this is > 0; callers add it
    /// to buffer-relative diarization times to realign them with the transcript's capture-time stamps.
    private var offset: TimeInterval = 0       // guarded by `lock`
    private var offsetSet = false              // guarded by `lock`
    /// AVAudioConverter cached per input sample rate — building one per callback is wasteful, and the
    /// `.others` rate is stable for a session (48 kHz). Guarded by `lock`.
    private var converter: AVAudioConverter?
    private var converterInputRate: Double = 0

    /// Whether the cap was hit and later audio was dropped — surfaced so the UI can be honest.
    var didTruncate: Bool { lock.withLock { truncated } }

    /// Capture-time of the buffer's sample 0 (0 until the first append after a reset). Add this to
    /// buffer-relative diarization times to convert them into the transcript's capture-time frame.
    var startOffset: TimeInterval { lock.withLock { offset } }

    /// The current generation, to be captured by a freshly-built capture right after `reset()` and
    /// handed back to every `append` so stale (pre-reset) appends can be rejected.
    func currentGeneration() -> Int { lock.withLock { generation } }

    /// Resamples `samples` (mono Float at `sampleRate`) to 16 kHz and appends, up to the cap.
    /// `timestamp` is the chunk's capture-time; the first append after a reset records it as the
    /// buffer's `startOffset`. `generation` is the value the calling capture captured at its creation;
    /// the append is dropped if a later `reset()` has since bumped the buffer's generation — so an
    /// append that was mid-resample across a restart can't contaminate the new run's samples/offset.
    ///
    /// The ENTIRE body runs under `lock`: the generation guard is checked FIRST (before any resampling),
    /// then the resample + append happen while the lock is held. This serializes use of the shared,
    /// cached `AVAudioConverter` to one thread at a time — across a Listen→Stop→Listen restart the old
    /// and new captures run on different DispatchQueues, so without this a stale append could race the
    /// new one through the same converter and corrupt resampling. Per-chunk resample is tiny
    /// (~1–4k samples), so holding the lock for it is fine.
    func append(samples input: [Float], sampleRate: Double, timestamp: TimeInterval, generation: Int) {
        guard !input.isEmpty, sampleRate > 0 else { return }
        lock.withLock {
            guard generation == self.generation else { return }   // superseded — reject before resampling
            guard !truncated else { return }
            let resampled = (sampleRate == Self.targetSampleRate)
                ? input : resampleLocked(input, from: sampleRate)
            guard !resampled.isEmpty else { return }
            if !offsetSet {
                offset = timestamp
                offsetSet = true
            }
            let room = Self.maxSamples - total
            if resampled.count >= room {
                appendLocked(resampled.prefix(room))
                truncated = true
            } else {
                appendLocked(resampled[...])
            }
        }
    }

    /// Distributes `input` over the fixed-size blocks, filling the partial last block first.
    /// PRECONDITION: `lock` is held. Appending into `blocks[last]` mutates it in place (the array of
    /// blocks is uniquely referenced here); at worst a snapshot that is still holding the last block
    /// costs one copy of that single 640 KB block — never of the whole session.
    private func appendLocked(_ input: ArraySlice<Float>) {
        var remaining = input
        while !remaining.isEmpty {
            if blocks.isEmpty || blocks[blocks.count - 1].count >= Self.blockSize {
                var block = [Float]()
                block.reserveCapacity(Self.blockSize)
                blocks.append(block)
            }
            let last = blocks.count - 1
            let take = min(Self.blockSize - blocks[last].count, remaining.count)
            blocks[last].append(contentsOf: remaining.prefix(take))
            remaining = remaining.dropFirst(take)
            total += take
        }
    }

    /// Clears the buffer for a fresh session (resets the truncation flag too). Releases the backing
    /// store — it can grow to ~460 MB, so we don't keep that capacity alive between sessions.
    func reset() {
        lock.withLock {
            blocks.removeAll(keepingCapacity: false)
            total = 0
            truncated = false
            offset = 0
            offsetSet = false
            generation &+= 1   // invalidate any in-flight append from the prior run's capture
            // Drop the cached converter: AVAudioConverter carries internal sample-rate-conversion
            // filter state, so reusing it across runs would let the previous stream's tail taint the
            // first converted samples of the next run. The next append rebuilds a fresh one.
            converter = nil
            converterInputRate = 0
        }
    }

    /// One window of accumulated audio, plus where it sits in the buffer.
    struct Snapshot: Sendable {
        /// Contiguous 16 kHz mono samples for the requested window.
        let samples: [Float]
        /// Index of `samples[0]` within the whole buffer (block-aligned, so `<=` what was requested).
        let startSample: Int
        /// Capture-time of the buffer's sample 0 (see `startOffset`).
        let startOffset: TimeInterval
        /// Buffer-relative time of `samples[0]`, to shift window-relative diarization times by.
        var startTime: TimeInterval { TimeInterval(startSample) / SpeakerAudioBuffer.targetSampleRate }
    }

    /// Total samples accumulated so far.
    var sampleCount: Int { lock.withLock { total } }

    /// Accumulated 16 kHz samples from `fromSample` (rounded DOWN to a block boundary) to the end.
    ///
    /// Only block references are copied under the lock — O(blocks) regardless of session length — and
    /// the concatenation happens off the lock, so a periodic pass while recording never stalls the
    /// capture callback and never forces a copy-on-write of the whole session (issue #109).
    func snapshot(fromSample requested: Int = 0) -> Snapshot {
        let (window, startSample, offsetCopy): ([[Float]], Int, TimeInterval) = lock.withLock {
            let index = max(0, min(requested, total)) / Self.blockSize
            return (Array(blocks.dropFirst(index)), index * Self.blockSize, offset)
        }
        var out = [Float]()
        out.reserveCapacity(window.reduce(0) { $0 + $1.count })
        for block in window { out.append(contentsOf: block) }
        return Snapshot(samples: out, startSample: startSample, startOffset: offsetCopy)
    }

    /// Converts mono Float at `inputRate` to 16 kHz mono Float via a cached `AVAudioConverter`.
    /// Mirrors `DualChannelCapture.convertToMonoFloat`'s single-shot convert idiom, retargeted to
    /// 16 kHz. Returns `[]` on any setup/convert failure (the sample run is simply skipped).
    ///
    /// PRECONDITION: `lock` is already held by the caller (`append`). This must NOT acquire `lock`
    /// itself — NSLock is non-recursive, so re-entry would deadlock. Holding the lock here is what
    /// serializes the shared converter across concurrent captures.
    private func resampleLocked(_ input: [Float], from inputRate: Double) -> [Float] {
        guard let inFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inputRate,
                                           channels: 1, interleaved: false),
              let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: Self.targetSampleRate,
                                            channels: 1, interleaved: false) else { return [] }
        if converter == nil || converterInputRate != inputRate {
            converter = AVAudioConverter(from: inFormat, to: outFormat)
            converterInputRate = inputRate
        }
        guard let converter,
              let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat,
                                              frameCapacity: AVAudioFrameCount(input.count)),
              let channel = inBuffer.floatChannelData?[0] else { return [] }
        input.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: input.count) }
        inBuffer.frameLength = AVAudioFrameCount(input.count)

        let ratio = Self.targetSampleRate / inputRate
        let outCapacity = AVAudioFrameCount(Double(input.count) * ratio) + 1
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outCapacity),
              let outChannel = outBuffer.floatChannelData?[0] else { return [] }
        var consumed = false
        var convError: NSError?
        let status = converter.convert(to: outBuffer, error: &convError) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return inBuffer
        }
        if status == .error || convError != nil { return [] }
        return Array(UnsafeBufferPointer(start: outChannel, count: Int(outBuffer.frameLength)))
    }
}
