import Foundation
import ListenToMeCore
import SwiftUI

/// What the iOS Summary, Quick and Deep panels say about their current text, beside it: which part
/// of the conversation a Quick/Deep answer read when it could not read all of it (issue #114), and
/// whether the answer stopped at the model's output limit (issue #215). Session-only, never saved.
struct MobileAnswerNotices: Equatable {
    private var grounding: [MobileSummaryMode: String] = [:]
    private var cutOff: Set<MobileSummaryMode> = []

    func lines(for mode: MobileSummaryMode) -> [String] {
        (grounding[mode].map { [$0] } ?? []) + (cutOff.contains(mode) ? [LLMOutputLimit.notice] : [])
    }

    /// A new answer replaced `mode`'s text; what was said about the previous one no longer applies.
    mutating func record(_ mode: MobileSummaryMode, grounding: String?, cutOff: Bool) {
        self.grounding[mode] = grounding
        if cutOff { self.cutOff.insert(mode) } else { self.cutOff.remove(mode) }
    }
}

/// The panel's one-line notes, above its text: "Using the last ~5 min of the conversation." and
/// "The answer was cut off at the model's output limit."
struct MobileAnswerNoticeLines: View {
    let session: MobileSession
    let mode: MobileSummaryMode

    var body: some View {
        ForEach(session.answerNotices.lines(for: mode), id: \.self) { line in
            Label(line, systemImage: line == LLMOutputLimit.notice ? "scissors" : "info.circle")
                .font(.caption).foregroundStyle(MobileStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(line == LLMOutputLimit.notice
                                         ? "outputLimitNotice-\(mode.rawValue)" : "groundingNotice-\(mode.rawValue)")
        }
    }
}

/// The manual Summary, Quick and Deep request. Kept out of MobileSession.swift, which sits at its
/// length limit.
extension MobileSession {
    /// A built request, and the panel line describing which part of the conversation it reads.
    struct AnswerRequest {
        let request: LLMRequest
        let grounding: String?
    }

    func summarize(mode: MobileSummaryMode = .summary) async {
        if let reason = summaryBlockReason(for: mode) { message = reason; return }
        // Capture a stable input snapshot; recording can continue while this request runs.
        let source = summarySource
        let reviewed = quickPieces
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "Add notes or record a transcript before summarizing."
            return
        }
        let cloud = summaryProvider != nil || ai.provider != .apple
        // Apple Intelligence's on-device model cannot be held to the evaluator's JSON envelope,
        // so manual Quick asks it for the bullets directly. See docs/IOS.md → Apple Intelligence.
        let proseQuick = mode == .quick && !cloud
        let built: AnswerRequest
        do {
            guard let request = try answerRequest(mode, source: source, cloud: cloud, proseQuick: proseQuick) else {
                message = "This conversation exceeds the selected provider's summary limit. "
                    + "Export it or shorten your notes."
                return
            }
            built = request
        } catch {
            message = "\(mode.title) failed: \(MobileAISettings.errorMessage(error)) Your previous summary is kept."
            return
        }
        generatingMode = mode
        isSummarizing = true
        if mode == .quick { manualQuickError = nil; quickReader.clearError() }
        message = nil
        summaryDraft = ""
        defer { isSummarizing = false; summaryDraft = ""; generatingMode = nil }
        do {
            // One transport per provider: the Apple path streams through AppleIntelligenceProvider,
            // which maps FoundationModels generation failures to messages a user can act on.
            let client: any LLMProvider = try summaryProvider
                ?? (cloud ? ai.client(for: mode) : (onDeviceProviderOverride ?? AppleIntelligenceProvider()))
            let (quickResponse, cutOff) = try await streamAnswer(built.request, mode: mode, client: client)
            switch mode {
            case .summary: summary = summaryDraft
            case .quick: quickSummary = try Self.quickOutput(quickResponse, prose: proseQuick, cutOff: cutOff)
            case .deep: deepThought = summaryDraft
            }
            answerNotices.record(mode, grounding: built.grounding, cutOff: cutOff)
            if let reviewMode = AutomaticReviewMode(rawValue: mode.rawValue) {
                automaticReviews.markManualCompletion(reviewMode, source: source)
            }
            if MobileQuickContext.isContinuation(of: reviewed, in: quickPieces) {
                quickReader.markReviewed(mode.rawValue)
            }
            save(announce: false)
        } catch {
            let failure = "\(mode.title) failed: \(MobileAISettings.errorMessage(error)) Your previous summary is kept."
            message = failure
            if mode == .quick { manualQuickError = failure }
        }
    }

    /// The request for `mode`, or nil when a Summary does not fit the provider.
    ///
    /// Summary covers the whole conversation, so one that does not fit is refused. Quick and Deep
    /// answer from what fits instead: the Summary already written plus the latest speech, or the
    /// opening plus the latest speech, and the panel says which (issue #114).
    private func answerRequest(_ mode: MobileSummaryMode, source: String, cloud: Bool,
                               proseQuick: Bool) throws -> AnswerRequest? {
        if mode == .summary {
            // The transcript is fenced as data, exactly as the macOS panes fence it (issue #140); the
            // cap is charged on the fenced text so the Apple window still holds (PromptBudget).
            let fencedSource = PromptData.block("transcript", source)
            let limit = cloud ? OnDemandGrounding.oneShotCharacters : PromptBudget.appleIntelligenceCharacters
            guard fencedSource.count <= limit else { return nil }
            return AnswerRequest(request: LLMRequest(system: mode.instructions,
                                                     messages: [ChatMessage(role: "user", content: fencedSource)]),
                                 grounding: nil)
        }
        let system = proseQuick ? MobileQuickContext.manualProseInstructions
            : (mode == .quick ? MobileQuickContext.instructions : mode.instructions)
        let excerpt = OnDemandGrounding.excerpt(
            notes: notes, segments: allSegments.map(Self.promptSegment), summary: summary,
            budget: OnDemandGrounding.oneShotBudget(window: cloud ? nil : PromptBudget.appleIntelligenceCharacters,
                                                    system: system))
        let grounding = excerpt.notice(summaryName: "your Summary")
        if mode == .quick && !proseQuick {
            return AnswerRequest(request: try MobileQuickContext.manualRequest(
                source: excerpt.transcript, runningContext: excerpt.summary ?? ""), grounding: grounding)
        }
        return AnswerRequest(request: LLMRequest(system: system,
                                                 messages: [ChatMessage(role: "user", content: excerpt.userMessage)]),
                             grounding: grounding)
    }

    /// Streams the answer: Summary and Deep into `summaryDraft`, Quick into the returned text. The
    /// flag is true when the model stopped at its output limit; the text so far is kept (#215).
    private func streamAnswer(_ request: LLMRequest, mode: MobileSummaryMode,
                              client: any LLMProvider) async throws -> (String, Bool) {
        var quickResponse = ""
        var cutOff = false
        for try await event in client.streamEvents(request) {
            try Task.checkCancellation()
            switch event {
            case .content(let delta): if mode == .quick { quickResponse += delta } else { summaryDraft += delta }
            case .thinking: break
            case .outputLimitReached: cutOff = true
            }
            guard summaryDraft.count <= 100_000, quickResponse.utf8.count <= 16_384 else {
                throw RecordingError.message("Summary response was too large.")
            }
        }
        try Task.checkCancellation()
        return (quickResponse, cutOff)
    }

    /// The Quick panel's bullets. A JSON evaluation that stopped at the output limit is unreadable
    /// JSON, so that failure is reported as the cut-off it is rather than as a parse error.
    static func quickOutput(_ response: String, prose: Bool, cutOff: Bool) throws -> String {
        if prose { return MobileQuickContext.proseSummary(response) ?? "No key takeaway yet." }
        do {
            return try QuickSummaryDecision.parse(response).summary ?? "No key takeaway yet."
        } catch {
            if cutOff { throw LLMOutputLimitError() }
            throw error
        }
    }
}
