import ListenToMeCore

struct SpeakerParticipant: Identifiable {
    let id: String
    var name: String
    let source: SpeakerSource
    let seconds: Double
}

