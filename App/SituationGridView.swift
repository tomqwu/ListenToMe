import SwiftUI
import ListenToMeCore

struct SituationGridView: View {
    let grid: SituationGrid
    let segments: [TranscriptSegment]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(grid.summary).textSelection(.enabled)
            section("Open", items: grid.open, icon: "questionmark.circle")
            section("To-do", items: grid.todo, icon: "checklist")
            section("Decided", items: grid.decided, icon: "checkmark.seal")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Theme.ink)
    }

    private func section(_ title: String, items: [SituationGrid.Item], icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.headline)
            if items.isEmpty { Text("None stated.").foregroundStyle(Theme.ink2) }
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.text).textSelection(.enabled)
                    if let owner = item.owner { Text("Owner: \(owner)").font(.caption) }
                    if let deadline = item.deadline { Text("Deadline: \(deadline)").font(.caption) }
                    DisclosureGroup("Sources") {
                        ForEach(Array(item.quotes.enumerated()), id: \.offset) { _, quote in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("“\(quote)”").textSelection(.enabled)
                                // Ambiguous repeated wording lists every matching line instead of guessing.
                                ForEach(segments.filter { $0.isFinal && $0.text.contains(quote) }) { segment in
                                    Text(TranscriptTimestamp.isTimed(segment)
                                         ? "\(segment.speakerLabel) · \(TranscriptTimestamp.clock(segment.start))"
                                         : segment.speakerLabel)
                                        .font(.caption).foregroundStyle(Theme.ink2)
                                }
                            }
                        }
                    }
                    .font(.caption)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}
