import ListenToMeCore

typealias MobileQuickReader = QuickSummaryReader
typealias MobileQuickDecision = QuickSummaryDecision

extension QuickSummaryReader {
    func markReviewed(_ mode: MobileSummaryMode) { markReviewed(mode.rawValue) }
}
