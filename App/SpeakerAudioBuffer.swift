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

    private let lock = NSLock()
    private var samples: [Float] = []          // guarded by `lock`
    private var truncated = false              // guarded by `lock`
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

    /// Resamples `samples` (mono Float at `sampleRate`) to 16 kHz and appends, up to the cap.
    /// `timestamp` is the chunk's capture-time; the first append after a reset records it as the
    /// buffer's `startOffset`.
    func append(samples input: [Float], sampleRate: Double, timestamp: TimeInterval) {
        guard !input.isEmpty, sampleRate > 0 else { return }
        let resampled = (sampleRate == Self.targetSampleRate) ? input : resample(input, from: sampleRate)
        guard !resampled.isEmpty else { return }
        lock.withLock {
            guard !truncated else { return }
            if !offsetSet {
                offset = timestamp
                offsetSet = true
            }
            let room = Self.maxSamples - samples.count
            if resampled.count >= room {
                samples.append(contentsOf: resampled.prefix(room))
                truncated = true
            } else {
                samples.append(contentsOf: resampled)
            }
        }
    }

    /// Clears the buffer for a fresh session (resets the truncation flag too). Releases the backing
    /// store — it can grow to ~460 MB, so we don't keep that capacity alive between sessions.
    func reset() {
        lock.withLock {
            samples.removeAll(keepingCapacity: false)
            truncated = false
            offset = 0
            offsetSet = false
        }
    }

    /// A copy of the accumulated 16 kHz mono samples.
    func snapshot() -> [Float] { lock.withLock { samples } }

    /// Converts mono Float at `inputRate` to 16 kHz mono Float via a cached `AVAudioConverter`.
    /// Mirrors `DualChannelCapture.convertToMonoFloat`'s single-shot convert idiom, retargeted to
    /// 16 kHz. Returns `[]` on any setup/convert failure (the sample run is simply skipped).
    private func resample(_ input: [Float], from inputRate: Double) -> [Float] {
        guard let inFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inputRate,
                                           channels: 1, interleaved: false),
              let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: Self.targetSampleRate,
                                            channels: 1, interleaved: false) else { return [] }
        let conv: AVAudioConverter? = lock.withLock {
            if converter == nil || converterInputRate != inputRate {
                converter = AVAudioConverter(from: inFormat, to: outFormat)
                converterInputRate = inputRate
            }
            return converter
        }
        guard let converter = conv,
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
