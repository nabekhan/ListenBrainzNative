import SwiftUI

enum GenreDaypart: String, CaseIterable, Identifiable, Hashable, Sendable {
    case night
    case morning
    case afternoon
    case evening

    var id: Self { self }

    var title: String {
        switch self {
        case .night: "Night"
        case .morning: "Morning"
        case .afternoon: "Afternoon"
        case .evening: "Evening"
        }
    }

    var timeRange: String {
        switch self {
        case .night: "12–6 AM"
        case .morning: "6 AM–12 PM"
        case .afternoon: "12–6 PM"
        case .evening: "6 PM–12 AM"
        }
    }

    var systemImage: String {
        switch self {
        case .night: "moon.stars.fill"
        case .morning: "sunrise.fill"
        case .afternoon: "sun.max.fill"
        case .evening: "sunset.fill"
        }
    }

    static func containing(localHour: Int) -> Self {
        switch localHour {
        case 6 ..< 12: .morning
        case 12 ..< 18: .afternoon
        case 18 ..< 24: .evening
        default: .night
        }
    }
}

struct GenreActivityPresentation: Hashable, Sendable {
    struct RankedGenre: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let listenCount: Int
    }

    struct Daypart: Identifiable, Hashable, Sendable {
        let daypart: GenreDaypart
        let genres: [RankedGenre]

        var id: GenreDaypart { daypart }
        var leadingGenre: RankedGenre? { genres.first }
        var isEmpty: Bool { leadingGenre == nil || leadingGenre?.listenCount == 0 }
        var totalListenCount: Int {
            genres.reduce(0) { GenreActivityPresentation.saturatedSum($0, $1.listenCount) }
        }
    }

    let dayparts: [Daypart]

    init(
        activity: GenreActivity,
        timeZone: TimeZone,
        referenceDate: Date? = nil
    ) {
        let referenceDate = referenceDate ?? activity.to
        var grouped: [GenreDaypart: [String: RankedGenre]] = [:]

        for genre in activity.genres {
            for utcHour in 0 ..< 24 {
                let count = genre.listenCount(atUTCHour: utcHour)
                guard count > 0 else { continue }
                let localHour = Self.localHour(
                    forUTCHour: utcHour,
                    referenceDate: referenceDate,
                    timeZone: timeZone
                )
                let daypart = GenreDaypart.containing(localHour: localHour)
                let current = grouped[daypart]?[genre.id]?.listenCount ?? 0
                grouped[daypart, default: [:]][genre.id] = RankedGenre(
                    id: genre.id,
                    name: genre.name,
                    listenCount: Self.saturatedSum(current, count)
                )
            }
        }

        dayparts = GenreDaypart.allCases.map { daypart in
            let genres = grouped[daypart, default: [:]].values.sorted { lhs, rhs in
                if lhs.listenCount == rhs.listenCount {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.listenCount > rhs.listenCount
            }
            return Daypart(daypart: daypart, genres: genres)
        }
    }

    var busiestDaypart: Daypart? {
        dayparts.max { lhs, rhs in lhs.totalListenCount < rhs.totalListenCount }
    }

    func daypart(_ value: GenreDaypart) -> Daypart? {
        dayparts.first { $0.daypart == value }
    }

    static func dateRange(
        _ activity: GenreActivity,
        timeZone: TimeZone,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        guard activity.from != .distantPast, activity.to != .distantPast else {
            return "Server-calculated by ListenBrainz"
        }
        let style = Date.FormatStyle(
            date: .abbreviated,
            time: .omitted,
            locale: locale,
            calendar: Calendar(identifier: .gregorian),
            timeZone: timeZone
        )
        return "\(activity.from.formatted(style)) – \(activity.to.formatted(style)) · calculated by ListenBrainz"
    }

    private static func localHour(
        forUTCHour utcHour: Int,
        referenceDate: Date,
        timeZone: TimeZone
    ) -> Int {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = utcCalendar.dateComponents([.year, .month, .day], from: referenceDate)
        components.hour = utcHour
        // Use the midpoint of the server's one-hour bucket so half-hour and
        // quarter-hour time zones are placed in the closest honest daypart.
        components.minute = 30
        guard let bucketMidpoint = utcCalendar.date(from: components) else { return utcHour }

        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = timeZone
        return localCalendar.component(.hour, from: bucketMidpoint)
    }

    private static func saturatedSum(_ lhs: Int, _ rhs: Int) -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? Int.max : result.partialValue
    }
}

struct GenreActivityView: View {
    @Bindable var model: ListeningModel
    @Binding var period: ListeningActivityPeriod
    @State private var selectedDaypart: GenreDaypart?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if !isRankingsVisualQA {
                    introduction
                    periodPicker
                }
                content
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
        .background {
            LinearGradient(
                colors: [AppTheme.secondary.opacity(0.14), .clear],
                startPoint: .topLeading,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
        .navigationTitle("Genre Activity")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await model.loadGenreActivity(for: period, retrying: true)
            selectUsefulDaypartIfNeeded()
        }
        .task(id: period) {
            selectedDaypart = nil
            await model.loadGenreActivity(for: period)
            selectUsefulDaypartIfNeeded()
        }
    }

    private var isRankingsVisualQA: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-brainz-genre-activity-demo")
            && (arguments.contains("-brainz-genre-activity-rankings-demo") || isListOnlyVisualQA)
        #else
        false
        #endif
    }

    private var isListOnlyVisualQA: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-brainz-genre-activity-demo")
            && arguments.contains("-brainz-genre-activity-list-demo")
        #else
        false
        #endif
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 34 : 22, weight: .semibold))
                .foregroundStyle(AppTheme.secondary)
                .frame(
                    width: dynamicTypeSize.isAccessibilitySize ? 68 : 46,
                    height: dynamicTypeSize.isAccessibilitySize ? 68 : 46
                )
                .background(AppTheme.secondary.opacity(0.14), in: .circle)
                .accessibilityHidden(true)

            Text("Hear how your soundtrack changes with the clock.")
                .font((dynamicTypeSize.isAccessibilitySize ? Font.headline : .title3).weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text("ListenBrainz finds the leading genre tags in each UTC hour. Brainz groups those hours into approximate local dayparts without making extra metadata requests.")
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
        .accessibilityLabel("Genre activity period")
    }

    @ViewBuilder
    private var content: some View {
        switch model.genreActivityState(for: period) {
        case .idle, .loading:
            loading
        case .unavailable:
            unavailable
        case let .failed(message):
            failure(message)
        case let .loaded(activity):
            if activity.isEmpty {
                empty
            } else {
                report(activity)
            }
        }
    }

    private var loading: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Finding your sound through the day…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var unavailable: some View {
        ContentUnavailableView(
            "Genre activity is not ready yet",
            systemImage: "waveform.path.ecg",
            description: Text("ListenBrainz has not calculated genre activity for \(period.title.lowercased()) yet.")
        )
        .frame(maxWidth: .infinity, minHeight: 300)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private var empty: some View {
        ContentUnavailableView(
            "No mapped genre data",
            systemImage: "music.note.list",
            description: Text("No leading genre tags were available for \(period.title.lowercased()). Unmapped listens may not appear here.")
        )
        .frame(maxWidth: .infinity, minHeight: 300)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private func failure(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Genre activity unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                Task {
                    await model.loadGenreActivity(for: period, retrying: true)
                    selectUsefulDaypartIfNeeded()
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private func report(_ activity: GenreActivity) -> some View {
        let presentation = GenreActivityPresentation(activity: activity, timeZone: timeZone)
        let selection = resolvedSelection(in: presentation)
        let selected = presentation.daypart(selection)

        return VStack(alignment: .leading, spacing: 18) {
            if !isRankingsVisualQA {
                daypartPicker(presentation, selection: selection)
            }
            if let selected, !selected.isEmpty {
                if !isListOnlyVisualQA {
                    daypartHero(selected)
                }
                rankedGenres(selected)
            }

            interpretation(activity)

            if let message = model.genreActivityRefreshMessage(for: period) {
                Label("Showing saved genre activity. \(message)", systemImage: "arrow.clockwise.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func daypartPicker(
        _ presentation: GenreActivityPresentation,
        selection: GenreDaypart
    ) -> some View {
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(presentation.dayparts) { item in
                daypartButton(item, isSelected: item.daypart == selection)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Local time of day")
    }

    private func daypartButton(
        _ item: GenreActivityPresentation.Daypart,
        isSelected: Bool
    ) -> some View {
        Button {
            withAnimation(.snappy) { selectedDaypart = item.daypart }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.daypart.systemImage)
                    .font(.headline)
                    .foregroundStyle(isSelected ? .white : AppTheme.secondary)
                    .frame(width: 34, height: 34)
                    .background(
                        isSelected ? Color.white.opacity(0.16) : AppTheme.secondary.opacity(0.12),
                        in: .circle
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.daypart.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? .white : .primary)
                    Text(item.daypart.timeRange)
                        .font(.caption)
                        .foregroundStyle(isSelected ? Color.white.opacity(0.78) : .secondary)
                    Text(item.leadingGenre?.name ?? "No mapped genres")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isSelected ? .white : .primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 88 : 72, alignment: .leading)
            .padding(14)
            .background(
                isSelected ? AppTheme.secondary : Color.secondary.opacity(0.09),
                in: .rect(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? Color.white.opacity(0.28) : Color.clear, lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.daypart.title), \(item.daypart.timeRange)")
        .accessibilityValue(
            item.leadingGenre.map { "Leading genre \($0.name), \($0.listenCount) matches" }
                ?? "No mapped genres"
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func daypartHero(_ item: GenreActivityPresentation.Daypart) -> some View {
        let leader = item.leadingGenre
        return ZStack(alignment: .bottomLeading) {
            AppTheme.artworkGradient(seed: "genre-\(item.daypart.rawValue)-\(leader?.name ?? "")")

            LinearGradient(
                colors: [.clear, .black.opacity(0.42)],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )

            VStack(alignment: .leading, spacing: 10) {
                Label(item.daypart.title.uppercased(), systemImage: item.daypart.systemImage)
                    .font(.caption.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.78))

                Text(leader?.name ?? "No mapped genres")
                    .font(.system(
                        size: dynamicTypeSize.isAccessibilitySize ? 38 : 46,
                        weight: .black,
                        design: .rounded
                    ))
                    .kerning(-0.8)
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.62)
                    .fixedSize(horizontal: false, vertical: true)

                Text(
                    dynamicTypeSize.isAccessibilitySize
                        ? "Leading genre · \(item.daypart.timeRange)"
                        : "Your leading mapped genre from \(item.daypart.timeRange)"
                )
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)

                heroMetrics(item, leader: leader)
                .padding(.top, 6)
            }
            .padding(22)
        }
        .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 330 : 250, alignment: .bottomLeading)
        .clipShape(.rect(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(item.daypart.title), \(item.daypart.timeRange). Leading genre \(leader?.name ?? "none"), \(leader?.listenCount ?? 0) genre matches. \(item.genres.count) genres represented."
        )
    }

    @ViewBuilder
    private func heroMetrics(
        _ item: GenreActivityPresentation.Daypart,
        leader: GenreActivityPresentation.RankedGenre?
    ) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                accessibilityHeroMetric(
                    value: (leader?.listenCount ?? 0).formatted(),
                    label: "top matches"
                )
                accessibilityHeroMetric(
                    value: item.genres.count.formatted(),
                    label: "genres represented"
                )
            }
        } else {
            HStack(spacing: 18) {
                heroMetric(
                    value: (leader?.listenCount ?? 0).formatted(),
                    label: "top matches"
                )
                heroMetric(
                    value: item.genres.count.formatted(),
                    label: "genres represented"
                )
            }
        }
    }

    private func accessibilityHeroMetric(value: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(value)
                .font(.title2.monospacedDigit().weight(.bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func heroMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rankedGenres(_ item: GenreActivityPresentation.Daypart) -> some View {
        let genres = Array(item.genres.prefix(6))
        let maximum = max(genres.first?.listenCount ?? 0, 1)
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Leading genres")
                    .font(.headline)
                Text("Relative strength inside this daypart")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(genres.enumerated()), id: \.element.id) { index, genre in
                genreBar(genre, rank: index + 1, maximum: maximum)
            }
        }
        .padding(16)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private func genreBar(
        _ genre: GenreActivityPresentation.RankedGenre,
        rank: Int,
        maximum: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(rank)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .leading)
                Text(genre.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                Spacer(minLength: 8)
                Text(genre.listenCount.formatted())
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.12))
                    Capsule()
                        .fill(AppTheme.secondary.gradient)
                        .frame(
                            width: max(
                                5,
                                geometry.size.width * CGFloat(Double(genre.listenCount) / Double(maximum))
                            )
                        )
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rank \(rank), \(genre.name)")
        .accessibilityValue("\(genre.listenCount) genre matches")
    }

    private func interpretation(_ activity: GenreActivity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "info.circle")
                    .accessibilityHidden(true)
                Text("How to read this")
                    .multilineTextAlignment(.leading)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.secondary)

            Text("This is a view of ListenBrainz’s leading genre-tag matches for each hour—not a complete genre distribution. Recordings can carry more than one genre, so counts may overlap.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("UTC hour buckets are placed into \(timeZoneName(at: activity.to)) using the time-zone offset at the report’s end date. Dayparts are approximate when a period crosses a daylight-saving change.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(GenreActivityPresentation.dateRange(activity, timeZone: timeZone))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func timeZoneName(at date: Date) -> String {
        let style: TimeZone.NameStyle = timeZone.isDaylightSavingTime(for: date)
            ? .daylightSaving
            : .standard
        return timeZone.localizedName(for: style, locale: .autoupdatingCurrent) ?? timeZone.identifier
    }

    private func resolvedSelection(in presentation: GenreActivityPresentation) -> GenreDaypart {
        if let selectedDaypart,
           let selected = presentation.daypart(selectedDaypart),
           !selected.isEmpty {
            return selectedDaypart
        }

        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = timeZone
        let current = GenreDaypart.containing(localHour: calendar.component(.hour, from: .now))
        if let currentDaypart = presentation.daypart(current), !currentDaypart.isEmpty {
            return current
        }
        return presentation.busiestDaypart?.daypart ?? .evening
    }

    private func selectUsefulDaypartIfNeeded() {
        guard case let .loaded(activity) = model.genreActivityState(for: period) else { return }
        let presentation = GenreActivityPresentation(activity: activity, timeZone: timeZone)
        selectedDaypart = resolvedSelection(in: presentation)
    }
}
