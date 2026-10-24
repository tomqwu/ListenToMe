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
