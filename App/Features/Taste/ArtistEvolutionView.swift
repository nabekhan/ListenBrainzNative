import Charts
import SwiftUI

struct ArtistEvolutionView: View {
    @Bindable var model: ListeningModel
    @Binding var period: ListeningActivityPeriod
    @State private var requestedArtistCount = 5
    @State private var selectedTimeUnit: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let artistCountOptions = [3, 5, 10]
    private let seriesColors: [Color] = [
        AppTheme.accent,
        .purple,
        .blue,
        .teal,
        .orange,
        .indigo,
        .green,
        .pink,
        .cyan,
        .mint,
    ]

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
                colors: [AppTheme.accent.opacity(0.12), .clear],
                startPoint: .topLeading,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
        .navigationTitle("Artist evolution")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await model.loadArtistEvolution(for: period, retrying: true)
            selectUsefulBucketIfNeeded()
        }
        .task(id: period) {
            selectedTimeUnit = nil
            await model.loadArtistEvolution(for: period)
            selectUsefulBucketIfNeeded()
        }
        .onChange(of: requestedArtistCount) { _, _ in
            selectUsefulBucketIfNeeded()
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 34 : 22, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(
                    width: dynamicTypeSize.isAccessibilitySize ? 68 : 46,
                    height: dynamicTypeSize.isAccessibilitySize ? 68 : 46
                )
                .background(AppTheme.accent.opacity(0.13), in: .circle)
                .accessibilityHidden(true)

            Text(
                dynamicTypeSize.isAccessibilitySize
                    ? "Your top artists through time."
                    : "See how the artists at the center of your listening change through time."
            )
                .font((dynamicTypeSize.isAccessibilitySize ? Font.headline : .title3).weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text(
                dynamicTypeSize.isAccessibilitySize
                    ? "Calculated by ListenBrainz from mapped recordings."
                    : "ListenBrainz calculates this from mapped recordings and returns only your leading artists for each period."
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
        .accessibilityLabel("Artist evolution period")
    }

    @ViewBuilder
    private var content: some View {
        switch model.artistEvolutionState(for: period) {
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
            Text("Following your top artists through time…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var unavailable: some View {
        ContentUnavailableView(
            "Artist evolution is not ready yet",
            systemImage: "chart.line.uptrend.xyaxis",
            description: Text("ListenBrainz has not calculated artist evolution for \(period.title.lowercased()) yet.")
        )
        .frame(maxWidth: .infinity, minHeight: 300)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private var empty: some View {
        ContentUnavailableView(
            "No mapped artist data",
            systemImage: "music.mic.circle",
            description: Text("No artist activity was available for \(period.title.lowercased()). Unmapped listens may not appear here.")
        )
        .frame(maxWidth: .infinity, minHeight: 300)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private func failure(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Artist evolution unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                Task {
                    await model.loadArtistEvolution(for: period, retrying: true)
                    selectUsefulBucketIfNeeded()
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private func report(_ activity: ArtistEvolutionActivity) -> some View {
        let artists = activity.artists(limit: requestedArtistCount)
        return VStack(alignment: .leading, spacing: 18) {
            reportHeader(activity, artists: artists)
            summaries(artists)
            evolutionChart(activity, artists: artists)
            artistLegend(artists)
            selectedBreakdown(activity, artists: artists)

            Text(dateRange(activity))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let message = model.artistEvolutionRefreshMessage(for: period) {
                Label("Showing saved artist evolution. \(message)", systemImage: "arrow.clockwise.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
        .sensoryFeedback(.selection, trigger: selectedTimeUnit)
    }

    private func reportHeader(
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
            Text(period.title)
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
        let availableCounts = Array(Set(artistCountOptions.map { min($0, activity.artists.count) }))
            .filter { $0 > 0 }
            .sorted()
        return Menu {
            ForEach(availableCounts, id: \.self) { count in
                Button {
                    requestedArtistCount = count
                } label: {
                    if artists.count == count {
                        Label("Top \(count)", systemImage: "checkmark")
                    } else {
                        Text("Top \(count)")
                    }
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
    private func summaries(_ artists: [ArtistEvolutionActivity.Artist]) -> some View {
        let visibleTotal = artists.reduce(0) { saturatedSum($0, $1.listenCount) }
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 12) {
                summary(value: visibleTotal.formatted(), label: "Top-artist listens", symbol: "waveform")
                if let leader = artists.first {
                    summary(value: leader.listenCount.formatted(), label: "Leading · \(leader.name)", symbol: "music.mic")
                }
            }
        } else {
            HStack(spacing: 12) {
                summary(value: visibleTotal.formatted(), label: "Top-artist listens", symbol: "waveform")
                if let leader = artists.first {
                    summary(value: leader.listenCount.formatted(), label: "Leading · \(leader.name)", symbol: "music.mic")
                }
            }
        }
    }

    private func summary(value: String, label: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline.monospacedDigit())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func evolutionChart(
        _ activity: ArtistEvolutionActivity,
        artists: [ArtistEvolutionActivity.Artist]
    ) -> some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: activity.timeUnits.count > 12) {
                Chart {
                    ForEach(artists) { artist in
                        ForEach(artist.points) { point in
                            LineMark(
                                x: .value("Time", point.timeUnit),
                                y: .value("Listens", point.listenCount),
                                series: .value("Artist identity", artist.id)
                            )
                            .foregroundStyle(by: .value("Artist identity", artist.id))
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.catmullRom)

                            if point.timeUnit == selectedTimeUnit {
                                PointMark(
                                    x: .value("Time", point.timeUnit),
                                    y: .value("Listens", point.listenCount)
                                )
                                .foregroundStyle(by: .value("Artist identity", artist.id))
                                .symbolSize(44)
                            }
                        }
                    }

                    // Emit this after the series so a categorical selection
                    // cannot become the first x-axis category.
                    if let selectedTimeUnit {
                        RuleMark(x: .value("Selected time", selectedTimeUnit))
                            .foregroundStyle(.secondary.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .chartForegroundStyleScale(
                    domain: artists.map(\.id),
                    range: Array(seriesColors.prefix(artists.count))
                )
                .chartLegend(.hidden)
                .chartXAxis {
                    AxisMarks(values: activity.timeUnits) { value in
                        if let label = value.as(String.self),
                           axisValues(activity.timeUnits).contains(label) {
                            AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                            AxisValueLabel {
                                Text(axisLabel(label, period: period))
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
                            } else if let count = value.as(Double.self) {
                                Text(count.formatted(.number.precision(.fractionLength(0)).notation(.compactName)))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYScale(range: .plotDimension(startPadding: 4, endPadding: 18))
                .chartXSelection(value: $selectedTimeUnit)
                .frame(
                    width: max(geometry.size.width, chartWidth(for: activity.timeUnits.count)),
                    height: dynamicTypeSize.isAccessibilitySize ? 330 : 250
                )
                .accessibilityChartDescriptor(
                    ArtistEvolutionDescriptor(activity: activity, artistLimit: requestedArtistCount)
                )
            }
        }
        .frame(height: dynamicTypeSize.isAccessibilitySize ? 330 : 250)
    }

    private func artistLegend(_ artists: [ArtistEvolutionActivity.Artist]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Artists")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(Array(artists.enumerated()), id: \.element.id) { index, artist in
                NavigationLink(value: artist.rankedArtist) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(seriesColors[index % seriesColors.count])
                            .frame(width: 10, height: 10)
                            .accessibilityHidden(true)
                        Text(artist.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(artist.listenCount.formatted())
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(artist.name), \(artist.listenCount) listens")
                .accessibilityHint("Opens artist details")
            }
        }
    }

    @ViewBuilder
    private func selectedBreakdown(
        _ activity: ArtistEvolutionActivity,
        artists: [ArtistEvolutionActivity.Artist]
    ) -> some View {
        if let selectedTimeUnit {
            let ranked = artists.sorted {
                let lhs = $0.listenCount(at: selectedTimeUnit)
                let rhs = $1.listenCount(at: selectedTimeUnit)
                if lhs == rhs {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return lhs > rhs
            }
            let bucketTotal = ranked.reduce(0) {
                saturatedSum($0, $1.listenCount(at: selectedTimeUnit))
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(selectedLabel(selectedTimeUnit, period: activity.period))
                        .font(.headline)
                    Spacer()
                    Text("\(bucketTotal.formatted()) listens")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, artist in
                    let count = artist.listenCount(at: selectedTimeUnit)
                    HStack(spacing: 10) {
                        Circle()
                            .fill(seriesColors[(artists.firstIndex(of: artist) ?? index) % seriesColors.count])
                            .frame(width: 8, height: 8)
                        Text(artist.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        Text(count.formatted())
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(count == 0 ? .tertiary : .secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(artist.name), \(count) listens")
                }
            }
            .padding(14)
            .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 16, style: .continuous))
        }
    }

    private func selectUsefulBucketIfNeeded() {
        guard case let .loaded(activity) = model.artistEvolutionState(for: period),
              !activity.timeUnits.isEmpty
        else { return }
        let artists = activity.artists(limit: requestedArtistCount)
        if let selectedTimeUnit, activity.timeUnits.contains(selectedTimeUnit) {
            return
        }
        if period == .allTime {
            selectedTimeUnit = activity.timeUnits.first { timeUnit in
                artists.contains { $0.listenCount(at: timeUnit) > 0 }
            } ?? activity.timeUnits.first
        } else {
            selectedTimeUnit = activity.timeUnits.last { timeUnit in
                artists.contains { $0.listenCount(at: timeUnit) > 0 }
            } ?? activity.timeUnits.last
        }
    }

    private func axisValues(_ values: [String]) -> [String] {
        guard values.count > 8 else { return values }
        let desiredCount = dynamicTypeSize.isAccessibilitySize ? 4 : 6
        let step = max(1, Int(ceil(Double(values.count - 1) / Double(desiredCount - 1))))
        var result = stride(from: 0, to: values.count, by: step).map { values[$0] }
        if let last = values.last, result.last != last {
            result.append(last)
        }
        return result
    }

    private func axisLabel(_ value: String, period: ListeningActivityPeriod) -> String {
        switch period {
        case .thisWeek, .lastWeek, .thisYear, .lastYear:
            return String(value.prefix(3))
        case .thisMonth, .lastMonth, .allTime:
            return value
        }
    }

    private func selectedLabel(_ value: String, period: ListeningActivityPeriod) -> String {
        switch period {
        case .thisMonth, .lastMonth:
            return "Day \(value)"
        case .allTime:
            return "Year \(value)"
        case .thisWeek, .lastWeek, .thisYear, .lastYear:
            return value
        }
    }

    private func chartWidth(for bucketCount: Int) -> CGFloat {
        guard bucketCount > 12 || dynamicTypeSize.isAccessibilitySize else { return 0 }
        return CGFloat(bucketCount) * (dynamicTypeSize.isAccessibilitySize ? 58 : 42)
    }

    private func dateRange(_ activity: ArtistEvolutionActivity) -> String {
        guard activity.from != .distantPast, activity.to != .distantPast else {
            return "Server-calculated by ListenBrainz"
        }
        return "\(activity.from.formatted(date: .abbreviated, time: .omitted)) – \(activity.to.formatted(date: .abbreviated, time: .omitted)) · calculated by ListenBrainz"
    }

    private func saturatedSum(_ lhs: Int, _ rhs: Int) -> Int {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? Int.max : result.partialValue
    }
}

private struct ArtistEvolutionDescriptor: AXChartDescriptorRepresentable {
    let activity: ArtistEvolutionActivity
    let artistLimit: Int

    func makeChartDescriptor() -> AXChartDescriptor {
        let artists = activity.artists(limit: artistLimit)
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: "Time",
            categoryOrder: activity.timeUnits
        )
        let maximum = Double(max(artists.flatMap(\.points).map(\.listenCount).max() ?? 0, 1))
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Listens",
            range: 0 ... maximum,
            gridlinePositions: []
        ) { $0.formatted() }
        let series = artists.map { artist in
            AXDataSeriesDescriptor(
                name: artist.name,
                isContinuous: false,
                dataPoints: artist.points.map {
                    AXDataPoint(x: $0.timeUnit, y: Double($0.listenCount))
                }
            )
        }
        return AXChartDescriptor(
            title: "\(activity.period.title) artist evolution",
            summary: "Listen counts for \(artists.count) leading artists across \(activity.timeUnits.count) time periods",
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: series
        )
    }
}
