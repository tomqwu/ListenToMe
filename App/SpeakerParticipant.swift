import ListenToMeCore

struct SpeakerParticipant: Identifiable {
    let id: String
    var name: String
    let source: SpeakerSource
    let seconds: Double
}


extension SpeakerParticipant {
    /// Update an existing participant or a restored transcript identity, never an unknown voice.
    static func rename(id: String, to name: String, participants: inout [SpeakerParticipant],
                       store: ConversationStore) -> SpeakerSource? {
        guard let source = participants.first(where: { $0.id == id })?.source
            ?? store.utterances.first(where: { $0.speakerID == id })?.source else { return nil }
        if let index = participants.firstIndex(where: { $0.id == id }) { participants[index].name = name }
        store.renameSpeaker(id: id, name: name)
        return source
    }
}
