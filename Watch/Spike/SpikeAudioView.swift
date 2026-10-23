import AVFoundation
import Foundation
import Observation
import SwiftUI
import WatchConnectivity
import WatchKit

/// SPIKE ONLY: issue #181, plan Task 15. Never merged. See SPIKE.md at the repo root of the branch.
///
/// Every reading shown here is also appended to `Documents/spike-log.csv` on the watch, so the
/// numbers survive the screen sleeping and can be pulled with Xcode's container download.
@MainActor @Observable
final class SpikeAudioModel {
    private(set) var isRecording = false
    private(set) var startedAt: Date?
    private(set) var stoppedAt: Date?
    private(set) var batteryAtStart: Float?
    private(set) var chunkCount = 0
    private(set) var lastChunk: SpikeAudioRecorder.Chunk?
    private(set) var freeCapacity: Int?
    private(set) var systemFreeSize: Int64?
    private(set) var controlFileProtection = "not checked"
    private(set) var lastEvent = ""
    private(set) var transferLine = "No transfer yet"
    @ObservationIgnored private var recorder: SpikeAudioRecorder?
    @ObservationIgnored private var transferSentAt: [String: Date] = [:]
    @ObservationIgnored private let logURL: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        logURL = documents.appendingPathComponent("spike-log.csv")
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
    }

    var battery: Float { WKInterfaceDevice.current().batteryLevel }

    func start() async {
        guard !isRecording else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            note("Microphone permission denied")
            return
        }
        let recorder = SpikeAudioRecorder()
        recorder.onChunkFinalized = { [weak self] chunk in
            Task { @MainActor in self?.chunkFinalized(chunk) }
        }
        recorder.onEvent = { [weak self] text in
            Task { @MainActor in self?.note(text) }
        }
        do {
            try recorder.start()
        } catch {
            note("Start failed: \(error.localizedDescription)")
            return
        }
        self.recorder = recorder
        isRecording = true
        startedAt = Date()
        stoppedAt = nil
        batteryAtStart = battery
        chunkCount = 0
        refreshStorage()
        log("start", chunk: nil)
        WKInterfaceDevice.current().play(.start)
    }

    func stop() {
        guard isRecording, let recorder else { return }
        recorder.stop()
        self.recorder = nil
        isRecording = false
        stoppedAt = Date()
        log("stop", chunk: nil)
        WKInterfaceDevice.current().play(.stop)
    }

    /// U4: free space as Task 17 will read it (F18), plus `systemFreeSize` for comparison, and a
    /// control file written with `.completeFileProtectionUntilFirstUserAuthentication`.
    func refreshStorage() {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        freeCapacity = (try? home.resourceValues(forKeys: [.volumeAvailableCapacityKey]))?.volumeAvailableCapacity
        let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        systemFreeSize = (attributes?[.systemFreeSize] as? NSNumber)?.int64Value
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let control = documents.appendingPathComponent("protection-control.txt")
        do {
            try Data("U4 control".utf8).write(to: control, options: .completeFileProtectionUntilFirstUserAuthentication)
            controlFileProtection = SpikeAudioRecorder.protection(of: control)
        } catch {
            controlFileProtection = "write failed: \(error.localizedDescription)"
        }
    }

    // MARK: Transfer (U2)

    func sendLastChunk() {
        guard let chunk = lastChunk else {
            transferLine = "No finalized chunk yet"
            return
        }
        let session = WCSession.default
        guard session.activationState == .activated else {
            transferLine = "WCSession not activated"
            return
        }
        let sentAt = Date()
        transferSentAt[chunk.url.lastPathComponent] = sentAt
        session.transferFile(chunk.url, metadata: [
            "spike181": true,
            "name": chunk.url.lastPathComponent,
            "bytes": chunk.bytes,
            "seconds": chunk.seconds,
            "sentAt": sentAt.timeIntervalSince1970,
        ])
        transferLine = "Sending \(chunk.url.lastPathComponent)…"
        log("transfer-sent", chunk: chunk)
    }

    /// Called by `WatchLinkClient` from `session(_:didFinish:error:)`.
    func transferFinished(fileName: String, error: String?) {
        let seconds = transferSentAt.removeValue(forKey: fileName).map { Date().timeIntervalSince($0) }
        let duration = seconds.map { String(format: "%.1f s", $0) } ?? "unknown"
        transferLine = error.map { "Transfer failed after \(duration): \($0)" }
            ?? "Delivered in \(duration) (watch clock)"
        appendLog("transfer-finished,\(fileName),\(seconds.map { String(format: "%.1f", $0) } ?? ""),\(error ?? "ok")")
    }

    // MARK: Private

    private func chunkFinalized(_ chunk: SpikeAudioRecorder.Chunk) {
        chunkCount += 1
        lastChunk = chunk
        refreshStorage()
        log("chunk", chunk: chunk)
    }

    private func note(_ text: String) {
        lastEvent = text
        appendLog("event,\(text.replacingOccurrences(of: ",", with: ";"))")
    }

    /// Columns: time, kind, elapsed s, battery, free bytes, chunk file, chunk s, chunk bytes,
    /// protection at create, protection after close.
    private func log(_ kind: String, chunk: SpikeAudioRecorder.Chunk?) {
        let elapsed = startedAt.map { String(format: "%.0f", Date().timeIntervalSince($0)) } ?? ""
        let fields: [String] = [
            kind, elapsed, String(format: "%.2f", battery), freeCapacity.map(String.init) ?? "",
            chunk?.url.lastPathComponent ?? "", chunk.map { String(format: "%.1f", $0.seconds) } ?? "",
            chunk.map { String($0.bytes) } ?? "", chunk?.protectionAtCreate ?? "", chunk?.protectionAfterClose ?? "",
        ]
        appendLog(fields.joined(separator: ","))
    }

    private func appendLog(_ line: String) {
        let row = ISO8601DateFormatter().string(from: Date()) + "," + line + "\n"
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(Data(row.utf8))
            try? handle.close()
        } else {
            let header = "time,kind,elapsedSeconds,battery,freeBytes,chunk,chunkSeconds,chunkBytes,"
                + "protectionAtCreate,protectionAfterClose\n"
            try? Data((header + row).utf8).write(to: logURL)
        }
    }
}

/// SPIKE ONLY: the debug screen reached from "DEBUG: Task 15 audio spike" on the watch.
struct SpikeAudioView: View {
    let model: SpikeAudioModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Button(model.isRecording ? "Stop" : "Start") {
                        if model.isRecording { model.stop() } else { Task { await model.start() } }
                    }
                    .tint(model.isRecording ? .red : .green)

                    row("Elapsed", elapsed(at: context.date))
                    row("Chunks", "\(model.chunkCount)")
                    row("Last chunk", model.lastChunk.map {
                        "#\($0.index) \(String(format: "%.0f", $0.seconds)) s, \($0.bytes) B"
                    } ?? "none")
                    row("Prot. create", model.lastChunk?.protectionAtCreate ?? "–")
                    row("Prot. closed", model.lastChunk?.protectionAfterClose ?? "–")
                    row("Prot. control", model.controlFileProtection)
                    row("Free (volCap)", model.freeCapacity.map(megabytes) ?? "unknown")
                    row("Free (sysFree)", model.systemFreeSize.map { megabytes(Int($0)) } ?? "unknown")
                    row("Battery", batteryLine)
                    if !model.lastEvent.isEmpty { row("Event", model.lastEvent) }

                    Button("Send last chunk to iPhone") { model.sendLastChunk() }
                        .disabled(model.lastChunk == nil)
                    Text(model.transferLine).font(.footnote)
                    Button("Refresh storage") { model.refreshStorage() }
                }
            }
        }
        .navigationTitle("Spike #181")
        .onAppear { model.refreshStorage() }
    }

    private var batteryLine: String {
        let now = model.battery
        guard now >= 0 else { return "unknown" }
        let current = String(format: "%.0f%%", now * 100)
        guard let start = model.batteryAtStart, start >= 0 else { return current }
        return current + String(format: " (start %.0f%%)", start * 100)
    }

    private func elapsed(at date: Date) -> String {
        guard let startedAt = model.startedAt else { return "–" }
        let seconds = Int((model.stoppedAt ?? date).timeIntervalSince(startedAt))
        return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }

    private func megabytes(_ bytes: Int) -> String {
        String(format: "%.0f MB (%d B)", Double(bytes) / 1_000_000, bytes)
    }

    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.footnote)
        }
    }
}
