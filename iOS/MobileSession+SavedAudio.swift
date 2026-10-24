import Foundation
import ListenToMeCore

/// Save audio recordings (issue #55), kept out of the class body.
extension MobileSession {
    /// Gives a new recording run its copies of the transcribed audio: speakers (#180), language (#197)
    /// and, when the user turned it on, the saved audio file. All three receive only what the analyzer
    /// accepted, so their times match the transcript's. `offset` is where this run's lines start.
    func attachRunAudio(to recorder: any MobileRecording, offset: TimeInterval) {
        recorder.attachSpeakerAudio(speakers.beginRun(offset: offset, existing: segments))
        recorder.attachLanguageAudio(languageDetection.beginRun(conversation: id, locale: transcriptionLanguage,
                                                                offset: offset, firstLine: segments.count))
        recorder.attachSavedAudio(savedAudio.beginRun(conversation: id, offset: offset))
    }

    /// The open conversation's saved files, for the share sheet.
    var savedAudioFiles: [URL] { savedAudio.fileURLs(for: id) }

    /// Whether the open conversation has audio that can be played now (never while recording).
    var canPlaySavedAudio: Bool { state == .idle && !savedAudio.runs(for: id).isEmpty }
}

extension MobileSession {
    /// A run ended. A recording that never became a saved conversation (no line, no notes) keeps no audio.
    func endSavedAudioRun() {
        savedAudio.endRun()
        if !history.contains(where: { $0.id == id }) { savedAudio.delete(conversation: id) }
    }

    /// At launch: repairs runs the app was killed in and deletes audio whose conversation is gone. Orphans
    /// are judged only against a History that read completely; a set-aside file's audio is never deleted.
    func tidySavedAudio() {
        guard let result = try? archive.read(), result.warning == nil else {
            savedAudio.tidy(keeping: nil)
            return
        }
        savedAudio.tidy(keeping: Set(result.records.map(\.id) + (state == .idle ? [] : [id])))
    }
}
