import SwiftUI

struct ListenInspectionSheet: View {
    let listen: Listen
    let account: Account?
    private let startsAtMapping: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isMappingPresented = false
    @State private var mappingStatus: ManualMappingStatusModel
    @State private var mappingStatusCheckRequestID: UUID?

    private var details: ListenInspection? { listen.inspection }

    init(
        listen: Listen,
        account: Account? = nil,
        startsAtMapping: Bool = false,
        mappingStatusProvider: (any ManualMappingStatusProviding)? = nil
    ) {
        self.listen = listen
        self.account = account
        self.startsAtMapping = startsAtMapping
        _mappingStatus = State(initialValue: ManualMappingStatusModel(
            account: account,
            listen: listen,
            provider: mappingStatusProvider
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    listenSection
                    if let details {
                        submittedMetadataSection(details)
                        submittedIdentifiersSection(details)
                        mappingSection(details).id("listen-mapping")
                        sourceSection(details)
                    } else {
                        ContentUnavailableView(
                            "Details unavailable",
                            systemImage: "text.magnifyingglass",
                            description: Text("This cached listen does not include submitted metadata."))
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle("Listen details")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .task {
                    #if DEBUG
                    guard startsAtMapping else { return }
                    let showsSavedMatch = ProcessInfo.processInfo.arguments.contains(
                        "-brainz-inspect-listen-saved-match-demo"
                    )
                    try? await Task.sleep(for: showsSavedMatch ? .milliseconds(600) : .milliseconds(150))
                    proxy.scrollTo(showsSavedMatch ? "saved-mapping-status" : "listen-mapping", anchor: .top)
                    #endif
                }
            }
        }
        .presentationDetents(
            startsAtMapping || dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large]
        )
        .task(id: mappingStatusCheckRequestID) {
            guard mappingStatusCheckRequestID != nil else { return }
            await mappingStatus.check()
        }
        #if DEBUG
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-brainz-inspect-listen-saved-match-demo") else {
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            mappingStatusCheckRequestID = UUID()
        }
        #endif
        .sheet(isPresented: $isMappingPresented) {
            if let account {
                ManualMappingSheet(listen: listen, account: account) { mbid in
                    mappingStatusCheckRequestID = nil
                    mappingStatus.confirmSaved(mbid: mbid)
                }
                .presentationDetents([.large])
            }
        }
    }

    private var listenSection: some View {
        Section("Listen") {
            valueRow("Listened", value: listen.listenedAt.formatted(date: .abbreviated, time: .shortened))
            if let insertedAt = listen.insertedAt {
                valueRow("Added to ListenBrainz", value: insertedAt.formatted(date: .abbreviated, time: .shortened))
            }
            if listen.isPlayingNow {
                Label("Playing now", systemImage: "waveform")
                    .foregroundStyle(.tint)
            }
        }
    }

    @ViewBuilder
    private func submittedMetadataSection(_ details: ListenInspection) -> some View {
        Section("Submitted metadata") {
            valueRow("Track", value: details.submittedTrack)
            valueRow("Artist", value: details.submittedArtist)
            if let release = details.submittedRelease { valueRow("Release", value: release) }
            if let trackNumber = details.trackNumber { valueRow("Track number", value: String(trackNumber)) }
            if let duration = details.durationMilliseconds { valueRow("Duration", value: formattedDuration(duration)) }
            if let isrc = details.isrc { identifierRow("ISRC", value: isrc) }
            if let spotifyID = details.spotifyID { identifierRow("Spotify ID", value: spotifyID) }
            if !details.tags.isEmpty { valueRow("Tags", value: details.tags.joined(separator: ", ")) }
        }
    }

    @ViewBuilder
    private func submittedIdentifiersSection(_ details: ListenInspection) -> some View {
        let hasIdentifiers = details.recordingMSID != nil
            || details.submittedRecordingMSID != nil
            || details.submittedRecordingMBID != nil
            || details.submittedReleaseMBID != nil
            || details.submittedReleaseGroupMBID != nil
            || details.submittedTrackMBID != nil
            || !details.submittedArtistMBIDs.isEmpty
            || !details.submittedWorkMBIDs.isEmpty

        if hasIdentifiers {
            Section("Submitted identifiers") {
                if let msid = details.recordingMSID {
                    identifierRow("ListenBrainz recording MSID", value: msid.uuidString)
                }
                if let submittedMSID = details.submittedRecordingMSID {
                    identifierRow("Submitted recording MSID", value: submittedMSID.uuidString)
                }
                musicBrainzIdentifier("Recording MBID", id: details.submittedRecordingMBID, path: "recording")
                musicBrainzIdentifier("Release MBID", id: details.submittedReleaseMBID, path: "release")
                musicBrainzIdentifier("Release group MBID", id: details.submittedReleaseGroupMBID, path: "release-group")
                musicBrainzIdentifiers("Artist MBID", ids: details.submittedArtistMBIDs, path: "artist")
                musicBrainzIdentifier("Track MBID", id: details.submittedTrackMBID, path: "track")
                musicBrainzIdentifiers("Work MBID", ids: details.submittedWorkMBIDs, path: "work")
            }
        }
    }

    @ViewBuilder
    private func mappingSection(_ details: ListenInspection) -> some View {
        Section("MusicBrainz mapping") {
            Label(details.mappingStatus.title, systemImage: mappingSymbol(details.mappingStatus))
                .foregroundStyle(details.mappingStatus == .noMusicBrainzMatch ? Color.secondary : Color.accentColor)
            if let name = details.resolvedRecordingName { valueRow("Matched recording", value: name) }
            musicBrainzIdentifier("Recording MBID", id: details.resolvedRecordingMBID, path: "recording")
            musicBrainzIdentifier("Release MBID", id: details.resolvedReleaseMBID, path: "release")
            musicBrainzIdentifier("Release group MBID", id: details.resolvedReleaseGroupMBID, path: "release-group")
            musicBrainzIdentifiers("Artist MBID", ids: details.resolvedArtistMBIDs, path: "artist")
            savedMappingStatus(details).id("saved-mapping-status")
            if let account {
                let availability = ManualMappingModel.availability(account: account, listen: listen)
                switch availability {
                case let .available(_, currentMBID):
                    Button {
                        isMappingPresented = true
                    } label: {
                        if (savedMappingMBID ?? currentMBID) == nil {
                            Label("Find MusicBrainz match", systemImage: "link.badge.plus")
                        } else {
                            Label("Change MusicBrainz match", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(mappingStatus.isChecking)
                case let .unavailable(reason) where details.submittedRecordingMBID != nil:
                    Label {
                        Text(reason)
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                case .unavailable:
                    EmptyView()
                }
            }
        }
    }

    private var savedMappingMBID: UUID? {
        guard case let .found(mbid) = mappingStatus.state else { return nil }
        return mbid
    }

    @ViewBuilder
    private func savedMappingStatus(_ details: ListenInspection) -> some View {
        switch mappingStatus.state {
        case .idle where mappingStatus.isEligible:
            Button {
                mappingStatusCheckRequestID = UUID()
            } label: {
                Label("Check saved match", systemImage: "magnifyingglass")
            }
        case .checking:
            HStack(spacing: 10) {
                ProgressView()
                Text("Checking saved match…")
            }
            .foregroundStyle(.secondary)
        case let .found(mbid):
            Label("Saved MusicBrainz match", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            musicBrainzIdentifier("Saved recording MBID", id: mbid, path: "recording")
            if ManualMappingStatusModel.shouldSuggestHistoryRefresh(
                details: details,
                savedMBID: mbid
            ) {
                Text("Refresh History to load this match into the listen metadata.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .notFound:
            Label("No saved MusicBrainz match", systemImage: "link.badge.plus")
                .foregroundStyle(.secondary)
            Text("ListenBrainz has no saved match for this recording ID.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case let .failed(message):
            Label {
                Text(message)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .font(.footnote)
            .foregroundStyle(.red)
            Button("Try Again") {
                mappingStatusCheckRequestID = UUID()
            }
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private func sourceSection(_ details: ListenInspection) -> some View {
        let client = versioned(details.submissionClient, version: details.submissionClientVersion)
        let player = versioned(details.mediaPlayer, version: details.mediaPlayerVersion)
        let service = details.musicServiceName ?? details.musicService
        if client != nil || player != nil || service != nil || details.originURL != nil || !listen.recording.externalMediaLinks.isEmpty {
            Section("Source") {
                if let client { valueRow("Submission client", value: client) }
                if let player { valueRow("Media player", value: player) }
                if let service { valueRow("Music service", value: service) }
                if let originURL = details.originURL { identifierRow("Origin URL", value: originURL) }
                ExternalMediaDestinationActions.linkItems(listen.recording.externalMediaLinks)
            }
        }
    }

    @ViewBuilder
    private func musicBrainzIdentifier(_ title: LocalizedStringResource, id: UUID?, path: String) -> some View {
        if let id, let url = musicBrainzURL(path: path, id: id) {
            Link(destination: url) {
                identifierRow(title, value: id.uuidString, showsDisclosure: true)
            }
        }
    }

    @ViewBuilder
    private func musicBrainzIdentifiers(_ title: LocalizedStringResource, ids: [UUID], path: String) -> some View {
        ForEach(ids, id: \.self) { id in
            musicBrainzIdentifier(title, id: id, path: path)
        }
    }

    @ViewBuilder
    private func valueRow(_ title: LocalizedStringResource, value: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                rowTitle(title)
                Text(value).textSelection(.enabled)
            }
        } else {
            LabeledContent {
                Text(value)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            } label: {
                Text(title)
            }
        }
    }

    @ViewBuilder
    private func identifierRow(_ title: LocalizedStringResource, value: String, showsDisclosure: Bool = false) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                rowTitle(title)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    identifierText(value)
                    if showsDisclosure { Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)) }
                }
            }
        } else {
            LabeledContent {
                HStack(spacing: 5) {
                    identifierText(value)
                    if showsDisclosure { Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)) }
                }
            } label: {
                Text(title)
            }
        }
    }

    private func rowTitle(_ title: LocalizedStringResource) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func identifierText(_ value: String) -> some View {
        Text(value)
            .font(.caption.monospaced())
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .textSelection(.enabled)
    }

    private func mappingSymbol(_ status: ListenInspection.MappingStatus) -> String {
        switch status {
        case .matchedByListenBrainz: "checkmark.seal"
        case .musicBrainzIDsSubmitted: "checkmark.circle"
        case .noMusicBrainzMatch: "questionmark.circle"
        }
    }

    private func versioned(_ name: String?, version: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        guard let version, !version.isEmpty else { return name }
        return "\(name) \(version)"
    }

    private func musicBrainzURL(path: String, id: UUID) -> URL? {
        URL(string: "https://musicbrainz.org/\(path)/\(id.uuidString.lowercased())")
    }

    private func formattedDuration(_ milliseconds: Int) -> String {
        let totalSeconds = max(milliseconds, 0) / 1_000
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#if DEBUG
struct ListenInspectionVisualQAScreen: View {
    let listen: Listen
    @State private var isPresentingDetails = true

    var body: some View {
        let arguments = ProcessInfo.processInfo.arguments
        NavigationStack {
            List {
                Section("Today") {
                    ListenRow(listen: listen)
                }
            }
            .navigationTitle("History")
        }
        .sheet(isPresented: $isPresentingDetails) {
            ListenInspectionSheet(
                listen: listen,
                account: Account(username: "visual-listener", token: "visual-token"),
                startsAtMapping: arguments.contains("-brainz-inspect-listen-scroll")
                    || arguments.contains("-brainz-inspect-listen-saved-match-demo"),
                mappingStatusProvider: ListenInspectionVisualMappingStatusProvider()
            )
        }
    }

    static func fixtureListen(unmapped: Bool = false) -> Listen {
        let recording = Recording(
            identity: .init(mbid: nil, msid: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")),
            title: "Visual track", artistName: "Visual artist", artistMBIDs: [], releaseTitle: "Visual release",
            releaseMBID: nil, releaseGroupMBID: nil, artworkReleaseMBID: nil, durationMilliseconds: nil, source: nil
        )
        if !unmapped { return Listen(recording: recording, listenedAt: .now, insertedAt: nil, isPlayingNow: false) }
        let inspection = ListenInspection(
            submittedArtist: "Visual artist", submittedTrack: "Visual track", submittedRelease: "Visual release",
            recordingMSID: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"), submittedRecordingMSID: nil,
            submittedArtistMBIDs: [], submittedRecordingMBID: nil, submittedReleaseMBID: nil, submittedReleaseGroupMBID: nil,
            submittedTrackMBID: nil, submittedWorkMBIDs: [], resolvedArtistMBIDs: [], resolvedRecordingMBID: nil,
            resolvedReleaseMBID: nil, resolvedReleaseGroupMBID: nil, resolvedRecordingName: nil, trackNumber: nil,
            isrc: nil, spotifyID: nil, tags: [], mediaPlayer: nil, mediaPlayerVersion: nil, submissionClient: nil,
            submissionClientVersion: nil, musicService: nil, musicServiceName: nil, originURL: nil, durationMilliseconds: nil
        )
        return Listen(recording: recording, listenedAt: .now, insertedAt: nil, isPlayingNow: false, inspection: inspection)
    }
}

private struct ListenInspectionVisualMappingStatusProvider: ManualMappingStatusProviding {
    func savedMapping(msid: UUID) async throws -> ManualMappingIdentity? {
        ManualMappingIdentity(
            msid: msid,
            mbid: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        )
    }
}
#endif
