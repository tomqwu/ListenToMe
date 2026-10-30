import SwiftUI

/// Shared actual Refresh action; reload changes only the archive snapshot read by the index owner.
struct HistoryRefreshControl: View {
    @Bindable var search: HistorySearchModel
    let reload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(search.isRefreshing ? "Refreshing search…" : "Refresh search", systemImage: "arrow.clockwise") {
                reload()
                search.refreshLocalModels()
            }
            .buttonStyle(.borderless)
            .disabled(search.isRefreshing)
            .accessibilityIdentifier("history-refresh")
            if let issue = search.refreshIssue {
                Text(issue).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("history-refresh-issue")
            }
        }
    }
}
