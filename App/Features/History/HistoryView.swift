import SwiftUI

struct HistoryView: View {
    private struct DeletionConfirmation: Identifiable {
        let listen: Listen
        let isRetryAnyway: Bool
        var id: String { "\(listen.id):\(isRetryAnyway)" }
    }

    private enum HistoryAlert: Identifiable {
        case deletionConfirmation(DeletionConfirmation)
        case deletionScheduled(String)
        case deletionSafetyRecovery

        var id: String {
            switch self {
            case let .deletionConfirmation(confirmation):
                "deletion-confirmation:\(confirmation.id)"
            case let .deletionScheduled(message):
                "deletion-scheduled:\(message)"
            case .deletionSafetyRecovery:
                "deletion-safety-recovery"
            }
        }
    }

    @Bindable var model: ListeningModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isDatePickerPresented = false
    @State private var draftDay = Date()
    @State private var dayLoadTask: Task<Void, Never>?
    @State private var historyAlert: HistoryAlert?
    @State private var inspectedListen: Listen?
    #if DEBUG
    @State private var didPresentDeleteDemo = false
    #endif

    private var calendar: Calendar { .autoupdatingCurrent }
    private var isShowingSelectedDay: Bool { model.selectedHistoryDay != nil }
    private var visibleListens: [Listen] { isShowingSelectedDay ? model.selectedDayListens : model.snapshot.recentListens }
    private var isLoadingMore: Bool { isShowingSelectedDay ? model.isLoadingMoreSelectedDay : model.isLoadingMore }
    private var canLoadMore: Bool { isShowingSelectedDay ? model.canLoadMoreSelectedDay : model.canLoadMore }

    var body: some View {
        NavigationStack {
            Group {
                if isShowingSelectedDay {
                    selectedDayContent
                } else if model.snapshot.recentListens.isEmpty, case .loading = model.phase {
                    LoadingStateView(title: "Opening listening history")
                } else if model.snapshot.recentListens.isEmpty {
                    ContentUnavailableView("No listens yet", systemImage: "waveform.slash", description: Text("Listens submitted to ListenBrainz will appear here."))
                } else {
                    historyList
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { historyToolbar }
            .mediaDestinations(model: model)
        }
        .sheet(isPresented: $isDatePickerPresented) { historyDatePicker }
        .sheet(item: $inspectedListen) { listen in
            ListenInspectionSheet(listen: listen)
        }
        .alert(item: historyAlertBinding) { alert in
            switch alert {
            case let .deletionConfirmation(confirmation):
                Alert(
                    title: Text(confirmation.isRetryAnyway ? "Send deletion again?" : "Delete this listen?"),
                    message: Text(deletionMessage(for: confirmation)),
                    primaryButton: .destructive(Text(confirmation.isRetryAnyway ? "Send again" : "Delete listen")) {
                        Task {
                            if confirmation.isRetryAnyway {
                                await model.retryListenDeletionAnyway(confirmation.listen)
                            } else {
                                await model.deleteListen(confirmation.listen)
                            }
                        }
                    },
                    secondaryButton: .cancel()
                )
            case let .deletionScheduled(message):
                Alert(
                    title: Text("Deletion scheduled"),
                    message: Text(message),
                    dismissButton: .cancel(Text("Done")) { model.deletionNotice = nil }
                )
            case .deletionSafetyRecovery:
                Alert(
                    title: Text(dynamicTypeSize.isAccessibilitySize ? "Status unknown" : "Deletion status unknown"),
                    message: Text(
                        dynamicTypeSize.isAccessibilitySize
                            ? "Reset may resend. Refresh after the next hour."
                            : "Resetting may resend a request. Wait until after the next hour, then refresh."
                    ),
                    primaryButton: .destructive(Text("Reset record")) { model.resetDeletionSafetyData() },
                    secondaryButton: .cancel(Text("Cancel")) { model.dismissDeletionSafetyRecovery() }
                )
            }
        }
        .onChange(of: model.deletionNotice, initial: true) { _, _ in
            presentPendingHistoryAlert()
        }
        .onChange(of: model.deletionSafetyRecoveryNeeded, initial: true) { _, _ in
            presentPendingHistoryAlert()
        }
        #if DEBUG
        .task(id: visibleListens.first?.id) {
            let arguments = ProcessInfo.processInfo.arguments
            guard arguments.contains("-brainz-history-delete-demo")
                    || arguments.contains("-brainz-history-delete-long-title-demo")
                    || arguments.contains("-brainz-history-delete-recovery-demo"),
                  !didPresentDeleteDemo
            else { return }
            if arguments.contains("-brainz-history-delete-recovery-demo") {
                didPresentDeleteDemo = true
                model.deletionSafetyRecoveryNeeded = true
                historyAlert = .deletionSafetyRecovery
                return
            }
            let candidates = visibleListens.filter {
                !$0.isPlayingNow && $0.recording.identity.msid != nil
            }
            let listen = arguments.contains("-brainz-history-delete-long-title-demo")
                ? candidates.max { $0.recording.title.count < $1.recording.title.count }
                : candidates.first
            guard let listen else { return }
            didPresentDeleteDemo = true
            historyAlert = .deletionConfirmation(.init(listen: listen, isRetryAnyway: false))
        }
        #endif
    }

    @ToolbarContentBuilder
    private var historyToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if isShowingSelectedDay {
                Button("Latest") {
                    dayLoadTask?.cancel()
                    model.showLatestHistory()
                }
                    .accessibilityHint("Return to your most recent listening history")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                draftDay = model.selectedHistoryDay?.day ?? .now
                isDatePickerPresented = true
            } label: {
                Label("Choose date", systemImage: "calendar")
            }
            .accessibilityHint("Browse listens from a specific local calendar day")
        }
    }

    private var selectedDayContent: some View {
        Group {
            if model.isLoadingSelectedDay, model.selectedDayListens.isEmpty {
                LoadingStateView(title: "Opening this day")
            } else if let error = model.selectedDayError, model.selectedDayListens.isEmpty {
                ContentUnavailableView {
                    Label("Couldn’t load this day", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await model.refreshSelectedHistoryDay() } }
                }
            } else if model.selectedDayListens.isEmpty {
                ContentUnavailableView {
                    Label("No listens on this day", systemImage: "calendar.badge.exclamationmark")
                } description: {
                    Text("Nothing was submitted on \(selectedDayTitle).")
                } actions: {
                    Button("Choose Another Day") {
                        draftDay = model.selectedHistoryDay?.day ?? .now
                        isDatePickerPresented = true
                    }
                    Button("Latest") {
                        dayLoadTask?.cancel()
                        model.showLatestHistory()
                    }
                }
            } else {
                historyList
            }
        }
    }

    private var historyList: some View {
        List {
            if isShowingSelectedDay {
                selectedDayNavigation
            } else if let playing = model.snapshot.playingNow {
                Section("Playing now") {
                    NavigationLink(value: playing.recording) { ListenRow(listen: playing) }
                        .contextMenu {
                            Button {
                                inspectedListen = playing
                            } label: {
                                Label("Listen details", systemImage: "text.magnifyingglass")
                            }
                            externalLinkAction(for: playing)
                        }
                }
            }

            ForEach(groupedDays, id: \.date) { day in
                Section {
                    ForEach(day.listens) { listen in
                        listenLink(listen)
                    }
                } header: {
                    if !isShowingSelectedDay {
                        Text(day.title)
                    }
                }
            }

            if let error = model.selectedDayError, isShowingSelectedDay, !model.selectedDayListens.isEmpty {
                Section {
                    Button("Try loading earlier listens again") { Task { await model.loadMoreSelectedHistoryDay() } }
                        .accessibilityHint(error)
                }
            }

            if isLoadingMore {
                HStack { Spacer(); ProgressView("Loading earlier listens…"); Spacer() }
                    .listRowSeparator(.hidden)
            } else if !canLoadMore {
                Text(isShowingSelectedDay ? "You’ve reached the start of this day." : "You’ve reached the end of the loaded history.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .refreshable {
            if isShowingSelectedDay { await model.refreshSelectedHistoryDay() }
            else { await model.refresh() }
        }
    }

    private var selectedDayNavigation: some View {
        Section {
            HStack {
                Button { shiftSelectedDay(by: -1) } label: { Label("Previous day", systemImage: "chevron.left").labelStyle(.iconOnly) }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Previous day")
                Spacer()
                VStack(spacing: 2) {
                    Text(selectedDayTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(loadedListenCountTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Showing \(loadedListenCountTitle) from \(selectedDayTitle)")
                Spacer()
                Button { shiftSelectedDay(by: 1) } label: { Label("Next day", systemImage: "chevron.right").labelStyle(.iconOnly) }
                    .buttonStyle(.borderless)
                    .disabled(isSelectedDayTodayOrLater)
                    .accessibilityLabel("Next day")
            }
        }
    }

    private func listenLink(_ listen: Listen) -> some View {
        NavigationLink(value: listen.recording) {
            ListenRow(listen: listen)
                .task {
                    guard listen.id == visibleListens.last?.id else { return }
                    if isShowingSelectedDay { await model.loadMoreSelectedHistoryDay() }
                    else { await model.loadMore() }
                }
        }
        .contextMenu {
            Button {
                inspectedListen = listen
            } label: {
                Label("Listen details", systemImage: "text.magnifyingglass")
            }
            Button { Task { await model.setFeedback(.love, for: listen.recording) } } label: { Label("Love", systemImage: "heart") }
            Button { Task { await model.setFeedback(.hate, for: listen.recording) } } label: { Label("Hate", systemImage: "hand.thumbsdown") }
            externalLinkAction(for: listen)
            if model.account.isAuthenticated,
               !listen.isPlayingNow,
               listen.recording.identity.msid != nil {
                if model.isDeletionIndeterminate(listen) {
                    Button(role: .destructive) {
                        historyAlert = .deletionConfirmation(.init(listen: listen, isRetryAnyway: true))
                    } label: {
                        Label("Retry deletion…", systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                    }
                } else {
                    Button(role: .destructive) {
                        historyAlert = .deletionConfirmation(.init(listen: listen, isRetryAnyway: false))
                    } label: {
                        Label("Delete listen", systemImage: "trash")
                    }
                }
            }
            if let mbid = listen.recording.identity.mbid {
                Link(destination: URL(string: "https://musicbrainz.org/recording/\(mbid.uuidString)")!) { Label("Open in MusicBrainz", systemImage: "arrow.up.right.square") }
            }
        }
    }

    @ViewBuilder
    private func externalLinkAction(for listen: Listen) -> some View {
        if let externalLink = listen.recording.externalLink ?? listen.inspection?.externalLink {
            Link(destination: externalLink.url) {
                Label(externalLink.actionTitle, systemImage: "arrow.up.right.square")
            }
            .accessibilityHint(externalLink.accessibilityHint)
        }
    }

    private var historyDatePicker: some View {
        NavigationStack {
            DatePicker("Listening day", selection: $draftDay, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("Choose a Day")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { isDatePickerPresented = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("View Day") {
                            isDatePickerPresented = false
                            requestHistoryDay(draftDay)
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }

    private var groupedDays: [(date: Date, title: String, listens: [Listen])] {
        let grouped = Dictionary(grouping: visibleListens) { calendar.startOfDay(for: $0.listenedAt) }
        return grouped.keys.sorted(by: >).map { date in
            let title: String
            if calendar.isDateInToday(date) { title = "Today" }
            else if calendar.isDateInYesterday(date) { title = "Yesterday" }
            else { title = date.formatted(.dateTime.weekday(.wide).month(.wide).day()) }
            return (date, title, grouped[date] ?? [])
        }
    }

    private var selectedDayTitle: String {
        model.selectedHistoryDay?.day.formatted(.dateTime.weekday(.wide).month(.wide).day().year()) ?? ""
    }

    private var loadedListenCountTitle: String {
        let count = model.selectedDayListens.count
        return "\(count) \(count == 1 ? "listen" : "listens") loaded"
    }

    private var historyAlertBinding: Binding<HistoryAlert?> {
        Binding(
            get: { historyAlert },
            set: { alert in
                historyAlert = alert
                guard alert == nil else { return }
                Task { @MainActor in
                    await Task.yield()
                    presentPendingHistoryAlert()
                }
            }
        )
    }

    private func presentPendingHistoryAlert() {
        guard historyAlert == nil else { return }
        if model.deletionSafetyRecoveryNeeded {
            historyAlert = .deletionSafetyRecovery
        } else if let notice = model.deletionNotice {
            historyAlert = .deletionScheduled(notice)
        }
    }

    private func deletionMessage(for confirmation: DeletionConfirmation) -> String {
        if dynamicTypeSize.isAccessibilitySize {
            return confirmation.isRetryAnyway
                ? "ListenBrainz may already have this request. Wait until after the next hour and refresh first."
                : "ListenBrainz usually removes this listen after the next hour. Statistics may update later."
        }

        let title = confirmation.listen.recording.title
        let displayTitle = title.count > 36 ? "\(title.prefix(35))…" : title
        return confirmation.isRetryAnyway
            ? "ListenBrainz may already have the request for “\(displayTitle)”. Wait until after the next hour and refresh first."
            : "Removes “\(displayTitle)” from your history, usually shortly after the next hour. Statistics may update later."
    }

    private var isSelectedDayTodayOrLater: Bool {
        guard let day = model.selectedHistoryDay?.day else { return true }
        return day >= calendar.startOfDay(for: .now)
    }

    private func shiftSelectedDay(by amount: Int) {
        guard let day = model.selectedHistoryDay?.day,
              let next = calendar.date(byAdding: .day, value: amount, to: day)
        else { return }
        requestHistoryDay(next)
    }

    private func requestHistoryDay(_ day: Date) {
        dayLoadTask?.cancel()
        let calendar = calendar
        let model = model
        dayLoadTask = Task {
            await model.selectHistoryDay(day, calendar: calendar)
        }
    }
}
