import SwiftUI

struct ArchivedHistorySnapshotView: View {
    @State private var model: ArchivedHistorySnapshotModel
    @State private var loadGeneration = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let reader: any ArchivedHistoryReading

    init(
        archive: UserDataExportArchive,
        expectedUsername: String,
        reader: any ArchivedHistoryReading = ArchivedHistoryReader()
    ) {
        self.reader = reader
        _model = State(initialValue: ArchivedHistorySnapshotModel(
            archive: archive,
            expectedUsername: expectedUsername,
            reader: reader
        ))
    }

    var body: some View {
        Group {
            if let catalog = model.catalog {
                catalogList(catalog)
            } else if model.isLoading {
                snapshotLoadingState
            } else if let errorMessage = model.errorMessage {
                failureState(errorMessage)
            } else {
                snapshotLoadingState
            }
        }
        .navigationTitle("History snapshot")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: loadGeneration) {
            await model.load(retrying: loadGeneration > 0)
        }
        .onDisappear { model.cancel() }
    }

    private var snapshotLoadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Opening history snapshot")
                .font(.headline)
            Text("Large archives may take a moment to check.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func failureState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Snapshot couldn’t open", systemImage: "archivebox.badge.xmark")
        } description: {
            Text(message)
        } actions: {
            Button("Try again") { loadGeneration += 1 }
                .buttonStyle(.borderedProminent)
        }
    }

    private func catalogList(_ catalog: ArchivedHistoryCatalog) -> some View {
        List {
            snapshotSummary(catalog)

            if !catalog.months.isEmpty {
                Section {
                    NavigationLink {
                        ArchivedHistorySearchView(
                            archive: model.archive,
                            expectedUsername: catalog.username,
                            reader: reader
                        )
                    } label: {
                        Label("Search all history", systemImage: "magnifyingglass")
                            .font(.body.weight(.semibold))
                    }
                    Text("Find artists, albums, or tracks in this downloaded archive. Search stays on this device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if catalog.months.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No listening history",
                        systemImage: "waveform.slash",
                        description: Text("This snapshot doesn’t contain any monthly listening files.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                }
            } else {
                ForEach(groupedMonths(catalog.months), id: \.year) { group in
                    Section(group.year.calendarYearText) {
                        ForEach(group.months) { descriptor in
                            NavigationLink {
                                ArchivedHistoryMonthView(
                                    archive: model.archive,
                                    expectedUsername: catalog.username,
                                    descriptor: descriptor,
                                    reader: reader
                                )
                            } label: {
                                monthRow(descriptor)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("archived-history-snapshot")
    }

    private func snapshotSummary(_ catalog: ArchivedHistoryCatalog) -> some View {
        let downloadedAt = model.archive.downloadedAt.formatted(date: .abbreviated, time: .shortened)
        return Section {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 14) {
                        snapshotIcon
                        snapshotCopy(catalog: catalog, downloadedAt: downloadedAt)
                    }
                } else {
                    HStack(alignment: .top, spacing: 14) {
                        snapshotIcon
                        snapshotCopy(catalog: catalog, downloadedAt: downloadedAt)
                    }
                }
            }
            .padding(.vertical, 5)
            .accessibilityElement(children: .combine)
        }
    }

    private var snapshotIcon: some View {
        Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
            .font(.title2.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(
                AppTheme.artworkGradient(seed: "history-snapshot"),
                in: .rect(cornerRadius: 15, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    private func snapshotCopy(catalog: ArchivedHistoryCatalog, downloadedAt: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(catalog.username)
                .font(.headline)
            archiveRangeLabel(model.archive.range)
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("archived-history-range")
            Text("Downloaded \(downloadedAt)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("This is a read-only copy. It won’t update or contact ListenBrainz while you browse.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func archiveRangeLabel(_ range: UserDataExportRange) -> Text {
        switch (range.startTime, range.endTime) {
        case (nil, nil):
            Text("All listening history")
        case let (.some(start), .some(end)):
            Text("Archive range: \(archiveDate(start)) – \(archiveDate(end))")
        case let (.some(start), nil):
            Text("Archive range: Since \(archiveDate(start))")
        case let (nil, .some(end)):
            Text("Archive range: Through \(archiveDate(end))")
        }
    }

    private func archiveDate(_ timestamp: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(timestamp))
            .formatted(date: .abbreviated, time: .omitted)
    }

    private func monthRow(_ descriptor: ArchivedHistoryMonthDescriptor) -> some View {
        let name = monthName(descriptor.month)
        let year = descriptor.year.calendarYearText
        let size = byteCount(descriptor.uncompressedByteCount)
        return HStack(spacing: 13) {
            Image(systemName: "calendar")
                .font(.headline)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 32, height: 32)
                .background(AppTheme.accent.opacity(0.12), in: .rect(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.body.weight(.semibold))
                Text(size)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "\(name) \(year), \(size)"))
    }

    private func groupedMonths(_ months: [ArchivedHistoryMonthDescriptor]) -> [(year: Int, months: [ArchivedHistoryMonthDescriptor])] {
        Dictionary(grouping: months, by: \.year)
            .map { (year: $0.key, months: $0.value.sorted { $0.month > $1.month }) }
            .sorted { $0.year > $1.year }
    }
}

private struct ArchivedHistorySearchView: View {
    @State private var model: ArchivedHistorySearchModel
    @FocusState private var isSearchFocused: Bool

    init(
        archive: UserDataExportArchive,
        expectedUsername: String,
        reader: any ArchivedHistoryReading
    ) {
        _model = State(initialValue: ArchivedHistorySearchModel(
            archive: archive,
            expectedUsername: expectedUsername,
            reader: reader
        ))
    }

    var body: some View {
        List {
            Section {
                TextField("Artist, album, or track", text: $model.query)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .onSubmit { submitSearch() }
                    .disabled(model.isSearching)
                    .accessibilityIdentifier("archived-history-search-field")

                Text("Search stays on this device. It can take a moment for a large archive.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let validationMessage = model.validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                Button("Search archive") {
                    submitSearch()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isSearching)
                .accessibilityIdentifier("archived-history-search-submit")
            }

            if model.isSearching {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Searching your downloaded history")
                    }
                    Button("Cancel search", role: .cancel) { model.cancel() }
                        .accessibilityIdentifier("archived-history-search-cancel")
                }
            } else if let errorMessage = model.errorMessage {
                Section {
                    ContentUnavailableView {
                        Label("Search couldn’t finish", systemImage: "magnifyingglass.circle")
                    } description: {
                        Text(errorMessage)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                }
            } else if let result = model.result {
                results(result)
            } else {
                Section {
                    ContentUnavailableView(
                        "Search your downloaded history",
                        systemImage: "magnifyingglass",
                        description: Text("Enter an artist, album, or track, then choose Search archive.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Search all history")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { isSearchFocused = true }
        .onDisappear { model.cancel() }
        .accessibilityIdentifier("archived-history-search")
    }

    private func submitSearch() {
        isSearchFocused = false
        model.submit()
    }

    @ViewBuilder
    private func results(_ result: ArchivedHistorySearchResult) -> some View {
        Section {
            if !result.matches.isEmpty {
                Text(matchCountCopy(result.matches.count))
                    .font(.headline)
            }

            Text("Searched \(result.scannedMonthCount) of \(result.totalMonthCount) months on this device.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if result.isPartial {
                Label(partialCopy(result), systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("archived-history-search-partial-warning")
            }

            if result.malformedLineCount > 0 {
                Label(skippedRowsCopy(result.malformedLineCount), systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }

        if result.matches.isEmpty {
            Section {
                ContentUnavailableView(
                    result.isPartial ? "No matches in the scanned history" : "No matching listens",
                    systemImage: "waveform.slash",
                    description: Text(
                        result.isPartial
                            ? "This search reached a safety limit before every month could be scanned."
                            : "Try another artist, album, or track."
                    )
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            }
        } else {
            ForEach(groupedSearchMatches(result.matches)) { group in
                Section(group.day.formatted(date: .complete, time: .omitted)) {
                    ForEach(group.matches) { match in
                        ArchivedListenRow(listen: match.listen, includesDateContext: true)
                    }
                }
            }
        }
    }

    private func partialCopy(_ result: ArchivedHistorySearchResult) -> String {
        if result.matchLimitReached {
            return String(localized: "Showing the newest 500 matches. Refine your search to see more.")
        }
        return String(localized: "Only the newest part of this archive was searched. Browse individual months to search older listens.")
    }

    private func matchCountCopy(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 match")
            : String(localized: "\(count) matches")
    }

    private func skippedRowsCopy(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 unreadable listen was skipped.")
            : String(localized: "\(count) unreadable listens were skipped.")
    }

    private func groupedSearchMatches(
        _ matches: [ArchivedHistorySearchMatch]
    ) -> [ArchivedHistorySearchDayGroup] {
        Dictionary(grouping: matches) { Calendar.autoupdatingCurrent.startOfDay(for: $0.listen.listenedAt) }
            .map { ArchivedHistorySearchDayGroup(day: $0.key, matches: $0.value) }
            .sorted { $0.day > $1.day }
    }
}

private struct ArchivedHistorySearchDayGroup: Identifiable {
    let day: Date
    let matches: [ArchivedHistorySearchMatch]
    var id: Date { day }
}

private struct ArchivedHistoryMonthView: View {
    @State private var model: ArchivedHistoryMonthModel
    @State private var searchQuery = ""
    @State private var loadGeneration = 0
    @Environment(\.calendar) private var calendar

    init(
        archive: UserDataExportArchive,
        expectedUsername: String,
        descriptor: ArchivedHistoryMonthDescriptor,
        reader: any ArchivedHistoryReading
    ) {
        _model = State(initialValue: ArchivedHistoryMonthModel(
            archive: archive,
            expectedUsername: expectedUsername,
            descriptor: descriptor,
            reader: reader
        ))
    }

    var body: some View {
        Group {
            if let snapshot = model.snapshot {
                monthList(snapshot)
            } else if model.isLoading {
                monthLoadingState
            } else if let errorMessage = model.errorMessage {
                failureState(errorMessage)
            } else {
                monthLoadingState
            }
        }
        .navigationTitle(monthTitle(model.descriptor))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchQuery, prompt: "Search this month")
        .task(id: loadGeneration) {
            await model.load(retrying: loadGeneration > 0)
        }
        .onDisappear { model.cancel() }
    }

    private var monthLoadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Opening this month")
                .font(.headline)
            Text("Brainz is reading the downloaded copy on this device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func failureState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Month couldn’t open", systemImage: "calendar.badge.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Try again") { loadGeneration += 1 }
                .buttonStyle(.borderedProminent)
        }
    }

    private func monthList(_ snapshot: ArchivedListenMonth) -> some View {
        let visibleListens = filtered(snapshot.listens.reversed())
        let groups = groupedByDay(visibleListens)
        return List {
            Section {
                Label("Read-only snapshot", systemImage: "lock.doc")
                    .font(.subheadline.weight(.semibold))
                Text("This read-only view uses the archive’s saved times and metadata.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if snapshot.malformedLineCount > 0 {
                Section {
                    Label(
                        "\(snapshot.malformedLineCount) unreadable listens were skipped.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("archived-history-skipped-warning")
                }
            }

            if groups.isEmpty {
                Section {
                    ContentUnavailableView(
                        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "No listens in this month"
                            : "No matching listens",
                        systemImage: "waveform.slash",
                        description: Text(
                            searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? "The monthly file is empty."
                                : "Try another artist, album, or track."
                        )
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                }
            } else {
                ForEach(groups) { group in
                    Section(group.day.formatted(date: .complete, time: .omitted)) {
                        ForEach(group.listens) { listen in
                            ArchivedListenRow(listen: listen)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("archived-history-month")
    }

    private func filtered<S: Sequence>(_ listens: S) -> [ArchivedListen] where S.Element == ArchivedListen {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return Array(listens) }
        return listens.filter { listen in
            listen.title.localizedCaseInsensitiveContains(query)
                || listen.artistName.localizedCaseInsensitiveContains(query)
                || (listen.releaseTitle?.localizedCaseInsensitiveContains(query) == true)
        }
    }

    private func groupedByDay(_ listens: [ArchivedListen]) -> [ArchivedListenDayGroup] {
        Dictionary(grouping: listens) { calendar.startOfDay(for: $0.listenedAt) }
            .map { ArchivedListenDayGroup(day: $0.key, listens: $0.value) }
            .sorted { $0.day > $1.day }
    }
}

private struct ArchivedListenDayGroup: Identifiable {
    let day: Date
    let listens: [ArchivedListen]
    var id: Date { day }
}

private struct ArchivedListenRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let listen: ArchivedListen
    var includesDateContext = false

    var body: some View {
        HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 12) {
            // A nil URL is intentional: browsing a downloaded snapshot must not
            // turn into implicit Cover Art Archive network traffic.
            ArtworkView(url: nil, title: listen.title, cornerRadius: 8)
                .frame(width: 54, height: 54)
                .accessibilityHidden(true)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    metadata
                    time
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                metadata
                Spacer(minLength: 8)
                time
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityValue(includesDateContext ? fullTimestamp : "")
        .accessibilityHint("Saved in a read-only history snapshot")
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(listen.title)
                .font(.body.weight(.semibold))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
            Text(listen.artistName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            if let releaseTitle = listen.releaseTitle, !releaseTitle.isEmpty {
                Text(releaseTitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            }
        }
    }

    private var time: some View {
        Text(listen.listenedAt.formatted(date: .omitted, time: .shortened))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityHidden(includesDateContext)
    }

    private var fullTimestamp: String {
        listen.listenedAt.formatted(date: .complete, time: .shortened)
    }
}

private func monthName(_ month: Int) -> String {
    let symbols = DateFormatter().standaloneMonthSymbols ?? []
    guard symbols.indices.contains(month - 1) else { return month.formatted() }
    return symbols[month - 1]
}

private func monthTitle(_ descriptor: ArchivedHistoryMonthDescriptor) -> String {
    let name = monthName(descriptor.month)
    let year = descriptor.year.calendarYearText
    return String(localized: "\(name) \(year)")
}

private func byteCount(_ value: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
}

#if DEBUG
    struct ArchivedHistorySnapshotVisualQAScreen: View {
        var body: some View {
            NavigationStack {
                ArchivedHistorySnapshotView(
                    archive: UserDataExportArchive(
                        exportID: 97,
                        range: UserDataExportRange(
                            startTime: 1_704_110_400,
                            endTime: 1_780_336_800
                        ),
                        downloadedAt: Date(timeIntervalSince1970: 1_790_634_600),
                        byteCount: 4_194_304,
                        fileURL: URL(fileURLWithPath: "/tmp/visual-history-snapshot.zip")
                    ),
                    expectedUsername: "visual-listener",
                    reader: ArchivedHistoryVisualQAReader()
                )
            }
        }
    }

    private actor ArchivedHistoryVisualQAReader: ArchivedHistoryReading {
        func catalog(
            from _: UserDataExportArchive,
            expectedUsername: String
        ) async throws -> ArchivedHistoryCatalog {
            ArchivedHistoryCatalog(
                username: expectedUsername,
                months: [
                    .init(year: 2026, month: 9, uncompressedByteCount: 9_437_184),
                    .init(year: 2026, month: 8, uncompressedByteCount: 12_582_912),
                    .init(year: 2025, month: 12, uncompressedByteCount: 7_340_032),
                ]
            )
        }

        func readMonth(
            from _: UserDataExportArchive,
            expectedUsername: String,
            year: Int,
            month: Int
        ) async throws -> ArchivedListenMonth {
            let base = Date(timeIntervalSince1970: 1_790_625_600)
            return ArchivedListenMonth(
                username: expectedUsername,
                year: year,
                month: month,
                listens: [
                    fixtureListen(
                        title: "The Place Where He Inserted the Blade",
                        artist: "Black Country, New Road",
                        release: "Ants From Up There",
                        date: base.addingTimeInterval(2_400),
                        line: 1
                    ),
                    fixtureListen(
                        title: "A Walk",
                        artist: "Tycho",
                        release: "Dive",
                        date: base.addingTimeInterval(4_200),
                        line: 2
                    ),
                    fixtureListen(
                        title: "Archie, Marry Me",
                        artist: "Alvvays",
                        release: "Alvvays",
                        date: base.addingTimeInterval(86_400 + 1_500),
                        line: 3
                    ),
                ],
                blankLineCount: 1,
                malformedLineCount: 2
            )
        }

        func search(
            in _: UserDataExportArchive,
            expectedUsername _: String,
            query: String
        ) async throws -> ArchivedHistorySearchResult {
            let month = try await readMonth(
                from: UserDataExportArchive(
                    exportID: 0,
                    range: .all,
                    downloadedAt: .now,
                    byteCount: 0,
                    fileURL: URL(fileURLWithPath: "/tmp/visual-history-snapshot.zip")
                ),
                expectedUsername: "visual-listener",
                year: 2026,
                month: 9
            )
            let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let matches = month.listens.reversed().filter { listen in
                listen.title.localizedCaseInsensitiveContains(normalizedQuery)
                    || listen.artistName.localizedCaseInsensitiveContains(normalizedQuery)
                    || (listen.releaseTitle?.localizedCaseInsensitiveContains(normalizedQuery) == true)
            }
            return ArchivedHistorySearchResult(
                query: query,
                matches: matches.map {
                    .init(listen: $0, year: 2026, month: 9)
                },
                totalMonthCount: 3,
                scannedMonthCount: 3,
                malformedLineCount: 2,
                matchLimitReached: false,
                scanLimitReached: false
            )
        }

        private func fixtureListen(
            title: String,
            artist: String,
            release: String,
            date: Date,
            line: Int
        ) -> ArchivedListen {
            ArchivedListen(
                title: title,
                artistName: artist,
                releaseTitle: release,
                listenedAt: date,
                sourceLineNumber: line
            )
        }
    }
#endif
