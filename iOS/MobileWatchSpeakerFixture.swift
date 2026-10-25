#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import ListenToMeCore

/// Synthetic Watch label results in the actual History/Notes/transcript views, without a model download.
struct MobileWatchSpeakerFixture: View {
    @State private var session: MobileSession = {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WatchSpeakersUI-\(UUID())")
        let session = MobileSession(storageDirectory: root)
        var labels = WatchSpeakerLabels(existing: [])
        labels.append(DiarizedWindow(segments: [
            DiarizedSegment(speakerId: "a", start: 0, duration: 8),
            DiarizedSegment(speakerId: "b", start: 10, duration: 8)
        ]), at: 0)
        let lines = [
            TranscriptSegment(source: .you, text: "We will test the release on Friday.", isFinal: true,
                              start: 1, end: 6, speakerName: MobileFileTranscriber.speakerName),
            TranscriptSegment(source: .you, text: "I will prepare the checklist.", isFinal: true,
                              start: 11, end: 16, speakerName: MobileFileTranscriber.speakerName)
        ].map { labels.label($0) }
        let record = SessionRecord(id: UUID().uuidString, title: "Watch planning conversation", date: Date(),
                                   transcript: MobileSession.transcriptText(for: lines), summary: "", segments: lines,
                                   sourceImportID: "watch:" + UUID().uuidString)
        session.restore(record)
        session.save(announce: false)
        return session
    }()

    var body: some View { MobileMeetingView(session: session) }
}
#endif
