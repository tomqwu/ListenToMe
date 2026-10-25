import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ListenToMeCore

// MARK: - Export (issue #130) and the conversation's language (issue #206)

extension MeetingView {
    /// The open conversation as a record: what a checkpoint saves and what every export formats.
    func currentRecord(date: Date = Date(), complete: Bool = false) -> SessionRecord {
        SessionRecord(
            id: currentSessionID, title: conversationTitle, date: date,
            transcript: store.utterances.map { "\($0.speakerLabel): \($0.text)" }.joined(separator: "\n"),
            summary: session.listenerSummary, segments: store.utterances, notes: session.notes,
            quickSuggestion: session.quickSuggestion, deepAnswer: session.deepAnswer, isComplete: complete,
            attachments: restoredRecord?.attachments, sourceImportID: restoredRecord?.sourceImportID,
            titleState: conversationTitleState, selectionSummaries: restoredRecord?.selectionSummaries,
            summaryInstructions: session.summaryInstructions,
            vocabularyDomainIDs: vocabulary.domainIDs(for: currentSessionID).sorted(), situationGrid: session.visibleSituation
        ).with(languages: conversationLanguages)
    }

    /// The full Markdown document, for Save As when history saving is off.
    func sessionMarkdown() -> String {
        SessionExporter.markdown(for: currentRecord(date: conversationStartedAt ?? Date()))
    }

    /// Cmd-E: the full transcript as Markdown.
    func exportSession() {
        ConversationExport.save(currentRecord(date: conversationStartedAt ?? Date()), as: .markdown) {
            startError = $0
        }
    }

    /// Notes the language this capture is transcribed in, for the conversation's record. WhisperKit's
    /// Automatic detects the language as it goes and reports none, so nothing is guessed for it.
    func noteCaptureLanguage(engine: String = ProviderSettings.transcriptionEngine) {
        guard engine != "whisperKit" || !ProviderSettings.transcriptionLocaleID.isEmpty else { return }
        conversationLanguages.record(ProviderSettings.transcriptionLocale().identifier)
    }
}

/// Writes exports through a save panel, named after the conversation's title and date.
@MainActor
enum ConversationExport {
    static func contentType(for format: SessionExportFormat) -> UTType {
        switch format {
        case .json: return .json
        case .plainText: return .plainText
        default: return UTType(filenameExtension: format.fileExtension, conformingTo: .plainText) ?? .plainText
        }
    }

    static func save(_ record: SessionRecord, as format: SessionExportFormat, onError: (String) -> Void) {
        write(Data(SessionExporter.export(record, as: format).utf8),
              name: SessionExporter.fileName(for: record, format: format), type: contentType(for: format),
              onError: onError)
    }

    static func saveRecap(_ record: SessionRecord, onError: (String) -> Void) {
        write(Data(SessionExporter.recap(for: record).utf8),
              name: SessionExporter.fileName(title: record.title, date: record.date, fileExtension: "md",
                                             suffix: "recap"),
              type: contentType(for: .markdown), onError: onError)
    }

    static func savePDF(_ record: SessionRecord, onError: (String) -> Void) {
        guard let data = PDFExport.data(fromMarkdown: SessionExporter.markdown(for: record), title: record.title) else {
            return onError("Couldn't render the PDF.")
        }
        write(data, name: SessionExporter.fileName(title: record.title, date: record.date, fileExtension: "pdf"),
              type: .pdf, onError: onError)
    }

    private static func write(_ data: Data, name: String, type: UTType, onError: (String) -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try data.write(to: url, options: .atomic) } catch {
            onError("Export failed: \(error.localizedDescription)")
        }
    }
}

/// The Export menu's items, shared by the live conversation and the History detail sheet. Subtitle
/// formats need lines with times, which only some engines report (see docs/export-formats.md).
struct ConversationExportMenu: View {
    let record: () -> SessionRecord
    let hasTimestamps: Bool
    let onError: (String) -> Void

    var body: some View {
        ForEach(SessionExportFormat.allCases) { format in
            Button("\(format.title)…") { ConversationExport.save(record(), as: format, onError: onError) }
                .disabled(format.needsTimestamps && !hasTimestamps)
        }
        if !hasTimestamps {
            Text("Subtitles need a transcript with timestamps (WhisperKit, or iPhone recordings).")
        }
        Divider()
        Button("Recap (Markdown)…") { ConversationExport.saveRecap(record(), onError: onError) }
        Button("PDF…") { ConversationExport.savePDF(record(), onError: onError) }
        Divider()
        Button("Copy conversation") { Clipboard.copy(SessionExporter.markdown(for: record())) }
    }
}
