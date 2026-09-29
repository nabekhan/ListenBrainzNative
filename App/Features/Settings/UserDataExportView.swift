import SwiftUI

struct UserDataExportView: View {
    private enum RangeMode: String, CaseIterable, Identifiable {
        case allTime
        case dateRange

        var id: Self { self }

        var title: LocalizedStringResource {
            switch self {
            case .allTime: "All listening history"
            case .dateRange: "Choose dates"
            }
        }
    }

    @State private var model: UserDataExportModel
    @State private var rangeMode: RangeMode = .allTime
    @State private var startDate: Date
    @State private var endDate = Date.now
    @State private var actionTask: Task<Void, Never>?
    @State private var archiveToRemove: UserDataExportArchive?

    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        account: Account,
        provider: (any UserDataExportProviding)? = nil
    ) {
        _model = State(initialValue: UserDataExportModel(
            account: account,
            provider: provider
        ))
        _startDate = State(
            initialValue: Calendar.autoupdatingCurrent.date(
                byAdding: .year,
                value: -1,
                to: .now
            ) ?? .now
        )
    }

    var body: some View {
        Group {
            if model.account.isAuthenticated {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        hero
                        privacyNotice
                        if let notice = model.notice {
                            noticeView(notice)
                        }
                        creationCard
                        exportsSection
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 20)
                }
                .accessibilityIdentifier("user-data-export-screen")
                .refreshable { await model.refresh() }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Refresh", systemImage: "arrow.clockwise") {
                            begin { await model.refresh() }
                        }
                        .disabled(model.isLoading || model.operation != nil)
                    }
                }
                .task { await model.load() }
                .onDisappear {
                    actionTask?.cancel()
                    actionTask = nil
                    model.cancel()
                }
            } else {
                ContentUnavailableView(
                    "Data exports are private",
                    systemImage: "lock.fill",
                    description: Text("Sign in to create and download your ListenBrainz data archive.")
                )
            }
        }
        .navigationTitle("Download your data")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Remove downloaded copy?",
            isPresented: Binding(
                get: { archiveToRemove != nil },
                set: { if !$0 { archiveToRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove from this device", role: .destructive) {
                guard let archive = archiveToRemove else { return }
                archiveToRemove = nil
                begin { await model.removeLocalArchive(exportID: archive.exportID) }
            }
            Button("Keep downloaded copy", role: .cancel) {
                archiveToRemove = nil
            }
        } message: {
            Text("This removes Brainz’s local copy. The archive on ListenBrainz remains available until it expires.")
        }
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: "archivebox.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(
                    AppTheme.artworkGradient(seed: "user-data-export"),
                    in: .rect(cornerRadius: 17, style: .continuous)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("Your ListenBrainz data")
                    .font(.headline)
                Text("Create a private ZIP archive of your listening history, profile, feedback, and pins.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var privacyNotice: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(AppTheme.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Keep this archive private")
                    .font(.subheadline.weight(.semibold))
                Text("It can contain your full listening history and account data. Share or save it only where you trust.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(AppTheme.secondary.opacity(0.10), in: .rect(cornerRadius: 17, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var creationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create an archive")
                .font(.title3.bold())

            Picker("Listening history", selection: $rangeMode) {
                ForEach(RangeMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)

            if rangeMode == .dateRange {
                VStack(spacing: 13) {
                    DatePicker(
                        "Start date",
                        selection: $startDate,
                        in: ...Date.now,
                        displayedComponents: .date
                    )
                    DatePicker(
                        "End date",
                        selection: $endDate,
                        in: ...Date.now,
                        displayedComponents: .date
                    )
                }
            }

            Text("Date limits apply only to listens. Feedback, pins, and profile data are always included.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if model.hasPendingExport {
                Label(
                    "ListenBrainz is already preparing an archive. Refresh later to check it.",
                    systemImage: "clock"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else if model.requiresReconciliation {
                Label(
                    "Refresh your exports before requesting another archive.",
                    systemImage: "arrow.clockwise"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            } else if !dateRangeIsValid {
                Label("Choose an end date on or after the start date.", systemImage: "calendar.badge.exclamationmark")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            Button {
                guard let range = selectedRange else { return }
                begin { await model.create(range: range) }
            } label: {
                if model.operation == .creating {
                    HStack(spacing: 9) {
                        ProgressView()
                        Text("Requesting archive…")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Label("Create archive", systemImage: "archivebox.badge.plus")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(AppTheme.accent)
            .disabled(!canCreate)
        }
        .padding(17)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder private var exportsSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Your archives")
                .font(.title3.bold())

            if model.isLoading {
                ProgressView("Loading data exports…")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if let loadError = model.loadError, model.jobs.isEmpty {
                ContentUnavailableView {
                    Label("Data exports couldn’t load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Try again") { begin { await model.refresh() } }
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else if model.jobs.isEmpty {
                ContentUnavailableView(
                    "No archives yet",
                    systemImage: "archivebox",
                    description: Text("Create an archive when you want a portable copy of your ListenBrainz data.")
                )
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                ForEach(model.jobs) { job in
                    exportCard(job)
                }
            }
        }
    }

    private func exportCard(_ job: UserDataExportJob) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 7) {
                    statusLabel(job.status)
                    createdLabel(job)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    statusLabel(job.status)
                    Spacer(minLength: 8)
                    createdLabel(job)
                }
            }

            rangeLabel(job.range)
                .font(.headline)

            if let availableUntil = job.availableUntil, job.status.canDownload {
                Text("Available until \(availableUntil.formatted(date: .abbreviated, time: .omitted))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            switch job.status {
            case .waiting, .inProgress:
                Text("ListenBrainz prepares this in the background. Brainz checks only when you refresh.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .completed:
                completedActions(job)
            case .failed:
                Text("ListenBrainz couldn’t prepare this archive. Refresh before requesting another one.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .unknown:
                Text("This archive has a status this version of Brainz doesn’t recognize.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func completedActions(_ job: UserDataExportJob) -> some View {
        if let archive = model.archives[job.id] {
            VStack(alignment: .leading, spacing: 10) {
                Text("Brainz removes this protected copy after 24 hours during its next storage cleanup, or when you disconnect.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                NavigationLink {
                    ArchivedHistorySnapshotView(
                        archive: archive,
                        expectedUsername: model.account.username
                    )
                } label: {
                    Label("Browse history snapshot", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .accessibilityHint("Opens the downloaded listening history without contacting ListenBrainz")

                ShareLink(
                    item: archive,
                    subject: Text("ListenBrainz data archive"),
                    preview: SharePreview(
                        "ListenBrainz data archive",
                        image: Image(systemName: "archivebox.fill")
                    )
                ) {
                    Label("Share or save archive", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Opens the system share sheet. Anyone you choose can read the archive.")

                Button("Remove downloaded copy", systemImage: "trash", role: .destructive) {
                    archiveToRemove = archive
                }
                .disabled(model.operation != nil)
            }
        } else {
            Button {
                begin { await model.download(job) }
            } label: {
                if model.operation == .downloading(job.id) {
                    HStack(spacing: 9) {
                        ProgressView()
                        Text("Downloading archive…")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Label("Download archive", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
            .disabled(model.operation != nil)
        }
    }

    private func statusLabel(_ status: UserDataExportStatus) -> some View {
        let content: (LocalizedStringResource, String, Color) = switch status {
        case .waiting: ("Waiting", "clock", .secondary)
        case .inProgress: ("Preparing", "arrow.triangle.2.circlepath", AppTheme.secondary)
        case .completed: ("Ready to download", "checkmark.circle.fill", AppTheme.secondary)
        case .failed: ("Couldn’t prepare", "exclamationmark.triangle.fill", .orange)
        case .unknown: ("Status unavailable", "questionmark.circle", .secondary)
        }
        return Label(content.0, systemImage: content.1)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(content.2)
    }

    private func createdLabel(_ job: UserDataExportJob) -> some View {
        Text("Requested \(job.createdAt.formatted(date: .abbreviated, time: .shortened))")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func rangeLabel(_ range: UserDataExportRange) -> Text {
        switch (range.startTime, range.endTime) {
        case (nil, nil):
            Text("All listening history")
        case let (.some(start), .some(end)):
            Text("\(Date(timeIntervalSince1970: TimeInterval(start)).formatted(date: .abbreviated, time: .omitted)) – \(Date(timeIntervalSince1970: TimeInterval(end)).formatted(date: .abbreviated, time: .omitted))")
        case let (.some(start), nil):
            Text("Since \(Date(timeIntervalSince1970: TimeInterval(start)).formatted(date: .abbreviated, time: .omitted))")
        case let (nil, .some(end)):
            Text("Through \(Date(timeIntervalSince1970: TimeInterval(end)).formatted(date: .abbreviated, time: .omitted))")
        }
    }

    private func noticeView(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: model.requiresReconciliation ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(model.requiresReconciliation ? .orange : AppTheme.secondary)
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(.thinMaterial, in: .rect(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var selectedRange: UserDataExportRange? {
        guard rangeMode == .dateRange else { return .all }
        let start = calendar.startOfDay(for: startDate)
        let endStart = calendar.startOfDay(for: endDate)
        guard start <= endStart,
              let dayAfterEnd = calendar.date(byAdding: .day, value: 1, to: endStart)
        else { return nil }
        return UserDataExportRange(
            startTime: Int(start.timeIntervalSince1970),
            endTime: Int(dayAfterEnd.timeIntervalSince1970) - 1
        )
    }

    private var dateRangeIsValid: Bool {
        rangeMode == .allTime || selectedRange != nil
    }

    private var canCreate: Bool {
        model.hasLoaded
            && model.loadError == nil
            && model.operation == nil
            && !model.isLoading
            && !model.hasPendingExport
            && !model.requiresReconciliation
            && dateRangeIsValid
    }

    private func begin(_ operation: @escaping @MainActor () async -> Void) {
        actionTask?.cancel()
        actionTask = Task { await operation() }
    }
}

#if DEBUG
    struct UserDataExportVisualQAScreen: View {
        let state: VisualQAUserDataExportProvider.State

        var body: some View {
            NavigationStack {
                UserDataExportView(
                    account: Account(
                        username: "visual-listener-with-a-long-name",
                        token: "visual-token"
                    ),
                    provider: VisualQAUserDataExportProvider(state: state)
                )
            }
        }
    }

    struct VisualQAUserDataExportProvider: UserDataExportProviding {
        enum State {
            case populated
            case empty
            case failure
        }

        let state: State

        func list() async throws -> [UserDataExportJob] {
            switch state {
            case .failure:
                throw UserDataExportProviderError.unavailable
            case .empty:
                return []
            case .populated:
                return [
                    UserDataExportJob(
                        id: 42,
                        createdAt: .now.addingTimeInterval(-3_600),
                        availableUntil: .now.addingTimeInterval(20 * 24 * 60 * 60),
                        range: .all,
                        status: .completed
                    ),
                    UserDataExportJob(
                        id: 41,
                        createdAt: .now.addingTimeInterval(-86_400),
                        availableUntil: nil,
                        range: UserDataExportRange(
                            startTime: Int(Date.now.addingTimeInterval(-180 * 86_400).timeIntervalSince1970),
                            endTime: Int(Date.now.timeIntervalSince1970)
                        ),
                        status: .inProgress
                    ),
                ]
            }
        }

        func status(exportID: Int) async throws -> UserDataExportJob {
            let values = try await list()
            guard let value = values.first(where: { $0.id == exportID }) ?? values.first else {
                throw UserDataExportProviderError.notFound
            }
            return value
        }

        func create(range: UserDataExportRange) async throws -> UserDataExportJob {
            UserDataExportJob(
                id: 43,
                createdAt: .now,
                availableUntil: nil,
                range: range,
                status: .waiting
            )
        }

        func download(_ job: UserDataExportJob) async throws -> UserDataExportArchive {
            throw UserDataExportProviderError.unavailable
        }

        func deleteFromListenBrainz(exportID: Int) async throws {}
        func removeLocalArchive(exportID: Int) async throws {}
    }
#endif
