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

                if !model.snapshot.topRecordings.isEmpty {
                    HomeTopRecordingsSection(recordings: Array(model.snapshot.topRecordings.prefix(12)))
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

struct HomeTopRecordingsSection: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let recordings: [RankedRecording]
    var loadsArtwork = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Most played tracks",
                subtitle: "The tracks you return to most"
            )

            if dynamicTypeSize.isAccessibilitySize {
                LazyVStack(spacing: 12) {
                    ForEach(recordings) { recording in
                        recordingDestination(recording) {
                            accessibilityRow(recording)
                        }
                    }
                }
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(recordings) { recording in
                            recordingDestination(recording) {
                                recordingCard(recording)
                            }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
            }
        }
    }

    @ViewBuilder
    private func recordingDestination<Content: View>(
        _ recording: RankedRecording,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if let destination = recording.detailDestination {
            NavigationLink(value: destination) {
                content()
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens track details")
        } else {
            content()
        }
    }

    private func recordingCard(_ recording: RankedRecording) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            artwork(for: recording, cornerRadius: 13)
                .frame(width: 152, height: 152)
            Text(recording.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(recording.artistName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(listenCountLabel(recording.listenCount))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 152, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: recording))
    }

    private func accessibilityRow(_ recording: RankedRecording) -> some View {
        HStack(alignment: .top, spacing: 14) {
            artwork(for: recording, cornerRadius: 12)
                .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 5) {
                Text(recording.title)
                    .font(.headline)
                Text(recording.artistName)
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text(listenCountLabel(recording.listenCount))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if recording.detailDestination != nil {
                Image(systemName: "chevron.right")
                    .font(.body.bold())
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: .rect(cornerRadius: 16, style: .continuous))
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: recording))
    }

    private func artwork(for recording: RankedRecording, cornerRadius: CGFloat) -> some View {
        ArtworkView(
            url: loadsArtwork ? recording.recording.artworkURL : nil,
            title: recording.title,
            cornerRadius: cornerRadius
        )
    }

    private func accessibilityLabel(for recording: RankedRecording) -> String {
        [recording.title, recording.artistName, listenCountLabel(recording.listenCount)]
            .joined(separator: ", ")
    }

    private func listenCountLabel(_ count: Int) -> String {
        "\(count.formatted()) \(count == 1 ? "listen" : "listens")"
    }
}

#if DEBUG
    struct HomeTopRecordingsVisualQAScreen: View {
        @Bindable var model: ListeningModel

        private let recordings = [
            RankedRecording(
                mbid: UUID(uuidString: "1bf70850-1a66-4e77-b751-51410977ff04"),
                releaseMBID: nil,
                title: "Belinda Says",
                artistName: "Alvvays",
                artistMBIDs: [UUID(uuidString: "526bd613-fddd-4bd6-9137-ab709ac74cab")!],
                releaseTitle: "Blue Rev",
                listenCount: 423
            ),
            RankedRecording(
                mbid: nil,
                releaseMBID: nil,
                title: "A Very Long Unmapped Track Title for Layout Inspection and VoiceOver",
                artistName: "Japanese Breakfast",
                artistMBIDs: [],
                releaseTitle: "Jubilee",
                listenCount: 287
            ),
            RankedRecording(
                mbid: UUID(uuidString: "35c5d972-9356-4880-bd56-37b43a726160"),
                releaseMBID: nil,
                title: "Hush",
                artistName: "The Marías",
                artistMBIDs: [],
                releaseTitle: "Cinema",
                listenCount: 1
            ),
        ]

        var body: some View {
            NavigationStack {
                ScrollView {
                    HomeTopRecordingsSection(recordings: recordings, loadsArtwork: false)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 24)
                }
                .navigationTitle("Good evening")
                .mediaDestinations(model: model)
            }
        }
    }
#endif
