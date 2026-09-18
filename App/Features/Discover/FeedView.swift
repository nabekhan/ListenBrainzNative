import SwiftUI

struct FeedView: View {
    let account: Account
    @Bindable var listeningModel: ListeningModel
    @State private var model: FeedModel
    @State private var mode: FeedMode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(account: Account, listeningModel: ListeningModel) {
        self.account = account
        _listeningModel = Bindable(wrappedValue: listeningModel)

        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-brainz-feed-demo") {
            _model = State(initialValue: FeedModel(
                account: Account(username: account.username, token: "visual-qa"),
                provider: FeedPreviewProvider(),
                cache: EntityDetailCache()
            ))
        } else {
            _model = State(initialValue: FeedModel(account: account))
        }
        let initialMode: FeedMode
        if arguments.contains("-brainz-feed-similar") {
            initialMode = .similar
        } else if arguments.contains("-brainz-feed-following") {
            initialMode = .following
        } else {
            initialMode = .activity
        }
        _mode = State(initialValue: initialMode)
        #else
        _model = State(initialValue: FeedModel(account: account))
        _mode = State(initialValue: .activity)
        #endif
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                hero
                modePicker
                content
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 44)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Listening Network")
        .navigationBarTitleDisplayMode(dynamicTypeSize.isAccessibilitySize ? .inline : .large)
        .refreshable { await model.refresh(mode: mode) }
        .task(id: mode) { await model.load(mode: mode) }
        .mediaDestinations(model: listeningModel)
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppTheme.heroGradient)

            Circle()
                .fill(.white.opacity(0.10))
                .frame(width: 170, height: 170)
                .offset(x: 235, y: -55)

            VStack(alignment: .leading, spacing: 8) {
                Label("Your ListenBrainz circle", systemImage: "person.2.wave.2.fill")
                    .font((dynamicTypeSize.isAccessibilitySize ? Font.caption : .subheadline).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Text("Music travels\nthrough people.")
                    .font(dynamicTypeSize.isAccessibilitySize
                        ? .title3.weight(.bold)
                        : .system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                Text("See what your network is sharing and hearing now.")
                    .font(dynamicTypeSize.isAccessibilitySize ? .footnote : .subheadline)
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
        .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 0 : 170)
        .clipped()
        .accessibilityElement(children: .combine)
    }

    private var modePicker: some View {
        Picker("Feed", selection: $mode) {
            ForEach(FeedMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityHint("My Feed shows social activity. Following and Similar show recent network listens.")
    }

    @ViewBuilder
    private var content: some View {
        let state = model.state(for: mode)
        switch state.phase {
        case .idle, .loading:
            loading
        case .requiresAuthentication:
            authenticationRequired
        case let .failed(message):
            failure(message)
        case .refreshing, .ready:
            if state.events.isEmpty {
                empty
            } else {
                timeline(state)
            }
        }
    }

    private var loading: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(mode == .activity ? "Opening your feed…" : "Finding recent listens…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var authenticationRequired: some View {
        ContentUnavailableView {
            Label("Sign in for your feed", systemImage: "lock.fill")
        } description: {
            Text("ListenBrainz keeps network feeds private. Open Profile, sign out of public browsing, then reconnect with your user token.")
        }
        .frame(maxWidth: .infinity, minHeight: 290)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private var empty: some View {
        ContentUnavailableView(
            emptyTitle,
            systemImage: mode == .activity ? "bubble.left.and.bubble.right" : "waveform",
            description: Text(emptyDescription)
        )
        .frame(maxWidth: .infinity, minHeight: 270)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private func failure(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Feed unavailable", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { Task { await model.refresh(mode: mode) } }
        }
        .frame(maxWidth: .infinity, minHeight: 290)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private func timeline(_ state: FeedModeState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: sectionTitle, subtitle: sectionSubtitle)

            if let message = state.refreshMessage {
                inlineWarning(message) { await model.refresh(mode: mode) }
            }

            ForEach(dayGroups(state.events)) { group in
                Text(dayTitle(group.day))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                ForEach(group.events) { event in
                    FeedEventCard(event: event, viewer: account)
                        .task {
                            guard event.id == state.events.last?.id else { return }
                            await model.loadMore(mode: mode)
                        }
                }
            }

            if state.isLoadingMore {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading earlier activity…")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            } else if let message = state.loadMoreError {
                inlineWarning(message) { await model.loadMore(mode: mode) }
            } else if !state.hasMore, mode != .activity {
                Label("Recent network window complete", systemImage: "checkmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
        }
    }

    private func inlineWarning(
        _ message: String,
        retry: @escaping @MainActor () async -> Void
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Retry") { Task { await retry() } }
                .font(.footnote.weight(.semibold))
        }
        .padding(12)
        .background(.thinMaterial, in: .rect(cornerRadius: 14, style: .continuous))
    }

    private var sectionTitle: String {
        switch mode {
        case .activity: "From your circle"
        case .following: "Recently heard by people you follow"
        case .similar: "Recently heard by similar listeners"
        }
    }

    private var sectionSubtitle: String {
        switch mode {
        case .activity:
            "Pins, recommendations, follows, reviews, and thanks"
        case .following:
            "A recent seven-day window from your listening network"
        case .similar:
            "A recent seven-day window, ranked by ListenBrainz taste similarity"
        }
    }

    private var emptyTitle: String {
        switch mode {
        case .activity: "Your feed is quiet"
        case .following: "No recent listens from people you follow"
        case .similar: "No recent listens from similar users"
        }
    }

    private var emptyDescription: String {
        switch mode {
        case .activity:
            "Follow listeners and share pins or recommendations on ListenBrainz to make this space more useful."
        case .following:
            "Recent plays will appear here when people in your network listen."
        case .similar:
            "ListenBrainz may need more listening history before it can build this view."
        }
    }

    private func dayGroups(_ events: [FeedEvent]) -> [FeedDayGroup] {
        let calendar = Calendar.autoupdatingCurrent
        var groups: [FeedDayGroup] = []
        for event in events {
            let day = calendar.startOfDay(for: event.created)
            if groups.last?.day == day {
                groups[groups.count - 1].events.append(event)
            } else {
                groups.append(FeedDayGroup(day: day, events: [event]))
            }
        }
        return groups
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

private struct FeedDayGroup: Identifiable {
    let day: Date
    var events: [FeedEvent]
    var id: Date { day }
}

private struct FeedEventCard: View {
    let event: FeedEvent
    let viewer: Account
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if event.hidden {
                hiddenContent
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    Divider()
                    eventContent
                }
            }
        }
        .padding(15)
        .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var header: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 9) {
                actorLink
                timestamp
            }
        } else {
            HStack(alignment: .center, spacing: 10) {
                actorLink
                Spacer(minLength: 8)
                timestamp
            }
        }
    }

    private var actorLink: some View {
        NavigationLink {
            UserDetailView(user: SearchUser(username: event.userName), viewer: viewer)
        } label: {
            HStack(spacing: 10) {
                FeedAvatar(username: event.userName, symbol: eventSymbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isViewer ? "You" : event.userName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(actionDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Open \(event.userName)’s profile")
    }

    private var timestamp: some View {
        Text(event.created.formatted(date: .omitted, time: .shortened))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.tertiary)
            .accessibilityLabel("Activity at \(event.created.formatted(date: .complete, time: .shortened))")
    }

    @ViewBuilder
    private var eventContent: some View {
        switch event.kind {
        case .follow:
            followContent
        case .notification:
            messageContent(event.message ?? "ListenBrainz shared an update.", symbol: "bell.fill")
        case .critiquebrainzReview:
            reviewContent
        case .thanks:
            thanksContent
        case .listen, .recordingRecommendation, .recordingPin, .personalRecordingRecommendation:
            if let recording = event.recording {
                recordingContent(recording)
            } else {
                genericContent
            }
        case .unknown:
            if let recording = event.recording {
                recordingContent(recording)
            } else {
                genericContent
            }
        }
    }

    private var hiddenContent: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Hidden activity").font(.subheadline.weight(.semibold))
                Text("This event stays private because it was hidden on ListenBrainz.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "eye.slash.fill")
                .foregroundStyle(.secondary)
        }
    }

    private func recordingContent(_ recording: Recording) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            NavigationLink(value: recording) {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 10) {
                            ArtworkView(url: recording.artworkURL, title: recording.title, cornerRadius: 13)
                                .frame(width: 96, height: 96)
                            recordingText(recording)
                        }
                    } else {
                        HStack(spacing: 13) {
                            ArtworkView(url: recording.artworkURL, title: recording.title, cornerRadius: 13)
                                .frame(width: 72, height: 72)
                            recordingText(recording)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Open recording details")

            if let blurb = event.blurb?.trimmingCharacters(in: .whitespacesAndNewlines), !blurb.isEmpty {
                Text("“\(blurb)”")
                    .font(.subheadline.italic())
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
            }

            if case .personalRecordingRecommendation = event.kind, !event.users.isEmpty {
                Label(recipientDescription, systemImage: "paperplane.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.accent)
            }
        }
    }

    private func recordingText(_ recording: Recording) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recording.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(recording.artistName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let release = recording.releaseTitle, !release.isEmpty {
                Text(release)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            if let similarity = event.similarity {
                Text(min(max(similarity, 0), 1), format: .percent.precision(.fractionLength(0)))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .accessibilityLabel("Taste similarity \(min(max(similarity, 0), 1).formatted(.percent.precision(.fractionLength(0))))")
            }
        }
    }

    @ViewBuilder
    private var followContent: some View {
        if let target = event.userName1, !target.isEmpty {
            NavigationLink {
                UserDetailView(user: SearchUser(username: target), viewer: viewer)
            } label: {
                HStack(spacing: 12) {
                    FeedAvatar(username: target, symbol: "person.fill")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(target)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("New listening connection")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Open \(target)’s profile")
        } else {
            genericContent
        }
    }

    private var reviewContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(event.entityName ?? "Music review", systemImage: "quote.bubble.fill")
                .font(.headline)
            if let rating = event.rating {
                HStack(spacing: 3) {
                    ForEach(1 ... 5, id: \.self) { value in
                        Image(systemName: value <= min(max(rating, 0), 5) ? "star.fill" : "star")
                    }
                }
                .font(.caption)
                .foregroundStyle(.yellow)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Rated \(rating) out of 5")
            }
            if let text = event.text, !text.isEmpty {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(7)
            }
        }
    }

    private var thanksContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(thanksDescription, systemImage: "hands.sparkles.fill")
                .font(.headline)
            if let blurb = event.blurb, !blurb.isEmpty {
                Text(blurb)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
            }
        }
    }

    private func messageContent(_ message: String, symbol: String) -> some View {
        Label {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(6)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(AppTheme.accent)
        }
    }

    private var genericContent: some View {
        messageContent("New ListenBrainz activity is available. Open the website for any actions this app does not understand yet.", symbol: "sparkles")
    }

    private var actionDescription: String {
        switch event.kind {
        case .listen: "listened to"
        case .recordingRecommendation: "recommended a track"
        case .recordingPin: "pinned a track"
        case .personalRecordingRecommendation:
            event.users.contains { normalized($0) == normalized(viewer.username) }
                ? "sent you a recommendation"
                : "shared a personal recommendation"
        case .follow: "followed a listener"
        case .notification: "shared an update"
        case .critiquebrainzReview: "reviewed music"
        case .thanks: "said thanks"
        case .unknown: "shared new activity"
        }
    }

    private var eventSymbol: String {
        switch event.kind {
        case .listen: "waveform"
        case .recordingRecommendation, .personalRecordingRecommendation: "paperplane.fill"
        case .recordingPin: "pin.fill"
        case .follow: "person.badge.plus"
        case .notification: "bell.fill"
        case .critiquebrainzReview: "quote.bubble.fill"
        case .thanks: "hands.sparkles.fill"
        case .unknown: "sparkles"
        }
    }

    private var recipientDescription: String {
        let recipients = event.users
        if recipients.count == 1, let first = recipients.first { return "Recommended to \(first)" }
        return "Recommended to \(recipients.count) listeners"
    }

    private var thanksDescription: String {
        let thanker = event.thankerUsername ?? event.userName
        if let thankee = event.thankeeUsername {
            return "\(thanker) thanked \(thankee)"
        }
        return "\(thanker) shared thanks"
    }

    private var isViewer: Bool { normalized(event.userName) == normalized(viewer.username) }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

#if DEBUG
private struct FeedPreviewProvider: FeedProviding {
    func page(
        username: String,
        mode: FeedMode,
        before: Date?,
        minimumTimestamp: Date?,
        count: Int
    ) async throws -> FeedPage {
        guard before == nil else {
            return FeedPage(username: username, serverCount: 0, events: [])
        }

        let now = Date()
        let events: [FeedEvent]
        switch mode {
        case .activity:
            events = [
                event(
                    id: 1,
                    kind: .recordingPin,
                    actor: "maya",
                    created: now.addingTimeInterval(-8 * 60),
                    recording: recording(
                        id: "00000000-0000-0000-0000-000000000101",
                        title: "Archie, Marry Me",
                        artist: "Alvvays",
                        release: "Alvvays"
                    ),
                    blurb: "This one still feels like late summer."
                ),
                event(
                    id: 2,
                    kind: .recordingRecommendation,
                    actor: "nocturne",
                    created: now.addingTimeInterval(-52 * 60),
                    recording: recording(
                        id: "00000000-0000-0000-0000-000000000102",
                        title: "Sea, Swallow Me",
                        artist: "Cocteau Twins & Harold Budd",
                        release: "The Moon and the Melodies"
                    ),
                    blurb: "Headphones recommended."
                ),
                event(
                    id: 3,
                    kind: .follow,
                    actor: "listener42",
                    created: now.addingTimeInterval(-3 * 60 * 60),
                    followedUser: "ambient_archives"
                ),
                event(
                    id: 4,
                    kind: .critiquebrainzReview,
                    actor: "cassetteclub",
                    created: now.addingTimeInterval(-26 * 60 * 60),
                    entityName: "Blue Rev",
                    rating: 5,
                    text: "A bright, beautifully overdriven record that keeps revealing new detail."
                ),
                event(
                    id: 5,
                    kind: .recordingPin,
                    actor: "private-listener",
                    created: now.addingTimeInterval(-30 * 60 * 60),
                    hidden: true
                ),
            ]
        case .following:
            events = networkListens(now: now, similar: false)
        case .similar:
            events = networkListens(now: now, similar: true)
        }
        return FeedPage(username: username, serverCount: events.count, events: Array(events.prefix(count)))
    }

    private func networkListens(now: Date, similar: Bool) -> [FeedEvent] {
        [
            event(
                id: similar ? 21 : 11,
                kind: .listen,
                actor: similar ? "tapeecho" : "maya",
                created: now.addingTimeInterval(-4 * 60),
                recording: recording(
                    id: "00000000-0000-0000-0000-000000000103",
                    title: "Dreams Tonite",
                    artist: "Alvvays",
                    release: "Antisocialites"
                ),
                similarity: similar ? 0.92 : nil
            ),
            event(
                id: similar ? 22 : 12,
                kind: .listen,
                actor: similar ? "softstatic" : "ambient_archives",
                created: now.addingTimeInterval(-19 * 60),
                recording: recording(
                    id: "00000000-0000-0000-0000-000000000104",
                    title: "An Ending (Ascent)",
                    artist: "Brian Eno",
                    release: "Apollo"
                ),
                similarity: similar ? 0.86 : nil
            ),
            event(
                id: similar ? 23 : 13,
                kind: .listen,
                actor: similar ? "polaroidghost" : "listener42",
                created: now.addingTimeInterval(-41 * 60),
                recording: recording(
                    id: "00000000-0000-0000-0000-000000000105",
                    title: "Cherry-coloured Funk",
                    artist: "Cocteau Twins",
                    release: "Heaven or Las Vegas"
                ),
                similarity: similar ? 0.81 : nil
            ),
        ]
    }

    private func recording(id: String, title: String, artist: String, release: String) -> Recording {
        Recording(
            identity: RecordingIdentity(mbid: UUID(uuidString: id), msid: nil),
            title: title,
            artistName: artist,
            artistMBIDs: [],
            releaseTitle: release,
            releaseMBID: nil,
            releaseGroupMBID: nil,
            artworkReleaseMBID: nil,
            durationMilliseconds: nil,
            source: "ListenBrainz"
        )
    }

    private func event(
        id: Int,
        kind: FeedEventKind,
        actor: String,
        created: Date,
        hidden: Bool = false,
        recording: Recording? = nil,
        blurb: String? = nil,
        similarity: Double? = nil,
        followedUser: String? = nil,
        entityName: String? = nil,
        rating: Int? = nil,
        text: String? = nil
    ) -> FeedEvent {
        FeedEvent(
            serverID: id,
            kind: kind,
            userName: actor,
            created: created,
            hidden: hidden,
            similarity: similarity,
            recording: recording,
            blurb: blurb,
            users: [],
            userName0: actor,
            userName1: followedUser,
            relationshipType: followedUser == nil ? nil : "follow",
            message: nil,
            entityName: entityName,
            entityID: nil,
            entityType: nil,
            rating: rating,
            text: text,
            reviewMBID: nil,
            originalEventID: nil,
            originalEventType: nil,
            thankerUsername: nil,
            thankeeUsername: nil
        )
    }
}
#endif

private struct FeedAvatar: View {
    let username: String
    let symbol: String

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(AppTheme.artworkGradient(seed: username))
                .overlay {
                    Text(username.prefix(1).uppercased())
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                .frame(width: 42, height: 42)

            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(AppTheme.accent, in: .circle)
                .overlay { Circle().stroke(.background, lineWidth: 2) }
                .offset(x: 2, y: 2)
        }
        .accessibilityHidden(true)
    }
}
