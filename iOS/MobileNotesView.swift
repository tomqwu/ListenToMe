import AVFoundation
import PhotosUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers
import ListenToMeCore

struct MobileNotesView: View {
    @Bindable var session: MobileSession
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var showFiles = false
    @State private var showCamera = false
    @State private var preview: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section("Notes") {
                    TextEditor(text: $session.notes).frame(minHeight: 180)
                        .accessibilityLabel("Conversation notes").disabled(session.isSummarizing)
                        .onChange(of: session.notes) { _, _ in session.save(announce: false) }
                    PasteButton(payloadType: String.self) { strings in
                        session.notes += "\n" + strings.joined(separator: "\n")
                        session.save(announce: false)
                    }.disabled(session.isSummarizing)
                }
                Section("Add to this conversation") {
                    Button("Take photo", systemImage: "camera") { requestCamera() }
                    PhotosPicker(selection: $photo, matching: .images) { Label("Photo library", systemImage: "photo") }
                    Button("Add files", systemImage: "paperclip") { showFiles = true }
                    Text("Up to 20 attachments, 20 MB each. Originals stay on this device. " +
                         "Only text you add to Notes is included in AI summaries.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Apple Notes") {
                    Text("In Apple Notes, choose Share → Send Copy → ListenToMe. " +
                         "Return here to open the imported conversation. You can also paste copied text or add an exported PDF.")
                        .font(.callout)
                }
                if !session.attachments.isEmpty {
                    Section("Attachments") {
                        ForEach(session.attachments) { item in
                            HStack {
                                Button {
                                    do { preview = try session.attachmentStore().url(for: item) }
                                    catch { session.message = error.localizedDescription }
                                } label: {
                                    Label(item.name, systemImage: "doc").lineLimit(2)
                                }.accessibilityIdentifier("attachment-\(item.id)")
                                Spacer()
                                Menu("Attachment actions", systemImage: "ellipsis.circle") {
                                    Button("Add text to notes") { session.addAttachmentTextToNotes(item) }
                                        .disabled(session.isSummarizing)
                                    if let url = try? session.attachmentStore().url(for: item) {
                                        ShareLink(item: url) { Text("Share original") }
                                    }
                                    Button("Remove attachment", role: .destructive) { session.removeAttachment(item) }
                                }
                            }
                        }
                    }
                }
                if let message = session.message { Section { Text(message).font(.callout) } }
            }
            .navigationTitle("Notes")
            .toolbar { Button("Done") { dismiss() } }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): for url in urls { session.importFile(url) }
                case .failure(let error): session.message = "File import failed: \(error.localizedDescription)"
                }
            }
            .onChange(of: photo) { _, item in
                let conversation = session.id
                Task {
                    do {
                        if let data = try await item?.loadTransferable(type: Data.self), session.id == conversation {
                            let ext = item?.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                            session.addAttachment(data: data, name: "Photo-\(Date().formatted(.iso8601)).\(ext)")
                        }
                    } catch { session.message = "Could not load photo: \(error.localizedDescription)" }
                    photo = nil
                }
            }
            .sheet(isPresented: $showCamera) {
                MobileCamera { image in
                    if let data = image?.jpegData(compressionQuality: 0.85) {
                        session.addAttachment(data: data, name: "Camera-\(Date().formatted(.iso8601)).jpg")
                    }
                    showCamera = false
                }.ignoresSafeArea()
            }
            .quickLookPreview($preview)
        }
    }

    private func requestCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            session.message = "Camera capture requires a physical device with a camera. Use Photo library or Add files here."
            return
        }
        Task {
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            if allowed { showCamera = true }
            else { session.message = "Camera access is disabled. Allow it in iPhone Settings → ListenToMe." }
        }
    }
}

private struct MobileCamera: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera; picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: (UIImage?) -> Void
        init(completion: @escaping (UIImage?) -> Void) { self.completion = completion }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            completion(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(nil) }
    }
}
