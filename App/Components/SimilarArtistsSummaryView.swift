import SwiftUI

private struct SimilarArtistsProviderEnvironmentKey: EnvironmentKey {
    static let defaultValue: (any SimilarArtistsProviding)? = nil
}

extension EnvironmentValues {
    var similarArtistsProvider: (any SimilarArtistsProviding)? {
        get { self[SimilarArtistsProviderEnvironmentKey.self] }
        set { self[SimilarArtistsProviderEnvironmentKey.self] = newValue }
    }
}

struct SimilarArtistsSummaryView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.similarArtistsProvider) private var provider
    @State private var model: SimilarArtistsModel?
    @State private var showsAll: Bool

    let artistMBID: UUID
    private let initiallyExpanded: Bool

    init(artistMBID: UUID, initiallyExpanded: Bool = false) {
        self.artistMBID = artistMBID
        self.initiallyExpanded = initiallyExpanded
        _showsAll = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        Group {
            switch model?.phase ?? .idle {
            case .idle, .loading:
                loadingShelf
            case let .loaded(value):
                shelf(value)
            case .unavailable, .failed:
                EmptyView()
            }
        }
        .task(id: artistMBID) {
            let current = SimilarArtistsModel(
                artistMBID: artistMBID,
                provider: provider ?? ListenBrainzSimilarArtistsProvider()
            )
            model = current
            showsAll = initiallyExpanded
            await current.load()
        }
    }

    private var loadingShelf: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Similar artists")
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: 14) {
                            Circle()
                                .fill(.secondary.opacity(0.14))
                                .frame(width: 64, height: 64)
                            RoundedRectangle(cornerRadius: 5)
                                .fill(.secondary.opacity(0.14))
                                .frame(maxWidth: 220)
                                .frame(height: 18)
                            Spacer(minLength: 0)
                        }
                    }
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(0..<5, id: \.self) { _ in
                            VStack(spacing: 9) {
                                Circle()
                                    .fill(.secondary.opacity(0.14))
                                    .frame(width: artworkSize, height: artworkSize)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.secondary.opacity(0.14))
                                    .frame(width: cellWidth * 0.72, height: 12)
                            }
                            .frame(width: cellWidth)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading similar artists")
    }

    private func shelf(_ result: SimilarArtists) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Similar artists")

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    ForEach(visibleArtists(result)) { artist in
                        NavigationLink(value: artist.rankedArtist) {
                            accessibilityArtistRow(artist)
                        }
                        .buttonStyle(.plain)
                        if artist.id != visibleArtists(result).last?.id {
                            Divider().padding(.leading, 78)
                        }
                    }
                }
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(visibleArtists(result)) { artist in
                            NavigationLink(value: artist.rankedArtist) {
                                artistCell(artist)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            if result.artists.count > 5 {
                Button {
                    withAnimation(.snappy) { showsAll.toggle() }
                } label: {
                    Text(showsAll ? "Show fewer artists" : "Show all similar artists")
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.bordered)
                .accessibilityHint(
                    showsAll
                        ? "Shows the first five similar artists"
                        : "Shows every similar artist returned by ListenBrainz"
                )
            }
        }
    }

    private func artistCell(_ artist: SimilarArtist) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ArtistArtworkView(artist: artist.rankedArtist)
                .frame(width: artworkSize, height: artworkSize)
                .accessibilityHidden(true)
            Text(artist.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: cellWidth, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(artist.name)
        .accessibilityHint("Opens artist details")
    }

    private func accessibilityArtistRow(_ artist: SimilarArtist) -> some View {
        Group {
            if usesStackedAccessibilityRows {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        accessibilityArtwork(artist)
                        Spacer(minLength: 8)
                        disclosureIndicator
                    }
                    accessibilityName(artist)
                }
            } else {
                HStack(spacing: 14) {
                    accessibilityArtwork(artist)
                    accessibilityName(artist)
                    Spacer(minLength: 8)
                    disclosureIndicator
                }
            }
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(artist.name)
        .accessibilityHint("Opens artist details")
    }

    private func accessibilityArtwork(_ artist: SimilarArtist) -> some View {
        ArtistArtworkView(artist: artist.rankedArtist)
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)
    }

    private func accessibilityName(_ artist: SimilarArtist) -> some View {
        Text(artist.name)
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var disclosureIndicator: some View {
        Image(systemName: "chevron.right")
            .font(.caption.bold())
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    private func visibleArtists(_ result: SimilarArtists) -> [SimilarArtist] {
        Array(result.artists.prefix(showsAll ? result.artists.count : 5))
    }

    private let artworkSize: CGFloat = 96
    private let cellWidth: CGFloat = 104

    private var usesStackedAccessibilityRows: Bool {
        switch dynamicTypeSize {
        case .accessibility4, .accessibility5: true
        default: false
        }
    }
}
