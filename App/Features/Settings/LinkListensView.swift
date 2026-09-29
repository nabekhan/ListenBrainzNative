import SwiftUI

struct LinkListensView: View {
    @State private var model: LinkListensModel
    @State private var query = ""
    @State private var selectedListen: Listen?
    @State private var actionTask: Task<Void, Never>?

    init(
        account: Account,
        provider: (any LinkListensProviding)? = nil,
        cache: EntityDetailCache<LinkListensCacheKey, LinkListensPage> = LinkListensCaches.pages
    ) {
        _model = State(
            initialValue: LinkListensModel(
                account: account,
                provider: provider,
                cache: cache
            )
        )
    }

    var body: some View {
        Group {
            switch model.phase {
            case .idle, .loading:
                ProgressView("Loading unmatched listens…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message) where model.retainedCount == 0:
                ContentUnavailableView {
                    Label("Couldn’t load unmatched listens", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { startAction { await model.refresh() } }
                }
            default:
                content
            }
        }
        .accessibilityIdentifier("link-listens-screen")
        .navigationTitle("Link listens")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if model.phase == .refreshing {
                    ProgressView()
                        .accessibilityLabel("Refreshing unmatched listens")
                } else if model.phase == .loaded {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        startAction { await model.refresh() }
                    }
                }
            }
        }
        .task { await model.load() }
        .onDisappear {
            actionTask?.cancel()
            actionTask = nil
            model.cancel()
        }
        .sheet(item: $selectedListen) { listen in
            ManualMappingSheet(listen: listen, account: model.account) { _ in
                guard let msid = listen.recording.identity.msid else { return }
                Task { await model.removeMapped(msid: msid) }
            }
        }
    }

    private var content: some View {
        let groups = model.groups.filter(matches)
        return List {
            introduction

            if let message = model.refreshMessage {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Try again") { startAction { await model.refresh() } }
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.vertical, 4)
                }
            }

            if model.retainedCount == 0 {
                ContentUnavailableView(
                    "No unmatched listens",
                    systemImage: "checkmark.circle",
                    description: Text("ListenBrainz didn’t find any in its latest scan.")
                )
                .listRowBackground(Color.clear)
            } else if groups.isEmpty {
                ContentUnavailableView.search(text: query)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.listens) { listen in
                            listenRow(listen)
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.title)
                                .font(.subheadline.weight(.semibold))
                                .textCase(nil)
                            Text(group.artistName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                        }
                    }
                }
            }
        }
        .modifier(
            LinkListensSearchModifier(
                query: $query,
                isEnabled: model.retainedCount > 0
            )
        )
    }

    private var introduction: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Label("Match your listening history", systemImage: "link.badge.plus")
                    .font(.headline)
                    .foregroundStyle(AppTheme.accent)

                Text("Link unmatched listens to MusicBrainz for richer artwork, statistics, and music details.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                LabeledContent("Unmatched listens") {
                    Text(model.retainedCount, format: .number)
                        .monospacedDigit()
                }

                if model.page.totalDataCount > model.retainedCount {
                    LabeledContent("Available from ListenBrainz") {
                        Text(model.page.totalDataCount, format: .number)
                            .monospacedDigit()
                    }
                }

                if let lastUpdated = model.page.lastUpdated {
                    LabeledContent("Last scanned") {
                        Text(lastUpdated, format: .dateTime.month().day().year().hour().minute())
                            .multilineTextAlignment(.trailing)
                    }
                }

                Text("ListenBrainz refreshes this list weekly. Choose a listen to find its MusicBrainz match.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 5)
        }
    }

    private func listenRow(_ listen: Listen) -> some View {
        Button { selectedListen = listen } label: {
            HStack(spacing: 12) {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.headline)
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 38, height: 38)
                    .background(
                        AppTheme.accent.opacity(0.12),
                        in: .rect(cornerRadius: 10, style: .continuous)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(listen.recording.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                    Text(listen.listenedAt, format: .dateTime.month().day().year().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Find a MusicBrainz match for this listen")
        .accessibilityIdentifier(
            "link-listens-row-\(listen.recording.identity.msid?.uuidString ?? listen.id)"
        )
    }

    private func matches(_ group: LinkListensGroup) -> Bool {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return true }
        return group.title.localizedCaseInsensitiveContains(text)
            || group.artistName.localizedCaseInsensitiveContains(text)
            || group.listens.contains {
                $0.recording.title.localizedCaseInsensitiveContains(text)
            }
    }

    private func startAction(_ action: @escaping @MainActor () async -> Void) {
        actionTask?.cancel()
        actionTask = Task { await action() }
    }
}

private struct LinkListensSearchModifier: ViewModifier {
    @Binding var query: String
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.searchable(text: $query, prompt: "Search unmatched listens")
        } else {
            content
        }
    }
}

#if DEBUG
struct LinkListensVisualQAScreen: View {
    enum Result {
        case populated
        case empty
        case failure
    }

    let result: Result

    var body: some View {
        NavigationStack {
            LinkListensView(
                account: .init(username: "visual-link-listens", token: "visual-token"),
                provider: LinkListensVisualQAProvider(result: result),
                cache: EntityDetailCache()
            )
        }
    }
}

private struct LinkListensVisualQAProvider: LinkListensProviding {
    let result: LinkListensVisualQAScreen.Result

    func unmatchedListens(username _: String) async throws -> LinkListensPage {
        switch result {
        case .empty:
            return .init(listens: [], totalDataCount: 0, lastUpdated: nil)
        case .failure:
            throw LinkListensProviderError.unavailable
        case .populated:
            let album = "A long album title for grouped unmatched listens"
            return .init(
                listens: [
                    fixture("First unmatched track", "Visual Artist", album, 1),
                    fixture("Second unmatched track", "Visual Artist", album, 2),
                    fixture("Single without a release", "Another Artist", nil, 3),
                ],
                totalDataCount: 3,
                lastUpdated: .now
            )
        }
    }

    private func fixture(
        _ title: String,
        _ artist: String,
        _ release: String?,
        _ seconds: TimeInterval
    ) -> Listen {
        let msid = UUID()
        return .init(
            recording: .init(
                identity: .init(mbid: nil, msid: msid),
                title: title,
                artistName: artist,
                artistMBIDs: [],
                releaseTitle: release,
                releaseMBID: nil,
                releaseGroupMBID: nil,
                artworkReleaseMBID: nil,
                durationMilliseconds: nil,
                source: nil
            ),
            listenedAt: .now.addingTimeInterval(-seconds),
            insertedAt: nil,
            isPlayingNow: false,
            inspection: .init(
                submittedArtist: artist,
                submittedTrack: title,
                submittedRelease: release,
                recordingMSID: msid,
                submittedRecordingMSID: msid,
                submittedArtistMBIDs: [],
                submittedRecordingMBID: nil,
                submittedReleaseMBID: nil,
                submittedReleaseGroupMBID: nil,
                submittedTrackMBID: nil,
                submittedWorkMBIDs: [],
                resolvedArtistMBIDs: [],
                resolvedRecordingMBID: nil,
                resolvedReleaseMBID: nil,
                resolvedReleaseGroupMBID: nil,
                resolvedRecordingName: nil,
                trackNumber: nil,
                isrc: nil,
                spotifyID: nil,
                tags: [],
                mediaPlayer: nil,
                mediaPlayerVersion: nil,
                submissionClient: nil,
                submissionClientVersion: nil,
                musicService: nil,
                musicServiceName: nil,
                originURL: nil,
                durationMilliseconds: nil
            )
        )
    }
}
#endif
