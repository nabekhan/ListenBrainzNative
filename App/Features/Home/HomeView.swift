import SwiftUI

struct HomeView: View {
    @Bindable var model: ListeningModel

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .idle where model.snapshot.recentListens.isEmpty,
                     .loading where model.snapshot.recentListens.isEmpty:
                    LoadingStateView(title: "Loading your music life")
                case let .failed(message) where model.snapshot.recentListens.isEmpty:
                    FailureStateView(message: message) { await model.refresh() }
                default:
                    content
                }
            }
            .navigationTitle(greeting)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await model.refresh() } } label: {
                        if model.phase == .refreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .accessibilityLabel("Refresh")
                }
            }
            .mediaDestinations(model: model)
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
                Text("@\(model.account.username)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let listen = model.snapshot.playingNow ?? model.snapshot.recentListens.first {
                    nowListeningCard(listen)
                }

                snapshotStrip

                if !model.snapshot.recentListens.isEmpty {
                    recentSection
                }

                if !model.snapshot.topArtists.isEmpty {
                    topArtistsSection
                }

                if !model.snapshot.topReleases.isEmpty {
                    topReleasesSection
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 36)
        }
        .refreshable { await model.refresh() }
    }

    private func nowListeningCard(_ listen: Listen) -> some View {
        NavigationLink(value: listen.recording) {
            ZStack(alignment: .bottomLeading) {
                ArtworkView(
                    url: listen.recording.artworkURL,
                    title: listen.recording.title,
                    cornerRadius: 24,
                    showsPlaceholderSymbol: false
                )
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1.45, contentMode: .fill)
                    .overlay {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.78)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                    }
                    .clipShape(.rect(cornerRadius: 24, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Label(
                        listen.isPlayingNow ? "PLAYING NOW" : "LATEST LISTEN",
                        systemImage: listen.isPlayingNow ? "waveform" : "clock.fill"
                    )
                    .font(.caption2.bold())
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.8))

                    Text(listen.recording.title)
                        .font(.title.bold())
                        .lineLimit(2)
                    Text(listen.recording.artistName)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .foregroundStyle(.white)
                .padding(20)
            }
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
    }

    private var snapshotStrip: some View {
        HStack(spacing: 12) {
            metric(
                model.snapshot.listenCount?.formatted(.number.notation(.compactName)) ?? "—",
                label: "Total listens",
                icon: "waveform"
            )
            metric(
                model.snapshot.topArtists.first?.name ?? "—",
                label: "Top artist",
                icon: "person.wave.2"
            )
        }
    }

    private func metric(_ value: String, label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.accent)
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: .rect(cornerRadius: 18, style: .continuous))
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Recently played", subtitle: "The last few moments in your listening history")
            ForEach(model.snapshot.recentListens.prefix(6)) { listen in
                NavigationLink(value: listen.recording) {
                    ListenRow(listen: listen)
                }
                .buttonStyle(.plain)
                if listen.id != model.snapshot.recentListens.prefix(6).last?.id {
                    Divider().padding(.leading, 66)
                }
            }
        }
    }

    private var topArtistsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Your artists", subtitle: "All-time favorites from ListenBrainz")
            ScrollView(.horizontal) {
                LazyHStack(spacing: 16) {
                    ForEach(model.snapshot.topArtists.prefix(12)) { artist in
                        NavigationLink(value: artist) {
                            VStack(alignment: .leading, spacing: 8) {
                                ArtistArtworkView(artist: artist)
                                    .frame(width: 116, height: 116)
                                Text(artist.name)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text("\(artist.listenCount.formatted()) listens")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 116, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }

    private var topReleasesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Albums on repeat")
            ScrollView(.horizontal) {
                LazyHStack(spacing: 16) {
                    ForEach(model.snapshot.topReleases.prefix(12)) { release in
                        VStack(alignment: .leading, spacing: 7) {
                            ArtworkView(url: release.artworkURL, title: release.name, cornerRadius: 13)
                                .frame(width: 152, height: 152)
                            Text(release.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(release.artistName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(width: 152, alignment: .leading)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }
}
