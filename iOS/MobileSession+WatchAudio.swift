import AVFoundation
import Foundation
import ListenToMeCore

extension MobileSession {
    /// Preserve the input before transcription can consume it. Storage failure leaves the inbox
    /// intact for Retry. The opt-in is read at each batch; turning it off keeps existing copies.
    func retainWatchAudio(_ chunks: [WatchAudioChunk], ledger: WatchCaptureLedger,
                          recordID: String) throws -> [WatchAudioChunk] {
        guard savedAudio.enabled else { return chunks }
        var prepared: [WatchAudioChunk] = []
        var through: TimeInterval = 0
        defer { savedAudio.applyRetention(); savedAudio.refresh() }
        for chunk in chunks {
            let file = try AVAudioFile(forReading: chunk.url)
            let duration = Double(file.length) / file.processingFormat.sampleRate
            let offset = max(chunk.startOffset, through) // Same monotonic placement as ChunkFeed.
            through = offset + duration
            if ledger.chunks.first(where: { $0.index == chunk.index })?.audioSaved == true {
                prepared.append(chunk)
                continue
            }
            let run = try savedAudio.library.importWatchChunk(from: chunk.url, conversationID: recordID,
                recordingID: ledger.recordingID, chunkIndex: chunk.index, startedAt: ledger.startedAt,
                timelineOffset: offset, duration: duration)
            let retainedDuration = run.duration ?? duration
            _ = try watchInbox.update(ledger.recordingID) {
                $0.markAudioSaved(chunk.index, offset: run.timelineOffset, duration: retainedDuration)
            }
            prepared.append(WatchAudioChunk(index: chunk.index, url: chunk.url,
                                            startOffset: run.timelineOffset, duration: retainedDuration))
            through = run.timelineOffset + retainedDuration
        }
        return prepared
    }
}
