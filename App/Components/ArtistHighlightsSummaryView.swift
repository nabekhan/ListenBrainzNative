import SwiftUI

private struct ArtistHighlightsProviderEnvironmentKey: EnvironmentKey {
    static let defaultValue: (any ArtistHighlightsProviding)? = nil
}

extension EnvironmentValues {
    var artistHighlightsProvider: (any ArtistHighlightsProviding)? {
        get { self[ArtistHighlightsProviderEnvironmentKey.self] }
        set { self[ArtistHighlightsProviderEnvironmentKey.self] = newValue }
    }
}

struct ArtistHighlightsSummaryView: View {
    @Environment(\.artistHighlightsProvider) private var provider
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model: ArtistHighlightsModel?
    @State private var showsAll = false
    @State private var retryTask: Task<Void, Never>?

    let artistMBID: UUID

    var body: some View {
        Group {
            switch model?.phase ?? .idle {
            case .idle, .loading:
                loadingShelf
            case let .loaded(highlights):
                loadedShelf(highlights)
            case .unavailable:
                EmptyView()
            case .failed:
                failureCard
            }
        }
        .task(id: artistMBID) {
            let current = ArtistHighlightsModel(
                artistMBID: artistMBID,
                provider: provider ?? ListenBrainzArtistHighlightsProvider()
            )
            model = current
            showsAll = false
            await current.load()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-brainz-artist-highlights-releases-demo") {
                current.select(.releases)
            }
            #endif
        }
        .onDisappear {
            retryTask?.cancel()
            retryTask = nil
        }
    }

    private var loadingShelf: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Popular on ListenBrainz",
                subtitle: "Community rankings, separate from your listening history"
            )

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in loadingRow }
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(0..<4, id: \.self) { _ in loadingCell }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading popular music")
    }

    private func loadedShelf(_ highlights: ArtistHighlights) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Popular on ListenBrainz",
                subtitle: "Community rankings, separate from your listening history"
            )

            if hasBothSections(highlights), let model {
                Picker(
                    "Popular music",
                    selection: Binding(
                        get: { model.selection },
                        set: { selection in
                            model.select(selection)
                            showsAll = false
                        }
                    )
                ) {
                    ForEach(ArtistHighlightsSelection.allCases) { selection in
                        Text(selection.title).tag(selection)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Popular music category")
            }

            switch model?.selection ?? .tracks {
            case .tracks:
                recordingContent(highlights.recordings)
            case .releases:
                releaseGroupContent(highlights.releaseGroups)
            }
        }
    }

    @ViewBuilder
    private func recordingContent(_ recordings: [ArtistPopularRecording]) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 0) {
                ForEach(Array(visible(recordings).enumerated()), id: \.element.id) { index, recording in
                    NavigationLink(value: recording.recording) {
                        accessibilityRecordingRow(recording, rank: index + 1)
                    }
                    .buttonStyle(.plain)
                    if recording.id != visible(recordings).last?.id {
                        Divider().padding(.leading, 78)
                    }
                }
            }
        } else {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(Array(visible(recordings).enumerated()), id: \.element.id) { index, recording in
                        NavigationLink(value: recording.recording) {
                            recordingCell(recording, rank: index + 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }

        expansionButton(total: recordings.count, kind: .tracks)
    }

    @ViewBuilder
    private func releaseGroupContent(_ releaseGroups: [ArtistPopularReleaseGroup]) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 0) {
                ForEach(Array(visible(releaseGroups).enumerated()), id: \.element.id) { index, releaseGroup in
                    NavigationLink(value: releaseGroup.releaseGroup) {
                        accessibilityReleaseGroupRow(releaseGroup, rank: index + 1)
                    }
                    .buttonStyle(.plain)
                    if releaseGroup.id != visible(releaseGroups).last?.id {
                        Divider().padding(.leading, 78)
                    }
                }
            }
        } else {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(Array(visible(releaseGroups).enumerated()), id: \.element.id) { index, releaseGroup in
                        NavigationLink(value: releaseGroup.releaseGroup) {
                            releaseGroupCell(releaseGroup, rank: index + 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }

        expansionButton(total: releaseGroups.count, kind: .releases)
    }

    private func recordingCell(_ recording: ArtistPopularRecording, rank: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            rankedArtwork(url: recording.artworkURL, title: recording.title, rank: rank, size: artworkSize)
            Text(recording.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(recording.releaseTitle ?? recording.artistName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            compactCountMetrics(
                listens: recording.totalListenCount,
                listeners: recording.totalUserCount
            )
        }
        .frame(width: cellWidth, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(
            rank: rank,
            title: recording.title,
            detail: recording.releaseTitle ?? recording.artistName,
            listens: recording.totalListenCount,
            listeners: recording.totalUserCount
        ))
        .accessibilityHint("Opens recording details")
    }

    private func releaseGroupCell(_ releaseGroup: ArtistPopularReleaseGroup, rank: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            rankedArtwork(url: releaseGroup.artworkURL, title: releaseGroup.title, rank: rank, size: artworkSize)
            Text(releaseGroup.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(releaseGroupMetadata(releaseGroup))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            compactCountMetrics(
                listens: releaseGroup.totalListenCount,
                listeners: releaseGroup.totalUserCount
            )
        }
        .frame(width: cellWidth, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(
            rank: rank,
            title: releaseGroup.title,
            detail: releaseGroupMetadata(releaseGroup),
            listens: releaseGroup.totalListenCount,
            listeners: releaseGroup.totalUserCount
        ))
        .accessibilityHint("Opens release group details")
    }

    private func accessibilityRecordingRow(_ recording: ArtistPopularRecording, rank: Int) -> some View {
        accessibilityRow(
            url: recording.artworkURL,
            title: recording.title,
            detail: recording.releaseTitle ?? recording.artistName,
            rank: rank,
            listens: recording.totalListenCount,
            listeners: recording.totalUserCount,
            hint: String(localized: "Opens recording details")
        )
    }

    private func accessibilityReleaseGroupRow(_ releaseGroup: ArtistPopularReleaseGroup, rank: Int) -> some View {
        accessibilityRow(
            url: releaseGroup.artworkURL,
            title: releaseGroup.title,
            detail: releaseGroupMetadata(releaseGroup),
            rank: rank,
            listens: releaseGroup.totalListenCount,
            listeners: releaseGroup.totalUserCount,
            hint: String(localized: "Opens release group details")
        )
    }

    private func accessibilityRow(
        url: URL?,
        title: String,
        detail: String,
        rank: Int,
        listens: Int?,
        listeners: Int?,
        hint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("#\(rank)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
                ArtworkView(url: url, title: title, cornerRadius: 10)
                    .frame(width: 58, height: 58)
                    .accessibilityHidden(true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let summary = fullCountSummary(listens: listens, listeners: listeners) {
                Text(summary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(
            rank: rank,
            title: title,
            detail: detail,
            listens: listens,
            listeners: listeners
        ))
        .accessibilityHint(hint)
    }

    private func rankedArtwork(url: URL?, title: String, rank: Int, size: CGFloat) -> some View {
        ArtworkView(url: url, title: title, cornerRadius: 12)
            .frame(width: size, height: size)
            .overlay(alignment: .topLeading) {
                Text("#\(rank)")
                    .font(.caption.bold().monospacedDigit())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: .capsule)
                    .padding(7)
                    .accessibilityHidden(true)
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func expansionButton(total: Int, kind: RankedContentKind) -> some View {
        if total > previewCount {
            Button(expansionTitle(total: total, kind: kind)) {
                withAnimation(.snappy) { showsAll.toggle() }
            }
            .buttonStyle(.bordered)
            .accessibilityHint(expansionHint(kind: kind))
        }
    }

    private func expansionTitle(total: Int, kind: RankedContentKind) -> String {
        switch (showsAll, kind) {
        case (true, .tracks):
            String(localized: "Show fewer tracks")
        case (true, .releases):
            String(localized: "Show fewer releases")
        case (false, .tracks):
            String(localized: "Show all \(total) tracks")
        case (false, .releases):
            String(localized: "Show all \(total) releases")
        }
    }

    private func expansionHint(kind: RankedContentKind) -> String {
        switch (showsAll, kind) {
        case (true, .tracks):
            String(localized: "Shows the first \(previewCount) tracks")
        case (true, .releases):
            String(localized: "Shows the first \(previewCount) releases")
        case (false, .tracks):
            String(localized: "Shows every track in this ListenBrainz ranking")
        case (false, .releases):
            String(localized: "Shows every release in this ListenBrainz ranking")
        }
    }

    private var failureCard: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Popular music unavailable")
                    .font(.subheadline.weight(.semibold))
                Text("The rest of this artist page is still available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Try again") {
                guard let model else { return }
                retryTask?.cancel()
                retryTask = Task { await model.retry() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: .rect(cornerRadius: 18, style: .continuous))
    }

    private var loadingCell: some View {
        VStack(alignment: .leading, spacing: 9) {
            RoundedRectangle(cornerRadius: 12)
                .fill(.secondary.opacity(0.14))
                .frame(width: artworkSize, height: artworkSize)
            RoundedRectangle(cornerRadius: 4)
                .fill(.secondary.opacity(0.14))
                .frame(width: cellWidth * 0.8, height: 13)
            RoundedRectangle(cornerRadius: 4)
                .fill(.secondary.opacity(0.1))
                .frame(width: cellWidth * 0.58, height: 10)
        }
        .frame(width: cellWidth, alignment: .leading)
    }

    private var loadingRow: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(.secondary.opacity(0.14))
                .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.secondary.opacity(0.14))
                    .frame(maxWidth: 220)
                    .frame(height: 16)
                RoundedRectangle(cornerRadius: 4)
                    .fill(.secondary.opacity(0.1))
                    .frame(maxWidth: 150)
                    .frame(height: 12)
            }
            Spacer(minLength: 0)
        }
    }

    private func hasBothSections(_ highlights: ArtistHighlights) -> Bool {
        !highlights.recordings.isEmpty && !highlights.releaseGroups.isEmpty
    }

    private func visible<Element>(_ values: [Element]) -> [Element] {
        Array(values.prefix(showsAll ? values.count : previewCount))
    }

    private func releaseGroupMetadata(_ releaseGroup: ArtistPopularReleaseGroup) -> String {
        let year = releaseGroup.firstReleaseDate?.prefix(4).description
        let facts = [releaseGroup.primaryType, year].compactMap { $0 }
        return facts.isEmpty ? releaseGroup.artistName : facts.joined(separator: " · ")
    }

    @ViewBuilder
    private func compactCountMetrics(listens: Int?, listeners: Int?) -> some View {
        if listens != nil || listeners != nil {
            HStack(spacing: 10) {
                if let listens {
                    Label(
                        listens.formatted(.number.notation(.compactName)),
                        systemImage: "waveform"
                    )
                }
                if let listeners {
                    Label(
                        listeners.formatted(.number.notation(.compactName)),
                        systemImage: "person"
                    )
                }
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    private func fullCountSummary(listens: Int?, listeners: Int?) -> String? {
        joinedCounts(
            listens: listens,
            listeners: listeners,
            formatter: { $0.formatted(.number.grouping(.automatic)) }
        )
    }

    private func joinedCounts(
        listens: Int?,
        listeners: Int?,
        formatter: (Int) -> String
    ) -> String? {
        let listenText = listens.map {
            let count = formatter($0)
            return $0 == 1
                ? String(localized: "\(count) listen")
                : String(localized: "\(count) listens")
        }
        let listenerText = listeners.map {
            let count = formatter($0)
            return $0 == 1
                ? String(localized: "\(count) listener")
                : String(localized: "\(count) listeners")
        }
        let values = [listenText, listenerText].compactMap { $0 }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    private func accessibilityLabel(
        rank: Int,
        title: String,
        detail: String,
        listens: Int?,
        listeners: Int?
    ) -> String {
        if let counts = fullCountSummary(listens: listens, listeners: listeners) {
            return String(localized: "\(rank). \(title), \(detail), \(counts) across ListenBrainz")
        }
        return String(localized: "\(rank). \(title), \(detail)")
    }

    private enum RankedContentKind {
        case tracks
        case releases
    }

    private let artworkSize: CGFloat = 132
    private let cellWidth: CGFloat = 140
    private let previewCount = 5
}
