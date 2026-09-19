import SwiftUI

private struct CritiqueBrainzReviewsProviderEnvironmentKey: EnvironmentKey {
    static let defaultValue: any CritiqueBrainzReviewsProviding = CritiqueBrainzReviewsProvider()
}

extension EnvironmentValues {
    var critiqueBrainzReviewsProvider: any CritiqueBrainzReviewsProviding {
        get { self[CritiqueBrainzReviewsProviderEnvironmentKey.self] }
        set { self[CritiqueBrainzReviewsProviderEnvironmentKey.self] = newValue }
    }
}

/// Published CritiqueBrainz review highlights for one canonical entity.
struct CritiqueBrainzReviewSummaryView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.critiqueBrainzReviewsProvider) private var provider
    @State private var model: CritiqueBrainzReviewModel?
    @State private var retryTask: Task<Void, Never>?

    let entity: CritiqueBrainzEntity

    var body: some View {
        Group {
            switch model?.phase ?? .idle {
            case .idle, .loading: loadingCard
            case let .loaded(summary): loadedCard(summary)
            case .unavailable: EmptyView()
            case .failed: failureCard
            }
        }
        .task(id: entity) {
            let current = CritiqueBrainzReviewModel(entity: entity, provider: provider)
            model = current
            await current.load()
        }
        .onDisappear {
            retryTask?.cancel()
            retryTask = nil
        }
    }

    private var loadingCard: some View {
        card {
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 2) {
                    Text("CritiqueBrainz reviews").font(.headline)
                    Text("Loading published reviews…").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func loadedCard(_ summary: CritiqueBrainzReviewSummary) -> some View {
        card {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CRITIQUEBRAINZ REVIEWS").font(.caption.bold()).foregroundStyle(.secondary)
                    if let rating = summary.averageRating, let count = summary.ratingCount {
                        Label(averageRatingLabel(rating, count: count), systemImage: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Average CritiqueBrainz rating: \(rating.formatted(.number.precision(.fractionLength(1)))) out of 5, from \(count) \(count == 1 ? "rating" : "ratings")")
                    } else {
                        Text("Published community reviews").font(.caption).foregroundStyle(.secondary)
                    }
                }

                if model?.refreshMessage != nil {
                    Label("Couldn’t refresh. Showing saved reviews.", systemImage: "clock.arrow.circlepath")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityLabel("Couldn’t refresh CritiqueBrainz reviews. Showing saved reviews.")
                }

                ForEach(summary.reviews.prefix(3)) { review in
                    CritiqueBrainzReviewCard(review: review, truncatesText: true)
                }

                if !summary.reviews.isEmpty {
                    NavigationLink {
                        CritiqueBrainzReviewReaderView(summary: summary)
                    } label: {
                        Label(
                            summary.reviews.count == 1 ? "Read this review" : "Read these reviews",
                            systemImage: "text.page"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                }

                Link(destination: summary.entity.browseURL) {
                    Label("View on CritiqueBrainz", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Opens this entity’s CritiqueBrainz page")
            }
        }
    }

    private var failureCard: some View {
        card {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "text.badge.xmark").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reviews couldn’t load").font(.subheadline.weight(.semibold))
                    Text("CritiqueBrainz couldn’t load reviews. Try again in a moment.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Try again") {
                    retryTask?.cancel()
                    retryTask = Task { await model?.retry() }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func averageRatingLabel(_ rating: Double, count: Int) -> String {
        "\(rating.formatted(.number.precision(.fractionLength(1)))) out of 5 · \(count.formatted()) \(count == 1 ? "rating" : "ratings")"
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
    }
}

/// A local, value-only reader for the short review page already loaded by the
/// summary card. It intentionally has no provider or task of its own.
struct CritiqueBrainzReviewReaderView: View {
    let summary: CritiqueBrainzReviewSummary

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Text("Published reviews from CritiqueBrainz")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(summary.reviews) { review in
                    CritiqueBrainzReviewCard(review: review, truncatesText: false)
                }

                Link(destination: summary.entity.browseURL) {
                    Label("View on CritiqueBrainz", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Opens this entity’s CritiqueBrainz page")
                .padding(.top, 2)
            }
            .padding(20)
        }
        .navigationTitle("CritiqueBrainz reviews")
        .navigationBarTitleDisplayMode(.inline)
    }

}

private struct CritiqueBrainzReviewCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let review: CritiqueBrainzReview
    let truncatesText: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(review.author ?? "CritiqueBrainz member")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    if let publishedAt = review.publishedAt {
                        Text(publishedAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 6)
                if let rating = review.rating {
                    Label("\(rating) out of 5", systemImage: "star.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityLabel("Rating \(rating) out of 5")
                }
            }
            if let text = review.text {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(truncatesText ? .secondary : .primary)
                    .lineLimit(truncatesText ? (dynamicTypeSize.isAccessibilitySize ? 8 : 4) : nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                if let license = review.licenseID, let url = review.licenseURL {
                    Link(license, destination: url)
                        .font(.caption)
                        .lineLimit(1)
                        .accessibilityLabel("License \(license)")
                } else if let license = review.licenseID {
                    Text(license).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Link("Read review", destination: review.reviewURL)
                    .font(.caption.weight(.semibold))
                    .accessibilityLabel(externalReviewAccessibilityLabel)
                    .accessibilityHint("Opens this review on CritiqueBrainz")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 14, style: .continuous))
    }

    private var externalReviewAccessibilityLabel: String {
        guard let author = review.author?.trimmingCharacters(in: .whitespacesAndNewlines),
              !author.isEmpty else {
            return "Read this review on CritiqueBrainz"
        }
        return "Read \(author)’s review on CritiqueBrainz"
    }
}
