import SwiftUI

private struct PopularityProviderEnvironmentKey: EnvironmentKey {
    static let defaultValue: any PopularityProviding = ListenBrainzPopularityProvider(token: "")
}

extension EnvironmentValues {
    var popularityProvider: any PopularityProviding {
        get { self[PopularityProviderEnvironmentKey.self] }
        set { self[PopularityProviderEnvironmentKey.self] = newValue }
    }
}

struct PopularitySummaryPresentation: Equatable {
    let listenCount: Int?
    let listenerCount: Int?

    init(_ popularity: GlobalPopularity) {
        listenCount = popularity.totalListenCount.flatMap { $0 >= 0 ? $0 : nil }
        listenerCount = popularity.totalUserCount.flatMap { $0 >= 0 ? $0 : nil }
    }

    func compact(_ count: Int, locale: Locale = .autoupdatingCurrent) -> String {
        count.formatted(
            .number
                .notation(.compactName)
                .locale(locale)
        )
    }

    func accessibilityLabel(locale: Locale = .autoupdatingCurrent) -> String {
        let listens = listenCount.map {
            String(localized: "\($0) listens", locale: locale)
        }
        let listeners = listenerCount.map {
            String(localized: "\($0) listeners", locale: locale)
        }

        let totals: String
        switch (listens, listeners) {
        case let (.some(listens), .some(listeners)):
            totals = String(localized: "\(listens) from \(listeners)", locale: locale)
        case let (.some(listens), .none):
            totals = listens
        case let (.none, .some(listeners)):
            totals = listeners
        case (.none, .none):
            totals = String(localized: "Popularity unavailable", locale: locale)
        }
        return String(
            localized: "Across ListenBrainz, \(totals). Global totals, refreshed daily.",
            locale: locale
        )
    }
}

struct PopularitySummaryView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.popularityProvider) private var provider
    @State private var model: PopularitySummaryModel?

    let entity: PopularityEntity

    var body: some View {
        Group {
            switch model?.phase ?? .idle {
            case .idle, .loading:
                loadingCard
            case let .loaded(popularity):
                loadedCard(PopularitySummaryPresentation(popularity))
            case .unavailable:
                EmptyView()
            case .failed:
                failureCard
            }
        }
        .task(id: entity) {
            let current = PopularitySummaryModel(entity: entity, provider: provider)
            model = current
            await current.load()
        }
    }

    private var loadingCard: some View {
        card {
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Across ListenBrainz")
                        .font(.headline)
                    Text("Loading community context…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func loadedCard(_ presentation: PopularitySummaryPresentation) -> some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ACROSS LISTENBRAINZ")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text("Global totals · refreshed daily")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 14) {
                        metrics(presentation)
                    }
                } else {
                    HStack(alignment: .top, spacing: 22) {
                        metrics(presentation)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(presentation.accessibilityLabel())
        }
    }

    @ViewBuilder
    private func metrics(_ presentation: PopularitySummaryPresentation) -> some View {
        if let count = presentation.listenCount {
            metric(
                count: presentation.compact(count),
                label: count == 1 ? "Listen" : "Listens",
                systemImage: "waveform"
            )
        }
        if let count = presentation.listenerCount {
            metric(
                count: presentation.compact(count),
                label: count == 1 ? "Listener" : "Listeners",
                systemImage: "person.2.fill"
            )
        }
    }

    private func metric(
        count: String,
        label: LocalizedStringResource,
        systemImage: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(count)
                    .font(.title3.bold().monospacedDigit())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var failureCard: some View {
        card {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Community totals unavailable")
                        .font(.subheadline.weight(.semibold))
                    Text("Your listening data is still available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Retry") {
                    guard let model else { return }
                    Task { await model.retry() }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
    }
}
