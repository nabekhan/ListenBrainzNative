import SwiftUI

struct HistoryView: View {
    @Bindable var model: ListeningModel

    var body: some View {
        NavigationStack {
            Group {
                if model.snapshot.recentListens.isEmpty, case .loading = model.phase {
                    LoadingStateView(title: "Opening listening history")
                } else if model.snapshot.recentListens.isEmpty {
                    ContentUnavailableView(
                        "No listens yet",
                        systemImage: "waveform.slash",
                        description: Text("Listens submitted to ListenBrainz will appear here.")
                    )
                } else {
                    historyList
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .mediaDestinations(model: model)
        }
    }

    private var historyList: some View {
        List {
            if let playing = model.snapshot.playingNow {
                Section("Playing now") {
                    NavigationLink(value: playing.recording) {
                        ListenRow(listen: playing)
                    }
                }
            }

            ForEach(groupedDays, id: \.date) { day in
                Section(day.title) {
                    ForEach(day.listens) { listen in
                        NavigationLink(value: listen.recording) {
                            ListenRow(listen: listen)
                                .task {
                                    if listen.id == model.snapshot.recentListens.last?.id {
                                        await model.loadMore()
                                    }
                                }
                        }
                        .contextMenu {
                            Button {
                                Task { await model.setFeedback(.love, for: listen.recording) }
                            } label: {
                                Label("Love", systemImage: "heart")
                            }
                            Button {
                                Task { await model.setFeedback(.hate, for: listen.recording) }
                            } label: {
                                Label("Hate", systemImage: "hand.thumbsdown")
                            }
                            if let mbid = listen.recording.identity.mbid {
                                Link(destination: URL(string: "https://musicbrainz.org/recording/\(mbid.uuidString)")!) {
                                    Label("Open in MusicBrainz", systemImage: "arrow.up.right.square")
                                }
                            }
                        }
                    }
                }
            }

            if model.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView("Loading earlier listens…")
                    Spacer()
                }
                .listRowSeparator(.hidden)
            } else if !model.canLoadMore {
                Text("You’ve reached the end of the loaded history.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .refreshable { await model.refresh() }
    }

    private var groupedDays: [(date: Date, title: String, listens: [Listen])] {
        let calendar = Calendar.autoupdatingCurrent
        let grouped = Dictionary(grouping: model.snapshot.recentListens) {
            calendar.startOfDay(for: $0.listenedAt)
        }
        return grouped.keys.sorted(by: >).map { date in
            let title: String
            if calendar.isDateInToday(date) {
                title = "Today"
            } else if calendar.isDateInYesterday(date) {
                title = "Yesterday"
            } else {
                title = date.formatted(.dateTime.weekday(.wide).month(.wide).day())
            }
            return (date, title, grouped[date] ?? [])
        }
    }
}
