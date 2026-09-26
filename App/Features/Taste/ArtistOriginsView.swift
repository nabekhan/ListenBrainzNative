import SwiftUI

enum ArtistOriginsMetric: String, CaseIterable, Identifiable {
    case artists = "Artists"
    case listens = "Listens"

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .artists: "Artists"
        case .listens: "Listens"
        }
    }

    func value(for country: ArtistOrigins.Country) -> Int {
        switch self {
        case .artists: country.artistCount
        case .listens: country.listenCount
        }
    }

    func unit(for count: Int) -> String {
        switch self {
        case .artists:
            return count == 1 ? String(localized: "artist") : String(localized: "artists")
        case .listens:
            return count == 1 ? String(localized: "listen") : String(localized: "listens")
        }
    }
}

struct ArtistOriginsPresentation {
    struct Row: Identifiable, Hashable {
        let country: ArtistOrigins.Country
        let name: String

        var id: String { country.id }
    }

    let rows: [Row]
    let maximumValue: Int

    init(
        origins: ArtistOrigins,
        metric: ArtistOriginsMetric,
        locale: Locale = .autoupdatingCurrent
    ) {
        rows = origins.countries.map { country in
            Row(country: country, name: Self.countryName(code: country.code, locale: locale))
        }.sorted { lhs, rhs in
            let left = metric.value(for: lhs.country)
            let right = metric.value(for: rhs.country)
            if left != right { return left > right }

            let leftSecondary = metric == .artists ? lhs.country.listenCount : lhs.country.artistCount
            let rightSecondary = metric == .artists ? rhs.country.listenCount : rhs.country.artistCount
            if leftSecondary != rightSecondary { return leftSecondary > rightSecondary }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        maximumValue = rows.map { metric.value(for: $0.country) }.max() ?? 0
    }

    static func countryName(code: String?, locale: Locale = .autoupdatingCurrent) -> String {
        guard let code else { return String(localized: "Unknown origin") }
        let localized = locale.localizedString(forRegionCode: code)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let localized, !localized.isEmpty else { return code }
        return localized
    }
}

struct ArtistOriginsView: View {
    @Bindable var model: ListeningModel
    @Binding var period: ListeningActivityPeriod
    @State private var metric: ArtistOriginsMetric = .artists
    @State private var selectedCountry: ArtistOrigins.Country?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                introduction
                periodPicker
                content
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
        .background {
            LinearGradient(
                colors: [AppTheme.secondary.opacity(0.16), .clear],
                startPoint: .topLeading,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
        .navigationTitle("Artist origins")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await model.loadArtistOrigins(for: period, retrying: true)
        }
        .task(id: period) {
            selectedCountry = nil
            await model.loadArtistOrigins(for: period)
            showCountryFixtureIfRequested()
        }
        .sheet(item: $selectedCountry) { country in
            ArtistOriginsCountryView(country: country, model: model, locale: locale)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "globe.americas.fill")
                .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 34 : 22, weight: .semibold))
                .foregroundStyle(AppTheme.secondary)
                .frame(
                    width: dynamicTypeSize.isAccessibilitySize ? 68 : 46,
                    height: dynamicTypeSize.isAccessibilitySize ? 68 : 46
                )
                .background(AppTheme.secondary.opacity(0.14), in: .circle)
                .accessibilityHidden(true)

            Text(
                dynamicTypeSize.isAccessibilitySize
                    ? "Where your artists come from."
                    : "See where the artists you listen to come from."
            )
                .font((dynamicTypeSize.isAccessibilitySize ? Font.headline : .title3).weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text(
                dynamicTypeSize.isAccessibilitySize
                    ? "Compare countries by artists or listens."
                    : "Compare countries by artists or listens, then open one to see the artists behind it."
            )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    private var periodPicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ListeningActivityPeriod.allCases) { value in
                        Button {
                            period = value
                        } label: {
                            Text(value.title)
                                .font(.subheadline.weight(period == value ? .semibold : .regular))
                                .foregroundStyle(period == value ? .white : .primary)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 9)
                                .background(
                                    period == value ? AppTheme.accent : Color.secondary.opacity(0.12),
                                    in: .capsule
                                )
                        }
                        .id(value)
                        .buttonStyle(.plain)
                        .accessibilityLabel(value.accessibilityLabel)
                        .accessibilityAddTraits(period == value ? .isSelected : [])
                    }
                }
            }
            .onAppear { proxy.scrollTo(period, anchor: .center) }
            .onChange(of: period) { _, value in
                withAnimation(.snappy) { proxy.scrollTo(value, anchor: .center) }
            }
        }
        .accessibilityLabel("Artist origins period")
    }

    @ViewBuilder
    private var content: some View {
        switch model.artistOriginsState(for: period) {
        case .idle, .loading:
            loading
        case .unavailable:
            unavailable
        case let .failed(message):
            failure(message)
        case let .loaded(origins):
            if origins.isEmpty {
                empty
            } else {
                report(origins)
            }
        }
    }

    private var loading: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Mapping your artist origins…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var unavailable: some View {
        ContentUnavailableView(
            "Artist origins aren’t ready yet",
            systemImage: "globe.americas",
            description: Text("ListenBrainz hasn’t calculated this report for \(period.title.lowercased()) yet.")
        )
        .frame(maxWidth: .infinity, minHeight: 300)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private var empty: some View {
        ContentUnavailableView(
            "No artist origins yet",
            systemImage: "globe.americas",
            description: Text("No artists with country data were available for \(period.title.lowercased()).")
        )
        .frame(maxWidth: .infinity, minHeight: 300)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private func failure(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Artist origins unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                Task { await model.loadArtistOrigins(for: period, retrying: true) }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private func report(_ origins: ArtistOrigins) -> some View {
        let presentation = ArtistOriginsPresentation(origins: origins, metric: metric, locale: locale)
        return VStack(alignment: .leading, spacing: 18) {
            Picker("Rank countries by", selection: $metric) {
                ForEach(ArtistOriginsMetric.allCases) { value in
                    Text(value.title).tag(value)
                }
            }
            .pickerStyle(.segmented)

            summaries(origins)

            VStack(alignment: .leading, spacing: 10) {
                Text("Countries")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                ForEach(Array(presentation.rows.enumerated()), id: \.element.id) { index, row in
                    countryRow(row, rank: index + 1, maximumValue: presentation.maximumValue)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(dateRange(origins))
                Text("Based on up to your top 1,000 artists with MusicBrainz country data. Artists without country data aren’t included.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if let message = model.artistOriginsRefreshMessage(for: period) {
                Label("Showing saved artist origins. \(message)", systemImage: "arrow.clockwise.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
        .animation(.snappy, value: metric)
    }

    @ViewBuilder
    private func summaries(_ origins: ArtistOrigins) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 12) {
                summary(value: origins.countries.count.formatted(), label: "Countries", symbol: "globe")
                summary(value: origins.totalArtistCount.formatted(), label: "Artists", symbol: "music.mic")
                summary(value: origins.totalListenCount.formatted(), label: "Listens", symbol: "waveform")
            }
        } else {
            HStack(spacing: 10) {
                summary(value: origins.countries.count.formatted(), label: "Countries", symbol: "globe")
                summary(value: origins.totalArtistCount.formatted(), label: "Artists", symbol: "music.mic")
                summary(value: origins.totalListenCount.formatted(), label: "Listens", symbol: "waveform")
            }
        }
    }

    private func summary(value: String, label: LocalizedStringResource, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol)
                .foregroundStyle(AppTheme.secondary)
                .accessibilityHidden(true)
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 15, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func countryRow(
        _ row: ArtistOriginsPresentation.Row,
        rank: Int,
        maximumValue: Int
    ) -> some View {
        let selectedValue = metric.value(for: row.country)
        let fraction = maximumValue > 0 ? Double(selectedValue) / Double(maximumValue) : 0
        return Button {
            selectedCountry = row.country
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 7) {
                            countryIdentity(row, rank: rank)
                            selectedMetric(value: selectedValue)
                        }
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            countryIdentity(row, rank: rank)
                            Spacer(minLength: 8)
                            selectedMetric(value: selectedValue)
                            Image(systemName: "chevron.forward")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.12))
                        Capsule()
                            .fill(AppTheme.secondary.gradient)
                            .frame(width: max(selectedValue > 0 ? 6 : 0, geometry.size.width * fraction))
                    }
                }
                .frame(height: 7)
                .accessibilityHidden(true)

                Text(countryCountsLabel(row.country))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.vertical, 7)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(countryAccessibilityLabel(row, rank: rank))
        .accessibilityHint("Shows the artists from this country")
    }

    private func countryIdentity(_ row: ArtistOriginsPresentation.Row, rank: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(rank.formatted())
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 22, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let code = row.country.code, code != row.name {
                    Text(code)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func selectedMetric(value: Int) -> some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 1) {
            Text(value.formatted())
                .font(.subheadline.monospacedDigit().weight(.semibold))
            Text(metric.unit(for: value))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func dateRange(_ origins: ArtistOrigins) -> String {
        guard origins.from != .distantPast, origins.to != .distantPast else {
            return String(localized: "Calculated by ListenBrainz")
        }
        return String(localized: "\(origins.from.formatted(date: .abbreviated, time: .omitted)) – \(origins.to.formatted(date: .abbreviated, time: .omitted)) · calculated by ListenBrainz")
    }

    private func countryCountsLabel(_ country: ArtistOrigins.Country) -> String {
        let artists = country.artistCount == 1
            ? String(localized: "\(country.artistCount) artist")
            : String(localized: "\(country.artistCount) artists")
        let listens = country.listenCount == 1
            ? String(localized: "\(country.listenCount) listen")
            : String(localized: "\(country.listenCount) listens")
        return String(localized: "\(artists) · \(listens)")
    }

    private func countryAccessibilityLabel(_ row: ArtistOriginsPresentation.Row, rank: Int) -> String {
        let artists = row.country.artistCount == 1
            ? String(localized: "\(row.country.artistCount) artist")
            : String(localized: "\(row.country.artistCount) artists")
        let listens = row.country.listenCount == 1
            ? String(localized: "\(row.country.listenCount) listen")
            : String(localized: "\(row.country.listenCount) listens")
        return String(localized: "\(rank). \(row.name). \(artists), \(listens)")
    }

    private func showCountryFixtureIfRequested() {
        #if DEBUG
            guard ProcessInfo.processInfo.arguments.contains("-brainz-artist-origins-country-demo"),
                  case let .loaded(origins) = model.artistOriginsState(for: period)
            else { return }
            selectedCountry = origins.countries.first
        #endif
    }
}

private struct ArtistOriginsCountryView: View {
    let country: ArtistOrigins.Country
    @Bindable var model: ListeningModel
    let locale: Locale
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var name: String {
        ArtistOriginsPresentation.countryName(code: country.code, locale: locale)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: 12) { summaries }
                    } else {
                        HStack(spacing: 12) { summaries }
                    }
                }

                Section("Leading artists") {
                    if country.artists.isEmpty {
                        ContentUnavailableView(
                            "Artist details unavailable",
                            systemImage: "music.mic",
                            description: Text("ListenBrainz didn’t include artist details for this country.")
                        )
                    } else {
                        ForEach(country.artists) { artist in
                            artistRow(artist)
                        }
                    }
                }

                Section {
                    Text("Artist details are limited to the leading artists included by ListenBrainz.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .mediaDestinations(model: model)
        }
    }

    @ViewBuilder
    private var summaries: some View {
        metric(value: country.artistCount.formatted(), label: "Artists", symbol: "music.mic")
        metric(value: country.listenCount.formatted(), label: "Listens", symbol: "waveform")
    }

    private func metric(value: String, label: LocalizedStringResource, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(AppTheme.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline.monospacedDigit())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func artistRow(_ artist: ArtistOrigins.Artist) -> some View {
        let content = HStack(spacing: 12) {
            Image(systemName: "music.mic")
                .foregroundStyle(AppTheme.secondary)
                .frame(width: 28, height: 28)
                .background(AppTheme.secondary.opacity(0.12), in: .circle)
                .accessibilityHidden(true)
            Text(artist.name)
                .font(.body.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(artist.listenCount.formatted())
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(artist.name), \(artist.listenCount) listens"))

        if let mbid = artist.mbid {
            NavigationLink(value: RankedArtist(mbid: mbid, name: artist.name, listenCount: artist.listenCount)) {
                content
            }
            .accessibilityHint("Opens artist details")
        } else {
            content
        }
    }
}
