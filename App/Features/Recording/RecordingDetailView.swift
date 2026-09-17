import SwiftUI

struct RecordingDetailView: View {
    let recording: Recording
    @Bindable var model: ListeningModel

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                hero
                feedbackControls
                metadata
                relatedListens
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background {
            AppTheme.artworkGradient(seed: recording.title)
                .opacity(0.12)
                .ignoresSafeArea()
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .center))
        }
        .navigationTitle(recording.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let mbid = recording.identity.mbid {
                ToolbarItem(placement: .topBarTrailing) {
                    Link(destination: URL(string: "https://musicbrainz.org/recording/\(mbid.uuidString)")!) {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .accessibilityLabel("Open in MusicBrainz")
                }
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 16) {
            ArtworkView(url: recording.artworkURL, title: recording.title, cornerRadius: 22)
                .frame(maxWidth: 320)
                .aspectRatio(1, contentMode: .fit)
                .shadow(color: .black.opacity(0.24), radius: 24, y: 12)
                .padding(.top, 12)

            VStack(spacing: 5) {
                Text(recording.title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text(recording.artistName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .multilineTextAlignment(.center)
                if let release = recording.releaseTitle {
                    Text(release)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var feedbackControls: some View {
        HStack(spacing: 14) {
            feedbackButton(.love, title: "Love", systemImage: "heart.fill")
            feedbackButton(.hate, title: "Hate", systemImage: "hand.thumbsdown.fill")
            ShareLink(item: shareText) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 13))
        }
    }

    @ViewBuilder
    private func feedbackButton(
        _ value: RecordingFeedback,
        title: String,
        systemImage: String
    ) -> some View {
        let selected = model.feedback[recording.id] == value
        if selected {
            feedbackAction(value, title: title, systemImage: systemImage, selected: true)
                .buttonStyle(.borderedProminent)
        } else {
            feedbackAction(value, title: title, systemImage: systemImage, selected: false)
                .buttonStyle(.bordered)
        }
    }

    private func feedbackAction(
        _ value: RecordingFeedback,
        title: String,
        systemImage: String,
        selected: Bool
    ) -> some View {
        Button {
            Task { await model.setFeedback(selected ? .none : value, for: recording) }
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonBorderShape(.roundedRectangle(radius: 13))
        .tint(value == .hate ? .secondary : AppTheme.accent)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "ListenBrainz details")
            detailRow("Identity", value: identityLabel, icon: "link")
            if let duration = recording.durationMilliseconds {
                detailRow("Duration", value: durationLabel(duration), icon: "timer")
            }
            if let source = recording.source {
                detailRow("Submitted by", value: source, icon: "dot.radiowaves.left.and.right")
            }
            detailRow(
                "Metadata",
                value: recording.identity.mbid == nil ? "Unmapped recording" : "MusicBrainz mapped",
                icon: recording.identity.mbid == nil ? "questionmark.diamond" : "checkmark.seal.fill"
            )
        }
        .padding(18)
        .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var relatedListens: some View {
        let listens = model.snapshot.recentListens.filter { item in
            if let mbid = recording.identity.mbid {
                return item.recording.identity.mbid == mbid
            }
            if let msid = recording.identity.msid {
                return item.recording.identity.msid == msid
            }
            return item.recording.title == recording.title && item.recording.artistName == recording.artistName
        }
        if !listens.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Recent plays", subtitle: "In the currently loaded history")
                ForEach(listens.prefix(8)) { listen in
                    ListenRow(listen: listen, showsDate: true)
                }
            }
        }
    }

    private func detailRow(_ label: String, value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(AppTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.subheadline.weight(.medium)).textSelection(.enabled)
            }
            Spacer()
        }
    }

    private var identityLabel: String {
        if let mbid = recording.identity.mbid { return "Recording MBID · \(mbid.uuidString)" }
        if let msid = recording.identity.msid { return "Recording MSID · \(msid.uuidString)" }
        return "No recording identifier"
    }

    private var shareText: String {
        "\(recording.title) by \(recording.artistName)"
    }

    private func durationLabel(_ milliseconds: Int) -> String {
        let seconds = max(milliseconds, 0) / 1_000
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}
