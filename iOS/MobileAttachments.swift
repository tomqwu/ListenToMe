import Foundation
import ListenToMeCore
import PDFKit

extension MobileSession {
    func attachmentStore(for sessionID: String? = nil) -> SessionAttachmentStore {
        let safeID = (sessionID ?? id).filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        return SessionAttachmentStore(directory: attachmentRoot.appendingPathComponent(safeID, isDirectory: true))
    }

    func addAttachment(data: Data, name: String) {
        guard attachments.count < 20 else { message = "A conversation can have up to 20 attachments."; return }
        do {
            let store = attachmentStore()
            let item = try store.add(data: data, name: name)
            attachments.append(item)
            // Keep the original and in-memory item if either persistence write fails, so Save can retry.
            save(announce: false)
        } catch { message = "Could not add attachment. Use a nonempty file up to 20 MB. \(error.localizedDescription)" }
    }

    func importFile(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= SessionAttachmentStore.maximumBytes else { throw CocoaError(.fileReadTooLarge) }
            addAttachment(data: try Data(contentsOf: url), name: url.lastPathComponent)
        } catch { message = "Could not import file: \(error.localizedDescription)" }
    }

    func removeAttachment(_ item: SessionAttachment) {
        let old = attachments
        attachments.removeAll { $0.id == item.id }
        guard save(announce: false) else { attachments = old; return }
        do { try attachmentStore().remove(item) }
        catch { message = "Attachment removed from the conversation, but its local file could not be deleted." }
    }

    func addAttachmentTextToNotes(_ item: SessionAttachment) {
        guard !isSummarizing else { return }
        do {
            let url = try attachmentStore().url(for: item)
            let text: String
            if url.pathExtension.lowercased() == "pdf" {
                text = PDFDocument(url: url)?.string ?? ""
            } else if ["txt", "md", "csv", "json"].contains(url.pathExtension.lowercased()) {
                text = try String(contentsOf: url, encoding: .utf8)
            } else { message = "Text extraction supports PDF, TXT, Markdown, CSV and JSON files."; return }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                message = "This file has no selectable text. Scanned images need OCR before importing text."; return
            }
            guard text.count <= 60_000 else { message = "This file has more than 60,000 characters. Import a shorter extract."; return }
            notes += "\n\n" + item.name + "\n" + text
            save(announce: false)
        } catch { message = "Could not read attachment text: \(error.localizedDescription)" }
    }
}
