import SwiftUI

struct ManualMappingSheet: View {
    let listen: Listen
    private let onSaved: (UUID) -> Void
    private let automaticallySelectFirstResult: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var search: SearchModel
    @State private var mapping: ManualMappingModel
    @State private var selected: Recording?
    @State private var sendAgainConfirmation = false
    @State private var didAutomaticallySelectResult = false

    init(
        listen: Listen,
        account: Account,
        searchProvider: (any SearchProviding)? = nil,
        mappingProvider: (any ManualMappingProviding)? = nil,
        automaticallySelectFirstResult: Bool = false,
        onSaved: @escaping (UUID) -> Void = { _ in }
    ) {
        self.listen = listen
        self.onSaved = onSaved
        self.automaticallySelectFirstResult = automaticallySelectFirstResult

        let query = [listen.inspection?.submittedTrack, listen.inspection?.submittedArtist]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        _search = State(initialValue: SearchModel(
            account: account,
            provider: searchProvider,
            initialQuery: query,
            initialScope: .recordings
        ))
        _mapping = State(initialValue: ManualMappingModel(
            account: account,
            listen: listen,
            provider: mappingProvider
        ))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let selected {
                    review(selected)
                } else {
                    searchContent
                        .searchable(
                            text: Binding(
                                get: { search.query },
                                set: { search.update(query: $0) }
                            ),
                            placement: .navigationBarDrawer(displayMode: .always),
                            prompt: "Track, artist, or recording ID"
                        )
                }
            }
            .navigationTitle(selected == nil ? String(localized: "Find MusicBrainz match") : String(localized: "Review match"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { mappingToolbar }
            .task { search.startInitialSearchIfNeeded() }
            .onChange(of: search.state) { _, state in
                #if DEBUG
                guard automaticallySelectFirstResult,
                      !didAutomaticallySelectResult,
                      state == .loaded,
                      let result = recordings.first
                else { return }
                didAutomaticallySelectResult = true
                choose(result)
                #endif
            }
            .onDisappear { search.cancel() }
            .interactiveDismissDisabled(mapping.isSaving)
            .alert("Send another match?", isPresented: $sendAgainConfirmation) {
                Button("Send again") {
                    guard let selected else { return }
                    save(selected, sendAgainAfterUnknown: true)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The first request may have succeeded. Refresh History before sending another match for this recording ID.")
            }
        }
        .presentationDragIndicator(.visible)
    }

    @ToolbarContentBuilder
    private var mappingToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if selected == nil {
                Button("Cancel") { dismiss() }
                    .disabled(mapping.isSaving)
            } else if mapping.savedMBID != nil {
                Button("Done") { dismiss() }
            } else {
                Button("Back") {
                    mapping.resetForNewSelection()
                    selected = nil
                }
                .disabled(mapping.isSaving)
            }
        }
    }

    private var searchContent: some View {
        VStack(spacing: 0) {
            submittedListenHeader
            Divider()
            searchResults
        }
    }

    private var submittedListenHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 38, height: 38)
                .background(AppTheme.accent.opacity(0.12), in: .rect(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(listen.inspection?.submittedTrack ?? listen.recording.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(listen.inspection?.submittedArtist ?? listen.recording.artistName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Submitted listen: \(listen.inspection?.submittedTrack ?? listen.recording.title), \(listen.inspection?.submittedArtist ?? listen.recording.artistName)")
    }

    @ViewBuilder
    private var searchResults: some View {
        switch search.state {
        case .waiting, .loading:
            VStack(spacing: 12) {
                ProgressView()
                if search.state == .waiting {
                    Text("Waiting to search…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Searching MusicBrainz…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            ContentUnavailableView {
                Label("MusicBrainz search unavailable", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await search.retry() } }
            }
        case .loaded where recordings.isEmpty:
            ContentUnavailableView {
                Label("No recordings found", systemImage: "music.note.list")
            } description: {
                Text("Try the track title with the artist name.")
            } actions: {
                if let musicBrainzSearchURL {
                    Link("Search on MusicBrainz", destination: musicBrainzSearchURL)
                }
            }
        case .loaded:
            List(recordings) { recording in
                Button { choose(recording) } label: {
                    recordingRow(recording, showsDisclosure: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Review this MusicBrainz match")
            }
            .listStyle(.plain)
        case .idle:
            ContentUnavailableView(
                "Search MusicBrainz",
                systemImage: "magnifyingglass",
                description: Text("Search by track, artist, or recording ID.")
            )
        }
    }

    private var recordings: [Recording] {
        search.results.compactMap {
            guard case let .recording(recording) = $0,
                  recording.identity.mbid != nil
            else { return nil }
            return recording
        }
    }

    private func recordingRow(_ recording: Recording, showsDisclosure: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(recording.title)
                    .font(.headline)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                let context = [nonempty(recording.artistName), nonempty(recording.releaseTitle)]
                    .compactMap { $0 }
                    .joined(separator: " · ")
                if !context.isEmpty {
                    Text(context)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                }
                if let mbid = recording.identity.mbid {
                    Text(mbid.uuidString.lowercased())
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if showsDisclosure {
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func review(_ recording: Recording) -> some View {
        let selectedMBID = recording.identity.mbid
        ScrollViewReader { proxy in
            List {
                Section("Submitted listen") {
                    detailRow("Track", value: listen.inspection?.submittedTrack ?? listen.recording.title)
                    detailRow("Artist", value: listen.inspection?.submittedArtist ?? listen.recording.artistName)
                    if let release = listen.inspection?.submittedRelease ?? listen.recording.releaseTitle {
                        detailRow("Release", value: release)
                    }
                }

                Section("MusicBrainz recording") {
                    detailRow("Track", value: recording.title)
                    detailRow("Artist", value: recording.artistName)
                    if let release = nonempty(recording.releaseTitle) {
                        detailRow("Release", value: release)
                    }
                    if let selectedMBID {
                        Link(destination: musicBrainzRecordingURL(selectedMBID)) {
                            detailRow(
                                "Recording MBID",
                                value: selectedMBID.uuidString.lowercased(),
                                showsDisclosure: true,
                                usesFullWidth: true
                            )
                        }
                    }
                }

                Section("Before you save") {
                    Label(
                        "This match also applies to your listens with the same ListenBrainz recording ID.",
                        systemImage: "link"
                    )
                    Label(
                        "Listening statistics may update after the next full rebuild.",
                        systemImage: "clock"
                    )
                    if let currentMBID = mapping.currentMBID,
                       currentMBID != selectedMBID {
                        Label("This will replace the current match for this recording ID.", systemImage: "arrow.triangle.2.circlepath")
                    }
                }

                statusSection

                if selectedMBID == mapping.currentMBID {
                    Section {
                        Label("This is already the current match. Nothing will be sent.", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    .id("manual-mapping-action")
                } else if mapping.savedMBID == nil {
                    Section {
                        mappingAction(for: recording)
                    }
                    .listRowBackground(Color.clear)
                    .id("manual-mapping-action")
                }
            }
            .task {
                #if DEBUG
                guard ProcessInfo.processInfo.arguments.contains("-brainz-manual-mapping-bottom-demo") else { return }
                try? await Task.sleep(for: .milliseconds(250))
                proxy.scrollTo("manual-mapping-action", anchor: .bottom)
                #endif
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch mapping.state {
        case .idle:
            EmptyView()
        case .saving:
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Saving match…")
                }
            }
        case let .saved(mbid):
            Section {
                Label("Match saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Refresh History to load the updated metadata. Listening statistics can take longer.")
                    .foregroundStyle(.secondary)
                Text(mbid.uuidString.lowercased())
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        case let .failed(message):
            Section {
                Label {
                    Text(message)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.red)
            }
        case .outcomeUnknown:
            Section {
                Label {
                    Text("Brainz couldn’t confirm whether the match was saved. Refresh History before sending it again.")
                } icon: {
                    Image(systemName: "questionmark.circle.fill")
                }
                .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func mappingAction(for recording: Recording) -> some View {
        switch mapping.state {
        case .outcomeUnknown:
            Button("Send another match…") { sendAgainConfirmation = true }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
        case .failed:
            Button("Try saving again") { save(recording) }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        default:
            Button("Save match") { save(recording) }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(mapping.isSaving || recording.identity.mbid == nil)
        }
    }

    @ViewBuilder
    private func detailRow(
        _ title: LocalizedStringResource,
        value: String,
        showsDisclosure: Bool = false,
        usesFullWidth: Bool = false
    ) -> some View {
        if dynamicTypeSize.isAccessibilitySize || usesFullWidth {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                detailValue(
                    value,
                    showsDisclosure: showsDisclosure,
                    usesIdentifierStyle: usesFullWidth
                )
            }
        } else {
            LabeledContent {
                detailValue(value, showsDisclosure: showsDisclosure)
                    .multilineTextAlignment(.trailing)
            } label: {
                Text(title)
            }
        }
    }

    private func detailValue(
        _ value: String,
        showsDisclosure: Bool,
        usesIdentifierStyle: Bool = false
    ) -> some View {
        HStack(spacing: 5) {
            Text(value)
                .font(usesIdentifierStyle ? .caption.monospaced() : .body)
                .textSelection(.enabled)
            if showsDisclosure {
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
            }
        }
    }

    private func choose(_ recording: Recording) {
        mapping.resetForNewSelection()
        selected = recording
    }

    private func save(_ recording: Recording, sendAgainAfterUnknown: Bool = false) {
        guard let mbid = recording.identity.mbid else { return }
        Task {
            await mapping.save(mbid: mbid, sendAgainAfterUnknown: sendAgainAfterUnknown)
            if mapping.savedMBID == mbid {
                onSaved(mbid)
            }
        }
    }

    private var musicBrainzSearchURL: URL? {
        let query = search.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        var components = URLComponents(string: "https://musicbrainz.org/search")
        components?.queryItems = [
            .init(name: "query", value: query),
            .init(name: "type", value: "recording"),
            .init(name: "method", value: "indexed"),
        ]
        return components?.url
    }

    private func musicBrainzRecordingURL(_ mbid: UUID) -> URL {
        URL(string: "https://musicbrainz.org/recording/\(mbid.uuidString.lowercased())")!
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

#if DEBUG
struct ManualMappingVisualQAScreen: View {
    @State private var presented = true

    var body: some View {
        Color.clear
            .sheet(isPresented: $presented) {
                ManualMappingSheet(
                    listen: ManualMappingVisualFixtures.listen,
                    account: Account(username: "visual-mapping", token: "visual-token"),
                    searchProvider: ManualMappingVisualFixtures.search,
                    mappingProvider: ManualMappingVisualFixtures.mapping,
                    automaticallySelectFirstResult: ProcessInfo.processInfo.arguments.contains(
                        "-brainz-manual-mapping-review-demo"
                    )
                )
            }
    }
}

@MainActor
private enum ManualMappingVisualFixtures {
    static let listen = ListenInspectionVisualQAScreen.fixtureListen(unmapped: true)
    static let search = ManualMappingVisualSearchProvider()
    static let mapping = ManualMappingVisualProvider()
}

private struct ManualMappingVisualSearchProvider: SearchProviding {
    func search(query: String, scope: SearchScope) async throws -> [SearchResult] {
        [
            .recording(Recording(
                identity: .init(
                    mbid: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
                    msid: nil
                ),
                title: "Visual match with a deliberately long title for wrapping",
                artistName: "Visual artist",
                artistMBIDs: [],
                releaseTitle: "Visual release",
                releaseMBID: nil,
                releaseGroupMBID: nil,
                artworkReleaseMBID: nil,
                durationMilliseconds: nil,
                source: nil
            )),
            .recording(Recording(
                identity: .init(
                    mbid: UUID(uuidString: "66666666-7777-8888-9999-aaaaaaaaaaaa")!,
                    msid: nil
                ),
                title: "Alternate recording",
                artistName: "Visual artist feat. Another Artist",
                artistMBIDs: [],
                releaseTitle: "A different visual release",
                releaseMBID: nil,
                releaseGroupMBID: nil,
                artworkReleaseMBID: nil,
                durationMilliseconds: nil,
                source: nil
            )),
        ]
    }
}

private struct ManualMappingVisualProvider: ManualMappingProviding {
    func submit(msid: UUID, mbid: UUID) async throws {}
}
#endif
