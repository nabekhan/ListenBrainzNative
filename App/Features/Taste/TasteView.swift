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

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    overview
                    recentActivity
                    rankings
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .refreshable { await model.refresh() }
            .navigationTitle("Taste")
            .navigationBarTitleDisplayMode(.large)
            .mediaDestinations(model: model)
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

    @ViewBuilder
    private var recentActivity: some View {
        let values = chartValues
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    title: "Recent rhythm",
                    subtitle: "Daily listens in the currently loaded history"
                )
                Chart(values) { value in
                    BarMark(
                        x: .value("Day", value.date, unit: .day),
                        y: .value("Listens", value.count)
                    )
                    .foregroundStyle(AppTheme.accent.gradient)
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 150)
                .accessibilityChartDescriptor(RecentActivityDescriptor(values: values))
                .padding(16)
                .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
            }
        }
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

    private var chartValues: [ActivityValue] {
        let calendar = Calendar.autoupdatingCurrent
        let grouped = Dictionary(grouping: model.snapshot.recentListens) {
            calendar.startOfDay(for: $0.listenedAt)
        }
        return Array(
            grouped.map { ActivityValue(date: $0.key, count: $0.value.count) }
                .sorted { $0.date < $1.date }
                .suffix(10)
        )
    }
}

private struct ActivityValue: Identifiable {
    let date: Date
    let count: Int
    var id: Date { date }
}

private struct RecentActivityDescriptor: AXChartDescriptorRepresentable {
    let values: [ActivityValue]

    func makeChartDescriptor() -> AXChartDescriptor {
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: "Day",
            categoryOrder: values.map { $0.date.formatted(date: .abbreviated, time: .omitted) }
        )
        let maximum = Double(values.map(\.count).max() ?? 1)
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Listens",
            range: 0 ... maximum,
            gridlinePositions: []
        ) { $0.formatted() }
        let points = values.map {
            AXDataPoint(
                x: $0.date.formatted(date: .abbreviated, time: .omitted),
                y: Double($0.count)
            )
        }
        return AXChartDescriptor(
            title: "Recent listening activity",
            summary: "Daily listen counts from loaded history",
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [AXDataSeriesDescriptor(name: "Listens", isContinuous: false, dataPoints: points)]
        )
    }
}
