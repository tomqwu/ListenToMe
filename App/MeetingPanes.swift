import SwiftUI

// MARK: - Shared pane chrome

/// A gently pulsing red dot used as the live-recording indicator.
struct RecordingIndicator: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 10, height: 10)
            .opacity(pulsing ? 0.35 : 1)
            .scaleEffect(pulsing ? 0.8 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
            .accessibilityLabel("Recording")
    }
}

/// Centered placeholder shown when a pane has no content: a subtle SF Symbol over secondary text.
struct PaneEmptyState: View {
    let systemImage: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
