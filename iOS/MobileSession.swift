import Foundation
import FoundationModels
import ListenToMeCore
import Observation
import UIKit

@MainActor @Observable
final class MobileSession {
    enum State { case idle, preparing, recording, stopping }
    var state = State.idle
    var title = "New conversation"
    var notes = ""
    var summary = ""
    var quickSummary = ""
    var deepThought = ""
    var attachments: [SessionAttachment] = []
    var generatingMode: MobileSummaryMode?
    var autoQuick = false
    private var lastAutoSource = ""
    private var sourceImportID: String?
    var segments: [TranscriptSegment] = []
    var partial: TranscriptSegment?
    var history: [SessionRecord] = []
    var message: String?
    var isSummarizing = false
    let ai = MobileAISettings()
    var summaryDraft = ""
    private var summaryTask: Task<Void, Never>?
    var language = Locale.current.identifier
    private(set) var id = UUID().uuidString
    private var date = Date()
    private var recorder: MobileRecorder?
    private var startTask: Task<Void, Never>?
    private let archive: SessionArchive
    private let activeURL: URL
    let attachmentRoot: URL

    init(storageDirectory: URL = .applicationSupportDirectory) {
        activeURL = storageDirectory.appendingPathComponent("ActiveConversation.json")
        attachmentRoot = storageDirectory.appendingPathComponent("Attachments", isDirectory: true)
        let directory = storageDirectory.appendingPathComponent("Conversations", isDirectory: true)
        archive = SessionArchive(directory: directory)
        refreshHistory()
        if FileManager.default.fileExists(atPath: activeURL.path) {
            do { restore(try JSONDecoder().decode(SessionRecord.self, from: Data(contentsOf: activeURL))) }
            catch { message = "Could not restore the current conversation: \(error.localizedDescription). Check History." }
        } else if let latest = history.first { restore(latest) }
    }

    var busy: Bool { state != .idle || isSummarizing }
    var hasContent: Bool {
        !segments.isEmpty || partial != nil || !notes.isEmpty || !summary.isEmpty
            || !quickSummary.isEmpty || !deepThought.isEmpty || !attachments.isEmpty
    }
    var allSegments: [TranscriptSegment] { segments + (partial.map { [$0] } ?? []) }
    var markdown: String {
        let text = SessionExporter.markdown(title: title, transcript: allSegments, notes: notes, listenerSummary: summary,
                                            quickSuggestion: quickSummary, deepAnswer: deepThought)
        return text + (attachments.isEmpty ? "" : "\n## Attachments\n" + attachments.map { "- \($0.name)" }.joined(separator: "\n"))
    }
    var summaryAvailability: String? { summaryAvailability(for: .summary) }
    func summaryAvailability(for mode: MobileSummaryMode) -> String? {
        if ai.provider == .ollama { return ai.availability(for: mode) }
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.deviceNotEligible): return "On-device summaries require an Apple Intelligence capable device."
        case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in Settings to use on-device summaries."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence’s on-device model is not ready. Check setup in Settings → Apple Intelligence & Siri."
        default: return "On-device summaries are unavailable on this device."
        }
    }

    var summarySource: String { notes + "\n" + allSegments.map(\.text).joined(separator: "\n") }

    func summaryBlockReason(for mode: MobileSummaryMode) -> String? {
        Self.summaryBlockReason(state: state, generating: isSummarizing, source: summarySource,
                                providerReason: summaryAvailability(for: mode))
    }

    static func summaryBlockReason(state: State, generating: Bool, source: String, providerReason: String?) -> String? {
        if generating { return "Generating an AI response. Wait for it to finish or tap Cancel summary." }
        if state == .preparing || state == .stopping { return "Wait for microphone setup or stopping to finish." }
        if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Add notes or wait for transcript text before generating a summary."
        }
        return providerReason
    }

    func recheckSummary(for mode: MobileSummaryMode) {
        message = summaryBlockReason(for: mode) ?? "Ready to generate \(mode.title)."
    }

    func start() {
        guard state == .idle, !isSummarizing else { return }
        message = nil
        // Keep any unfinished hypothesis from an interrupted earlier run.
        if let partial { segments.append(partial); self.partial = nil }
        state = .preparing
        let recorder = MobileRecorder()
        self.recorder = recorder
        let offset = segments.map(\.end).max() ?? 0
        startTask = Task {
            do {
                try await recorder.start(locale: Locale(identifier: language)) { [weak self] segment in
                    guard let self else { return }
                    let timed = TranscriptSegment(source: .you, text: segment.text, isFinal: segment.isFinal,
                                                  start: offset + segment.start, end: offset + segment.end,
                                                  speakerName: "Microphone")
                    if timed.isFinal {
                        self.segments.append(timed)
                        self.partial = nil
                        self.save(announce: false)
                    } else {
                        self.partial = timed.text.isEmpty ? nil : timed
                    }
                } onFailure: { [weak self] error in
                    guard let self, self.state == .recording || self.state == .preparing else { return }
                    self.message = error
                    Task { await self.stop() }
                }
                try Task.checkCancellation()
                state = .recording
                UIApplication.shared.isIdleTimerDisabled = true
            } catch {
                try? await recorder.stop()
                self.recorder = nil
                state = .idle
                if !(error is CancellationError) { message = error.localizedDescription }
                save(announce: false)
            }
            startTask = nil
        }
    }

    func stop() async {
        guard state == .recording else {
            if state == .preparing { startTask?.cancel(); await startTask?.value }
            return
        }
        state = .stopping
        do { try await recorder?.stop() } catch { message = "Could not finalize transcript: \(error.localizedDescription)" }
        recorder = nil
        UIApplication.shared.isIdleTimerDisabled = false
        state = .idle
        save(announce: false)
    }

    func background() async {
        summaryTask?.cancel()
        let token = UIApplication.shared.beginBackgroundTask(withName: "Save conversation")
        defer { if token != .invalid { UIApplication.shared.endBackgroundTask(token) } }
        await stop()
        save(announce: false)
    }

    @discardableResult
    func save(announce: Bool = true) -> Bool {
        let record = SessionRecord(id: id, title: title, date: date,
                                   transcript: allSegments.map { "Microphone: \($0.text)" }.joined(separator: "\n"),
                                   summary: summary, segments: allSegments, notes: notes,
                                   quickSuggestion: quickSummary, deepAnswer: deepThought,
                                   isComplete: state == .idle && allSegments.allSatisfy(\.isFinal),
                                   attachments: attachments, sourceImportID: sourceImportID)
        do {
            if hasContent || history.contains(where: { $0.id == id }) { try archive.save(record) }
            try FileManager.default.createDirectory(at: activeURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(record).write(to: activeURL, options: .atomic)
            refreshHistory()
            if announce { message = "Conversation saved on this device." }
            return true
        } catch {
            message = "Could not save conversation: \(error.localizedDescription). Your text is still here; try Save again."
            return false
        }
    }

    func newConversation() {
        guard !busy, save(announce: false) else { return }
        id = UUID().uuidString; date = Date()
        title = "New conversation"; notes = ""; summary = ""; quickSummary = ""; deepThought = ""
        segments = []; partial = nil; message = nil; attachments = []; sourceImportID = nil; lastAutoSource = ""
        save(announce: false)
    }

    func open(_ record: SessionRecord) {
        guard !busy, save(announce: false) else { return }
        restore(record)
        save(announce: false)
    }

    func deleteConversation(id targetID: String) {
        guard !busy else { return }
        let deletingActive = targetID == id
        var committed = false
        do {
            // Persist an empty active snapshot first so a deleted session cannot return on relaunch.
            let empty = SessionRecord(id: UUID().uuidString, title: "New conversation", date: Date(),
                                      transcript: "", summary: "", segments: [], notes: "")
            if deletingActive {
                try FileManager.default.createDirectory(at: activeURL.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try JSONEncoder().encode(empty).write(to: activeURL, options: .atomic)
            }
            try archive.delete(id: targetID)
            committed = true
            if deletingActive { restore(empty) }
            refreshHistory()
            let files = attachmentStore(for: targetID).directory
            if FileManager.default.fileExists(atPath: files.path) { try FileManager.default.removeItem(at: files) }
            message = "Conversation and attachments deleted from this device."
        } catch {
            if deletingActive && !committed { save(announce: false) }
            message = "Could not delete conversation: \(error.localizedDescription)"
        }
    }

    private func restore(_ record: SessionRecord) {
        id = record.id; date = record.date; title = record.title
        notes = record.notes ?? ""; summary = record.summary
        quickSummary = record.quickSuggestion ?? ""; deepThought = record.deepAnswer ?? ""
        attachments = record.attachments ?? []; sourceImportID = record.sourceImportID; lastAutoSource = ""
        segments = record.segments ?? []; partial = nil; message = nil
    }

    func importSharedInbox(from inbox: URL? = nil) {
        guard !busy else { return }
        do {
            let root = try inbox ?? SharedInbox.root()
            for folder in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
                let manifest = folder.appendingPathComponent("manifest.json")
                guard FileManager.default.fileExists(atPath: manifest.path) else { continue }
                guard (try manifest.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) < 2 * 1024 * 1024 else {
                    throw CocoaError(.fileReadTooLarge)
                }
                let batch = try JSONDecoder().decode(SharedImport.self, from: Data(contentsOf: manifest))
                if history.contains(where: { $0.sourceImportID == batch.id }) {
                    try FileManager.default.removeItem(at: folder); continue
                }
                guard save(announce: false) else { return }
                let newID = UUID().uuidString
                let store = attachmentStore(for: newID)
                var imported: [SessionAttachment] = []
                var committed = false
                do {
                    guard batch.files.count <= 20, batch.text.count <= 100_000 else { throw CocoaError(.fileReadTooLarge) }
                    for file in batch.files {
                        guard !file.storedName.contains("/"), !file.storedName.contains("\\"),
                              file.storedName != "..", file.storedName != "." else { throw CocoaError(.fileReadInvalidFileName) }
                        let url = folder.appendingPathComponent(file.storedName)
                        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max)
                                <= SessionAttachmentStore.maximumBytes else { throw CocoaError(.fileReadTooLarge) }
                        let data = try Data(contentsOf: url)
                        imported.append(try store.add(data: data, name: file.name))
                    }
                    let record = SessionRecord(id: newID, title: "Imported notes", date: Date(), transcript: "",
                                               summary: "", segments: [], notes: batch.text,
                                               attachments: imported, sourceImportID: batch.id)
                    try archive.save(record)
                    committed = true
                    restore(record)
                    guard save(announce: false) else { return }
                    try FileManager.default.removeItem(at: folder)
                    message = "Shared content imported into a new conversation."
                } catch {
                    if !committed { try? FileManager.default.removeItem(at: store.directory) }
                    throw error
                }
            }
        } catch { message = "Could not import shared content: \(error.localizedDescription)" }
    }

    private func refreshHistory() {
        do { history = try archive.all() } catch { message = "Could not load history: \(error.localizedDescription)" }
    }

    func output(for mode: MobileSummaryMode) -> String {
        switch mode {
        case .summary: return summary
        case .quick: return quickSummary
        case .deep: return deepThought
        }
    }

    func requestSummary(for mode: MobileSummaryMode = .summary) {
        guard summaryTask == nil else { return }
        if let reason = summaryBlockReason(for: mode) { message = reason; return }
        summaryTask = Task { await summarize(mode: mode); summaryTask = nil }
    }

    func updateQuickAutomatically() async {
        guard autoQuick, state == .recording, !isSummarizing else { return }
        let source = summarySource
        guard source.count >= 80, source != lastAutoSource else { return }
        guard summaryBlockReason(for: .quick) == nil else { return }
        lastAutoSource = source
        requestSummary(for: .quick)
    }

    func cancelSummary() { summaryTask?.cancel() }

    func summarize(mode: MobileSummaryMode = .summary) async {
        if let reason = summaryBlockReason(for: mode) { message = reason; return }
        // Capture a stable input snapshot; recording can continue while this request runs.
        let source = summarySource
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "Add notes or record a transcript before summarizing."
            return
        }
        let cloud = ai.provider == .ollama
        guard source.count <= (cloud ? 60_000 : 8_000) else {
            message = "This conversation exceeds the selected provider's summary limit. Export it or shorten your notes."
            return
        }
        generatingMode = mode
        isSummarizing = true
        message = nil
        summaryDraft = ""
        defer { isSummarizing = false; summaryDraft = ""; generatingMode = nil }
        do {
            let instructions = mode.instructions
            if cloud {
                let client = try ai.client(for: mode)
                for try await delta in client.stream(LLMRequest(system: instructions,
                    messages: [ChatMessage(role: "user", content: source)])) {
                    try Task.checkCancellation()
                    summaryDraft += delta
                    guard summaryDraft.count <= 100_000 else { throw RecordingError.message("Summary response was too large.") }
                }
            } else {
                let model = LanguageModelSession(instructions: instructions)
                summaryDraft = try await model.respond(to: source).content
            }
            try Task.checkCancellation()
            switch mode {
            case .summary: summary = summaryDraft
            case .quick: quickSummary = summaryDraft
            case .deep: deepThought = summaryDraft
            }
            save(announce: false)
        } catch { message = "\(mode.title) failed: \(MobileAISettings.errorMessage(error)) Your previous summary is kept." }
    }
}
