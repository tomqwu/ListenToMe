import SwiftUI

/// Optional workspace controls stay reachable without competing with the transcript.
struct MacWorkspaceSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(title, isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 14) { content() }
                .padding(.top, 8)
        }
        .font(.callout)
        .foregroundStyle(Theme.ink)
    }
}
