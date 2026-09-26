import SwiftUI

struct FollowingPinsView: View {
    let account: Account
    @Bindable var listeningModel: ListeningModel
    @State private var model: FollowingPinsModel
    @State private var actionTask: Task<Void, Never>?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(account: Account, listeningModel: ListeningModel) {
        self.account = account
        _listeningModel = Bindable(wrappedValue: listeningModel)
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-brainz-following-pins-empty-demo") {
            _model = State(initialValue: FollowingPinsModel(
                username: account.username,
                provider: FollowingPinsPreviewProvider.empty,
                cache: EntityDetailCache()
            ))
        } else if arguments.contains("-brainz-following-pins-failure-demo") {
            _model = State(initialValue: FollowingPinsModel(
                username: account.username,
                provider: FollowingPinsPreviewProvider.failure,
                cache: EntityDetailCache()
            ))
        } else if arguments.contains("-brainz-following-pins-demo") {
            _model = State(initialValue: FollowingPinsModel(
                username: account.username,
                provider: FollowingPinsPreviewProvider.populated,
                cache: EntityDetailCache(),
                pageSize: 3
            ))
        } else {
            _model = State(initialValue: FollowingPinsModel(username: account.username))
        }
        #else
        _model = State(initialValue: FollowingPinsModel(username: account.username))
        #endif
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if !dynamicTypeSize.isAccessibilitySize {
                    hero
                }
                content
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 44)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Following pins")
        .navigationBarTitleDisplayMode(dynamicTypeSize.isAccessibilitySize ? .inline : .large)
        .refreshable { await model.refresh() }
        .task { await model.load() }
        .onDisappear {
            actionTask?.cancel()
            actionTask = nil
            model.cancel()
        }
        .mediaDestinations(model: listeningModel)
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: "pin.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(AppTheme.artworkGradient(seed: "following-pins"), in: .rect(cornerRadius: 17, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("Chosen by your circle")
                    .font(.headline)
                Text("Tracks pinned by people you follow")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle, .loading:
            ProgressView("Loading pins from your network…")
                .frame(maxWidth: .infinity, minHeight: 260)
        case let .failed(message):
            ContentUnavailableView {
                Label("Following pins couldn’t load", systemImage: "wifi.exclamationmark")
            } description: { Text(message) } actions: {
                Button("Try again") { startAction { await model.refresh() } }
            }
            .frame(maxWidth: .infinity, minHeight: 280)
        case .ready:
            if model.pins.isEmpty {
                ContentUnavailableView(
                    "No pins from your network",
                    systemImage: "pin.slash",
                    description: Text("When someone you follow pins a track, it will appear here.")
                )
                .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                pins
            }
        }
    }

    private var pins: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let message = model.refreshMessage { warning(message) { await model.refresh() } }
            ForEach(model.pins, id: \.followingPinIdentity) { pin in
                FollowingPinCard(pin: pin, viewer: account)
            }
            if model.isLoadingMore {
                ProgressView("Loading more pins…")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else if let message = model.loadMoreError {
                warning(message) { await model.loadMore() }
            } else if model.hasMore {
                Button("Load more pins") { startAction { await model.loadMore() } }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.bordered)
            } else {
                Label("No more pins right now.", systemImage: "checkmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
        }
    }

    private func warning(_ message: String, retry: @escaping @MainActor () async -> Void) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.footnote).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Retry") { startAction(retry) }.font(.footnote.weight(.semibold))
        }
        .padding(12)
        .background(.thinMaterial, in: .rect(cornerRadius: 14, style: .continuous))
    }

    private func startAction(_ action: @escaping @MainActor () async -> Void) {
        actionTask?.cancel()
        actionTask = Task { await action() }
    }
}

private struct FollowingPinCard: View {
    let pin: PinnedRecording
    let viewer: Account
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            NavigationLink(value: pin.recording) {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 10) {
                            artwork(size: 108)
                            recordingDetails
                        }
                    } else {
                        HStack(alignment: .top, spacing: 13) {
                            artwork(size: 74)
                            recordingDetails
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.forward")
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Open recording details")
            if let blurb = pin.blurb?.trimmingCharacters(in: .whitespacesAndNewlines), !blurb.isEmpty {
                Text(blurb).font(.subheadline).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
            }
            if let username = pin.username?.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty {
                NavigationLink {
                    UserDetailView(user: SearchUser(username: username), viewer: viewer)
                } label: {
                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 7) {
                                UserAvatar(username: username, size: 36)
                                Text(username)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                pinnedTime
                            }
                        } else {
                            HStack(spacing: 9) {
                                UserAvatar(username: username, size: 28)
                                Text(username).font(.footnote.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                                Spacer(minLength: 0)
                                pinnedTime
                            }
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Open \(username)’s profile")
            }
        }
        .padding(14)
        .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func artwork(size: CGFloat) -> some View {
        ArtworkView(
            url: pin.recording.artworkURL,
            title: pin.recording.releaseTitle ?? pin.recording.title,
            cornerRadius: 14
        )
        .frame(width: size, height: size)
    }

    private var recordingDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pin.recording.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            Text(pin.recording.artistName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            if let release = pin.recording.releaseTitle {
                Text(release)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            }
        }
    }

    private var pinnedTime: some View {
        Text(String(localized: "Pinned \(pin.created.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))"))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

#if DEBUG
private struct FollowingPinsPreviewProvider: FollowingPinsProviding {
    let result: Result<FollowingPinsPage, Error>
    func page(username: String, count: Int, offset: Int) async throws -> FollowingPinsPage {
        let page = try result.get()
        guard offset == 0 else {
            return FollowingPinsPage(username: page.username, pins: [], serverCount: 0, offset: offset)
        }
        return page
    }

    static let populated = FollowingPinsPreviewProvider(result: .success(.init(
        username: "visual-listener", pins: [
            pin(1, "long-form-listener-with-an-exceptionally-careful-music-journal", "Long Way Home", "A Very Long Artist Credit That Holds Together", "A thoughtful note about a track that keeps revealing itself on late walks."),
            pin(2, "bluehour", "Horizon", "Still Corners", nil),
            pin(3, "tape-archive", "Soft Focus", "Fazerdaze", "A new favorite."),
        ], serverCount: 3, offset: 0
    )))
    static let empty = FollowingPinsPreviewProvider(result: .success(.init(username: "visual-listener", pins: [], serverCount: 0, offset: 0)))
    static let failure = FollowingPinsPreviewProvider(result: .failure(FollowingPinsPreviewError.unavailable))

    private static func pin(_ row: Int, _ user: String, _ title: String, _ artist: String, _ blurb: String?) -> PinnedRecording {
        PinnedRecording(rowID: row, created: .now.addingTimeInterval(TimeInterval(-row * 3_600)), pinnedUntil: nil, blurb: blurb, username: user, recording: .init(identity: .init(mbid: nil, msid: nil), title: title, artistName: artist, artistMBIDs: [], releaseTitle: nil, releaseMBID: nil, releaseGroupMBID: nil, artworkReleaseMBID: nil, durationMilliseconds: nil, source: nil), isCurrent: true)
    }
}
private enum FollowingPinsPreviewError: LocalizedError {
    case unavailable

    var errorDescription: String? { String(localized: "Check your connection, then try again.") }
}
#endif
