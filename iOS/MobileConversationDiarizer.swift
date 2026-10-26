import FluidAudio
import Foundation
import ListenToMeCore

/// Per-recording end-to-end voice state. Only unseen audio enters the model; overlap is returned
/// for alignment without being fed twice. File/Watch analysis keeps its separate prepared pipeline.
actor MobileConversationDiarizer: MobileSpeakerDiarizing {
    private static let sampleRate = 16_000
    nonisolated var requiresFinalFlush: Bool { true }

    /// All mutable third-party operations run inside the actor's serial chain, including awaits
    /// during preparation. The loaded weights are reusable; each recording owns separate state.
    private final class ModelBox: @unchecked Sendable {
        let model: LSEENDDiarizer
        init() {
            var config = DiarizerTimelineConfig.default(numSpeakers: 10, frameDurationSeconds: 0.1)
            config.maxStoredFrames = 6_000
            // Cover the model's 100 ms frame boundary and brief low-confidence speech edges.
            // Clip padding to captured/confirmed time when exposing the resulting segments.
            config.onsetPadSeconds = 0.2
            config.offsetPadSeconds = 0.2
            model = LSEENDDiarizer(timelineConfig: config)
        }
        func prepare() async throws {
            try await model.initialize(variant: .dihard2, stepSize: .step500ms)
        }
        func reset() { model.reset() }
    }

    private let box = ModelBox()
    private let fileModel: any MobileSpeakerDiarizing
    private var prepared = false
    private var modelFailure: String?
    private var tail: Task<Void, Never>?
    private var activeRun: Int?
    private var newestRun = Int.min
    private var closedThrough = Int.min
    private var scope: String?
    private var baseSample = 0
    private var processedSamples = 0
    private var finalized = false

    init(fileModel: any MobileSpeakerDiarizing = SpeakerDiarizer()) { self.fileModel = fileModel }

    var retainedPredictionFrames: Int {
        box.model.timeline.finalizedPredictions.count / box.model.timeline.speakerCapacity
    }

    nonisolated static func excludingModelsFromBackup() -> MobileConversationDiarizer {
        let directory = OfflineDiarizerModels.defaultModelsDirectory()
        try? PrivateStorage.createDirectory(at: directory)
        try? PrivateStorage.setExcludedFromBackup(true, at: directory)
        return MobileConversationDiarizer()
    }

    func retryModelLoad() async {
        modelFailure = nil
        await fileModel.retryModelLoad()
    }

    func prepareModels() async throws {
        let previous = tail
        let work = Task {
            await previous?.value
            try Task.checkCancellation()
            try await self.loadModelsIfNeeded()
        }
        tail = Task { _ = try? await work.value }
        try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }

    /// An import may use weights already prepared in the foreground, but cannot download them or
    /// mutate the live stream's state. MobileSpeakers additionally enforces its enabled/ready gates.
    func diarize(samples: [Float]) async throws -> DiarizedWindow {
        let previous = tail
        let work = Task {
            await previous?.value
            try Task.checkCancellation()
            guard self.prepared else {
                throw SpeakerDiarizer.DiarizationError.modelsUnavailable("Prepare speaker models in the foreground first.")
            }
            return try await self.fileModel.diarize(samples: samples)
        }
        tail = Task { _ = try? await work.value }
        return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }

    func diarizeLive(samples: [Float], startingAtSample: Int, runToken: Int, final: Bool) async throws -> DiarizedWindow {
        let (end, overflow) = startingAtSample.addingReportingOverflow(samples.count)
        guard startingAtSample >= 0, !overflow, samples.count >= Self.sampleRate * 3,
              samples.allSatisfy(\.isFinite) else { throw SpeakerDiarizer.DiarizationError.notEnoughAudio }
        try validate(runToken)
        let previous = tail
        let work = Task {
            await previous?.value
            try Task.checkCancellation()
            try self.validate(runToken)
            try await self.loadModelsIfNeeded()
            try Task.checkCancellation()
            try self.validate(runToken)
            return try self.process(samples, from: startingAtSample, through: end, token: runToken, final: final)
        }
        tail = Task { _ = try? await work.value }
        return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }

    /// Fence queued work immediately. Cleanup itself waits for outstanding inference and never
    /// resets a newer run that reached the model before this delayed cleanup task.
    func endRun(token: Int) async {
        closedThrough = max(closedThrough, token)
        let previous = tail
        let work = Task {
            await previous?.value
            if self.activeRun == token { self.resetStream() }
        }
        tail = Task { await work.value }
        await work.value
    }

    private func validate(_ token: Int) throws {
        guard token > closedThrough, token >= newestRun else { throw CancellationError() }
    }

    private func process(_ samples: [Float], from start: Int, through end: Int,
                         token: Int, final: Bool) throws -> DiarizedWindow {
        // Reject before gap recovery: resetting a finalized run would otherwise reopen it under
        // the same token and give late producer callbacks a new identity epoch.
        if activeRun == token, finalized, end > processedSamples { throw CancellationError() }
        if activeRun != token || start > processedSamples {
            resetStream()
            activeRun = token
            newestRun = max(newestRun, token)
            scope = UUID().uuidString
            baseSample = start
            processedSamples = start
        }
        do {
            if end > processedSamples {
                try box.model.addAudio(samples.dropFirst(processedSamples - start), sourceSampleRate: Double(Self.sampleRate))
                processedSamples = end
            }
            if final && !finalized {
                _ = try box.model.finalizeSession()
                finalized = true
            } else if !finalized {
                _ = try box.model.process()
            }
            return result(from: start, through: end)
        } catch {
            resetStream()
            throw error
        }
    }

    private func result(from start: Int, through end: Int) -> DiarizedWindow {
        let rate = Double(Self.sampleRate)
        let frameSeconds = 1 / (box.model.modelFrameHz ?? 10)
        let windowStart = Double(start) / rate
        let windowEnd = Double(end) / rate
        let modelBase = Double(baseSample) / rate
        let confirmedEnd = min(windowEnd, modelBase + Double(box.model.numFramesProcessed) * frameSeconds)
        // An open speech segment is a preview even when its frames are committed. Include that
        // preview only through confirmed model time; keep right-context audio outside authority.
        let segments = box.model.timeline.speakers.values.flatMap { $0.finalizedSegments + $0.tentativeSegments }
            .compactMap { segment -> DiarizedSegment? in
                let lower = max(windowStart, modelBase + Double(segment.startFrame) * frameSeconds)
                let upper = min(confirmedEnd, modelBase + Double(segment.endFrame) * frameSeconds)
                guard upper > lower else { return nil }
                return DiarizedSegment(speakerId: "voice-\(segment.speakerIndex)", start: lower - windowStart,
                                        duration: upper - lower)
            }.sorted { $0.start == $1.start ? $0.speakerId < $1.speakerId : $0.start < $1.start }
        return DiarizedWindow(segments: segments, stableSpeakerIDScope: scope,
                              analyzedThrough: max(0, confirmedEnd - windowStart))
    }

    private func resetStream() {
        box.reset()
        activeRun = nil
        scope = nil
        baseSample = 0
        processedSamples = 0
        finalized = false
    }

    private func loadModelsIfNeeded() async throws {
        if let modelFailure { throw SpeakerDiarizer.DiarizationError.modelsUnavailable(modelFailure) }
        guard !prepared else { return }
        do {
            try await box.prepare()
            try Task.checkCancellation()
            try await fileModel.prepareModels()
            prepared = true
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            modelFailure = error.localizedDescription
            throw SpeakerDiarizer.DiarizationError.modelsUnavailable(error.localizedDescription)
        }
    }
}
