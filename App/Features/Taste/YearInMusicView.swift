// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Portions adapted from Cassette's Wrapped views and MeshGradientBackground.
// Copyright (C) 2026 Mathieu Dubart.

import Foundation
import SwiftUI

struct YearInMusicView: View {
    static let latestSupportedYear = 2025

    let listeningModel: ListeningModel
    private let artworkProvider: any YearInMusicArtworkProviding
    private let reportProvider: any YearInMusicProviding
    private let currentReportCache: EntityDetailCache<YearInMusicCacheKey, YearInMusicReport>
    private let archiveReportCache: EntityDetailCache<YearInMusicCacheKey, YearInMusicReport>
    private let automaticallyPresentsArtwork: Bool
    @State private var model: YearInMusicModel
    @State private var selectedYear: Int
    @State private var showsArtwork = false

    init(
        account: Account,
        listeningModel: ListeningModel,
        year: Int = Self.latestSupportedYear,
        provider: (any YearInMusicProviding)? = nil,
        artworkProvider: (any YearInMusicArtworkProviding)? = nil,
        cache: EntityDetailCache<YearInMusicCacheKey, YearInMusicReport>? = nil
    ) {
        self.listeningModel = listeningModel
        reportProvider = provider ?? ListenBrainzYearInMusicProvider(token: account.token)
        let currentCache = cache ?? YearInMusicCaches.reports
        let archiveCache = cache ?? YearInMusicCaches.archives
        currentReportCache = currentCache
        archiveReportCache = archiveCache
        self.artworkProvider = artworkProvider ?? ListenBrainzYearInMusicArtworkProvider(token: "")
        #if DEBUG
        automaticallyPresentsArtwork = ProcessInfo.processInfo.arguments.contains("-brainz-year-in-music-art-demo")
        #else
        automaticallyPresentsArtwork = false
        #endif
        _model = State(
            initialValue: YearInMusicModel(
                account: account,
                year: year,
                provider: reportProvider,
                cache: (2021 ... 2024).contains(year) ? archiveCache : currentCache
            )
        )
        _selectedYear = State(initialValue: year)
    }

    var body: some View {
        Group {
            if let report = model.report {
                reportContent(report)
            } else {
                stateContent
            }
        }
        .navigationTitle("Year in Music \(String(selectedYear))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Year", selection: $selectedYear) {
                        ForEach([2025, 2024, 2023, 2022, 2021], id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                } label: {
                    Label("Choose year", systemImage: "calendar")
                }
                .accessibilityLabel("Choose Year in Music year")
            }
            if let report = model.report,
               let url = reportURL(username: report.username ?? model.account.username) {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ShareLink(
                            item: url,
                            subject: Text("My \(String(report.year)) Year in Music"),
                            message: Text("My \(String(report.year)) listening story on ListenBrainz")
                        ) {
                            Label("Share report link", systemImage: "link")
                        }

                        if selectedYear != 2021 {
                            Button { showsArtwork = true } label: {
                                Label("Preview official artwork…", systemImage: "photo.badge.arrow.down")
                            }
                        }
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(isPresented: $showsArtwork) {
            if let report = model.report,
               let url = reportURL(username: report.username ?? model.account.username) {
                YearInMusicArtworkSheet(
                    report: report,
                    username: report.username ?? model.account.username,
                    reportURL: url,
                    provider: artworkProvider
                )
            }
        }
        .task(id: model.year) { await model.load() }
        .onChange(of: selectedYear) { _, year in
            showsArtwork = false
            model = YearInMusicModel(
                account: model.account,
                year: year,
                provider: reportProvider,
                cache: (2021 ... 2024).contains(year) ? archiveReportCache : currentReportCache
            )
        }
        .onChange(of: model.report != nil, initial: true) { _, reportIsReady in
            guard automaticallyPresentsArtwork, reportIsReady else { return }
            showsArtwork = true
        }
        .mediaDestinations(model: listeningModel)
    }

    private func reportContent(_ report: YearInMusicReport) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                if model.state == .refreshing {
                    Label("Updating from ListenBrainz…", systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Updating Year in Music from ListenBrainz")
                }

                if let message = model.refreshMessage {
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                visibleSections(report)

                Text("Calculated by ListenBrainz from your submitted listening history.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .padding(.bottom, 32)
        }
        .refreshable { await model.refresh() }
    }

    @ViewBuilder
    private func visibleSections(_ report: YearInMusicReport) -> some View {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-brainz-year-in-music-identity-demo") {
            YearInMusicIdentitySection(report: report)
        } else if arguments.contains("-brainz-year-in-music-evolution-demo") {
            YearInMusicArtistEvolutionSection(report: report)
        } else if arguments.contains("-brainz-year-in-music-artists-demo") {
            YearInMusicArtistsSection(
                artists: report.topArtists,
                allowsNavigation: allowsMediaNavigation
            )
        } else if arguments.contains("-brainz-year-in-music-new-releases-demo") {
            YearInMusicNewReleasesSection(
                releases: report.newReleasesOfTopArtists,
                year: report.year,
                allowsNavigation: allowsMediaNavigation,
                loadsArtwork: false
            )
        } else if arguments.contains("-brainz-year-in-music-albums-demo") {
            releaseSection(report)
        } else if arguments.contains("-brainz-year-in-music-tracks-demo") {
            YearInMusicTracksSection(
                recordings: report.topRecordings,
                allowsNavigation: allowsMediaNavigation
            )
        } else {
            YearInMusicHero(report: report)
            YearInMusicCalendarSection(report: report)
            if report.hasIdentityContent { YearInMusicIdentitySection(report: report) }
            if report.artistEvolution != nil { YearInMusicArtistEvolutionSection(report: report) }
            YearInMusicArtistsSection(
                artists: report.topArtists,
                allowsNavigation: allowsMediaNavigation
            )
            YearInMusicNewReleasesSection(
                releases: report.newReleasesOfTopArtists,
                year: report.year,
                allowsNavigation: allowsMediaNavigation
            )
            releaseSection(report)
            YearInMusicTracksSection(
                recordings: report.topRecordings,
                allowsNavigation: allowsMediaNavigation
            )
        }
        #else
        YearInMusicHero(report: report)
        if !report.listeningDays.isEmpty { YearInMusicCalendarSection(report: report) }
        if report.hasIdentityContent { YearInMusicIdentitySection(report: report) }
        if report.artistEvolution != nil { YearInMusicArtistEvolutionSection(report: report) }
        if !report.topArtists.isEmpty { YearInMusicArtistsSection(artists: report.topArtists, allowsNavigation: true) }
        if !report.newReleasesOfTopArtists.isEmpty {
            YearInMusicNewReleasesSection(
                releases: report.newReleasesOfTopArtists,
                year: report.year,
                allowsNavigation: true
            )
        }
        releaseSection(report)
        if !report.topRecordings.isEmpty { YearInMusicTracksSection(recordings: report.topRecordings, allowsNavigation: true) }
        #endif
    }

    @ViewBuilder
    private func releaseSection(_ report: YearInMusicReport) -> some View {
        if !report.topReleases.isEmpty {
            YearInMusicReleasesSection(releases: report.topReleases, allowsNavigation: allowsMediaNavigation)
        } else if !report.topReleaseGroups.isEmpty {
            YearInMusicAlbumsSection(releases: report.topReleaseGroups, allowsNavigation: allowsMediaNavigation)
        }
    }

    private var allowsMediaNavigation: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return !arguments.contains("-brainz-year-in-music-demo")
            && !arguments.contains("-brainz-year-in-music-new-releases-demo")
            && !arguments.contains("-brainz-taste-demo")
            && !arguments.contains("-brainz-year-in-music-teaser-demo")
        #else
        true
        #endif
    }

    @ViewBuilder
    private var stateContent: some View {
        switch model.state {
        case .idle, .loading, .refreshing:
            VStack(spacing: 18) {
                ProgressView()
                    .controlSize(.large)
                Text("Building your \(String(model.year)) listening story…")
                    .font(.headline)
                Text("One ListenBrainz report powers the whole retrospective.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)
            .accessibilityElement(children: .combine)
        case .unavailable:
            ContentUnavailableView {
                Label("No \(String(model.year)) report yet", systemImage: "sparkles.rectangle.stack")
            } description: {
                Text("ListenBrainz has not generated a Year in Music report for this account.")
            } actions: {
                Button("Try Again") { Task { await model.refresh() } }
            }
        case let .failed(message):
            ContentUnavailableView {
                Label("Year in Music unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await model.refresh() } }
            }
        case .ready:
            ContentUnavailableView(
                "Report unavailable",
                systemImage: "sparkles.rectangle.stack",
                description: Text("ListenBrainz did not return a usable report.")
            )
        }
    }

    private func reportURL(username: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "listenbrainz.org"
        let archivePath = model.report?.source == .archive ? "/legacy" : ""
        components.path = "/user/\(username)/year-in-music\(archivePath)/\(model.year)/"
        return components.url
    }
}

private struct YearInMusicArtistEvolutionSection: View {
    let report: YearInMusicReport
    @State private var requestedArtistCount = 5
    @State private var selectedTimeUnit: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let artistCountOptions = [3, 5, 10]

    var body: some View {
        if let activity = report.artistEvolution, !activity.isEmpty {
            let artists = activity.artists(limit: requestedArtistCount)
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    title: "Artists through the year",
                    subtitle: "See how your favorites changed month by month."
                )

                VStack(alignment: .leading, spacing: 18) {
                    header(activity, artists: artists)
                    ArtistEvolutionChart(
                        activity: activity,
                        artists: artists,
                        selectedTimeUnit: $selectedTimeUnit,
                        accessibilityTitle: "\(report.year) artist evolution"
                    )
                    ArtistEvolutionArtistLegend(artists: artists)
                    selectedBreakdown(activity, artists: artists)
                }
                .padding(16)
                .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
            }
            .sensoryFeedback(.selection, trigger: selectedTimeUnit)
            .onAppear { selectUsefulBucketIfNeeded(activity, artists: artists) }
            .onChange(of: requestedArtistCount) { _, _ in
                selectUsefulBucketIfNeeded(activity, artists: activity.artists(limit: requestedArtistCount))
            }
        }
    }

    private func header(
        _ activity: ArtistEvolutionActivity,
        artists: [ArtistEvolutionActivity.Artist]
    ) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    reportContext
                    artistCountMenu(activity, artists: artists)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    reportContext
                    Spacer(minLength: 8)
                    artistCountMenu(activity, artists: artists)
                }
            }
        }
    }

    private var reportContext: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(String(report.year))
                .font(.headline)
            Text("Tap the chart to inspect a time slice")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func artistCountMenu(
        _ activity: ArtistEvolutionActivity,
        artists: [ArtistEvolutionActivity.Artist]
    ) -> some View {
        let counts = Array(Set(artistCountOptions.map { min($0, activity.artists.count) }))
            .filter { $0 > 0 }
            .sorted()
        return Menu {
            ForEach(counts, id: \.self) { count in
                Button {
                    requestedArtistCount = count
                } label: {
                    if artists.count == count { Label("Top \(count)", systemImage: "checkmark") }
                    else { Text("Top \(count)") }
                }
            }
        } label: {
            Label("Top \(artists.count)", systemImage: "line.3.horizontal.decrease.circle")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel("Show top \(artists.count) artists")
    }

    @ViewBuilder
    private func selectedBreakdown(
        _ activity: ArtistEvolutionActivity,
        artists: [ArtistEvolutionActivity.Artist]
    ) -> some View {
        if let selectedTimeUnit {
            ArtistEvolutionSelectedBreakdown(
                period: activity.period,
                selectedTimeUnit: selectedTimeUnit,
                artists: artists
            )
        }
    }

    private func selectUsefulBucketIfNeeded(
        _ activity: ArtistEvolutionActivity,
        artists: [ArtistEvolutionActivity.Artist]
    ) {
        guard selectedTimeUnit == nil || !activity.timeUnits.contains(selectedTimeUnit!) else { return }
        selectedTimeUnit = activity.timeUnits.last { timeUnit in
            artists.contains { $0.listenCount(at: timeUnit) > 0 }
        } ?? activity.timeUnits.last
    }
}

struct YearInMusicTeaserCard: View {
    let year: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        YearInMusicMeshBackground(animated: false)
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 300 : 156)
            .overlay {
                LinearGradient(
                    colors: [.black.opacity(0.05), .black.opacity(0.42)],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
            }
            .overlay(alignment: .bottomLeading) {
                teaserContent
            }
            .clipShape(.rect(cornerRadius: 24, style: .continuous))
            .contentShape(.rect(cornerRadius: 24, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Year in Music \(String(year))")
            .accessibilityHint("Opens your annual ListenBrainz retrospective")
    }

    private var teaserContent: some View {
        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 10 : 5) {
                Text("YOUR \(String(year))")
                    .font(.caption.bold())
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.78))

                if dynamicTypeSize.isAccessibilitySize {
                    Text("Open your Year in Music")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Year in Music")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Text("A native story of the artists, albums and days that shaped your year.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font((dynamicTypeSize.isAccessibilitySize ? Font.title : .headline).weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.bottom, 3)
        }
        .padding(18)
    }
}

private struct YearInMusicHero: View {
    let report: YearInMusicReport

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var revealed = false

    var body: some View {
        YearInMusicMeshBackground(animated: !reduceMotion)
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 500 : 350)
            .overlay {
                LinearGradient(
                    colors: [.black.opacity(0.05), .black.opacity(0.28)],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
            }
            .overlay(alignment: .bottomLeading) { heroContent }
            .clipShape(.rect(cornerRadius: 28, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
            .onAppear {
                if reduceMotion {
                    revealed = true
                } else {
                    withAnimation(.spring(response: 0.75, dampingFraction: 0.82)) {
                        revealed = true
                    }
                }
            }
    }

    private var heroContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("YOUR \(String(report.year))")
                    .font(.caption.bold())
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.76))

                Text(heroValue)
                    .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 62 : 84, weight: .black, design: .rounded))
                    .kerning(-2)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .contentTransition(.numericText())
                    .scaleEffect(revealed ? 1 : 0.92, anchor: .bottomLeading)
                    .opacity(revealed ? 1 : 0)

                Text(heroUnit)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Rectangle()
                .fill(.white.opacity(0.22))
                .frame(height: 1)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { metrics }
            } else {
                HStack(spacing: 9) { metrics }
            }
        }
        .padding(22)
    }

    @ViewBuilder
    private var metrics: some View {
        heroMetric(report.totals.listenCount, label: "listens")
        if report.totals.hasArtistCount { separator; heroMetric(report.totals.artistCount, label: "artists") }
        if report.totals.hasRecordingCount { separator; heroMetric(report.totals.recordingCount, label: "tracks") }
    }

    private func heroMetric(_ value: Int, label: String) -> some View {
        Text("\(value.formatted(.number.notation(.compactName))) \(label)")
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.76))
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
    }

    @ViewBuilder
    private var separator: some View {
        if !dynamicTypeSize.isAccessibilitySize {
            Text("·")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private var heroValue: String {
        guard report.totals.hasListeningTime, report.totals.listeningTime > 0 else {
            return report.totals.listenCount.formatted(.number.notation(.compactName))
        }
        return listeningDuration.value.formatted(.number.notation(.compactName))
    }

    private var heroUnit: String {
        guard report.totals.hasListeningTime, report.totals.listeningTime > 0 else { return "listens in the year" }
        let measurement = listeningDuration
        return "\(measurement.unit) with music"
    }

    private var listeningDuration: (value: Int, unit: String) {
        if report.totals.listeningTime < 3_600 {
            let minutes = max(1, Int((report.totals.listeningTime / 60).rounded()))
            return (minutes, minutes == 1 ? "minute" : "minutes")
        }
        let hours = max(1, Int((report.totals.listeningTime / 3_600).rounded()))
        return (hours, hours == 1 ? "hour" : "hours")
    }

    private var accessibilitySummary: String {
        let duration: String
        if report.totals.hasListeningTime, report.totals.listeningTime > 0 {
            let measurement = listeningDuration
            duration = "\(measurement.value.formatted()) \(measurement.unit) with music"
        } else {
            duration = "Listening duration unavailable"
        }
        var summary = "Year in Music \(report.year). \(duration). \(report.totals.listenCount.formatted()) listens"
        if report.totals.hasArtistCount { summary += ", \(report.totals.artistCount.formatted()) artists" }
        if report.totals.hasReleaseCount { summary += ", \(report.totals.releaseGroupCount.formatted()) releases" }
        if report.totals.hasRecordingCount { summary += ", and \(report.totals.recordingCount.formatted()) tracks" }
        return summary + "."
    }
}

private struct YearInMusicIdentitySection: View {
    let report: YearInMusicReport

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "How you listened",
                subtitle: "A few patterns from your annual report"
            )

            VStack(alignment: .leading, spacing: 12) {
                if report.totals.hasNewArtistCount {
                    newArtistsCard
                }
                if let weekday = report.mostActiveWeekday {
                    weekdayCard(weekday)
                }
                if !report.topGenres.isEmpty {
                    genresCard
                }
                if !report.releaseDecades.isEmpty {
                    decadesCard
                }
            }
        }
    }

    private var newArtistsCard: some View {
        YearInMusicIdentityCard(icon: "person.badge.plus", title: "New artists") {
            Text("\(report.totals.newArtistCount.formatted()) new \(report.totals.newArtistCount == 1 ? "artist" : "artists") discovered")
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(.primary)
        } accessibilityLabel: {
            "New artists. \(report.totals.newArtistCount.formatted()) \(report.totals.newArtistCount == 1 ? "artist" : "artists") discovered."
        }
    }

    private func weekdayCard(_ weekday: YearInMusicReport.Weekday) -> some View {
        YearInMusicIdentityCard(icon: "calendar", title: "Most active weekday") {
            Text(weekday.name)
                .font(.title3.bold())
            Text("Your busiest day for listening.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } accessibilityLabel: {
            "Most active weekday. \(weekday.name) was your busiest day for listening."
        }
    }

    private var genresCard: some View {
        YearInMusicIdentityCard(
            icon: "tag",
            title: "Top genre tags",
            subtitle: "ListenBrainz tags, not a complete genre profile"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(report.topGenres.prefix(6)) { genre in
                    genreRow(genre)
                }
            }
        } accessibilityLabel: {
            "Top genre tags. " + report.topGenres.prefix(6).map(genreAccessibilitySummary).joined(separator: ". ")
        }
    }

    private var decadesCard: some View {
        YearInMusicIdentityCard(
            icon: "clock.arrow.circlepath",
            title: "Release decades",
            subtitle: "Release years for the music you played"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(report.releaseDecades.prefix(6)) { decade in
                    decadeRow(decade)
                }
            }
        } accessibilityLabel: {
            "Release decades. " + report.releaseDecades.prefix(6).map { "\($0.label), \($0.listenCount.formatted()) \($0.listenCount == 1 ? "listen" : "listens")" }.joined(separator: ". ")
        }
    }

    private func genreRow(_ genre: YearInMusicReport.Genre) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            identityRowLabel(genre.name, detail: genreDetail(genre))
            if let proportion = genre.percentage {
                YearInMusicProportionBar(value: proportion / 100)
            }
        }
    }

    private func decadeRow(_ decade: YearInMusicReport.ReleaseDecade) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            identityRowLabel(
                decade.label,
                detail: "\(decade.listenCount.formatted()) \(decade.listenCount == 1 ? "listen" : "listens")"
            )
            YearInMusicProportionBar(
                value: Double(decade.listenCount) / Double(max(1, report.releaseDecades.map(\.listenCount).max() ?? 1))
            )
        }
    }

    @ViewBuilder
    private func identityRowLabel(_ title: String, detail: String?) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                if let detail {
                    Text(detail)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func genreDetail(_ genre: YearInMusicReport.Genre) -> String? {
        if genre.hasListenCount {
            return "\(genre.listenCount.formatted()) \(genre.listenCount == 1 ? "listen" : "listens")"
        }
        if let percentage = genre.percentage {
            return (percentage / 100).formatted(.percent.precision(.fractionLength(0)))
        }
        return nil
    }

    private func genreAccessibilitySummary(_ genre: YearInMusicReport.Genre) -> String {
        if let detail = genreDetail(genre) { return "\(genre.name), \(detail)" }
        return genre.name
    }
}

private struct YearInMusicIdentityCard<Content: View>: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: Content
    let accessibilityLabel: () -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(AppTheme.accent)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel())
    }
}

private struct YearInMusicProportionBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(AppTheme.accent.opacity(0.16))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.accent)
                        .frame(width: proxy.size.width * max(0, min(1, value)))
                }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

private struct YearInMusicCalendarSection: View {
    let report: YearInMusicReport

    private var layout: YearInMusicCalendarLayout {
        YearInMusicCalendarLayout(year: report.year, listeningDays: report.listeningDays)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Your year at a glance",
                subtitle: "Every listening day · UTC"
            )

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    calendarMetric(layout.activeDayCount.formatted(), label: "active days")
                    Spacer()
                    if let busiest = layout.busiestDay {
                        calendarMetric(
                            busiest.listenCount.formatted(),
                            label: "peak · \(layout.shortDayLabel(busiest.date))",
                            alignment: .trailing
                        )
                    }
                }

                YearInMusicHeatmap(layout: layout)
            }
            .padding(18)
            .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
        }
    }

    private func calendarMetric(
        _ value: String,
        label: String,
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct YearInMusicHeatmap: View {
    let layout: YearInMusicCalendarLayout

    private let spacing: CGFloat = 2
    private let labelWidth: CGFloat = 17

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("JAN")
                Spacer()
                Text("APR")
                Spacer()
                Text("JUL")
                Spacer()
                Text("OCT")
                Spacer()
                Text("DEC")
            }
            .font(.system(size: 8, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.leading, labelWidth + 5)

            GeometryReader { proxy in
                let usableWidth = proxy.size.width - labelWidth - 5 - spacing * CGFloat(max(0, layout.weekCount - 1))
                let cellSize = min(7, max(3.5, usableWidth / CGFloat(max(1, layout.weekCount))))

                HStack(alignment: .top, spacing: 5) {
                    VStack(spacing: spacing) {
                        dayLabel("M", size: cellSize)
                        dayLabel("", size: cellSize)
                        dayLabel("W", size: cellSize)
                        dayLabel("", size: cellSize)
                        dayLabel("F", size: cellSize)
                        dayLabel("", size: cellSize)
                        dayLabel("", size: cellSize)
                    }
                    .frame(width: labelWidth)

                    HStack(spacing: spacing) {
                        ForEach(0 ..< layout.weekCount, id: \.self) { week in
                            VStack(spacing: spacing) {
                                ForEach(0 ..< 7, id: \.self) { weekday in
                                    dayCell(week: week, weekday: weekday, size: cellSize)
                                }
                            }
                        }
                    }
                }
            }
            .frame(height: 62)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(layout.accessibilitySummary)
    }

    private func dayLabel(_ label: String, size: CGFloat) -> some View {
        Text(label)
            .font(.system(size: 7, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(width: labelWidth, height: size)
    }

    @ViewBuilder
    private func dayCell(week: Int, weekday: Int, size: CGFloat) -> some View {
        if let day = layout.day(week: week, weekday: weekday) {
            let intensity = layout.intensity(for: day.listenCount)
            RoundedRectangle(cornerRadius: min(2, size * 0.28), style: .continuous)
                .fill(
                    day.listenCount == 0
                        ? Color.secondary.opacity(0.09)
                        : AppTheme.accent.opacity(0.24 + intensity * 0.76)
                )
                .frame(width: size, height: size)
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }
}

struct YearInMusicCalendarLayout: Equatable {
    struct Day: Equatable, Identifiable {
        let date: Date
        let listenCount: Int
        var id: Date { date }
    }

    let year: Int
    let leadingDayCount: Int
    let days: [Day]
    let maximumListenCount: Int

    init(year: Int, listeningDays: [YearInMusicReport.ListeningDay]) {
        self.year = year
        let calendar = Self.utcCalendar
        let first = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? .distantPast
        let range = calendar.range(of: .day, in: .year, for: first) ?? 1 ..< 1
        let counts = Dictionary(
            listeningDays.map { (calendar.startOfDay(for: $0.day), max(0, $0.listenCount)) },
            uniquingKeysWith: { lhs, rhs in
                let value = lhs.addingReportingOverflow(rhs)
                return value.overflow ? Int.max : value.partialValue
            }
        )
        days = range.compactMap { ordinal in
            guard let date = calendar.date(byAdding: .day, value: ordinal - 1, to: first) else { return nil }
            return Day(date: date, listenCount: counts[date, default: 0])
        }
        // Gregorian weekday is 1=Sunday. Convert to a Monday-first index.
        leadingDayCount = (calendar.component(.weekday, from: first) + 5) % 7
        maximumListenCount = days.map(\.listenCount).max() ?? 0
    }

    var weekCount: Int {
        max(1, Int(ceil(Double(leadingDayCount + days.count) / 7)))
    }

    var activeDayCount: Int { days.count { $0.listenCount > 0 } }

    var busiestDay: Day? {
        days.filter { $0.listenCount > 0 }.max { lhs, rhs in
            if lhs.listenCount != rhs.listenCount { return lhs.listenCount < rhs.listenCount }
            return lhs.date > rhs.date
        }
    }

    func day(week: Int, weekday: Int) -> Day? {
        let index = week * 7 + weekday - leadingDayCount
        guard days.indices.contains(index) else { return nil }
        return days[index]
    }

    func intensity(for listenCount: Int) -> Double {
        guard maximumListenCount > 0, listenCount > 0 else { return 0 }
        return sqrt(Double(listenCount) / Double(maximumListenCount))
    }

    var accessibilitySummary: String {
        if let busiestDay {
            return "Listening calendar for \(year), \(activeDayCount.formatted()) active days. Busiest day was \(longDayLabel(busiestDay.date)) with \(busiestDay.listenCount.formatted()) listens."
        }
        return "Listening calendar for \(year), with no active days in the report."
    }

    func shortDayLabel(_ date: Date) -> String {
        Self.utcDayLabel(date, template: "MMM d")
    }

    func longDayLabel(_ date: Date) -> String {
        Self.utcDayLabel(date, template: "MMMM d")
    }

    private static func utcDayLabel(_ date: Date, template: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = utcCalendar
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

private struct YearInMusicArtistsSection: View {
    let artists: [RankedArtist]
    let allowsNavigation: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Top artists", subtitle: "The voices that stayed with you")

            if artists.isEmpty {
                sectionEmpty("No artist ranking was included in this report.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(Array(artists.prefix(10).enumerated()), id: \.element.id) { index, artist in
                            if allowsNavigation, let destination = artist.detailDestination() {
                                NavigationLink(value: destination) {
                                    artistCard(artist, rank: index + 1, featured: index == 0)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Opens artist details")
                            } else {
                                artistCard(artist, rank: index + 1, featured: index == 0)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                }
                .contentMargins(.horizontal, -18, for: .scrollContent)
            }
        }
    }

    private func artistCard(_ artist: RankedArtist, rank: Int, featured: Bool) -> some View {
        let width: CGFloat = featured ? 190 : 156
        return VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                ArtistArtworkView(artist: artist)
                    .frame(width: width, height: width)
                    .overlay {
                        Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    }
                YearInMusicRankBadge(rank: rank)
                    .padding(8)
            }
            Text(artist.name)
                .font(.headline)
                .lineLimit(2)
            Text("\(artist.listenCount.formatted()) listens")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: width, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Number \(rank), \(artist.name), \(artist.listenCount.formatted()) \(artist.listenCount == 1 ? "listen" : "listens")"
        )
    }
}

private struct YearInMusicAlbumsSection: View {
    let releases: [YearInMusicReport.ReleaseGroup]
    let allowsNavigation: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 14, alignment: .top),
            count: dynamicTypeSize.isAccessibilitySize ? 1 : 2
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Top albums", subtitle: "The records you returned to")

            if releases.isEmpty {
                sectionEmpty("No album ranking was included in this report.")
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    ForEach(Array(releases.prefix(6).enumerated()), id: \.element.id) { index, release in
                        if allowsNavigation, let seed = release.searchSeed {
                            NavigationLink(value: seed) {
                                albumCard(release, rank: index + 1)
                            }
                            .buttonStyle(.plain)
                        } else {
                            albumCard(release, rank: index + 1)
                        }
                    }
                }
            }
        }
    }

    private func albumCard(_ release: YearInMusicReport.ReleaseGroup, rank: Int) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: 14) {
                    albumArtwork(release, rank: rank)
                        .frame(width: 116, height: 116)
                    albumIdentity(release, accessibilityLayout: true)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    albumArtwork(release, rank: rank)
                        .aspectRatio(1, contentMode: .fit)
                    albumIdentity(release, accessibilityLayout: false)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Number \(rank), \(release.title) by \(release.artistName), \(release.listenCount.formatted()) listens")
        .accessibilityHint(release.searchSeed == nil ? "" : "Opens album details")
    }

    private func albumArtwork(_ release: YearInMusicReport.ReleaseGroup, rank: Int) -> some View {
        ZStack(alignment: .topLeading) {
            ArtworkView(url: release.artworkURL, title: release.title, cornerRadius: 14)
            YearInMusicRankBadge(rank: rank)
                .padding(8)
        }
    }

    private func albumIdentity(
        _ release: YearInMusicReport.ReleaseGroup,
        accessibilityLayout: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(release.title)
                .font(.headline)
                .lineLimit(accessibilityLayout ? 3 : 2)
            Text(release.artistName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text("\(release.listenCount.formatted()) listens")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct YearInMusicNewReleasesSection: View {
    let releases: [YearInMusicReport.NewRelease]
    let year: Int
    let allowsNavigation: Bool
    var loadsArtwork = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 14, alignment: .top),
            count: dynamicTypeSize.isAccessibilitySize ? 1 : 2
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "New from top artists",
                subtitle: "Albums and singles released in \(year)"
            )

            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                ForEach(releases.prefix(6)) { release in
                    if allowsNavigation, let destination = release.detailDestination {
                        NavigationLink(value: destination) {
                            card(release)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens release details")
                    } else {
                        card(release)
                    }
                }
            }
        }
    }

    private func card(_ release: YearInMusicReport.NewRelease) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: 14) {
                    ArtworkView(
                        url: loadsArtwork ? release.artworkURL : nil,
                        title: release.title,
                        cornerRadius: 14
                    )
                        .frame(width: 116, height: 116)
                    identity(release, accessibilityLayout: true)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ArtworkView(
                        url: loadsArtwork ? release.artworkURL : nil,
                        title: release.title,
                        cornerRadius: 14
                    )
                        .aspectRatio(1, contentMode: .fit)
                    identity(release, accessibilityLayout: false)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(release.title) by \(release.artistName)")
    }

    private func identity(
        _ release: YearInMusicReport.NewRelease,
        accessibilityLayout: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(release.title)
                .font(.headline)
                .lineLimit(accessibilityLayout ? nil : 3)
            Text(release.artistName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Archival 2021/22 reports rank concrete MusicBrainz releases, not release
/// groups. Keep both the label and navigation truthful.
private struct YearInMusicReleasesSection: View {
    let releases: [YearInMusicReport.Release]
    let allowsNavigation: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Top releases", subtitle: "The editions you returned to")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 18) {
                ForEach(Array(releases.prefix(6).enumerated()), id: \.offset) { index, release in
                    Group {
                        if allowsNavigation, let seed = release.seed {
                            NavigationLink(value: seed) { card(release, rank: index + 1) }.buttonStyle(.plain)
                        } else { card(release, rank: index + 1) }
                    }
                }
            }
        }
    }

    private func card(_ release: YearInMusicReport.Release, rank: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                ArtworkView(url: release.artworkURL, title: release.title, cornerRadius: 14)
                YearInMusicRankBadge(rank: rank).padding(8)
            }
            .aspectRatio(1, contentMode: .fit)
            Text(release.title).font(.headline).lineLimit(2)
            Text(release.artistName).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            Text("\(release.listenCount.formatted()) listens").font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Number \(rank), \(release.title) by \(release.artistName), \(release.listenCount.formatted()) listens")
        .accessibilityHint(allowsNavigation && release.seed != nil ? "Opens release details" : "")
    }
}

private struct YearInMusicTracksSection: View {
    let recordings: [YearInMusicReport.TopRecording]
    let allowsNavigation: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var rankCircleSize: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Top tracks", subtitle: "Your most-played tracks")

            if recordings.isEmpty {
                sectionEmpty("No track ranking was included in this report.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recordings.prefix(10).enumerated()), id: \.element.id) { index, item in
                        if allowsNavigation, let destination = item.detailDestination {
                            NavigationLink(value: destination) {
                                trackRow(item, rank: index + 1, showsDisclosure: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens track details")
                        } else {
                            trackRow(item, rank: index + 1, showsDisclosure: false)
                        }

                        if index < min(recordings.count, 10) - 1 {
                            Divider().padding(.leading, dynamicTypeSize.isAccessibilitySize ? 0 : 96)
                        }
                    }
                }
            }
        }
    }

    private func trackRow(
        _ item: YearInMusicReport.TopRecording,
        rank: Int,
        showsDisclosure: Bool
    ) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        rankCircle(rank)
                        trackIdentity(item)
                        if showsDisclosure {
                            Image(systemName: "chevron.right")
                                .font(.body.bold())
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                    }
                    Text("\(item.listenCount.formatted()) listens")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 12) {
                    rankCircle(rank)
                    ArtworkView(url: item.artworkURL, title: item.recording.title, cornerRadius: 9)
                        .frame(width: 52, height: 52)
                    trackIdentity(item)
                    Spacer(minLength: 8)
                    Text("\(item.listenCount.formatted())")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if showsDisclosure {
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Number \(rank), \(item.recording.title) by \(item.recording.artistName), \(item.listenCount.formatted()) listens")
    }

    private func trackIdentity(_ item: YearInMusicReport.TopRecording) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.recording.title)
                .font(.body.weight(.semibold))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
            Text(item.recording.artistName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rankCircle(_ rank: Int) -> some View {
        Text("\(rank)")
            .font(.caption.bold().monospacedDigit())
            .foregroundStyle(rank <= 3 ? .black : AppTheme.accent)
            .frame(width: min(rankCircleSize, 72), height: min(rankCircleSize, 72))
            .background(rank <= 3 ? YearInMusicPalette.medal(rank) : AppTheme.accent.opacity(0.13), in: .circle)
    }
}

private struct YearInMusicRankBadge: View {
    let rank: Int

    var body: some View {
        Text("#\(rank)")
            .font(.caption2.bold().monospacedDigit())
            .foregroundStyle(rank <= 3 ? .black : .primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(rank <= 3 ? YearInMusicPalette.medal(rank) : Color.clear, in: .capsule)
            .background(.ultraThinMaterial, in: .capsule)
            .accessibilityHidden(true)
    }
}

private func sectionEmpty(_ message: String) -> some View {
    Text(message)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .center)
        .multilineTextAlignment(.center)
        .padding(.horizontal)
        .background(.thinMaterial, in: .rect(cornerRadius: 18, style: .continuous))
}

private struct YearInMusicMeshBackground: View {
    let animated: Bool
    @State private var phase: CGFloat = 0

    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: points,
            colors: YearInMusicPalette.distributedColors
        )
        .onAppear {
            guard animated else { return }
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    private var points: [SIMD2<Float>] {
        let value = Float(phase)
        return [
            [0, 0], [0.5 + 0.04 * value, 0], [1, 0],
            [0, 0.5 + 0.03 * value], [0.5 - 0.04 * value, 0.5 + 0.04 * value], [1, 0.5 - 0.03 * value],
            [0, 1], [0.5 + 0.03 * value, 1], [1, 1],
        ]
    }
}

private enum YearInMusicPalette {
    // Cassette's 2025 "electric dusk" palette, retained for provenance and
    // used consistently across the first current-schema retrospective.
    private static let colors = [
        Color(red: 0.671, green: 0.278, blue: 0.737),
        Color(red: 0.925, green: 0.251, blue: 0.478),
        Color(red: 0.157, green: 0.208, blue: 0.576),
    ]

    static let distributedColors = [
        colors[0], colors[0], colors[1],
        colors[0], colors[1], colors[1],
        colors[1], colors[2], colors[2],
    ]

    static func medal(_ rank: Int) -> Color {
        switch rank {
        case 1: Color(red: 1, green: 0.84, blue: 0)
        case 2: Color(red: 0.75, green: 0.75, blue: 0.75)
        default: Color(red: 0.80, green: 0.50, blue: 0.20)
        }
    }
}

#if DEBUG
struct VisualQAYearInMusicProvider: YearInMusicProviding {
    func report(username: String, year: Int) async throws -> YearInMusicReport? {
        .visualQA(year: year)
    }
}

private extension YearInMusicReport {
    static func visualQA(year: Int) -> Self {
        let artistIDs = [
            UUID(uuidString: "28cbf94d-0700-4095-a188-37e15f5c3c45"),
            UUID(uuidString: "10adbe5d-305b-4b75-9415-f00a3f2ed75e"),
            UUID(uuidString: "b10bbbfc-cf9e-42e0-be17-e2c3e1d2600d"),
            UUID(uuidString: "9c9f1380-2516-4fc9-a3e6-f9f61941d090"),
        ]
        let artists = [
            RankedArtist(mbid: artistIDs[0], name: "Alvvays", listenCount: 612),
            RankedArtist(mbid: artistIDs[1], name: "Japanese Breakfast", listenCount: 497),
            RankedArtist(mbid: artistIDs[2], name: "Radiohead", listenCount: 421),
            RankedArtist(mbid: artistIDs[3], name: "Men I Trust", listenCount: 318),
        ]
        let releaseGroups = [
            visualRelease(title: "Blue Rev", artist: "Alvvays", count: 184, seed: 1),
            visualRelease(title: "Jubilee", artist: "Japanese Breakfast", count: 151, seed: 2),
            visualRelease(title: "In Rainbows", artist: "Radiohead", count: 143, seed: 3),
            visualRelease(title: "Untourable Album", artist: "Men I Trust", count: 109, seed: 4),
        ]
        let newReleases = [
            NewRelease(
                releaseGroupMBID: visualUUID(40), concreteReleaseMBID: visualUUID(140),
                title: "A very long new release title that wraps cleanly at larger text sizes",
                artistName: "Alvvays", artistMBIDs: [artistIDs[0]!],
                coverArtArchiveID: nil, artworkReleaseMBID: nil
            ),
            NewRelease(
                releaseGroupMBID: visualUUID(41), concreteReleaseMBID: visualUUID(141),
                title: "For Melancholy Brunettes (& Sad Women)",
                artistName: "Japanese Breakfast", artistMBIDs: [artistIDs[1]!],
                coverArtArchiveID: nil, artworkReleaseMBID: nil
            ),
            NewRelease(
                releaseGroupMBID: nil, concreteReleaseMBID: visualUUID(142),
                title: "Unmapped edition", artistName: "Radiohead", artistMBIDs: [artistIDs[2]!],
                coverArtArchiveID: nil, artworkReleaseMBID: nil
            ),
        ]
        let tracks = [
            visualRecording(title: "Belinda Says", artist: "Alvvays", release: "Blue Rev", count: 73, seed: 10),
            visualRecording(title: "Be Sweet", artist: "Japanese Breakfast", release: "Jubilee", count: 68, seed: nil),
            visualRecording(title: "Weird Fishes / Arpeggi", artist: "Radiohead", release: "In Rainbows", count: 62, seed: 12),
            visualRecording(title: "Sugar", artist: "Men I Trust", release: "Untourable Album", count: 51, seed: 13),
            visualRecording(title: "Dreams Tonite", artist: "Alvvays", release: "Antisocialites", count: 48, seed: 14),
        ]
        let days = stride(from: 0, through: 364, by: 1).compactMap { offset -> ListeningDay? in
            guard offset % 3 != 0 || offset % 11 == 0,
                  let date = visualDate(year: year, dayOffset: offset)
            else { return nil }
            let count = 2 + ((offset * 17) % 31)
            return ListeningDay(day: date, listenCount: count, sourceTimeRange: nil)
        }
        let archive = (2021 ... 2024).contains(year)
        let concreteReleases = year <= 2022 ? releaseGroups.enumerated().map { index, group in
            Release(
                releaseMBID: visualUUID(index + 100), title: group.title,
                artistName: group.artistName, artistMBIDs: group.artistMBIDs,
                listenCount: group.listenCount, coverArtArchiveID: nil,
                artworkReleaseMBID: visualUUID(index + 100),
                providedArtworkURL: nil
            )
        } : []
        return YearInMusicReport(
            username: "visual-taste",
            year: year,
            source: archive ? .archive : .current,
            totals: Totals(
                listenCount: 18_742,
                artistCount: 1_286,
                recordingCount: 6_403,
                releaseGroupCount: 2_138,
                newArtistCount: 412,
                listeningTime: 4_982 * 3_600,
                hasArtistCount: year != 2021,
                hasRecordingCount: year != 2021,
                hasReleaseCount: year != 2021,
                hasListeningTime: year != 2021
            ),
            listeningDays: days,
            topArtists: artists,
            newReleasesOfTopArtists: newReleases,
            topReleaseGroups: year <= 2022 ? [] : releaseGroups,
            topReleases: concreteReleases,
            topRecordings: tracks,
            mostActiveWeekday: .init(name: "Saturday", order: 5),
            topGenres: [
                .init(name: "Dream pop", listenCount: 2_184, percentage: 34.8, hasListenCount: true),
                .init(name: "Indie rock", listenCount: 1_806, percentage: 28.8, hasListenCount: true),
                .init(name: "Art pop", listenCount: 1_174, percentage: 18.7, hasListenCount: true),
                .init(name: "Atmospheric experimental indie rock", listenCount: 961, percentage: 15.3, hasListenCount: true),
            ],
            releaseDecades: [
                .init(decade: 2020, listenCount: 6_942),
                .init(decade: 2010, listenCount: 5_817),
                .init(decade: 2000, listenCount: 3_420),
                .init(decade: 1990, listenCount: 1_163),
            ],
            artistEvolution: ArtistEvolutionActivity(
                period: .thisYear,
                from: visualDate(year: year, dayOffset: 0) ?? .distantPast,
                to: visualDate(year: year + 1, dayOffset: 0) ?? .distantPast,
                lastUpdated: .distantPast,
                rows: visualArtistEvolutionRows(artistIDs: artistIDs)
            )
        )
    }

    static func visualRelease(title: String, artist: String, count: Int, seed: Int) -> ReleaseGroup {
        ReleaseGroup(
            releaseGroupMBID: visualUUID(seed),
            title: title,
            artistName: artist,
            artistMBIDs: [],
            listenCount: count,
            coverArtArchiveID: nil,
            artworkReleaseMBID: nil
        )
    }

    static func visualRecording(title: String, artist: String, release: String, count: Int, seed: Int?) -> TopRecording {
        TopRecording(
            recording: Recording(
                identity: .init(mbid: seed.map(visualUUID), msid: nil),
                title: title,
                artistName: artist,
                artistMBIDs: [],
                releaseTitle: release,
                releaseMBID: nil,
                releaseGroupMBID: nil,
                artworkReleaseMBID: nil,
                durationMilliseconds: nil,
                source: "ListenBrainz"
            ),
            listenCount: count,
            coverArtArchiveID: nil
        )
    }

    static func visualDate(year: Int, dayOffset: Int) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) else { return nil }
        return calendar.date(byAdding: .day, value: dayOffset, to: start)
    }

    static func visualArtistEvolutionRows(artistIDs: [UUID?]) -> [ArtistEvolutionActivity.Row] {
        ArtistEvolutionActivity.monthNames.enumerated().flatMap { month, name in
            artistIDs.enumerated().map { index, identifier in
                let listenCount = max(0, 24 + ((month * 19 + index * 31) % 92) - (index == 3 && month < 4 ? 45 : 0))
                return .init(
                    timeUnit: name,
                    artistMBID: identifier,
                    artistName: ["Alvvays", "Japanese Breakfast", "Radiohead", "Men I Trust"][index],
                    listenCount: listenCount
                )
            }
        }
    }

    static func visualUUID(_ seed: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", seed))!
    }
}
#endif
