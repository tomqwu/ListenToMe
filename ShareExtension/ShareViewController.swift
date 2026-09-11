import UIKit
import UniformTypeIdentifiers

@MainActor
final class ShareViewController: UIViewController {
    private let status = UILabel()
    private let importButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let title = UILabel()
        title.text = "Import to ListenToMe"; title.font = .preferredFont(forTextStyle: .title2)
        title.numberOfLines = 0
        status.text = "Save this content as a new conversation. Open ListenToMe after importing."
        status.numberOfLines = 0
        importButton.setTitle("Import", for: .normal)
        importButton.addTarget(self, action: #selector(importContent), for: .touchUpInside)
        let cancel = UIButton(type: .system)
        cancel.setTitle("Done", for: .normal)
        cancel.addTarget(self, action: #selector(finish), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [title, status, importButton, cancel])
        stack.axis = .vertical; stack.spacing = 24; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32)
        ])
    }

    @objc private func finish() { extensionContext?.completeRequest(returningItems: nil) }

    @objc private func importContent() {
        importButton.isEnabled = false
        Task {
            var folder: URL?
            do {
                let id = UUID().uuidString
                let destination = try SharedInbox.root().appendingPathComponent(id, isDirectory: true)
                folder = destination
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
                var text: [String] = []
                var files: [SharedImport.File] = []
                let providers = items.flatMap { $0.attachments ?? [] }
                guard providers.count <= 20 else { throw failure("Share up to 20 items at a time.") }
                for provider in providers {
                    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                        files.append(try await saveURLFile(provider, to: destination))
                    } else if let type = provider.registeredTypeIdentifiers.first(where: {
                        guard let type = UTType($0) else { return false }
                        return type.conforms(to: .image) || type.conforms(to: .pdf)
                    }) {
                        files.append(try await saveFile(provider, type: type, to: destination))
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                        let data = try await loadData(provider, type: UTType.plainText.identifier)
                        if let value = String(data: data, encoding: .utf8) { text.append(value) }
                    } else if let type = provider.registeredTypeIdentifiers.first(where: {
                        UTType($0)?.conforms(to: .data) == true
                    }) {
                        files.append(try await saveFile(provider, type: type, to: destination))
                    }
                }
                if text.isEmpty, files.isEmpty {
                    text = items.compactMap { $0.attributedContentText?.string }
                }
                guard !text.isEmpty || !files.isEmpty else { throw failure("No supported text or file was shared.") }
                let joined = text.joined(separator: "\n\n")
                guard joined.count <= 100_000 else { throw failure("Share a shorter note (up to 100,000 characters).") }
                let batch = SharedImport(id: id, text: joined, files: files)
                try JSONEncoder().encode(batch).write(to: destination.appendingPathComponent("manifest.json"), options: .atomic)
                status.text = "Imported. Open ListenToMe to view your new conversation."
                importButton.setTitle("Saved", for: .normal)
            } catch {
                if let folder { try? FileManager.default.removeItem(at: folder) }
                status.text = error.localizedDescription
                importButton.isEnabled = true
            }
        }
    }

    private func loadData(_ provider: NSItemProvider, type: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                if let data, !data.isEmpty, data.count <= 20 * 1024 * 1024 { continuation.resume(returning: data) }
                else { continuation.resume(throwing: error ?? NSError(domain: "Import", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Each shared item must be no larger than 20 MB."])) }
            }
        }
    }

    private func saveFile(_ provider: NSItemProvider, type: String, to folder: URL) async throws -> SharedImport.File {
        let data = try await loadData(provider, type: type)
        let ext = UTType(type)?.preferredFilenameExtension ?? "data"
        let stored = UUID().uuidString + "." + ext
        let suggested = provider.suggestedName ?? "Shared file"
        let name = (suggested as NSString).pathExtension.isEmpty ? suggested + "." + ext : suggested
        try data.write(to: folder.appendingPathComponent(stored), options: .atomic)
        return SharedImport.File(name: name, storedName: stored)
    }

    private func saveURLFile(_ provider: NSItemProvider, to folder: URL) async throws -> SharedImport.File {
        let payload: (Data, String) = try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, error in
                guard let url = item as? URL else {
                    continuation.resume(throwing: error ?? NSError(domain: "Import", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "The shared file could not be opened."]))
                    return
                }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
                    guard size > 0, size <= 20 * 1024 * 1024 else {
                        throw NSError(domain: "Import", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Each shared file must be no larger than 20 MB."])
                    }
                    continuation.resume(returning: (try Data(contentsOf: url), url.lastPathComponent))
                } catch { continuation.resume(throwing: error) }
            }
        }
        let stored = UUID().uuidString + "." + (payload.1 as NSString).pathExtension
        try payload.0.write(to: folder.appendingPathComponent(stored), options: .atomic)
        return SharedImport.File(name: payload.1, storedName: stored)
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "Import", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
