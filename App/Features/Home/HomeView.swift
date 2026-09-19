import SwiftUI

struct HomeView: View {
    @Bindable var model: ListeningModel
    @State private var isLogListenPresented = false

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
                if model.account.isAuthenticated {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { isLogListenPresented = true } label: { Image(systemName: "plus.circle") }
                            .accessibilityLabel("Log a listen")
                    }
                }
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
            .sheet(isPresented: $isLogListenPresented) { LogListenSheet(account: model.account) }
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
                Text("@\(model.account.username)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let listen = model.snapshot.playingNow ?? model.snapshot.recentListens.first {
                    FeaturedListenCard(
                        listen: listen,
                        label: listen.isPlayingNow ? "Playing now" : "Latest listen",
                        systemImage: listen.isPlayingNow ? "waveform" : "clock.fill"
                    )
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
                        if let seed = release.releaseSeed {
                            NavigationLink(value: seed) {
                                releaseCard(release)
                            }
                            .buttonStyle(.plain)
                        } else {
                            releaseCard(release)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }

    private func releaseCard(_ release: RankedRelease) -> some View {
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

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }
}
