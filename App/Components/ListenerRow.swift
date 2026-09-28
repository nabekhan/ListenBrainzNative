import SwiftUI

/// A compact, non-interactive listener identity row. Parents decide whether a
/// row navigates, so retrospective surfaces never trigger social requests just
/// by rendering.
struct ListenerRow: View {
    let user: SearchUser
    var similarity: Double?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        UserAvatar(username: user.username, size: 42)
                        Text(user.username)
                            .font(.body.weight(.semibold))
                            .lineLimit(2)
                    }
                    similarityLabel
                        .padding(.leading, 54)
                }
            } else {
                HStack(spacing: 12) {
                    UserAvatar(username: user.username, size: 42)
                    Text(user.username)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    similarityLabel
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var similarityLabel: some View {
        if let similarity {
            Text(similarity, format: .percent.precision(.fractionLength(0)))
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(similarity.formatted(.percent)) similar")
        }
    }
}
