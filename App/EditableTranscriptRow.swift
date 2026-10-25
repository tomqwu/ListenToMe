import SwiftUI
import ListenToMeCore

struct EditableTranscriptRow: View {
    let segment: TranscriptSegment
    let speakerLabel: String
    let copyTranscript: () -> Void
    let edit: (String) -> Void
    let delete: () -> Void
    let addTerm: () -> Void
    @State private var editing = false
    @State private var draft = ""
    @State private var confirmingDelete = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(CommandCenterLabels.stamp(segment.start))
                .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.ink3)
                .frame(width: 40, alignment: .leading)
            Text(speakerLabel).font(.system(size: 11, weight: .bold))
                .foregroundStyle(segment.source == .you ? Theme.you : Theme.others)
                .frame(width: 100, alignment: .leading).lineLimit(2).help(segment.speakerLabel)
            if editing {
                VStack(alignment: .leading) {
                    TextField("Transcript text", text: $draft, axis: .vertical)
                        .lineLimit(2...8).textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Save") { edit(draft); editing = false }
                            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Cancel") { editing = false }
                    }.controlSize(.small)
                }
            } else {
                Text(segment.text).font(.system(size: 12.5)).foregroundStyle(Theme.ink)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture(count: 2) { beginEditing() }
            }
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button("Copy line") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(segment.text, forType: .string)
            }
            Button("Copy transcript", action: copyTranscript)
            if segment.isFinal {
                Divider()
                Button("Edit line…", action: beginEditing)
                Button("Delete line…", role: .destructive) { confirmingDelete = true }
                Button("Add to My terms…", action: addTerm)
            }
        }
        .confirmationDialog("Delete this transcript line?", isPresented: $confirmingDelete) {
            Button("Delete line", role: .destructive, action: delete)
        } message: {
            Text("The line is removed from this conversation. Saved audio and exported copies are unchanged.")
        }
    }

    private func beginEditing() {
        guard segment.isFinal else { return }
        draft = segment.text; editing = true
    }
}
