import Charts
import SwiftUI

struct TasteView: View {
    enum Ranking: String, CaseIterable, Identifiable {
        case artists = "Artists"
        case releases = "Albums"
        case releaseGroups = "Release groups"
        case recordings = "Tracks"
        var id: Self { self }

        var title: LocalizedStringResource {
            switch self {
            case .artists: "Artists"
            case .releases: "Albums"
            case .releaseGroups: "Release groups"
            case .recordings: "Tracks"
            }
        }
    }

    @Bindable var model: ListeningModel
    @State private var ranking: Ranking = .artists
    @AppStorage("taste.activityPeriod") private var activityPeriod: ListeningActivityPeriod = .thisWeek
    @State private var selectedDailyCellID: DailyActivity.Cell.ID?
    @State private var selectedEraDecade: Int?
    @State private var showsStatsArtwork = false
    @State private var showsCustomArtwork = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    #if DEBUG
                    if isYearInMusicTeaserVisualQA {
                        yearInMusic
                    } else if isHeatmapVisualQA {
                        dailyListeningHours
                    } else if isEraCardVisualQA {
                        musicByDecade
                    } else if isEraVisualQA {
                        periodControls
                        musicByDecade
                    } else if isReleaseGroupsVisualQA || isTracksVisualQA {
                        rankings
                    } else {
                        overview
                        albumCollage
                        yearInMusic
                        periodControls
                        dailyListeningHours
                        genreActivity
                        artistActivity
                        artistOrigins
                        musicByDecade
                        artistEvolution
                        listeningActivity
                        if !isTasteVisualQA {
                            rankings
                        }
                    }
                    #else
                    overview
                    albumCollage
                    yearInMusic
                    periodControls
                    dailyListeningHours
                    genreActivity
                    artistActivity
                    artistOrigins
                    musicByDecade
                    artistEvolution
                    listeningActivity
                    rankings
                    #endif
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .refreshable {
                if isEraVisualQA {
                    await model.loadEraActivity(for: activityPeriod, retrying: true)
                } else if isHeatmapVisualQA {
                    await model.loadDailyActivity(for: activityPeriod, retrying: true)
                } else {
                    await model.refresh()
                    await model.loadDailyActivity(for: activityPeriod, retrying: true)
                    await model.loadEraActivity(for: activityPeriod, retrying: true)
                    await model.loadListeningActivity(for: activityPeriod, retrying: true)
                    await model.refreshReleaseGroupRankingIfLoaded()
                }
            }
            .navigationTitle("Taste")
            .navigationBarTitleDisplayMode(isFocusedVisualQA ? .inline : .large)
            .mediaDestinations(model: model)
            .task(id: activityPeriod) {
                if isEraVisualQA {
                    await model.loadEraActivity(for: activityPeriod)
                } else if isHeatmapVisualQA {
                    await model.loadDailyActivity(for: activityPeriod)
                } else {
                    await model.loadDailyActivity(for: activityPeriod)
                    await model.loadEraActivity(for: activityPeriod)
                    await model.loadListeningActivity(for: activityPeriod)
                }
            }
            .task(id: ranking) {
                guard ranking == .releaseGroups else { return }
                await model.loadReleaseGroupRanking()
            }
            .onChange(of: activityPeriod) { _, _ in
                selectedDailyCellID = nil
                selectedEraDecade = nil
            }
            #if DEBUG
            .onAppear {
                if isEraZoomVisualQA {
                    selectedEraDecade = 2020
                }
                if isReleaseGroupsVisualQA {
                    ranking = .releaseGroups
                } else if isTracksVisualQA {
                    ranking = .recordings
                }
            }
            #endif
        }
        .sheet(isPresented: $showsStatsArtwork) {
            GeneratedArtworkSheet(
                presentation: .statistics(
                    username: model.account.username,
                    period: activityPeriod
                ),
                request: .statistics(username: model.account.username, range: activityPeriod.artRange),
                provider: ListenBrainzGeneratedArtworkProvider(token: model.account.token)
            )
        }
        .sheet(isPresented: $showsCustomArtwork) {
            CustomArtworkComposerSheet(
                username: model.account.username,
                albums: customArtworkAlbums,
                provider: ListenBrainzGeneratedArtworkProvider(
                    token: model.account.token
                )
            )
        }
    }

    private var isTasteVisualQA: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-brainz-taste-demo")
            || isHeatmapVisualQA
            || isYearInMusicTeaserVisualQA
            || isEraVisualQA
            || isReleaseGroupsVisualQA
            || isTracksVisualQA
        #else
        false
        #endif
    }

    private var isHeatmapVisualQA: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-brainz-taste-heatmap-demo")
        #else
        false
        #endif
    }

    private var isYearInMusicTeaserVisualQA: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-brainz-year-in-music-teaser-demo")
        #else
        false
        #endif
    }

    private var isEraVisualQA: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-brainz-taste-era-demo")
            || isEraZoomVisualQA
            || isEraCardVisualQA
        #else
        false
        #endif
    }

    private var isEraZoomVisualQA: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-brainz-taste-era-zoom-demo")
        #else
        false
        #endif
    }

    private var isEraCardVisualQA: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-brainz-taste-era-card-demo")
        #else
        false
        #endif
    }

    private var isFocusedVisualQA: Bool {
        isYearInMusicTeaserVisualQA
            || isHeatmapVisualQA
            || isEraVisualQA
            || isReleaseGroupsVisualQA
            || isTracksVisualQA
    }

    private var isReleaseGroupsVisualQA: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-brainz-taste-release-groups-demo")
        #else
        false
        #endif
    }

    private var isTracksVisualQA: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-brainz-taste-tracks-demo")
        #else
        false
        #endif
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeader(title: "Your listening", subtitle: "All-time ListenBrainz snapshot")
                Spacer()
                Text("ALL TIME")
                    .font(.caption2.bold())
                    .tracking(0.9)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(AppTheme.accent.opacity(0.14), in: .capsule)
                    .foregroundStyle(AppTheme.accent)
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) { overviewMetrics }
            } else {
                HStack(spacing: 12) { overviewMetrics }
            }
        }
    }

    private var albumCollage: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Album collage",
                subtitle: "Arrange your top albums into shareable artwork"
            )

            Button { showsCustomArtwork = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "square.grid.3x3.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(
                            AppTheme.artworkGradient(seed: "Album collage"),
                            in: .rect(cornerRadius: 16, style: .continuous)
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Create album collage")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(customArtworkAvailabilityLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 8)
                    Image(systemName: "chevron.forward")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .padding(14)
                .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the album collage editor")
        }
    }

    private var customArtworkAlbums: [CustomArtworkAlbum] {
        CustomArtworkAlbum.candidates(from: model.snapshot.topReleases)
    }

    private var customArtworkAvailabilityLabel: String {
        switch customArtworkAlbums.count {
        case 0:
            String(localized: "Waiting for matched top albums")
        default:
            String(localized: "\(customArtworkAlbums.count) matched albums are ready")
        }
    }

    @ViewBuilder
    private var overviewMetrics: some View {
        tasteMetric(
            model.snapshot.listenCount?.formatted(.number.notation(.compactName)) ?? "—",
            label: "Listens",
            symbol: "waveform"
        )
        tasteMetric(
            model.snapshot.topArtists.first?.name ?? "—",
            label: "Top artist",
            symbol: "person.wave.2"
        )
        tasteMetric(
            model.snapshot.topRecordings.first?.title ?? "—",
            label: "Top track",
            symbol: "music.note"
        )
    }

    private func tasteMetric(_ value: String, label: LocalizedStringResource, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(AppTheme.accent)
            Text(value)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .padding(14)
        .background(.thinMaterial, in: .rect(cornerRadius: 18, style: .continuous))
    }

    private var listeningActivity: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Listening activity",
                subtitle: "Calculated by ListenBrainz"
            )
            switch model.activityState(for: activityPeriod) {
            case .idle, .loading:
                activityLoading
            case let .loaded(activity):
                if activity.buckets.isEmpty {
                    activityEmpty
                } else {
                    activityChart(activity)
                }
            case let .failed(message):
                activityFailure(message)
            }
        }
    }

    private var yearInMusic: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Your year",
                subtitle: "The listening story only ListenBrainz can tell"
            )

            NavigationLink {
                yearInMusicDestination
            } label: {
                YearInMusicTeaserCard(year: YearInMusicView.latestSupportedYear)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var yearInMusicDestination: some View {
        #if DEBUG
        if isTasteVisualQA {
            YearInMusicView(
                account: model.account,
                listeningModel: model,
                provider: VisualQAYearInMusicProvider(),
                cache: EntityDetailCache()
            )
        } else {
            YearInMusicView(account: model.account, listeningModel: model)
        }
        #else
        YearInMusicView(account: model.account, listeningModel: model)
        #endif
    }

    private var periodControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Explore a period",
                subtitle: "One range shapes every server-calculated view below"
            )
            activityPeriodPicker
            Button { showsStatsArtwork = true } label: {
                Label("Create stats artwork", systemImage: "photo.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private var activityPeriodPicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ListeningActivityPeriod.allCases) { period in
                        Button {
                            activityPeriod = period
                        } label: {
                            Text(period.title)
                                .font(.subheadline.weight(activityPeriod == period ? .semibold : .regular))
                                .foregroundStyle(activityPeriod == period ? .white : .primary)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 9)
                                .background(
                                    activityPeriod == period ? AppTheme.accent : Color.secondary.opacity(0.12),
                                    in: .capsule
                                )
                        }
                        .id(period)
                        .buttonStyle(.plain)
                        .accessibilityLabel(period.accessibilityLabel)
                        .accessibilityAddTraits(activityPeriod == period ? .isSelected : [])
                    }
                }
            }
            .onAppear { proxy.scrollTo(activityPeriod, anchor: .center) }
            .onChange(of: activityPeriod) { _, period in
                withAnimation(.snappy) { proxy.scrollTo(period, anchor: .center) }
            }
        }
        .accessibilityLabel("Statistics period")
    }

    private var dailyListeningHours: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !isHeatmapVisualQA {
                SectionHeader(
                    title: "When you listen",
                    subtitle: "Listening hours calculated by ListenBrainz · UTC"
                )
            }

            switch model.dailyActivityState(for: activityPeriod) {
            case .idle, .loading:
                dailyActivityLoading
            case .unavailable:
                dailyActivityUnavailable
            case let .failed(message):
                dailyActivityFailure(message)
            case let .loaded(activity):
                if activity.isEmpty {
                    dailyActivityEmpty
                } else {
                    dailyActivityHeatmap(activity)
                }
            }
        }
    }

    private var dailyActivityLoading: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Loading listening hours…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 176)
        .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var dailyActivityUnavailable: some View {
        ContentUnavailableView(
            "Hours are not ready yet",
            systemImage: "calendar.badge.clock",
            description: Text("ListenBrainz has not calculated a listening-hours report for \(activityPeriod.title.lowercased()) yet.")
        )
        .frame(maxWidth: .infinity, minHeight: 198)
        .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
    }

    private var dailyActivityEmpty: some View {
        ContentUnavailableView(
            "No listening hours yet",
            systemImage: "calendar.badge.exclamationmark",
            description: Text("ListenBrainz returned this period, but it contains no listens. Hours are shown in UTC.")
        )
        .frame(maxWidth: .infinity, minHeight: 198)
        .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
    }

    private func dailyActivityFailure(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Listening hours unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                Task { await model.loadDailyActivity(for: activityPeriod, retrying: true) }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 198)
        .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
    }

    private func dailyActivityHeatmap(_ activity: DailyActivity) -> some View {
        let selected = selectedDailyCell(in: activity)
        return VStack(alignment: .leading, spacing: 14) {
            if !isHeatmapVisualQA {
                activitySummaryRow(activity)
            }

            ScrollView(.horizontal, showsIndicators: dynamicTypeSize.isAccessibilitySize) {
                VStack(alignment: .leading, spacing: heatmapCellSpacing) {
                    HStack(spacing: heatmapCellSpacing) {
                        Text("UTC")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .allowsTightening(true)
                            .frame(width: heatmapLabelWidth, alignment: .leading)
                        ForEach(0 ..< 24, id: \.self) { hour in
                            Text(hour.isMultiple(of: 6) ? String(hour) : "")
                                .font(.system(size: 7, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .allowsTightening(true)
                                .frame(width: heatmapCellSide, height: 12)
                        }
                    }

                    ForEach(ListeningWeekday.allCases) { weekday in
                        HStack(spacing: heatmapCellSpacing) {
                            Text(weekday.shortTitle)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .frame(width: heatmapLabelWidth, alignment: .leading)
                            ForEach(activity.cells.filter { $0.weekday == weekday }) { cell in
                                Button {
                                    selectedDailyCellID = cell.id
                                } label: {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(heatmapColor(for: cell, maximum: activity.maximumListenCount))
                                        .overlay {
                                            if selected?.id == cell.id {
                                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                                    .strokeBorder(.primary, lineWidth: 1.5)
                                            }
                                        }
                                        .frame(width: heatmapCellSide, height: heatmapCellSide)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(String(localized: "\(weekday.title), \(hourLabel(cell.hour)) UTC"))
                                .accessibilityValue(listenCountLabel(cell.listenCount))
                                .accessibilityAddTraits(selected?.id == cell.id ? .isSelected : [])
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Listening hours heatmap in UTC")
            .accessibilityHint("Select an hour to hear its listen count")

            if let selected {
                Label(
                    String(localized: "\(selected.weekday.title), \(hourLabel(selected.hour)) UTC · \(listenCountLabel(selected.listenCount))"),
                    systemImage: "clock"
                )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityLabel(String(localized: "Selected: \(selected.weekday.title), \(hourLabel(selected.hour)) UTC, \(listenCountLabel(selected.listenCount))"))
            }

            if let message = model.dailyActivityRefreshMessage(for: activityPeriod) {
                Label("Showing saved hours. \(message)", systemImage: "arrow.clockwise.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(Self.dailyActivityDateRange(activity))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(dailyActivitySummary(activity))
    }

    private var heatmapCellSide: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 22 : 9
    }

    private var heatmapLabelWidth: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 92 : 34
    }

    private var heatmapCellSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 5 : 3
    }

    @ViewBuilder
    private func activitySummaryRow(_ activity: DailyActivity) -> some View {
        let peak = activity.cells.max(by: { $0.listenCount < $1.listenCount })
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 12) {
                activitySummary(activity.totalListens.formatted(), label: Text("Listens"), symbol: "clock")
                if let peak {
                    activitySummary(
                        peak.listenCount.formatted(),
                        label: Text(String(localized: "Peak · \(peak.weekday.shortTitle) \(hourLabel(peak.hour))")),
                        symbol: "sun.max.fill"
                    )
                }
            }
        } else {
            HStack(spacing: 12) {
                activitySummary(activity.totalListens.formatted(), label: Text("Listens"), symbol: "clock")
                if let peak {
                    activitySummary(
                        peak.listenCount.formatted(),
                        label: Text(String(localized: "Peak · \(peak.weekday.shortTitle) \(hourLabel(peak.hour))")),
                        symbol: "sun.max.fill"
                    )
                }
            }
        }
    }

    private func selectedDailyCell(in activity: DailyActivity) -> DailyActivity.Cell? {
        if let selectedDailyCellID,
           let selected = activity.cells.first(where: { $0.id == selectedDailyCellID }) {
            return selected
        }
        return activity.cells.max { $0.listenCount < $1.listenCount }
    }

    private func heatmapColor(for cell: DailyActivity.Cell, maximum: Int) -> Color {
        guard maximum > 0, cell.listenCount > 0 else {
            return Color.secondary.opacity(0.13)
        }
        let intensity = Double(cell.listenCount) / Double(maximum)
        return AppTheme.accent.opacity(0.28 + (0.72 * intensity))
    }

    private func hourLabel(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }

    private func dailyActivitySummary(_ activity: DailyActivity) -> String {
        guard let peak = activity.cells.max(by: { $0.listenCount < $1.listenCount }) else {
            return String(localized: "Listening hours heatmap in UTC")
        }
        return String(localized: "\(activity.period.title) listening hours in UTC. \(listenCountLabel(activity.totalListens)). Peak: \(peak.weekday.title) at \(hourLabel(peak.hour)), \(listenCountLabel(peak.listenCount)).")
    }

    private var musicByDecade: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Music by decade",
                subtitle: "Original release years calculated by ListenBrainz"
            )

            switch model.eraActivityState(for: activityPeriod) {
            case .idle, .loading:
                eraActivityLoading
            case .unavailable:
                eraActivityUnavailable
            case let .failed(message):
                eraActivityFailure(message)
            case let .loaded(activity):
                if activity.isEmpty {
                    eraActivityEmpty
                } else {
                    eraActivityCard(activity)
                }
            }
        }
    }

    private var genreActivity: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Your sound through the day",
                subtitle: "Leading genre tags by local time of day"
            )

            NavigationLink {
                GenreActivityView(model: model, period: $activityPeriod)
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(AppTheme.secondary)
                        .frame(width: 52, height: 52)
                        .background(AppTheme.secondary.opacity(0.14), in: .circle)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Find your genre rhythm")
                            .font(.headline)
                        Text("See which sounds lead your mornings, afternoons, evenings, and nights.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 4)
                    Image(systemName: "chevron.forward")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
                .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Loads one ListenBrainz genre activity report for the selected period")
        }
    }

    private var artistEvolution: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Artist evolution",
                subtitle: "How your leading artists move through time"
            )

            NavigationLink {
                ArtistEvolutionView(model: model, period: $activityPeriod)
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 52, height: 52)
                        .background(AppTheme.accent.opacity(0.13), in: .circle)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Follow your top artists")
                            .font(.headline)
                        Text("Compare their listening patterns across \(activityPeriod.title.lowercased()).")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 4)
                    Image(systemName: "chevron.forward")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
                .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Loads one ListenBrainz artist evolution report for the selected period")
        }
    }

    private var artistOrigins: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Artist origins",
                subtitle: "Where your leading artists come from"
            )

            NavigationLink {
                ArtistOriginsView(model: model, period: $activityPeriod)
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: "globe.americas.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(AppTheme.secondary)
                        .frame(width: 52, height: 52)
                        .background(AppTheme.secondary.opacity(0.14), in: .circle)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Explore your music’s geography")
                            .font(.headline)
                        Text("Compare countries for \(activityPeriod.title.lowercased()) by artists or listens.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 4)
                    Image(systemName: "chevron.forward")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
                .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Loads one ListenBrainz artist origins report for the selected period")
        }
    }

    private var artistActivity: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Artist activity", subtitle: "See how your listens are spread across artists and albums.")
            NavigationLink { ArtistActivityView(model: model, period: $activityPeriod) } label: {
                HStack(spacing: 16) {
                    Image(systemName: "rectangle.3.group.fill").font(.title2.weight(.semibold)).foregroundStyle(AppTheme.accent).frame(width: 52, height: 52).background(AppTheme.accent.opacity(0.13), in: .circle)
                    VStack(alignment: .leading, spacing: 4) { Text("Open artist activity").font(.headline); Text("See which albums shaped \(activityPeriod.title.lowercased()).").font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    Spacer(minLength: 4); Image(systemName: "chevron.forward").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
                }.padding(16).background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous)).contentShape(.rect)
            }.buttonStyle(.plain).accessibilityHint("Opens artist activity for the selected period")
        }
    }

    private var eraActivityLoading: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Loading release years…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 210)
        .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var eraActivityUnavailable: some View {
        ContentUnavailableView(
            "Release years are not ready yet",
            systemImage: "calendar.badge.clock",
            description: Text("ListenBrainz has not calculated music-by-decade statistics for \(activityPeriod.title.lowercased()) yet.")
        )
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
    }

    private var eraActivityEmpty: some View {
        ContentUnavailableView(
            "No release-year data",
            systemImage: "chart.bar.xaxis",
            description: Text("No listens with original release-year metadata were available for \(activityPeriod.title.lowercased()).")
        )
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
    }

    private func eraActivityFailure(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Release years unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                Task { await model.loadEraActivity(for: activityPeriod, retrying: true) }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
    }

    private func eraActivityCard(_ activity: EraActivity) -> some View {
        let points = eraChartPoints(activity)
        return VStack(alignment: .leading, spacing: 16) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    eraActivityContext(activity)
                    eraNavigationControl(activity)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    eraActivityContext(activity)
                    Spacer(minLength: 8)
                    eraNavigationControl(activity)
                }
            }

            eraSummaryRow(activity)
            eraChart(points, activity: activity)

            Text(eraActivityFootnote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let message = model.eraActivityRefreshMessage(for: activityPeriod) {
                Label("Showing saved release years. \(message)", systemImage: "arrow.clockwise.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
        .sensoryFeedback(.selection, trigger: selectedEraDecade)
    }

    private func eraActivityContext(_ activity: EraActivity) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let selectedEraDecade {
                Text(String(localized: "\(selectedEraDecade.calendarYearText)s"))
                    .font(.headline)
                Text(String(localized: "\(activity.listenCount(in: selectedEraDecade)) listens across individual years"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(activityPeriod.title)
                    .font(.headline)
                Text("Tap a decade to see its individual years")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func eraNavigationControl(_ activity: EraActivity) -> some View {
        if selectedEraDecade != nil {
            Button {
                withAnimation(.snappy) { selectedEraDecade = nil }
            } label: {
                Label("All decades", systemImage: "arrow.up.backward")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } else {
            Menu {
                ForEach(activity.decades.filter { $0.listenCount > 0 }) { decade in
                    Button(String(localized: "\(decade.title) · \(listenCountLabel(decade.listenCount))")) {
                        withAnimation(.snappy) { selectedEraDecade = decade.year }
                    }
                }
            } label: {
                Label("Explore", systemImage: "magnifyingglass")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityHint("Choose a decade to inspect individual release years")
        }
    }

    @ViewBuilder
    private func eraSummaryRow(_ activity: EraActivity) -> some View {
        let selectedYears = selectedEraDecade.map { activity.years(in: $0) }
        let peakYear = selectedYears?.max {
            if $0.listenCount == $1.listenCount { return $0.year < $1.year }
            return $0.listenCount < $1.listenCount
        }

        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 12) {
                eraSummaryPrimary(activity)
                if selectedEraDecade != nil, let peakYear {
                    activitySummary(
                        peakYear.listenCount.formatted(),
                        label: Text(String(localized: "Peak year · \(peakYear.year.calendarYearText)")),
                        symbol: "calendar"
                    )
                } else if let leading = activity.leadingDecade {
                    activitySummary(
                        leading.listenCount.formatted(),
                        label: Text(String(localized: "Leading · \(leading.title)")),
                        symbol: "sparkles"
                    )
                }
            }
        } else {
            HStack(spacing: 12) {
                eraSummaryPrimary(activity)
                if selectedEraDecade != nil, let peakYear {
                    activitySummary(
                        peakYear.listenCount.formatted(),
                        label: Text(String(localized: "Peak year · \(peakYear.year.calendarYearText)")),
                        symbol: "calendar"
                    )
                } else if let leading = activity.leadingDecade {
                    activitySummary(
                        leading.listenCount.formatted(),
                        label: Text(String(localized: "Leading · \(leading.title)")),
                        symbol: "sparkles"
                    )
                }
            }
        }
    }

    private func eraSummaryPrimary(_ activity: EraActivity) -> some View {
        let count = selectedEraDecade.map { activity.listenCount(in: $0) } ?? activity.totalListens
        return activitySummary(
            count.formatted(),
            label: selectedEraDecade == nil ? Text("Dated listens") : Text("Decade listens"),
            symbol: "opticaldisc"
        )
    }

    private func eraChart(_ points: [EraChartPoint], activity: EraActivity) -> some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: dynamicTypeSize.isAccessibilitySize || points.count > 7) {
                Chart(points) { point in
                    BarMark(
                        x: .value(selectedEraDecade == nil ? "Decade" : "Year", point.label),
                        y: .value("Listens", point.listenCount)
                    )
                    .foregroundStyle(AppTheme.accent.gradient)
                    .cornerRadius(5)
                    .accessibilityLabel(String(localized: "\(point.label): \(listenCountLabel(point.listenCount))"))
                }
                .chartXAxis {
                    AxisMarks(values: points.map(\.label)) { value in
                        AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                        AxisValueLabel {
                            if let label = value.as(String.self) {
                                Text(label)
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(.tertiary)
                        AxisValueLabel {
                            if let count = value.as(Int.self) {
                                Text(count.formatted(.number.notation(.compactName)))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartXScale(
                    range: .plotDimension(
                        startPadding: 18,
                        endPadding: dynamicTypeSize.isAccessibilitySize ? 42 : 30
                    )
                )
                .chartYScale(
                    range: .plotDimension(
                        startPadding: 4,
                        endPadding: dynamicTypeSize.isAccessibilitySize ? 24 : 10
                    )
                )
                .chartOverlay { proxy in
                    if selectedEraDecade == nil {
                        GeometryReader { chartGeometry in
                            Rectangle()
                                .fill(.clear)
                                .contentShape(.rect)
                                .gesture(
                                    SpatialTapGesture().onEnded { event in
                                        selectEraBar(
                                            at: event.location,
                                            proxy: proxy,
                                            geometry: chartGeometry,
                                            points: points
                                        )
                                    }
                                )
                        }
                    }
                }
                .frame(
                    width: max(geometry.size.width, CGFloat(points.count) * eraChartColumnWidth),
                    height: eraChartHeight
                )
                .accessibilityChartDescriptor(
                    EraActivityDescriptor(
                        points: points,
                        period: activity.period,
                        selectedDecade: selectedEraDecade
                    )
                )
            }
        }
        .frame(height: eraChartHeight)
    }

    private func selectEraBar(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy,
        points: [EraChartPoint]
    ) {
        guard let plotFrame = proxy.plotFrame else { return }
        let frame = geometry[plotFrame]
        guard frame.contains(location),
              let chartLabel: String = proxy.value(atX: location.x - frame.origin.x),
              let selected = points.first(where: { $0.label == chartLabel }),
              selected.listenCount > 0
        else { return }
        withAnimation(.snappy) { selectedEraDecade = selected.value }
    }

    private func eraChartPoints(_ activity: EraActivity) -> [EraChartPoint] {
        if let selectedEraDecade {
            return activity.years(in: selectedEraDecade).map {
                EraChartPoint(value: $0.year, listenCount: $0.listenCount, label: $0.year.calendarYearText)
            }
        }
        return activity.decades.map {
            EraChartPoint(value: $0.year, listenCount: $0.listenCount, label: $0.title)
        }
    }

    private var eraChartColumnWidth: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 70 : 52
    }

    private var eraChartHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 280 : 220
    }

    private var eraActivityFootnote: String {
        if let selectedEraDecade {
            return String(localized: "Showing every year in the \(selectedEraDecade.calendarYearText)s, including years with no matched listens.")
        }
        return String(localized: "Counts include listens whose recordings have original release-year metadata. Empty decades are kept within ordinary release-year spans.")
    }

    fileprivate struct EraChartPoint: Identifiable, Hashable {
        let value: Int
        let listenCount: Int
        let label: String

        var id: Int { value }
    }

    static func dailyActivityDateRange(
        _ activity: DailyActivity,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        guard activity.from != .distantPast, activity.to != .distantPast else {
            return String(localized: "Server-calculated listening hours · UTC")
        }
        let style = Date.FormatStyle(
            date: .abbreviated,
            time: .omitted,
            locale: locale,
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        return String(localized: "\(activity.from.formatted(style)) – \(activity.to.formatted(style)) · UTC")
    }

    private var activityLoading: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Loading listening activity…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 164, alignment: .center)
        .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var activityEmpty: some View {
        ContentUnavailableView(
            "No activity yet",
            systemImage: "chart.bar.xaxis",
            description: Text("ListenBrainz has no listening-activity buckets for \(activityPeriod.title.lowercased()).")
        )
        .frame(maxWidth: .infinity, minHeight: 190)
        .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
    }

    private func activityFailure(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Activity unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                Task { await model.loadListeningActivity(for: activityPeriod, retrying: true) }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 190)
        .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
    }

    private func activityChart(_ activity: ListeningActivity) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) { listeningActivitySummaries(activity) }
            } else {
                HStack(spacing: 12) { listeningActivitySummaries(activity) }
            }

            Chart(activity.buckets) { bucket in
                BarMark(
                    x: .value("Time", bucket.label),
                    y: .value("Listens", bucket.listenCount)
                )
                .foregroundStyle(AppTheme.accent.gradient)
                .cornerRadius(4)
                .accessibilityLabel(String(localized: "\(bucket.label): \(listenCountLabel(bucket.listenCount))"))
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.tertiary)
                    AxisValueLabel {
                        if let count = value.as(Int.self) {
                            Text(count.formatted())
                        }
                    }
                }
            }
            .chartXAxis(.hidden)
            .frame(height: 180)
            .accessibilityChartDescriptor(ListeningActivityDescriptor(activity: activity))

            HStack(spacing: 0) {
                ForEach(chartAxisLabels(activity.buckets), id: \.self) { label in
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.leading, 38)

            Text(activityDateRange(activity))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
    }

    private func chartAxisLabels(_ buckets: [ListeningActivity.Bucket]) -> [String] {
        guard buckets.count > 6 else { return buckets.map(\.label) }
        let step = max(1, Int(ceil(Double(buckets.count - 1) / 5)))
        var labels = stride(from: 0, to: buckets.count, by: step).map { buckets[$0].label }
        if let last = buckets.last?.label, labels.last != last {
            labels.append(last)
        }
        return labels
    }

    private func activitySummary(_ value: String, label: Text, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.headline.monospacedDigit())
                label
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func listeningActivitySummaries(_ activity: ListeningActivity) -> some View {
        activitySummary(
            activity.totalListens.formatted(),
            label: Text("Listens"),
            symbol: "waveform"
        )
        if let busiest = activity.busiestBucket {
            activitySummary(
                busiest.listenCount.formatted(),
                label: Text(String(localized: "Peak · \(busiest.label)")),
                symbol: "chart.bar.fill"
            )
        }
    }

    private func activityDateRange(_ activity: ListeningActivity) -> String {
        guard activity.from != .distantPast, activity.to != .distantPast else {
            return String(localized: "Server-calculated activity")
        }
        return String(localized: "\(activity.from.formatted(date: .abbreviated, time: .omitted)) – \(activity.to.formatted(date: .abbreviated, time: .omitted))")
    }

    private var rankings: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Rankings")
            rankingPicker

            switch ranking {
            case .artists:
                artistRankings
            case .releases:
                releaseRankings
            case .releaseGroups:
                releaseGroupRankings
            case .recordings:
                recordingRankings
            }
        }
    }

    private var rankingPicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: dynamicTypeSize.isAccessibilitySize) {
                HStack(spacing: 8) {
                    ForEach(Ranking.allCases) { value in
                        Button {
                            ranking = value
                        } label: {
                            Text(value.title)
                                .font(.subheadline.weight(ranking == value ? .semibold : .regular))
                                .foregroundStyle(ranking == value ? .white : .primary)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 9)
                                .background(ranking == value ? AppTheme.accent : Color.secondary.opacity(0.12), in: .capsule)
                        }
                        .id(value)
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: value.title))
                        .accessibilityAddTraits(ranking == value ? .isSelected : [])
                    }
                }
            }
            .onAppear { proxy.scrollTo(ranking, anchor: .center) }
            .onChange(of: ranking) { _, value in
                withAnimation(.snappy) { proxy.scrollTo(value, anchor: .center) }
            }
            .onChange(of: dynamicTypeSize) { _, _ in
                proxy.scrollTo(ranking, anchor: .center)
            }
        }
        .accessibilityLabel("Ranking type")
    }

    private var artistRankings: some View {
        ForEach(Array(model.snapshot.topArtists.prefix(20).enumerated()), id: \.element.id) { index, artist in
            if let destination = artist.detailDestination() {
                NavigationLink(value: destination) {
                    rankedArtistRow(index: index, artist: artist, showsDisclosure: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens artist details")
            } else {
                rankedArtistRow(index: index, artist: artist, showsDisclosure: false)
            }
        }
    }

    private var releaseRankings: some View {
        ForEach(Array(model.snapshot.topReleases.prefix(20).enumerated()), id: \.element.id) { index, release in
            if let seed = release.releaseSeed {
                NavigationLink(value: seed) {
                    rankedReleaseRow(index: index, release: release)
                }
                .buttonStyle(.plain)
            } else {
                rankedReleaseRow(index: index, release: release)
            }
        }
    }

    private var recordingRankings: some View {
        ForEach(Array(model.snapshot.topRecordings.prefix(20).enumerated()), id: \.element.id) { index, recording in
            if let destination = recording.detailDestination {
                NavigationLink(value: destination) {
                    rankedRecordingRow(index: index, recording: recording, showsDisclosure: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens track details")
            } else {
                rankedRecordingRow(index: index, recording: recording, showsDisclosure: false)
            }
        }
    }

    @ViewBuilder
    private var releaseGroupRankings: some View {
        switch model.releaseGroupRankingState {
        case .idle, .loading:
            ProgressView("Loading release groups…")
                .frame(maxWidth: .infinity, minHeight: 180)
        case let .failed(message):
            VStack(spacing: 12) {
                ContentUnavailableView(
                    "Release groups couldn’t load",
                    systemImage: "square.stack.3d.up",
                    description: Text("Check your connection, then try again.\n\n\(message)")
                )
                Button("Try again") {
                    Task { await model.loadReleaseGroupRanking(retrying: true) }
                }
                .buttonStyle(.bordered)
            }
        case let .loaded(groups):
            if groups.isEmpty {
                ContentUnavailableView(
                    "No release groups yet",
                    systemImage: "square.stack.3d.up",
                    description: Text("ListenBrainz has not calculated this ranking yet.")
                )
            } else {
                if let message = model.releaseGroupRankingRefreshMessage {
                    Label("Showing saved rankings. \(message)", systemImage: "arrow.clockwise")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(groups.prefix(20).enumerated()), id: \.element.id) { index, group in
                    if let destination = group.detailDestination {
                        NavigationLink(value: destination) {
                            rankedReleaseGroupRow(index: index, group: group, showsDisclosure: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens release group details")
                    } else {
                        rankedReleaseGroupRow(index: index, group: group, showsDisclosure: false)
                    }
                }
            }
        }
    }

    private func rankedArtistRow(index: Int, artist: RankedArtist, showsDisclosure: Bool) -> some View {
        HStack(spacing: 12) {
            rank(index)
            ArtistArtworkView(artist: artist).frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text(artist.name).font(.body.weight(.semibold)).lineLimit(1)
                Text(listenCountLabel(artist.listenCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if showsDisclosure {
                Image(systemName: "chevron.forward")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private func rankedReleaseRow(index: Int, release: RankedRelease) -> some View {
        HStack(spacing: 12) {
            rank(index)
            ArtworkView(url: release.artworkURL, title: release.name, cornerRadius: 8).frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text(release.name).font(.body.weight(.semibold)).lineLimit(1)
                Text(String(localized: "\(release.artistName) · \(listenCountLabel(release.listenCount))"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
    }

    private func rankedReleaseGroupRow(index: Int, group: RankedReleaseGroup, showsDisclosure: Bool) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        rank(index)
                        releaseGroupArtwork(group, size: 76, cornerRadius: 12)
                        Spacer(minLength: 12)
                        if showsDisclosure {
                            Image(systemName: "chevron.forward")
                                .font(.body.bold())
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                    }
                    Text(group.name)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(group.artistName)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(listenCountLabel(group.listenCount))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 12) {
                    rank(index)
                    releaseGroupArtwork(group, size: 50, cornerRadius: 8)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.name)
                            .font(.body.weight(.semibold))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(String(localized: "\(group.artistName) · \(listenCountLabel(group.listenCount))"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    if showsDisclosure {
                        Image(systemName: "chevron.forward")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 8 : 0)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(localized: "Rank \(index + 1), \(group.name), \(group.artistName), \(listenCountLabel(group.listenCount))")
        )
    }

    private func releaseGroupArtwork(_ group: RankedReleaseGroup, size: CGFloat, cornerRadius: CGFloat) -> some View {
        ArtworkView(
            url: isReleaseGroupsVisualQA ? nil : group.artworkURL,
            title: group.name,
            cornerRadius: cornerRadius
        )
        .frame(width: size, height: size)
    }

    private func listenCountLabel(_ count: Int) -> String {
        String(localized: "\(count) listens")
    }

    private func rankedRecordingRow(
        index: Int,
        recording: RankedRecording,
        showsDisclosure: Bool
    ) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        rank(index)
                        recordingArtwork(recording, size: 76, cornerRadius: 12)
                        Spacer(minLength: 8)
                        if showsDisclosure {
                            Image(systemName: "chevron.forward")
                                .font(.body.bold())
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                    }
                    Text(recording.title)
                        .font(.headline)
                    Text(recording.artistName)
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Text(listenCountLabel(recording.listenCount))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 12) {
                    rank(index)
                    recordingArtwork(recording, size: 50, cornerRadius: 8)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(recording.title).font(.body.weight(.semibold)).lineLimit(1)
                        Text(String(localized: "\(recording.artistName) · \(listenCountLabel(recording.listenCount))"))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    if showsDisclosure {
                        Image(systemName: "chevron.forward")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 8 : 0)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(localized: "Rank \(index + 1), \(recording.title), \(recording.artistName), \(listenCountLabel(recording.listenCount))")
        )
    }

    private func recordingArtwork(
        _ recording: RankedRecording,
        size: CGFloat,
        cornerRadius: CGFloat
    ) -> some View {
        ArtworkView(
            url: isTracksVisualQA ? nil : recording.recording.artworkURL,
            title: recording.title,
            cornerRadius: cornerRadius
        )
        .frame(width: size, height: size)
    }

    private func rank(_ index: Int) -> some View {
        Text("\(index + 1)")
            .font(.subheadline.monospacedDigit().weight(index < 3 ? .bold : .regular))
            .foregroundStyle(index < 3 ? AppTheme.accent : .secondary)
            .frame(width: 26)
    }

}

private struct ListeningActivityDescriptor: AXChartDescriptorRepresentable {
    let activity: ListeningActivity

    func makeChartDescriptor() -> AXChartDescriptor {
        let listens = String(localized: "\(activity.totalListens) listens")
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: String(localized: "Time"),
            categoryOrder: activity.buckets.map(\.label)
        )
        let maximum = Double(activity.buckets.map(\.listenCount).max() ?? 1)
        let yAxis = AXNumericDataAxisDescriptor(
            title: String(localized: "Listens"),
            range: 0 ... maximum,
            gridlinePositions: []
        ) { $0.formatted() }
        let points = activity.buckets.map {
            AXDataPoint(
                x: $0.label,
                y: Double($0.listenCount)
            )
        }
        return AXChartDescriptor(
            title: String(localized: "\(activity.period.title) listening activity"),
            summary: String(localized: "\(listens) calculated by ListenBrainz"),
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [AXDataSeriesDescriptor(name: String(localized: "Listens"), isContinuous: false, dataPoints: points)]
        )
    }
}

private struct EraActivityDescriptor: AXChartDescriptorRepresentable {
    let points: [Point]
    let period: ListeningActivityPeriod
    let selectedDecade: Int?

    init(
        points: [TasteView.EraChartPoint],
        period: ListeningActivityPeriod,
        selectedDecade: Int?
    ) {
        self.points = points.map { Point(label: $0.label, listenCount: $0.listenCount) }
        self.period = period
        self.selectedDecade = selectedDecade
    }

    func makeChartDescriptor() -> AXChartDescriptor {
        let axisTitle = selectedDecade == nil ? String(localized: "Decade") : String(localized: "Year")
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: axisTitle,
            categoryOrder: points.map(\.label)
        )
        let maximum = Double(max(points.map(\.listenCount).max() ?? 0, 1))
        let yAxis = AXNumericDataAxisDescriptor(
            title: String(localized: "Listens"),
            range: 0 ... maximum,
            gridlinePositions: []
        ) { $0.formatted() }
        let dataPoints = points.map {
            AXDataPoint(x: $0.label, y: Double($0.listenCount))
        }
        let scope = selectedDecade.map { String(localized: "\($0)s release years") }
            ?? String(localized: "music by decade")
        return AXChartDescriptor(
            title: String(localized: "\(period.title) \(scope)"),
            summary: String(localized: "Listen counts grouped by original release year"),
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [AXDataSeriesDescriptor(name: String(localized: "Listens"), isContinuous: false, dataPoints: dataPoints)]
        )
    }

    struct Point {
        let label: String
        let listenCount: Int
    }
}
