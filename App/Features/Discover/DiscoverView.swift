import SwiftUI

struct DiscoverView: View {
    @State private var model: FreshReleasesModel
    @State private var isSearchPresented = false
    @State private var isRecommendationsPresented = false
    @State private var isFeedPresented = false
    @State private var isFollowingPinsPresented = false
    @State private var isFiltersPresented = false
    @State private var appliedFilters = FreshReleaseFilters()
    @State private var draftFilters = FreshReleaseFilters()
    @State private var didConfigureVisualQA = false
    @Bindable var listeningModel: ListeningModel
    private let account: Account
    @AppStorage("discover.freshReleaseScope") private var scope: FreshReleaseScope = .forYou
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        account: Account,
        listeningModel: ListeningModel,
        freshReleasesProvider: (any ListeningProvider)? = nil
    ) {
        self.account = account
        _model = State(initialValue: FreshReleasesModel(account: account, provider: freshReleasesProvider))
        _listeningModel = Bindable(wrappedValue: listeningModel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if !isFreshReleasesVisualQA {
                        recommendationsLink
                        radioLink
                        feedLink
                        followingPinsLink
                    }
                    header
                    scopePicker
                    querySummary
                    content
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isSearchPresented = true } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Search ListenBrainz and MusicBrainz")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { presentFilters() } label: {
                        Image(systemName: appliedFilters.activeCount(for: scope) == 0
                            ? "line.3.horizontal.decrease.circle"
                            : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel(filterAccessibilityLabel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await model.refresh(query: activeQuery) } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh fresh releases")
                    .disabled(model.isLoading(query: activeQuery))
                }
            }
            .task(id: activeQuery) { await model.load(query: activeQuery) }
            .onChange(of: scope) { _, value in
                appliedFilters = appliedFilters.normalized(for: value)
            }
            .onAppear {
                #if DEBUG
                if isFreshReleasesVisualQA, !didConfigureVisualQA {
                    didConfigureVisualQA = true
                    scope = .forYou
                    appliedFilters = .init()
                }
                if ProcessInfo.processInfo.arguments.contains("-brainz-open-search") {
                    isSearchPresented = true
                }
                if ProcessInfo.processInfo.arguments.contains("-brainz-open-recommendations") {
                    isRecommendationsPresented = true
                }
                if ProcessInfo.processInfo.arguments.contains("-brainz-open-feed") {
                    isFeedPresented = true
                }
                if ProcessInfo.processInfo.arguments.contains("-brainz-open-following-pins") {
                    isFollowingPinsPresented = true
                }
                if ProcessInfo.processInfo.arguments.contains("-brainz-fresh-releases-filters-demo") {
                    presentFilters()
                }
                #endif
            }
            .sheet(isPresented: $isSearchPresented) {
                SearchView(account: account, listeningModel: listeningModel)
            }
            .navigationDestination(isPresented: $isRecommendationsPresented) {
                RecommendationsView(account: account, listeningModel: listeningModel)
            }
            .navigationDestination(isPresented: $isFeedPresented) {
                FeedView(account: account, listeningModel: listeningModel)
            }
            .navigationDestination(isPresented: $isFollowingPinsPresented) {
                FollowingPinsView(account: account, listeningModel: listeningModel)
            }
            .sheet(isPresented: $isFiltersPresented) {
                FreshReleaseFiltersSheet(
                    scope: scope,
                    releases: loadedReleases,
                    filters: $draftFilters,
                    onApply: {
                        appliedFilters = draftFilters.normalized(for: scope)
                        isFiltersPresented = false
                    }
                )
                .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .mediaDestinations(model: listeningModel)
        }
    }

    private var activeQuery: FreshReleaseQuery {
        appliedFilters.query(for: scope)
    }

    private var loadedReleases: [FreshRelease] {
        guard case let .loaded(releases) = model.state(for: activeQuery) else { return [] }
        return releases
    }

    private var isFreshReleasesVisualQA: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-brainz-fresh-releases-demo")
            || ProcessInfo.processInfo.arguments.contains("-brainz-fresh-releases-filters-demo")
        #else
        false
        #endif
    }

    private var filterAccessibilityLabel: String {
        let count = appliedFilters.activeCount(for: scope)
        return count == 0
            ? String(localized: "Fresh releases filters")
            : String(localized: "Fresh releases filters, \(count) active")
    }

    private func presentFilters() {
        draftFilters = appliedFilters.normalized(for: scope)
        isFiltersPresented = true
    }

    private var followingPinsLink: some View {
        NavigationLink {
            FollowingPinsView(account: account, listeningModel: listeningModel)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.artworkGradient(seed: "following-pins"))
                    Image(systemName: "pin.fill").font(.system(size: 27, weight: .semibold)).foregroundStyle(.white)
                }.frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Following pins").font(.headline).foregroundStyle(.primary)
                    Text("Tracks pinned by people you follow").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading).lineLimit(3)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
            .padding(14).background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous)).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Open current pins from people you follow")
    }

    private var feedLink: some View {
        NavigationLink {
            FeedView(account: account, listeningModel: listeningModel)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.artworkGradient(seed: "listening-network"))
                    Image(systemName: "person.2.wave.2.fill")
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Listening network")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(account.isAuthenticated
                        ? "Pins, recommendations, and recent plays from your music circle"
                        : "Connect your token to open your private ListenBrainz feed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }
                Spacer(minLength: 8)
                Image(systemName: account.isAuthenticated ? "chevron.right" : "lock.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(account.isAuthenticated
            ? "Open your ListenBrainz activity and recent network listens"
            : "Explains how to sign in for private feed access")
    }

    private var recommendationsLink: some View {
        NavigationLink {
            RecommendationsView(account: account, listeningModel: listeningModel)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.heroGradient)
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 29, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Made for you")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Recommended tracks, Weekly Jams, and exploration playlists")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Open ListenBrainz recommendations")
    }

    private var radioLink: some View {
        NavigationLink {
            RadioView(account: account, listeningModel: listeningModel)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.artworkGradient(seed: "lb-radio"))
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Tune LB Radio")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(account.isAuthenticated
                        ? "Generate a mix from your taste, recommendations, artists, or tags"
                        : "Connect your token to use ListenBrainz's playlist generator")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }
                Spacer(minLength: 8)
                Image(systemName: account.isAuthenticated ? "chevron.right" : "lock.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(account.isAuthenticated
            ? "Open the native ListenBrainz Radio playlist generator"
            : "Explains why ListenBrainz Radio requires sign-in")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(scope == .forYou ? "Fresh for you" : "New across ListenBrainz")
                .font(.title2.bold())
            Text(scope == .forYou
                ? "New music from artists in your listening history."
                : "Explore recent and upcoming releases from across ListenBrainz.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var scopePicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                Text("Release source")
                    .font(.headline)
                Picker("Release source", selection: $scope) {
                    ForEach(FreshReleaseScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityHint("For You uses your listening history. All shows releases from across ListenBrainz.")
        } else {
            Picker("Release source", selection: $scope) {
                ForEach(FreshReleaseScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityHint("For You uses your listening history. All shows releases from across ListenBrainz.")
        }
    }

    private var querySummary: some View {
        let value = appliedFilters.normalized(for: scope)
        return VStack(alignment: .leading, spacing: 5) {
            if dynamicTypeSize.isAccessibilitySize {
                Label(value.days.title, systemImage: "calendar")
                Label(value.timing.title, systemImage: "clock")
                Label(value.sort.summaryTitle(direction: value.direction), systemImage: "arrow.up.arrow.down")
            } else {
                Label(value.summary, systemImage: "calendar.badge.clock")
            }
            if appliedFilters.hasLocalFilters, !loadedReleases.isEmpty {
                Text("Showing \(appliedFilters.filtered(loadedReleases, using: activeQuery.sort).count) of \(loadedReleases.count) releases")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state(for: activeQuery) {
        case .idle, .loading:
            loading
        case let .loaded(releases):
            if releases.isEmpty {
                empty
            } else {
                let visible = appliedFilters.filtered(releases, using: activeQuery.sort)
                if visible.isEmpty {
                    filteredEmpty
                } else {
                    releaseGrid(visible)
                }
            }
        case let .failed(message):
            failure(message)
        }
    }

    private var loading: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Finding fresh releases…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 250)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var empty: some View {
        ContentUnavailableView(
            emptyTitle,
            systemImage: "sparkles",
            description: Text(emptyDescription)
        )
        .frame(maxWidth: .infinity, minHeight: 290)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private var filteredEmpty: some View {
        ContentUnavailableView {
            Label("No releases match these filters", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("Try changing or clearing a release type or tag filter.")
        } actions: {
            Button("Clear type and tag filters") {
                appliedFilters.clearLocalFilters()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 290)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private var emptyTitle: String {
        if activeQuery.includesUpcoming, !activeQuery.includesPast { return String(localized: "No upcoming releases") }
        if activeQuery.includesPast, !activeQuery.includesUpcoming { return String(localized: "No recent releases") }
        return scope == .forYou ? String(localized: "Nothing fresh for you yet") : String(localized: "No fresh releases right now")
    }

    private var emptyDescription: String {
        if activeQuery.days == .seven {
            return String(localized: "Try a wider release window or another source.")
        }
        return scope == .forYou
            ? String(localized: "Try All to explore releases from across ListenBrainz.")
            : String(localized: "Try another release window or check again later.")
    }

    private func failure(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Fresh Releases couldn’t load", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Try again") { Task { await model.load(query: activeQuery, retrying: true) } }
        }
        .frame(maxWidth: .infinity, minHeight: 290)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private func releaseGrid(_ releases: [FreshRelease]) -> some View {
        LazyVGrid(
            columns: dynamicTypeSize.isAccessibilitySize
                ? [GridItem(.flexible())]
                : [GridItem(.adaptive(minimum: 148), spacing: 16)],
            spacing: 22
        ) {
            ForEach(releases) { release in
                if let seed = ReleaseSeed(freshRelease: release) {
                    NavigationLink(value: seed) {
                        FreshReleaseCard(release: release)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens release details")
                } else if let groupMBID = release.releaseGroupMBID {
                    NavigationLink {
                        ReleaseGroupDetailView(
                            group: SearchReleaseGroup(
                                mbid: groupMBID,
                                title: release.title,
                                artistName: release.artistName,
                                primaryType: release.primaryType,
                                firstReleaseDate: release.releaseDate
                            ),
                            viewer: account,
                            discoveryContext: release.discoveryContext
                        )
                    } label: {
                        FreshReleaseCard(release: release)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens release details")
                } else {
                    FreshReleaseCard(release: release)
                }
            }
        }
    }
}

private struct FreshReleaseCard: View {
    let release: FreshRelease
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ArtworkView(url: release.artworkURL, title: release.title, cornerRadius: 16, showsPlaceholderSymbol: false)
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    if release.isUpcoming {
                        if dynamicTypeSize.isAccessibilitySize {
                            Image(systemName: "hourglass")
                                .font(.body.bold())
                                .padding(8)
                                .background(.ultraThinMaterial, in: .circle)
                                .padding(10)
                                .accessibilityLabel("Upcoming release")
                        } else {
                            Label("Upcoming", systemImage: "hourglass")
                                .font(.caption2.bold())
                                .padding(.horizontal, 7)
                                .padding(.vertical, 5)
                                .background(.ultraThinMaterial, in: .capsule)
                                .padding(8)
                        }
                    }
                }
            Text(release.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(release.artistName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            metadata
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var metadata: some View {
        let values = [release.releaseDateDescription, release.typeDescription].compactMap { $0 }
        if !values.isEmpty {
            Text(values.joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }
}

enum FreshReleaseTiming: String, CaseIterable, Identifiable, Sendable {
    case releasedAndUpcoming
    case released
    case upcoming

    var id: Self { self }

    var title: String {
        switch self {
        case .releasedAndUpcoming: String(localized: "Released & upcoming")
        case .released: String(localized: "Released")
        case .upcoming: String(localized: "Upcoming")
        }
    }

    var includesPast: Bool { self != .upcoming }
    var includesUpcoming: Bool { self != .released }

    func pickerTitle(isAccessibilitySize: Bool) -> String {
        isAccessibilitySize && self == .releasedAndUpcoming ? String(localized: "Both") : title
    }
}

enum FreshReleaseSortDirection: String, CaseIterable, Identifiable, Sendable {
    case ascending
    case descending

    var id: Self { self }
}

/// Presentation choices are deliberately provider-free. Changing direction,
/// release type, or tags only transforms the aggregate response already held
/// by `FreshReleasesModel` and can never schedule a request.
struct FreshReleaseFilters: Equatable, Sendable {
    var days: FreshReleaseQuery.Days = .seven
    var timing: FreshReleaseTiming = .releasedAndUpcoming
    var sort: FreshReleaseQuery.Sort = .releaseDate
    var direction: FreshReleaseSortDirection = .descending
    var releaseTypes: Set<String> = []
    var includedTags: Set<String> = []
    var excludedTags: Set<String> = []

    var hasLocalFilters: Bool {
        !releaseTypes.isEmpty || !includedTags.isEmpty || !excludedTags.isEmpty
    }

    func query(for scope: FreshReleaseScope) -> FreshReleaseQuery {
        FreshReleaseQuery(
            scope: scope,
            days: days,
            includesPast: timing.includesPast,
            includesUpcoming: timing.includesUpcoming,
            sort: sort
        )
    }

    func normalized(for scope: FreshReleaseScope) -> Self {
        var result = self
        if scope == .all, result.days == .ninety {
            result.days = .thirty
        }
        if scope == .all, result.sort == .confidence {
            result.sort = .releaseDate
            result.direction = .descending
        }
        return result
    }

    func activeCount(for scope: FreshReleaseScope) -> Int {
        let value = normalized(for: scope)
        var count = 0
        if value.days != .seven { count += 1 }
        if value.timing != .releasedAndUpcoming { count += 1 }
        if value.sort != .releaseDate || value.direction != .descending { count += 1 }
        if !value.releaseTypes.isEmpty { count += 1 }
        if !value.includedTags.isEmpty { count += 1 }
        if !value.excludedTags.isEmpty { count += 1 }
        return count
    }

    mutating func clearLocalFilters() {
        releaseTypes.removeAll()
        includedTags.removeAll()
        excludedTags.removeAll()
    }

    func summary(for scope: FreshReleaseScope) -> String {
        normalized(for: scope).summary
    }

    var summary: String {
        [days.title, timing.title, sort.summaryTitle(direction: direction)].joined(separator: " · ")
    }

    func filtered(_ releases: [FreshRelease], using sort: FreshReleaseQuery.Sort) -> [FreshRelease] {
        let selectedTypes = Set(releaseTypes.map(Self.normalizedValue))
        let requiredTags = Set(includedTags.map(Self.normalizedValue))
        let hiddenTags = Set(excludedTags.map(Self.normalizedValue))

        return releases
            .filter { release in
                let types = Set(release.filterTypes.map(Self.normalizedValue))
                let tags = Set(release.tags.map(Self.normalizedValue))
                let matchesType = selectedTypes.isEmpty || !types.isDisjoint(with: selectedTypes)
                let matchesIncludedTag = requiredTags.isEmpty || !tags.isDisjoint(with: requiredTags)
                let avoidsExcludedTag = tags.isDisjoint(with: hiddenTags)
                return matchesType && matchesIncludedTag && avoidsExcludedTag
            }
            .sorted { comesBefore($0, $1, sort: sort) }
    }

    static func availableTypes(in releases: [FreshRelease]) -> [String] {
        uniqueValues(releases.flatMap(\.filterTypes))
    }

    static func availableTags(in releases: [FreshRelease]) -> [String] {
        uniqueValues(releases.flatMap(\.tags))
    }

    private func comesBefore(
        _ lhs: FreshRelease,
        _ rhs: FreshRelease,
        sort: FreshReleaseQuery.Sort
    ) -> Bool {
        let leftHasValue: Bool
        let rightHasValue: Bool
        let comparison: ComparisonResult

        switch sort {
        case .releaseDate:
            let left = lhs.releaseDateValue
            let right = rhs.releaseDateValue
            leftHasValue = left != nil
            rightHasValue = right != nil
            comparison = Self.compare(left, right)
        case .artistCreditName:
            leftHasValue = true
            rightHasValue = true
            comparison = lhs.artistName.localizedCaseInsensitiveCompare(rhs.artistName)
        case .releaseName:
            leftHasValue = true
            rightHasValue = true
            comparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        case .confidence:
            leftHasValue = lhs.confidence != nil
            rightHasValue = rhs.confidence != nil
            comparison = Self.compare(lhs.confidence, rhs.confidence)
        }

        if leftHasValue != rightHasValue { return leftHasValue }
        if comparison == .orderedSame { return lhs.sourcePosition < rhs.sourcePosition }
        return direction == .ascending ? comparison == .orderedAscending : comparison == .orderedDescending
    }

    private static func compare<T: Comparable>(_ lhs: T?, _ rhs: T?) -> ComparisonResult {
        guard let lhs, let rhs else { return .orderedSame }
        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    }

    private static func uniqueValues(_ values: [String]) -> [String] {
        var keyed: [String: String] = [:]
        for value in values {
            let display = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !display.isEmpty else { continue }
            keyed[normalizedValue(display), default: display] = display
        }
        return keyed.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private static func normalizedValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}

private struct FreshReleaseFiltersSheet: View {
    let scope: FreshReleaseScope
    let releases: [FreshRelease]
    @Binding var filters: FreshReleaseFilters
    let onApply: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var availableDays: [FreshReleaseQuery.Days] {
        scope == .all ? [.seven, .thirty] : FreshReleaseQuery.Days.allCases
    }

    private var availableSorts: [FreshReleaseQuery.Sort] {
        scope == .all
            ? [.releaseDate, .artistCreditName, .releaseName]
            : FreshReleaseQuery.Sort.allCases
    }

    private var availableTypes: [String] { FreshReleaseFilters.availableTypes(in: releases) }
    private var availableTags: [String] { FreshReleaseFilters.availableTags(in: releases) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Release window") {
                    adaptivePicker("Time range", selection: $filters.days) {
                        ForEach(availableDays, id: \.self) { days in
                            Text(days.title).tag(days)
                        }
                    }
                    adaptivePicker("Timing", selection: $filters.timing) {
                        ForEach(FreshReleaseTiming.allCases) { timing in
                            Text(timing.pickerTitle(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)).tag(timing)
                        }
                    }
                }

                Section("Sort") {
                    adaptivePicker("Sort by", selection: $filters.sort) {
                        ForEach(availableSorts, id: \.self) { sort in
                            Text(sort.title).tag(sort)
                        }
                    }
                    adaptivePicker("Order", selection: $filters.direction) {
                        ForEach(FreshReleaseSortDirection.allCases) { direction in
                            Text(filters.sort.directionTitle(direction)).tag(direction)
                        }
                    }
                }

                if !availableTypes.isEmpty {
                    Section("Release types") {
                        ForEach(availableTypes, id: \.self) { type in
                            selectionRow(type, selection: $filters.releaseTypes)
                        }
                    }
                }

                if !availableTags.isEmpty {
                    Section {
                        NavigationLink {
                            FreshReleaseTagSelectionView(
                                mode: .include,
                                tags: availableTags,
                                included: $filters.includedTags,
                                excluded: $filters.excludedTags
                            )
                        } label: {
                            filterLinkLabel("Include tags", count: filters.includedTags.count)
                        }

                        NavigationLink {
                            FreshReleaseTagSelectionView(
                                mode: .exclude,
                                tags: availableTags,
                                included: $filters.includedTags,
                                excluded: $filters.excludedTags
                            )
                        } label: {
                            filterLinkLabel("Exclude tags", count: filters.excludedTags.count)
                        }
                    } footer: {
                        Text("Choose one or more types or tags to narrow these releases.")
                    }
                }

                Section {
                    Button("Reset filters") {
                        filters = FreshReleaseFilters().normalized(for: scope)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Fresh releases filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply", action: onApply)
                }
            }
            .onChange(of: filters.sort) { oldValue, newValue in
                guard oldValue != newValue else { return }
                filters.direction = newValue.defaultDirection
            }
        }
    }

    @ViewBuilder
    private func adaptivePicker<Selection: Hashable, Content: View>(
        _ title: String,
        selection: Binding<Selection>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                Picker(title, selection: selection, content: content)
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Picker(title, selection: selection, content: content)
        }
    }

    private func selectionRow(_ title: String, selection: Binding<Set<String>>) -> some View {
        let isSelected = selection.wrappedValue.contains(title)
        return Button {
            if isSelected {
                selection.wrappedValue.remove(title)
            } else {
                selection.wrappedValue.insert(title)
            }
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AppTheme.accent : Color.secondary.opacity(0.55))
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func filterLinkLabel(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            if count > 0 {
                Text(count.formatted())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(count) selected")
            }
        }
    }
}

private struct FreshReleaseTagSelectionView: View {
    enum Mode {
        case include
        case exclude

        var title: String { self == .include ? String(localized: "Include tags") : String(localized: "Exclude tags") }
        var footer: String {
            self == .include
                ? String(localized: "A release can match any selected tag.")
                : String(localized: "Releases with any selected tag stay hidden.")
        }
    }

    let mode: Mode
    let tags: [String]
    @Binding var included: Set<String>
    @Binding var excluded: Set<String>
    @State private var searchText = ""

    private var visibleTags: [String] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return tags }
        return tags.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List {
            if visibleTags.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                Section {
                    ForEach(visibleTags, id: \.self) { tag in
                        tagRow(tag)
                    }
                } footer: {
                    Text(mode.footer)
                }
            }
        }
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search tags")
    }

    private func tagRow(_ tag: String) -> some View {
        let isSelected = selection.contains(tag)
        return Button {
            if isSelected {
                selection.remove(tag)
            } else {
                selection.insert(tag)
                oppositeSelection.remove(tag)
            }
        } label: {
            HStack {
                Text(tag)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AppTheme.accent : Color.secondary.opacity(0.55))
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var selection: Set<String> {
        get { mode == .include ? included : excluded }
        nonmutating set {
            if mode == .include { included = newValue }
            else { excluded = newValue }
        }
    }

    private var oppositeSelection: Set<String> {
        get { mode == .include ? excluded : included }
        nonmutating set {
            if mode == .include { excluded = newValue }
            else { included = newValue }
        }
    }
}

private extension FreshRelease {
    var filterTypes: [String] {
        [primaryType, secondaryType].compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
    }
}

private extension FreshReleaseQuery.Days {
    var title: String { String(localized: "\(rawValue) days") }
}

private extension FreshReleaseQuery.Sort {
    var title: String {
        switch self {
        case .releaseDate: String(localized: "Release date")
        case .artistCreditName: String(localized: "Artist")
        case .releaseName: String(localized: "Release title")
        case .confidence: String(localized: "Best match")
        }
    }

    var defaultDirection: FreshReleaseSortDirection {
        switch self {
        case .releaseDate, .confidence: .descending
        case .artistCreditName, .releaseName: .ascending
        }
    }

    func directionTitle(_ direction: FreshReleaseSortDirection) -> String {
        switch (self, direction) {
        case (.releaseDate, .ascending): String(localized: "Oldest first")
        case (.releaseDate, .descending): String(localized: "Newest first")
        case (.artistCreditName, .ascending), (.releaseName, .ascending): String(localized: "A–Z")
        case (.artistCreditName, .descending), (.releaseName, .descending): String(localized: "Z–A")
        case (.confidence, .ascending): String(localized: "Lowest match first")
        case (.confidence, .descending): String(localized: "Best match first")
        }
    }

    func summaryTitle(direction: FreshReleaseSortDirection) -> String {
        directionTitle(direction)
    }
}
