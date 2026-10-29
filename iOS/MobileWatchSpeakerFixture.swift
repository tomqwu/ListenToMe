#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import AVFoundation
import ListenToMeCore

/// Synthetic Watch label results in the actual History/Notes/transcript views, without a model download.
struct MobileWatchSpeakerFixture: View {
    @State private var session: MobileSession = {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WatchSpeakersUI-\(UUID())")
        let session = MobileSession(storageDirectory: root, recordingSupport: { _ in .ready })
        var labels = WatchSpeakerLabels(existing: [])
        labels.append(DiarizedWindow(segments: [
            DiarizedSegment(speakerId: "a", start: 0, duration: 8),
            DiarizedSegment(speakerId: "b", start: 10, duration: 8)
        ]), at: 0)
        let lines = [
            TranscriptSegment(source: .you, text: "We will test the release on Friday.", isFinal: true,
                              start: 1, end: 6, speakerName: MobileFileTranscriber.speakerName),
            TranscriptSegment(source: .you, text: "Please include the speaker rename check.", isFinal: true,
                              start: 6.2, end: 7.8, speakerName: MobileFileTranscriber.speakerName),
            TranscriptSegment(source: .you, text: "I will prepare the checklist.", isFinal: true,
                              start: 11, end: 16, speakerName: MobileFileTranscriber.speakerName)
        ].map { labels.label($0) }
        let record = SessionRecord(id: UUID().uuidString, title: "Watch planning conversation", date: Date(),
                                   transcript: MobileSession.transcriptText(for: lines), summary: "", segments: lines,
                                   sourceImportID: "watch:" + UUID().uuidString)
        session.restore(record)
        session.save(announce: false)
        let url = root.appendingPathComponent("watch-tone.m4a")
        do {
            let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 320_000)!
            buffer.frameLength = 320_000
            for i in 0..<320_000 { buffer.floatChannelData![0][i] = Float(sin(Double(i) * 0.06) * 0.1) }
            do {
                let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1])
                try file.write(from: buffer)
            }
            try session.savedAudio.library.importWatchChunk(from: url, conversationID: record.id,
                recordingID: UUID(), chunkIndex: 0, startedAt: Date(), timelineOffset: 0, duration: 20)
            session.savedAudio.refresh()
        } catch { session.message = "Fixture audio failed: \(error.localizedDescription)" }
        return session
    }()

    var body: some View {
        MobileMeetingView(session: session)
            .mobileSessionLifecycle(session)
    }
}
#endif
