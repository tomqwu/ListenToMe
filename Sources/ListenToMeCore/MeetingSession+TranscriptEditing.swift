import Foundation

extension MeetingSession {
    @discardableResult
    public func editTranscript(id: UUID, text: String) -> Bool {
        guard store.edit(id: id, text: text) else { return false }
        transcriptWasEdited()
        return true
    }

    @discardableResult
    public func deleteTranscript(id: UUID) -> Bool {
        guard store.delete(id: id) else { return false }
        transcriptWasEdited()
        return true
    }

    private func transcriptWasEdited() {
        // No recap, suggestions or in-flight response may keep removed or corrected wording.
        quickReader.reset()
        speakerNamesChanged()
        handleLiveEvent(.conversationChanged)
    }
}
