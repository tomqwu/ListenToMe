import Foundation

struct SituationGridCache {
    let grid: SituationGrid
    let revision: Int
    let valid: Bool
    let markdown: String
}

extension MeetingSession {
    var structuredSummaryGuidance: String? {
        VocabularyPrompt.combined(persona: summaryGuidance,
                                  guidance: structuredListenerEnabled ? SituationGrid.instructions : nil)
    }

    func normalizeCompletedSituation(_ role: CopilotRole) {
        if role == .listener { setOutput(role, finishSituationGrid(listenerSummary)) }
    }

    func finishSituationGrid(_ output: String) -> String {
        guard structuredListenerEnabled else { listenerSituation = nil; return output }
        let grid = SituationGrid.decode(output, segments: store.utterances)
        listenerSituation = grid
        return grid?.markdown ?? output
    }

    /// Revalidate sources on display after a transcript edit; stale references never appear as verified.
    public var visibleSituation: SituationGrid? {
        guard let grid = listenerSituation else { return nil }
        if situationCache?.grid != grid || situationCache?.revision != store.revision {
            situationCache = SituationGridCache(grid: grid, revision: store.revision,
                valid: grid.isValid(segments: store.utterances), markdown: grid.markdown)
        }
        guard situationCache?.valid == true, situationCache?.markdown == listenerSummary else { return nil }
        return grid
    }
}
