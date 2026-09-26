import SwiftUI

struct ArtistActivityPresentation {
    let artists: [ArtistActivity.Artist]
    let maximumListenCount: Int

    init(_ activity: ArtistActivity) {
        artists = activity.artists
        maximumListenCount = activity.artists.map(\.listenCount).max() ?? 0
    }

    func fraction(_ value: Int) -> Double {
        guard maximumListenCount > 0 else { return 0 }
        return min(max(Double(value) / Double(maximumListenCount), 0), 1)
    }
}

struct ArtistActivityView: View {
    @Bindable var model: ListeningModel
    @Binding var period: ListeningActivityPeriod
    @State private var expanded: Set<String> = []
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                intro
                periodPicker
                content
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
        .navigationTitle("Artist activity")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await model.loadArtistActivity(for: period, retrying: true)
        }
        .task(id: period) {
            expanded.removeAll()
            await model.loadArtistActivity(for: period)
            showExpandedFixtureIfRequested()
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "rectangle.3.group.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .accessibilityHidden(true)
            Text("See the artists and albums shaping this period.")
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    private var periodPicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ListeningActivityPeriod.allCases) { value in
                        Button {
                            period = value
                        } label: {
                            Text(value.title)
                                .font(.subheadline.weight(period == value ? .semibold : .regular))
                                .foregroundStyle(period == value ? .white : .primary)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 9)
                                .background(
                                    period == value ? AppTheme.accent : Color.secondary.opacity(0.12),
                                    in: .capsule
                                )
                        }
                        .id(value)
                        .buttonStyle(.plain)
                        .accessibilityLabel(value.accessibilityLabel)
                        .accessibilityAddTraits(period == value ? .isSelected : [])
                    }
                }
            }
            .onAppear { proxy.scrollTo(period, anchor: .center) }
            .onChange(of: period) { _, value in
                withAnimation(.snappy) { proxy.scrollTo(value, anchor: .center) }
            }
        }
        .accessibilityLabel("Artist activity period")
    }

    @ViewBuilder
    private var content: some View {
        switch model.artistActivityState(for: period) {
        case .idle, .loading:
            loading
        case .unavailable:
            unavailable
        case .failed:
            failure
        case let .loaded(activity):
            if activity.isEmpty {
                empty
            } else {
                report(activity)
            }
        }
    }

    private var loading: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("Loading artist activity…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var unavailable: some View {
        ContentUnavailableView(
            "Artist activity isn’t ready yet",
            systemImage: "chart.bar.xaxis",
            description: Text("ListenBrainz hasn’t calculated this report for \(period.title.lowercased()) yet.")
        )
        .frame(maxWidth: .infinity, minHeight: 280)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private var empty: some View {
        ContentUnavailableView(
            "No artist activity yet",
            systemImage: "music.note.list",
            description: Text("There are no ranked artists for \(period.title.lowercased()) yet.")
        )
        .frame(maxWidth: .infinity, minHeight: 280)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private var failure: some View {
        ContentUnavailableView {
            Label("Artist activity unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Check your connection, then try again.")
        } actions: {
            Button("Try again") {
                Task { await model.loadArtistActivity(for: period, retrying: true) }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private func report(_ activity: ArtistActivity) -> some View {
        let presentation = ArtistActivityPresentation(activity)
        return VStack(alignment: .leading, spacing: 16) {
            summaries(activity)

            if model.artistActivityRefreshMessage(for: period) != nil {
                Label("Showing saved results. Pull to refresh and try again.", systemImage: "arrow.clockwise")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(presentation.artists.enumerated()), id: \.element.id) { offset, artist in
                    artistRow(artist, rank: offset + 1, presentation: presentation)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(dateRange(activity))
                Text("ListenBrainz shows up to 15 leading artists from mapped album data. Collaborative listens can count toward more than one artist, and unmapped listens may not appear.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func summaries(_ activity: ArtistActivity) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 12) {
                summary(value: activity.artists.count, label: "Artists shown", symbol: "music.mic")
                summary(value: activity.albumEntryCount, label: "Album entries", symbol: "square.stack")
            }
        } else {
            HStack(spacing: 12) {
                summary(value: activity.artists.count, label: "Artists shown", symbol: "music.mic")
                summary(value: activity.albumEntryCount, label: "Album entries", symbol: "square.stack")
            }
        }
    }

    private func summary(value: Int, label: LocalizedStringResource, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppTheme.secondary)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(value.formatted())
                    .font(.headline.monospacedDigit())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 15, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func artistRow(
        _ artist: ArtistActivity.Artist,
        rank: Int,
        presentation: ArtistActivityPresentation
    ) -> some View {
        let isExpanded = expanded.contains(artist.id)
        return VStack(alignment: .leading, spacing: 12) {
            artistHeader(artist, rank: rank)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.14))
                    Capsule()
                        .fill(AppTheme.accent.gradient)
                        .frame(width: proxy.size.width * presentation.fraction(artist.listenCount))
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)

            if !artist.albums.isEmpty {
                albumComposition(artist.albums)

                Button {
                    withAnimation(.snappy) {
                        if isExpanded {
                            expanded.remove(artist.id)
                        } else {
                            expanded.insert(artist.id)
                        }
                    }
                } label: {
                    Label(
                        albumDisclosureTitle(albumCount: artist.albums.count, isExpanded: isExpanded),
                        systemImage: isExpanded ? "chevron.up" : "chevron.down"
                    )
                    .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.accent)
                .accessibilityHint(isExpanded ? "Hides this artist’s albums" : "Shows albums for this artist")

                if isExpanded {
                    Divider()
                    ForEach(artist.albums) { album in
                        albumRow(album, artist: artist)
                    }
                }
            }
        }
        .padding(16)
        .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func artistHeader(_ artist: ArtistActivity.Artist, rank: Int) -> some View {
        let listens = String(localized: "\(artist.listenCount) listens")
        let content = artistHeaderContent(artist, rank: rank)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "\(rank). \(artist.name), \(listens)"))

        if artist.mbid != nil {
            NavigationLink(value: artist.rankedArtist) { content }
                .buttonStyle(.plain)
                .accessibilityHint("Opens artist details")
        } else {
            content
        }
    }

    @ViewBuilder
    private func artistHeaderContent(_ artist: ArtistActivity.Artist, rank: Int) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    rankLabel(rank)
                    artistName(artist)
                }
                Text(listenCountLabel(artist.listenCount))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                rankLabel(rank)
                artistName(artist)
                Spacer(minLength: 8)
                Text(listenCountLabel(artist.listenCount))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func rankLabel(_ rank: Int) -> some View {
        Text(rank.formatted())
            .font(.caption.monospacedDigit().weight(.bold))
            .foregroundStyle(AppTheme.accent)
            .frame(minWidth: 22, alignment: .trailing)
    }

    private func artistName(_ artist: ArtistActivity.Artist) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(artist.name)
                .font(.headline)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let canonical = artist.canonicalName,
               canonical.localizedCaseInsensitiveCompare(artist.creditedName) != .orderedSame
            {
                Text(String(localized: "Credited as \(artist.creditedName)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func albumComposition(_ albums: [ArtistActivity.Album]) -> some View {
        let total = albums.reduce(0.0) { $0 + Double(max(0, $1.listenCount)) }
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.12))
                if total > 0 {
                    HStack(spacing: 0) {
                        ForEach(Array(albums.enumerated()), id: \.element.id) { index, album in
                            Rectangle()
                                .fill(AppTheme.secondary.opacity(0.9 - (Double(index % 5) * 0.12)))
                                .frame(
                                    width: proxy.size.width * Double(max(0, album.listenCount)) / total
                                )
                        }
                    }
                    .frame(width: proxy.size.width, alignment: .leading)
                    .clipShape(.capsule)
                }
            }
        }
        .frame(height: 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(albumMixAccessibilityLabel(albums.count))
    }

    @ViewBuilder
    private func albumRow(_ album: ArtistActivity.Album, artist: ArtistActivity.Artist) -> some View {
        let listens = String(localized: "\(album.listenCount) listens")
        let content = albumRowContent(album)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "\(album.name), \(listens)"))

        if let group = album.releaseGroup(artistName: artist.name) {
            NavigationLink(value: group) { content }
                .buttonStyle(.plain)
                .accessibilityHint("Opens album details")
        } else {
            content
        }
    }

    @ViewBuilder
    private func albumRowContent(_ album: ArtistActivity.Album) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                Text(album.name)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(listenCountLabel(album.listenCount))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(album.name)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(album.listenCount.formatted())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func albumDisclosureTitle(albumCount: Int, isExpanded: Bool) -> String {
        if isExpanded { return String(localized: "Hide albums") }
        return String(localized: "Show \(albumCount) albums")
    }

    private func dateRange(_ activity: ArtistActivity) -> String {
        guard activity.from != .distantPast, activity.to != .distantPast else {
            return String(localized: "Calculated by ListenBrainz")
        }
        return String(localized: "\(activity.from.formatted(date: .abbreviated, time: .omitted)) – \(activity.to.formatted(date: .abbreviated, time: .omitted)) · calculated by ListenBrainz")
    }

    private func listenCountLabel(_ count: Int) -> String {
        String(localized: "\(count) listens")
    }

    private func albumMixAccessibilityLabel(_ count: Int) -> String {
        String(localized: "Album mix across \(count) albums")
    }

    private func showExpandedFixtureIfRequested() {
        #if DEBUG
            guard ProcessInfo.processInfo.arguments.contains("-brainz-artist-activity-expanded-demo"),
                  case let .loaded(activity) = model.artistActivityState(for: period),
                  let first = activity.artists.first
            else { return }
            expanded.insert(first.id)
        #endif
    }
}
