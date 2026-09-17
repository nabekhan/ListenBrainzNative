import SwiftUI

struct ReleaseGroupDetailView: View {
    let group: SearchReleaseGroup
    @State private var model: ReleaseGroupDetailModel

    init(group: SearchReleaseGroup, token: String) {
        self.group = group
        _model = State(initialValue: ReleaseGroupDetailModel(seed: group, token: token))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                loadNotice
                artists
                tags
                facts
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 44)
        }
        .refreshable { await model.refresh() }
        .background {
            AppTheme.artworkGradient(seed: displayTitle)
                .opacity(0.12)
                .ignoresSafeArea()
                .mask(
                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
        }
        .navigationTitle(displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Link(destination: group.musicBrainzURL) {
                    Image(systemName: "arrow.up.right.square")
                }
                .accessibilityLabel("Open release group in MusicBrainz")
            }
        }
        .task { await model.load() }
    }

    private var hero: some View {
        VStack(spacing: 16) {
            ArtworkView(
                url: model.detail?.artworkURL,
                title: displayTitle,
                cornerRadius: 24,
                showsPlaceholderSymbol: false
            )
            .frame(maxWidth: 360)
            .aspectRatio(1, contentMode: .fit)
            .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
            .padding(.top, 12)

            VStack(spacing: 6) {
                Text(displayTitle)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text(displayArtist)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .multilineTextAlignment(.center)

                let metadata = [displayType, displayDate].compactMap { $0 }
                if !metadata.isEmpty {
                    Text(metadata.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var loadNotice: some View {
        switch model.phase {
        case .idle, .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading release context…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(.thinMaterial, in: .rect(cornerRadius: 16, style: .continuous))
        case .refreshing:
            Label("Refreshing release context…", systemImage: "arrow.clockwise")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        case .unavailable:
            notice(
                title: "ListenBrainz details aren’t indexed yet",
                message: "The MusicBrainz identity is still available, and this page will fill in when metadata becomes available."
            )
        case let .failed(message):
            retryNotice(message: message)
        case .ready:
            if let message = model.refreshMessage {
                retryNotice(message: message)
            }
        }
    }

    @ViewBuilder
    private var artists: some View {
        if let artists = model.detail?.artists, !artists.isEmpty {
            detailSection("Artists") {
                VStack(spacing: 0) {
                    ForEach(artists) { artist in
                        NavigationLink(value: artist) {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(AppTheme.artworkGradient(seed: artist.name))
                                    .frame(width: 42, height: 42)
                                    .overlay {
                                        Text(artist.name.prefix(1).uppercased())
                                            .font(.headline)
                                            .foregroundStyle(.white)
                                    }
                                Text(artist.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var tags: some View {
        if let tags = model.detail?.tags, !tags.isEmpty {
            detailSection("Tags") {
                Text(tags.prefix(12).joined(separator: " · "))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var facts: some View {
        detailSection("MusicBrainz identity") {
            VStack(alignment: .leading, spacing: 12) {
                Label(displayType ?? "Release group", systemImage: "square.stack.3d.up")
                Link(destination: group.musicBrainzURL) {
                    Label("Open release group", systemImage: "arrow.up.right.square")
                }
            }
        }
    }

    private var displayTitle: String {
        nonempty(model.detail?.title) ?? group.title
    }

    private var displayArtist: String {
        nonempty(model.detail?.artistCreditName) ?? group.artistName
    }

    private var displayType: String? {
        nonempty(model.detail?.primaryType) ?? nonempty(group.primaryType)
    }

    private var displayDate: String? {
        formattedMusicBrainzDate(model.detail?.releaseDate)
            ?? formattedMusicBrainzDate(group.firstReleaseDate)
    }

    private func detailSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: .rect(cornerRadius: 18, style: .continuous))
    }

    private func retryNotice(message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Release context unavailable", systemImage: "wifi.exclamationmark")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Try Again") { Task { await model.refresh() } }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: .rect(cornerRadius: 18, style: .continuous))
    }

    private func notice(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: .rect(cornerRadius: 18, style: .continuous))
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func formattedMusicBrainzDate(_ value: String?) -> String? {
        guard let value = nonempty(value) else { return nil }
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else { return value }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        guard let date = calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: 12
        )) else { return value }
        return date.formatted(.dateTime.year().month(.abbreviated).day())
    }
}
