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
    var segments: [TranscriptSegment] = []
    var partial: TranscriptSegment?
    var history: [SessionRecord] = []
    var message: String?
    var isSummarizing = false
    let ai = MobileAISettings()
    var summaryDraft = ""
    private var summaryTask: Task<Void, Never>?
    var language = Locale.current.identifier
    private var id = UUID().uuidString
    private var date = Date()
    private var recorder: MobileRecorder?
    private var startTask: Task<Void, Never>?
    private let archive: SessionArchive
    private let activeURL: URL

    init(storageDirectory: URL = .applicationSupportDirectory) {
        activeURL = storageDirectory.appendingPathComponent("ActiveConversation.json")
        let directory = storageDirectory.appendingPathComponent("Conversations", isDirectory: true)
        archive = SessionArchive(directory: directory)
        refreshHistory()
        if FileManager.default.fileExists(atPath: activeURL.path) {
            do { restore(try JSONDecoder().decode(SessionRecord.self, from: Data(contentsOf: activeURL))) }
            catch { message = "Could not restore the current conversation: \(error.localizedDescription). Check History." }
        } else if let latest = history.first { restore(latest) }
    }

    var busy: Bool { state != .idle || isSummarizing }
    var hasContent: Bool { !segments.isEmpty || partial != nil || !notes.isEmpty || !summary.isEmpty || !quickSummary.isEmpty || !deepThought.isEmpty }
    var allSegments: [TranscriptSegment] { segments + (partial.map { [$0] } ?? []) }
    var markdown: String {
        SessionExporter.markdown(title: title, transcript: allSegments, notes: notes, listenerSummary: summary,
                                 quickSuggestion: quickSummary, deepAnswer: deepThought)
    }
    var summaryAvailability: String? { summaryAvailability(for: .summary) }
    func summaryAvailability(for mode: MobileSummaryMode) -> String? {
        if ai.provider == .ollama { return ai.availability(for: mode) }
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.deviceNotEligible): return "On-device summaries require an Apple Intelligence capable device."
        case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in Settings to use on-device summaries."
        case .unavailable(.modelNotReady): return "Apple Intelligence is downloading its model. Try again when it is ready."
        default: return "On-device summaries are unavailable on this device."
        }
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
                                   isComplete: state == .idle && allSegments.allSatisfy(\.isFinal))
        do {
            if hasContent { try archive.save(record) }
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
        segments = []; partial = nil; message = nil
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
            if deletingActive { restore(empty) }
            refreshHistory()
            message = "Conversation deleted from this device."
        } catch {
            if deletingActive { save(announce: false) }
            message = "Could not delete conversation: \(error.localizedDescription)"
        }
    }

    private func restore(_ record: SessionRecord) {
        id = record.id; date = record.date; title = record.title
        notes = record.notes ?? ""; summary = record.summary
        quickSummary = record.quickSuggestion ?? ""; deepThought = record.deepAnswer ?? ""
        segments = record.segments ?? []; partial = nil; message = nil
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
        guard !busy else { return }
        summaryTask = Task { await summarize(mode: mode); summaryTask = nil }
    }

    func cancelSummary() { summaryTask?.cancel() }

    func summarize(mode: MobileSummaryMode = .summary) async {
        guard !busy, hasContent else { return }
        if let reason = summaryAvailability(for: mode) { message = reason; return }
        let source = notes + "\n" + allSegments.map(\.text).joined(separator: "\n")
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "Add notes or record a transcript before summarizing."
            return
        }
        let cloud = ai.provider == .ollama
        guard source.count <= (cloud ? 60_000 : 8_000) else {
            message = "This conversation exceeds the selected provider's summary limit. Export it or shorten your notes."
            return
        }
        isSummarizing = true
        message = nil
        summaryDraft = ""
        defer { isSummarizing = false; summaryDraft = "" }
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
