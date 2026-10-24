import Foundation

/// Converts audio chunks into transcript segments. Real impl lives in the app target.
public protocol Transcribing: Sendable {
    var statusUpdates: AsyncStream<String> { get }
    var segments: AsyncStream<TranscriptSegment> { get }
    /// Warms the transcription pipeline (model download/load, analyzer start) BEFORE any audio is
    /// fed, so `feed` never blocks on one-time setup and the opening seconds of a meeting aren't
    /// dropped by the capture stream's bounded buffer. Called by `MeetingSession` before capture
    /// starts (and before the first chunk of an imported file).
    ///
    /// Implementations MUST observe `Task.isCancelled` around long awaits (a first-run model
    /// download can take minutes): the session cancels this work when the user stops, closes the
    /// window or quits while it is still in flight.
    func prepare() async
    func feed(_ chunk: AudioChunk) async
    func finish() async
    /// Words and short phrases recognition should favor (issue #222): the active vocabularies, capped by
    /// `ActiveVocabulary.recognitionTerms`. Set before `prepare()` and again whenever the user changes
    /// them while recording; an engine that can update a running recognizer applies them at once.
    func setContextualStrings(_ strings: [String]) async
}

public extension Transcribing {
    var statusUpdates: AsyncStream<String> { AsyncStream { $0.finish() } }
    /// Transcribers with no one-time setup (e.g. `SFSpeechRecognizer`) need no warm-up.
    func prepare() async {}
    /// Engines without contextual strings (WhisperKit) ignore the vocabulary.
    func setContextualStrings(_ strings: [String]) async {}
}
