import SwiftUI

struct ArtistDetailView: View {
    let artist: RankedArtist
    @Bindable var model: ListeningModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                hero
                topRecordings
                recentListens
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
        .background {
            AppTheme.artworkGradient(seed: artist.name)
                .opacity(0.16)
                .ignoresSafeArea()
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .center))
        }
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Recording.self) { recording in
            RecordingDetailView(recording: recording, model: model)
        }
        .toolbar {
            if let mbid = artist.mbid {
                ToolbarItem(placement: .topBarTrailing) {
                    Link(destination: URL(string: "https://musicbrainz.org/artist/\(mbid.uuidString)")!) {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .accessibilityLabel("Open artist in MusicBrainz")
                }
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 16) {
            ArtistArtworkView(artist: artist)
                .frame(width: 210, height: 210)
                .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
                .padding(.top, 14)
            Text(artist.name)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            if artist.listenCount > 0 {
                Label("\(artist.listenCount.formatted()) of your listens", systemImage: "waveform")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            } else {
                Label("MusicBrainz artist", systemImage: "music.mic")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var topRecordings: some View {
        let recordings = model.recordings(for: artist)
        if !recordings.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Your top recordings")
                ForEach(Array(recordings.prefix(10).enumerated()), id: \.element.id) { index, item in
                    NavigationLink(value: item.recording) {
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 22)
                            ArtworkView(url: item.recording.artworkURL, title: item.title, cornerRadius: 7)
                                .frame(width: 48, height: 48)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title).font(.body.weight(.semibold)).lineLimit(1)
                                Text("\(item.listenCount.formatted()) listens")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var recentListens: some View {
        let listens = model.listens(for: artist)
        if !listens.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Recent history", subtitle: "Recent listens from this artist")
                ForEach(listens.prefix(10)) { listen in
                    NavigationLink(value: listen.recording) {
                        ListenRow(listen: listen, showsDate: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
