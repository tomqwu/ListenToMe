import SwiftUI
import ListenToMeCore

struct MobileSpeakerRenameRequest: Identifiable {
    let id = UUID()
    let line: TranscriptSegment
    let conversationID: String
}

/// Hosted above layout branches so a keyboard or rotation cannot discard the edit.
struct MobileSpeakerRenameSheet: View {
    let session: MobileSession
    let request: MobileSpeakerRenameRequest
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        SpeakerRenameEditor(name: request.line.speakerLabel) { name in
            guard session.id == request.conversationID, let id = request.line.speakerID,
                  session.segments.contains(where: { $0.id == request.line.id && $0.speakerID == id }) else { return }
            session.renameSpeaker(id: id, to: name)
        }.presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
    }
}
