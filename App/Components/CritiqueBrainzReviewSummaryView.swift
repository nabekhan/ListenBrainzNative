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
                            .accessibilityLabel(averageRatingAccessibilityLabel(rating, count: count))
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
                        CritiqueBrainzReviewReaderView(summary: summary, provider: provider)
                    } label: {
                        Label(
                            String(localized: "Read \(summary.reviews.count) reviews"),
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
        let ratingValue = rating.formatted(.number.precision(.fractionLength(1)))
        let ratingCount = String(localized: "\(count) ratings")
        return String(localized: "\(ratingValue) out of 5 · \(ratingCount)")
    }

    private func averageRatingAccessibilityLabel(_ rating: Double, count: Int) -> String {
        let ratingValue = rating.formatted(.number.precision(.fractionLength(1)))
        let ratingCount = String(localized: "\(count) ratings")
        return String(localized: "Average CritiqueBrainz rating: \(ratingValue) out of 5, from \(ratingCount)")
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
    }
}

/// A local reader for the summary page. It makes no request when opened; a
/// deliberately tapped control can append one bounded server page at a time.
struct CritiqueBrainzReviewReaderView: View {
    @Environment(\.critiqueBrainzReviewsProvider) private var environmentProvider
    @State private var model: CritiqueBrainzReviewReaderModel?
    @State private var loadMoreTask: Task<Void, Never>?

    let summary: CritiqueBrainzReviewSummary
    private let providedProvider: (any CritiqueBrainzReviewsProviding)?

    init(summary: CritiqueBrainzReviewSummary, provider: (any CritiqueBrainzReviewsProviding)? = nil) {
        self.summary = summary
        providedProvider = provider
    }

    var body: some View {
        let displayedSummary = model?.summary ?? summary
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Text("Published reviews from CritiqueBrainz")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(displayedSummary.reviews) { review in
                    CritiqueBrainzReviewCard(review: review, truncatesText: false)
                }

                paginationControl

                Link(destination: displayedSummary.entity.browseURL) {
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
        .task(id: summary) {
            model = CritiqueBrainzReviewReaderModel(
                summary: summary,
                provider: providedProvider ?? environmentProvider
            )
        }
        .onDisappear {
            loadMoreTask?.cancel()
            loadMoreTask = nil
            model?.cancel()
        }
    }

    @ViewBuilder
    private var paginationControl: some View {
        if let model {
            if model.isLoadingMore {
                Label("Loading more reviews…", systemImage: "arrow.down.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
            } else if let message = model.loadMoreMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text("More reviews couldn’t load.")
                        .font(.subheadline.weight(.semibold))
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Try again") { startLoadingMore() }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if model.canLoadMore {
                Button("Load more reviews") { startLoadingMore() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func startLoadingMore() {
        loadMoreTask?.cancel()
        loadMoreTask = Task { await model?.loadMore() }
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
                    Text(review.author ?? String(localized: "CritiqueBrainz member"))
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
                        .accessibilityLabel(String(localized: "License \(license)"))
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
            return String(localized: "Read this review on CritiqueBrainz")
        }
        return String(localized: "Read \(author)’s review on CritiqueBrainz")
    }
}
