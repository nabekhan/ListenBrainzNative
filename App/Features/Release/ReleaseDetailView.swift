import SwiftUI

/// Detail for one concrete MusicBrainz release/edition. Release groups remain
/// a separate destination because they do not define an ordered track list.
struct ReleaseDetailView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let release: ReleaseSeed
    @State private var model: ReleaseDetailModel

    init(
        release: ReleaseSeed,
        provider: (any ConcreteReleaseDetailProviding)? = nil,
        cache: EntityDetailCache<UUID, ReleaseDetail> = EntityDetailCaches.releases
    ) {
        self.release = release
        _model = State(initialValue: ReleaseDetailModel(
            seed: release,
            provider: provider,
            cache: cache
        ))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    hero
                    loadNotice
                    facts
                    listenBrainzContext
                    popularity
                    trackList.id("release-track-list")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 44)
            }
            .refreshable { await model.refresh() }
            .background {
                AppTheme.artworkGradient(seed: displayTitle)
                    .opacity(0.12)
                    .ignoresSafeArea()
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .center))
            }
            .navigationTitle(displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Link(destination: release.musicBrainzURL) {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .accessibilityLabel("Open release in MusicBrainz")
                }
            }
            .task {
                await model.load()
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-brainz-release-detail-demo-tracks") {
                    try? await Task.sleep(for: .milliseconds(150))
                    proxy.scrollTo("release-track-list", anchor: .top)
                }
                #endif
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 16) {
            ArtworkView(url: model.detail?.artworkURL ?? release.artworkURL, title: displayTitle, cornerRadius: 24, showsPlaceholderSymbol: false)
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
                Text("Loading this edition’s track list…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(.thinMaterial, in: .rect(cornerRadius: 16, style: .continuous))
        case .refreshing:
            Label("Refreshing edition details…", systemImage: "arrow.clockwise")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        case .unavailable:
            notice(title: "This release is unavailable", message: "Its MusicBrainz identity is still available, but this edition no longer has a track listing to show.")
        case let .failed(message):
            retryNotice(message: message)
        case .ready:
            if let message = model.refreshMessage { retryNotice(message: message) }
        }
    }

    @ViewBuilder
    private var facts: some View {
        if let detail = model.detail {
            section("Release details") {
                LazyVGrid(columns: factColumns, spacing: 14) {
                    fact("Tracks", value: detail.trackCount.formatted(), systemImage: "music.note.list")
                    fact("Duration", value: detail.totalDurationMilliseconds.map(durationLabel) ?? "—", systemImage: "timer")
                    fact("Country", value: detail.country ?? "—", systemImage: "globe")
                    fact("Status", value: detail.status ?? "—", systemImage: "checkmark.seal")
                }
                if let releaseGroupSeed {
                    Divider().padding(.vertical, 2)
                    NavigationLink(value: releaseGroupSeed) {
                        Label("View release group", systemImage: "square.stack.3d.up")
                            .frame(minHeight: 44)
                    }
                    .accessibilityHint("Open the album grouping across editions")
                }
                if !detail.labels.isEmpty {
                    Divider().padding(.vertical, 2)
                    Label(detail.labels.joined(separator: " · "), systemImage: "tag")
                        .font(.subheadline)
                }
                if let barcode = detail.barcode, !barcode.isEmpty {
                    Label(barcode, systemImage: "barcode")
                        .font(.subheadline.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder
    private var listenBrainzContext: some View {
        if let context = release.discoveryContext, context.hasVisibleContent {
            section("ListenBrainz context") {
                ReleaseDiscoveryContextContent(context: context)
            }
        }
    }

    private var popularity: some View {
        PopularitySummaryView(entity: PopularityEntity(kind: .release, mbid: release.mbid))
    }

    @ViewBuilder
    private var trackList: some View {
        if let detail = model.detail, !detail.media.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                if dynamicTypeSize.isAccessibilitySize {
                    SectionHeader(title: "Track list")
                } else {
                    SectionHeader(
                        title: "Track list",
                        subtitle: "Ordered by this specific MusicBrainz edition"
                    )
                }
                ForEach(detail.media) { medium in
                    VStack(alignment: .leading, spacing: 0) {
                        if detail.media.count > 1 || medium.format != nil || medium.title != nil {
                            Text(mediumTitle(medium))
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                        }
                        ForEach(medium.tracks) { track in
                            trackRow(track)
                            if track.id != medium.tracks.last?.id {
                                Divider().padding(.leading, 58)
                            }
                        }
                    }
                    .background(.thinMaterial, in: .rect(cornerRadius: 18, style: .continuous))
                }
            }
        }
    }

    @ViewBuilder
    private func trackRow(_ track: ReleaseTrack) -> some View {
        if track.recording.identity.mbid != nil {
            NavigationLink(value: track.recording) { trackRowContent(track) }
                .buttonStyle(.plain)
                .accessibilityHint("Open recording details")
        } else {
            trackRowContent(track)
                .accessibilityHint("This track is not mapped to a MusicBrainz recording")
        }
    }

    private func trackRowContent(_ track: ReleaseTrack) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(track.number ?? String(track.position))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 30, alignment: .trailing)
                .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 3) {
                Text(track.recording.title)
                    .font(.body.weight(.semibold))
                if track.recording.artistName != displayArtist {
                    Text(track.recording.artistName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if dynamicTypeSize.isAccessibilitySize,
                   let duration = track.recording.durationMilliseconds {
                    Text(durationLabel(duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if !dynamicTypeSize.isAccessibilitySize,
               let duration = track.recording.durationMilliseconds {
                Text(durationLabel(duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if track.recording.identity.mbid != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(.rect)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private var displayTitle: String { nonempty(model.detail?.title) ?? release.title }
    private var displayArtist: String { nonempty(model.detail?.artistCreditName) ?? release.artistName }
    private var displayType: String? {
        nonempty(model.detail?.releaseGroupPrimaryType) ?? nonempty(release.primaryType)
    }
    private var displayDate: String? { formattedDate(model.detail?.releaseDate ?? release.releaseDate) }

    private var factColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            [GridItem(.flexible(), alignment: .leading)]
        } else {
            [GridItem(.adaptive(minimum: 128), spacing: 12)]
        }
    }

    private var releaseGroupSeed: SearchReleaseGroup? {
        guard let mbid = model.detail?.releaseGroupMBID ?? release.releaseGroupMBID else { return nil }
        return SearchReleaseGroup(
            mbid: mbid,
            title: displayTitle,
            artistName: displayArtist,
            primaryType: model.detail?.releaseGroupPrimaryType ?? release.primaryType,
            firstReleaseDate: model.detail?.releaseDate ?? release.releaseDate
        )
    }

    private func mediumTitle(_ medium: ReleaseMedium) -> String {
        guard let label = medium.title ?? medium.format else {
            return String(localized: "Disc \(medium.position)")
        }
        guard (model.detail?.media.count ?? 0) > 1 else { return label }
        return String(localized: "Disc \(medium.position) · \(label)")
    }

    private func section<Content: View>(
        _ title: LocalizedStringResource,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: .rect(cornerRadius: 18, style: .continuous))
    }

    private func retryNotice(message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Edition details unavailable", systemImage: "wifi.exclamationmark").font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary)
            Button("Try Again") { Task { await model.refresh() } }.buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: .rect(cornerRadius: 18, style: .continuous))
    }

    private func notice(
        title: LocalizedStringResource,
        message: LocalizedStringResource
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: .rect(cornerRadius: 18, style: .continuous))
    }

    private func fact(
        _ label: LocalizedStringResource,
        value: String,
        systemImage: String
    ) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.subheadline.weight(.semibold)).lineLimit(2)
            }
        } icon: {
            Image(systemName: systemImage).foregroundStyle(AppTheme.accent)
        }
    }

    private func durationLabel(_ milliseconds: Int) -> String {
        let seconds = max(milliseconds, 0) / 1_000
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func formattedDate(_ value: String?) -> String? {
        guard let value = nonempty(value) else { return nil }
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return value }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        guard let date = calendar.date(from: DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: year, month: month, day: day, hour: 12)) else { return value }
        return date.formatted(.dateTime.year().month(.abbreviated).day())
    }
}

struct ReleaseDiscoveryContextContent: View {
    let context: ReleaseDiscoveryContext

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let count = context.listenCount {
                Label(
                    count == 1
                        ? String(localized: "\(count.formatted()) ListenBrainz listen")
                        : String(localized: "\(count.formatted()) ListenBrainz listens"),
                    systemImage: "waveform"
                )
                .font(.subheadline.weight(.semibold))
            }
            if let confidence = context.confidence {
                Label(
                    "Fresh Releases confidence \(confidence.formatted(.number.precision(.fractionLength(0 ... 2))))",
                    systemImage: "sparkles"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHint("A raw ListenBrainz relevance signal, not a percentage")
            }
            if !context.tags.isEmpty {
                Text(context.tags.prefix(8).joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
