import SwiftUI

/// A deliberate Save/Cancel editor shared by transcript speaker shortcuts.
struct SpeakerRenameEditor: View {
    let saveName: (String) -> Void
    @State private var name: String
    @Environment(\.dismiss) private var dismiss

    init(name: String, saveName: @escaping (String) -> Void) {
        _name = State(initialValue: name)
        self.saveName = saveName
    }

    static func normalized(_ name: String) -> String? {
        let cleaned = String(name.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(80))
        guard !cleaned.isEmpty, cleaned != "Microphone", cleaned != "Apple Watch" else { return nil }
        return cleaned
    }

    var body: some View {
        #if os(iOS)
        ScrollView {
            fields.padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { actions.padding(24).background(.regularMaterial) }
        #else
        VStack(alignment: .leading, spacing: 16) {
            fields
            actions
        }.padding(24).frame(minWidth: 280, maxWidth: 440)
        #endif
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename speaker").font(.headline).fixedSize(horizontal: false, vertical: true)
            Text("Applies to all lines from this speaker in this conversation.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Speaker name", text: $name)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("renameSpeakerName")
                .onSubmit { save() }
        }
    }

    private var actions: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .accessibilityIdentifier("renameSpeakerCancel")
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button("Save", action: save)
                .accessibilityIdentifier("renameSpeakerSave")
                .disabled(Self.normalized(name) == nil)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func save() {
        guard let value = Self.normalized(name) else { return }
        saveName(value)
        dismiss()
    }
}
