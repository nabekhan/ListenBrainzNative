import SwiftUI

struct CommunityChartsView: View {
    @State private var model: CommunityChartsModel
    @Bindable private var listeningModel: ListeningModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        listeningModel: ListeningModel,
        provider: (any CommunityChartsProviding)? = nil,
        cache: EntityDetailCache<CommunityChartPageCacheKey, CommunityChartPage>? = nil,
        pageSize: Int = ListenBrainzCommunityChartsProvider.maximumPageSize,
        visibleLimit: Int = 200
    ) {
        _listeningModel = Bindable(wrappedValue: listeningModel)
        _model = State(initialValue: CommunityChartsModel(
            provider: provider,
            cache: cache,
            pageSize: pageSize,
            visibleLimit: visibleLimit
        ))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                introduction
                chartPicker
                periodPicker
                content
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
        .accessibilityIdentifier("community-charts-screen")
        .navigationTitle("Community charts")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await model.refresh() }
                } label: {
                    if model.isRefreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .accessibilityLabel("Refresh community charts")
                .disabled(model.state != .loaded || model.isRefreshing)
            }
        }
        .task(id: model.query) {
            await model.loadSelectedIfNeeded()
        }
        .onDisappear { model.cancel() }
        .mediaDestinations(model: listeningModel)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Across ListenBrainz", systemImage: "globe.americas.fill")
                .font(.headline)
                .foregroundStyle(AppTheme.accent)
            Text("A snapshot of listening across ListenBrainz, separate from your history.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var chartPicker: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Chart")
                .font(.headline)
            if dynamicTypeSize.isAccessibilitySize {
                chartPickerControl.pickerStyle(.menu)
            } else {
                chartPickerControl.pickerStyle(.segmented)
            }
        }
    }

    private var chartPickerControl: some View {
        Picker(
            "Chart type",
            selection: Binding(
                get: { model.kind },
                set: { model.select(kind: $0) }
            )
        ) {
            ForEach(CommunityChartKind.allCases) { kind in
                Label(kind.title, systemImage: kind.systemImage).tag(kind)
            }
        }
        .accessibilityIdentifier("community-charts-kind")
    }

    private var periodPicker: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Time period", systemImage: "calendar")
                        .font(.headline)
                    periodMenu
                }
            } else {
                HStack(spacing: 12) {
                    Label("Time period", systemImage: "calendar")
                        .font(.headline)
                    Spacer(minLength: 8)
                    periodMenu
                }
            }
        }
        .accessibilityIdentifier("community-charts-period")
    }

    private var periodMenu: some View {
        Picker(
            "Time period",
            selection: Binding(
                get: { model.period },
                set: { model.select(period: $0) }
            )
        ) {
            ForEach(ListeningActivityPeriod.allCases) { period in
                Text(period.title).tag(period)
            }
        }
        .pickerStyle(.menu)
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            loading
        case let .failed(message):
            failure(message)
        case .loaded where model.items.isEmpty:
            empty
        case .loaded:
            rankings
        }
    }

    private var loading: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading community charts…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var empty: some View {
        ContentUnavailableView(
            "No community rankings yet",
            systemImage: "chart.bar.xaxis",
            description: Text("ListenBrainz has not calculated this period yet.")
        )
        .frame(maxWidth: .infinity, minHeight: 280)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private func failure(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Community charts couldn’t load", systemImage: "wifi.exclamationmark")
        } description: {
            Text("Check your connection, then try again.\n\n\(message)")
        } actions: {
            Button("Try again") { Task { await model.retry() } }
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private var rankings: some View {
        VStack(alignment: .leading, spacing: 12) {
            rankingSummary

            if let message = model.refreshError {
                Label(
                    String(localized: "Showing saved rankings. \(message)"),
                    systemImage: "arrow.clockwise"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            LazyVStack(spacing: 0) {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                    destinationRow(item: item, rank: index + 1)
                    if index < model.items.count - 1 {
                        Divider().padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : 102)
                    }
                }
                paginationFooter
            }
            .padding(.horizontal, 14)
            .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
        }
    }

    private var rankingSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Top \(model.kind.title)"))
                .font(.title3.bold())
            HStack(spacing: 6) {
                if let total = model.totalResultCount {
                    Text("Showing \(model.items.count) of \(total) rankings")
                } else {
                    Text("Showing \(model.items.count) rankings")
                }
                if let lastUpdated = model.lastUpdated {
                    Text("·")
                    Text("Updated \(lastUpdated.formatted(.relative(presentation: .named)))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func destinationRow(item: CommunityChartItem, rank: Int) -> some View {
        switch item {
        case let .artist(artist):
            if let destination = artist.detailDestination(includingListenCount: false) {
                NavigationLink(value: destination) {
                    CommunityChartRow(item: item, rank: rank, maximumCount: maximumListenCount, showsDisclosure: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens artist details")
            } else {
                CommunityChartRow(item: item, rank: rank, maximumCount: maximumListenCount, showsDisclosure: false)
            }
        case let .releaseGroup(group):
            if let destination = group.detailDestination {
                NavigationLink(value: destination) {
                    CommunityChartRow(item: item, rank: rank, maximumCount: maximumListenCount, showsDisclosure: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens album details")
            } else {
                CommunityChartRow(item: item, rank: rank, maximumCount: maximumListenCount, showsDisclosure: false)
            }
        case let .recording(recording):
            if let destination = recording.detailDestination {
                NavigationLink(value: destination) {
                    CommunityChartRow(item: item, rank: rank, maximumCount: maximumListenCount, showsDisclosure: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens track details")
            } else {
                CommunityChartRow(item: item, rank: rank, maximumCount: maximumListenCount, showsDisclosure: false)
            }
        }
    }

    private var maximumListenCount: Int {
        model.items.map(\.listenCount).max() ?? 0
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if model.isLoadingMore {
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading more rankings…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .accessibilityElement(children: .combine)
        } else if let message = model.loadMoreError {
            VStack(spacing: 9) {
                Label("More rankings couldn’t load", systemImage: "wifi.exclamationmark")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try again") { Task { await model.loadMore() } }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .accessibilityIdentifier("community-charts-load-more-error")
        } else if model.canLoadMore {
            Button {
                Task { await model.loadMore() }
            } label: {
                Label("Load more rankings", systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .padding(.vertical, 16)
            .accessibilityIdentifier("community-charts-load-more")
        } else if model.hasReachedVisibleLimit {
            Text("Showing the first \(model.visibleResultLimit) results.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
    }
}

private struct CommunityChartRow: View {
    let item: CommunityChartItem
    let rank: Int
    let maximumCount: Int
    let showsDisclosure: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                regularLayout
            }
        }
        .padding(.vertical, 12)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("community-chart-row-\(rank)")
    }

    private var regularLayout: some View {
        HStack(spacing: 12) {
            rankLabel
            artwork(size: 54, cornerRadius: 9)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                if let artistName = item.artistName {
                    Text(artistName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    listeningBar
                    Text(listenCountLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if showsDisclosure {
                Image(systemName: "chevron.forward")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
    }

    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                rankLabel
                artwork(size: 78, cornerRadius: 13)
                Spacer(minLength: 8)
                if showsDisclosure {
                    Image(systemName: "chevron.forward")
                        .font(.body.bold())
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            Text(item.title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            if let artistName = item.artistName {
                Text(artistName)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(listenCountLabel)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var rankLabel: some View {
        Text("\(rank)")
            .font(.subheadline.monospacedDigit().weight(rank <= 3 ? .bold : .regular))
            .foregroundStyle(rank <= 3 ? AppTheme.accent : .secondary)
            .frame(width: 28)
    }

    @ViewBuilder
    private func artwork(size: CGFloat, cornerRadius: CGFloat) -> some View {
        switch item {
        case let .artist(artist):
            ArtistArtworkView(artist: artist)
                .frame(width: size, height: size)
        case let .releaseGroup(group):
            ArtworkView(url: group.artworkURL, title: group.name, cornerRadius: cornerRadius)
                .frame(width: size, height: size)
        case let .recording(recording):
            ArtworkView(
                url: recording.recording.artworkURL,
                title: recording.title,
                cornerRadius: cornerRadius
            )
            .frame(width: size, height: size)
        }
    }

    private var listeningBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.14))
                Capsule()
                    .fill(AppTheme.accent.opacity(0.72))
                    .frame(width: proxy.size.width * relativeShare)
            }
        }
        .frame(maxWidth: 74, minHeight: 4, maxHeight: 4)
        .accessibilityHidden(true)
    }

    private var relativeShare: CGFloat {
        guard maximumCount > 0 else { return 0 }
        return min(max(CGFloat(item.listenCount) / CGFloat(maximumCount), 0), 1)
    }

    private var listenCountLabel: String {
        String(localized: "\(item.listenCount) listens")
    }

    private var accessibilityLabel: String {
        [
            String(localized: "Rank \(rank)"),
            item.title,
            item.artistName,
            listenCountLabel,
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

#if DEBUG
struct CommunityChartsVisualQAScreen: View {
    @Bindable var listeningModel: ListeningModel
    private let provider = VisualQACommunityChartsProvider()

    var body: some View {
        NavigationStack {
            CommunityChartsView(
                listeningModel: listeningModel,
                provider: provider,
                pageSize: 2
            )
        }
    }
}

private actor VisualQACommunityChartsProvider: CommunityChartsProviding {
    func page(
        query: CommunityChartQuery,
        offset: Int,
        limit _: Int
    ) async throws -> CommunityChartPage {
        let first = CommunityChartItem.artist(.init(
            mbid: nil,
            name: "Nina Simone",
            listenCount: 148_205
        ))
        let second = CommunityChartItem.artist(.init(
            mbid: nil,
            name: "Radiohead",
            listenCount: 131_840
        ))
        let third = CommunityChartItem.artist(.init(
            mbid: nil,
            name: "Björk",
            listenCount: 118_734
        ))
        let fourth = CommunityChartItem.artist(.init(
            mbid: nil,
            name: "Massive Attack",
            listenCount: 104_622
        ))

        if query.kind != .artists {
            return CommunityChartPage(
                items: [],
                offset: offset,
                rawResultCount: 0,
                totalResultCount: 0,
                lastUpdated: .now,
                allowsPagination: false
            )
        }
        if offset == 0 {
            return CommunityChartPage(
                items: [first, second],
                offset: 0,
                rawResultCount: 2,
                totalResultCount: 4,
                lastUpdated: .now,
                allowsPagination: true
            )
        }
        return CommunityChartPage(
            items: [third, fourth],
            offset: offset,
            rawResultCount: 2,
            totalResultCount: 4,
            lastUpdated: .now,
            allowsPagination: true
        )
    }
}
#endif
