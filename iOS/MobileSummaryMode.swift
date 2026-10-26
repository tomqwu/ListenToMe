import Foundation
import ListenToMeCore

/// The iOS answer panes: Summary and Quick Summary. iOS has no Deep pane (issue #235); Deep stays on
/// macOS, and a saved conversation's earlier Deep analysis is kept read-only (`earlierDeepAnalysis`).
enum MobileSummaryMode: String, CaseIterable, Identifiable {
    case summary, quick
    var id: String { rawValue }
    var title: String {
        switch self {
        case .summary: return "Summary"
        case .quick: return "Quick Summary"
        }
    }
    /// Core owns manual-summary grounding and output constraints; this adapter owns UI labels.
    var instructions: String { PromptBuilder.summaryInstructions(for: self == .summary ? .summary : .quick) }
}
