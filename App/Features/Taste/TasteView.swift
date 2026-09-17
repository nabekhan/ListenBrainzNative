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

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    overview
                    listeningActivity
                    rankings
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .refreshable { await model.refresh() }
            .navigationTitle("Taste")
            .navigationBarTitleDisplayMode(.large)
            .mediaDestinations(model: model)
            .task(id: activityPeriod) {
                await model.loadListeningActivity(for: activityPeriod)
            }
        }
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

            HStack(spacing: 12) {
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
        }
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
            HStack(spacing: 12) {
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
                Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    rankedReleaseRow(index: index, release: release)
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
