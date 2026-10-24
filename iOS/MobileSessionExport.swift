import Foundation
import SwiftUI
import UniformTypeIdentifiers
import ListenToMeCore

extension MobileSession {
    var markdown: String { SessionExporter.markdown(for: currentRecord) }

    var readableShareText: String { Self.readableText(markdown) }

    static func readableShareText(for record: SessionRecord) -> String { readableText(markdown(for: record)) }

    static func readableText(_ markdown: String) -> String {
        MarkdownText.blocks(markdown).map { block in
            switch block {
            case .code(let code): return code
            case .markdown(let text):
                let styled = MarkdownText.inlineAttributed(text)
                return styled.runs.map { run in
                    let label = String(styled[run.range].characters)
                    if let link = run.link, label != link.absoluteString { return label + " (" + link.absoluteString + ")" }
                    return label
                }.joined()
            }
        }.joined(separator: "\n\n")
    }

    /// Export the chosen saved record without opening it or changing the active conversation.
    static func markdown(for record: SessionRecord) -> String { SessionExporter.markdown(for: record) }

    /// Encodes the active snapshot with sorted keys, so an unchanged conversation always produces the
    /// same bytes and `save()` can skip rewriting it (dictionary-backed key order otherwise varies).
    static let stableEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    // MARK: The conversation's own languages (issue #206)

    /// `record` with the languages this conversation was transcribed in: the languages its lines are in
    /// (each line keeps the one it was recognized in), and as the current one the latest recording's,
    /// switch's or Undo's since it was opened, else what it was saved with.
    func withConversationLanguages(_ record: SessionRecord) -> SessionRecord {
        let saved = history.first { $0.id == record.id }?.conversationLanguages ?? record.conversationLanguages
        return record.with(languages: saved.resolving(recorded: languageDetection.languageChanges[record.id] ?? [],
                                                      segments: record.segments ?? []))
    }

    /// New lines of the open conversation were transcribed in `identifier` outside a recording.
    func noteConversationLanguage(_ identifier: String) {
        languageDetection.languageChanges[id, default: []].append(identifier)
    }

    /// An Undo switched transcription back to the language before the switch. Lines spoken after the
    /// switch keep theirs, so the switched-to language stays listed while any line is in it.
    func noteLanguageUndo(_ change: MobileLanguageDetection.Switch) {
        languageDetection.languageChanges[change.conversation, default: []].append(change.from)
    }
}

/// One conversation as a file in one export format (issue #130), named after its title and date. The
/// file is written to this app's temporary folder only when the user picks a share destination, with
/// the same data protection as the archive; the previous export's file is removed then.
struct ConversationExportFile: Transferable {
    let record: SessionRecord
    let format: SessionExportFormat

    var fileName: String { SessionExporter.fileName(for: record, format: format) }

    static let markdownType = UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText
    static let srtType = UTType(filenameExtension: "srt", conformingTo: .plainText) ?? .plainText
    static let vttType = UTType(filenameExtension: "vtt", conformingTo: .plainText) ?? .plainText

    static var folder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ConversationExports", isDirectory: true)
    }

    /// Removes every exported file: before the next export, at launch, and when conversations are
    /// deleted (an owner in `conversationDataOwners`), so no copy outlives Delete or Delete all.
    static func removeAll() throws {
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        try FileManager.default.removeItem(at: folder)
    }

    func write() throws -> URL {
        try? Self.removeAll()
        let directory = Self.folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try PrivateStorage.createDirectory(at: directory)
        let url = directory.appendingPathComponent(fileName)
        try Data(SessionExporter.export(record, as: format).utf8).write(to: url, options: PrivateStorage.writingOptions)
        return url
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: markdownType) { SentTransferredFile(try $0.write()) }
            .exportingCondition { $0.format == .markdown }
        FileRepresentation(exportedContentType: .plainText) { SentTransferredFile(try $0.write()) }
            .exportingCondition { $0.format == .plainText }
        FileRepresentation(exportedContentType: srtType) { SentTransferredFile(try $0.write()) }
            .exportingCondition { $0.format == .srt }
        FileRepresentation(exportedContentType: vttType) { SentTransferredFile(try $0.write()) }
            .exportingCondition { $0.format == .webVTT }
        FileRepresentation(exportedContentType: .json) { SentTransferredFile(try $0.write()) }
            .exportingCondition { $0.format == .json }
    }
}

/// The Export as menu's items: one share link per format. Subtitles are offered only when the
/// conversation's lines carry times (every iPhone and Apple Watch recording does).
struct ConversationExportLinks: View {
    let record: SessionRecord

    var body: some View {
        ForEach(SessionExporter.formats(for: record)) { format in
            let file = ConversationExportFile(record: record, format: format)
            ShareLink(item: file, preview: SharePreview(file.fileName)) {
                Label(format.title, systemImage: Self.symbol(format))
            }
            .accessibilityIdentifier("export-\(format.rawValue)")
        }
    }

    static func symbol(_ format: SessionExportFormat) -> String {
        switch format {
        case .markdown: return "doc.richtext"
        case .plainText: return "doc.plaintext"
        case .srt, .webVTT: return "captions.bubble"
        case .json: return "curlybraces"
        }
    }
}
