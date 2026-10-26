import Foundation
import ListenToMeCore

/// Constructs one coherent graph; SwiftUI retains its objects rather than coordinating tasks.
@MainActor
struct MacMeetingEnvironment {
    let store: ConversationStore
    let session: MeetingSession
    let othersSink: SpeakerAudioBuffer
    let microphoneSink: SpeakerAudioBuffer

    init(makeSession: (ConversationStore, SpeakerAudioBuffer, SpeakerAudioBuffer) -> MeetingSession) {
        let store = ConversationStore()
        let others = SpeakerAudioBuffer()
        let microphone = SpeakerAudioBuffer()
        self.store = store; othersSink = others; microphoneSink = microphone
        session = makeSession(store, others, microphone)
    }
}
