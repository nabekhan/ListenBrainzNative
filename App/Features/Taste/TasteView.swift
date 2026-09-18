import Charts
import SwiftUI

struct TasteView: View {
    enum Ranking: String, CaseIterable, Identifiable {
        case artists = "Artists"
        case releases = "Albums"
        case recordings = "Tracks"
        var id: Self { self }
    }

    @Bindable var model: ListeningModel
    @State private var ranking: Ranking = .artists
    @AppStorage("taste.activityPeriod") private var activityPeriod: ListeningActivityPeriod = .thisWeek
    @State private var selectedDailyCellID: DailyActivity.Cell.ID?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    #if DEBUG
                    if isHeatmapVisualQA {
                        dailyListeningHours
                    } else {
                        overview
                        dailyListeningHours
                        listeningActivity
                        if !isTasteVisualQA {
                            rankings
                        }
                    }
                    #else
                    overview
                    dailyListeningHours
                    listeningActivity
                    rankings
                    #endif
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .refreshable {
                await model.refresh()
                await model.loadListeningActivity(for: activityPeriod, retrying: true)
                await model.loadDailyActivity(for: activityPeriod, retrying: true)
            }
            .navigationTitle("Taste")
            .navigationBarTitleDisplayMode(isHeatmapVisualQA ? .inline : .large)
            .mediaDestinations(model: model)
            .task(id: activityPeriod) {
                if !isHeatmapVisualQA {
                    await model.loadListeningActivity(for: activityPeriod)
                }
                await model.loadDailyActivity(for: activityPeriod)
            }
        }
    }

    private var isTasteVisualQA: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-brainz-taste-demo")
            || isHeatmapVisualQA
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

    private func tasteMetric(_ value: String, label: String, symbol: String) -> some View {
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
            activityPeriodPicker

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
        .accessibilityLabel("Activity period")
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
                                .accessibilityLabel("\(weekday.rawValue), \(hourLabel(cell.hour)) UTC")
                                .accessibilityValue("\(cell.listenCount) listens")
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
                    "\(selected.weekday.rawValue), \(hourLabel(selected.hour)) UTC · \(selected.listenCount.formatted()) listens",
                    systemImage: "clock"
                )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Selected: \(selected.weekday.rawValue), \(hourLabel(selected.hour)) UTC, \(selected.listenCount) listens")
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
                activitySummary(activity.totalListens.formatted(), label: "Listens", symbol: "clock")
                if let peak {
                    activitySummary(
                        peak.listenCount.formatted(),
                        label: "Peak · \(peak.weekday.shortTitle) \(hourLabel(peak.hour))",
                        symbol: "sun.max.fill"
                    )
                }
            }
        } else {
            HStack(spacing: 12) {
                activitySummary(activity.totalListens.formatted(), label: "Listens", symbol: "clock")
                if let peak {
                    activitySummary(
                        peak.listenCount.formatted(),
                        label: "Peak · \(peak.weekday.shortTitle) \(hourLabel(peak.hour))",
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
            return "Listening hours heatmap in UTC"
        }
        return "\(activity.period.title) listening hours in UTC. \(activity.totalListens) listens. Peak: \(peak.weekday.rawValue) at \(hourLabel(peak.hour)), \(peak.listenCount) listens."
    }

    static func dailyActivityDateRange(
        _ activity: DailyActivity,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        guard activity.from != .distantPast, activity.to != .distantPast else {
            return "Server-calculated listening hours · UTC"
        }
        let style = Date.FormatStyle(
            date: .abbreviated,
            time: .omitted,
            locale: locale,
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        return "\(activity.from.formatted(style)) – \(activity.to.formatted(style)) · UTC"
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
                .accessibilityLabel("\(bucket.label): \(bucket.listenCount) listens")
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

    private func activitySummary(_ value: String, label: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.headline.monospacedDigit())
                Text(label)
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
            label: "Listens",
            symbol: "waveform"
        )
        if let busiest = activity.busiestBucket {
            activitySummary(
                busiest.listenCount.formatted(),
                label: "Peak · \(busiest.label)",
                symbol: "chart.bar.fill"
            )
        }
    }

    private func activityDateRange(_ activity: ListeningActivity) -> String {
        guard activity.from != .distantPast, activity.to != .distantPast else {
            return "Server-calculated activity"
        }
        return "\(activity.from.formatted(date: .abbreviated, time: .omitted)) – \(activity.to.formatted(date: .abbreviated, time: .omitted))"
    }

    private var rankings: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Rankings")
            Picker("Ranking", selection: $ranking) {
                ForEach(Ranking.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            switch ranking {
            case .artists:
                ForEach(Array(model.snapshot.topArtists.prefix(20).enumerated()), id: \.element.id) { index, artist in
                    NavigationLink(value: artist) {
                        rankedArtistRow(index: index, artist: artist)
                    }
                    .buttonStyle(.plain)
                }
            case .releases:
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
            case .recordings:
                ForEach(Array(model.snapshot.topRecordings.prefix(20).enumerated()), id: \.element.id) { index, recording in
                    NavigationLink(value: recording.recording) {
                        rankedRecordingRow(index: index, recording: recording)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func rankedArtistRow(index: Int, artist: RankedArtist) -> some View {
        HStack(spacing: 12) {
            rank(index)
            ArtistArtworkView(artist: artist).frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text(artist.name).font(.body.weight(.semibold)).lineLimit(1)
                Text("\(artist.listenCount.formatted()) listens").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
    }

    private func rankedReleaseRow(index: Int, release: RankedRelease) -> some View {
        HStack(spacing: 12) {
            rank(index)
            ArtworkView(url: release.artworkURL, title: release.name, cornerRadius: 8).frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text(release.name).font(.body.weight(.semibold)).lineLimit(1)
                Text("\(release.artistName) · \(release.listenCount.formatted()) listens")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
    }

    private func rankedRecordingRow(index: Int, recording: RankedRecording) -> some View {
        HStack(spacing: 12) {
            rank(index)
            ArtworkView(url: recording.recording.artworkURL, title: recording.title, cornerRadius: 8)
                .frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text(recording.title).font(.body.weight(.semibold)).lineLimit(1)
                Text("\(recording.artistName) · \(recording.listenCount.formatted()) listens")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
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
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: "Time",
            categoryOrder: activity.buckets.map(\.label)
        )
        let maximum = Double(activity.buckets.map(\.listenCount).max() ?? 1)
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Listens",
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
            title: "\(activity.period.title) listening activity",
            summary: "\(activity.totalListens) listens calculated by ListenBrainz",
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [AXDataSeriesDescriptor(name: "Listens", isContinuous: false, dataPoints: points)]
        )
    }
}
