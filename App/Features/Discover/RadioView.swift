import ListenBrainzKit
import SwiftUI

struct RadioView: View {
    let account: Account
    @Bindable var listeningModel: ListeningModel
    @State private var model: RadioModel
    @State private var playlistSaveModel: RadioPlaylistSaveModel
    @State private var source: RadioPromptSource = .listening
    @State private var mode: LBRadioMode = .easy
    @State private var artistInput = ""
    @State private var tagInput = ""
    @State private var advancedInput = ""
    @State private var generationTask: Task<Void, Never>?
    @State private var showsSaveConfirmation = false
    @State private var savedPlaylist: SearchPlaylist?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        account: Account,
        listeningModel: ListeningModel,
        provider: (any RadioProviding)? = nil,
        playlistSaveProvider: (any RadioPlaylistSaveProviding)? = nil,
        ownedPlaylistsProvider: (any ProfilePlaylistsProviding)? = nil,
        playlistSaveJournal: RadioPlaylistSaveJournal = .shared
    ) {
        self.account = account
        _listeningModel = Bindable(wrappedValue: listeningModel)
        _model = State(
            initialValue: RadioModel(
                provider: provider ?? ListenBrainzRadioProvider(token: account.token)
            ))
        _playlistSaveModel = State(
            initialValue: RadioPlaylistSaveModel(
                account: account,
                provider: playlistSaveProvider,
                profileProvider: ownedPlaylistsProvider,
                journal: playlistSaveJournal
            ))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    hero
                    if account.isAuthenticated {
                        recipeBuilder
                        if let errorMessage = model.errorMessage {
                            failureBanner(errorMessage)
                        }
                        if model.isGenerating, model.mix == nil {
                            generatingState
                        }
                        if let mix = model.mix {
                            mixSection(mix)
                                .id("radio-mix")
                        } else if !model.isGenerating {
                            beforeGeneration
                        }
                    } else {
                        authenticationRequired
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 48)
            }
            .onChange(of: model.mix?.generatedAt) { _, generatedAt in
                #if DEBUG
                    if generatedAt != nil,
                        ProcessInfo.processInfo.arguments.contains("-brainz-radio-results-demo")
                    {
                        withAnimation(.snappy) { proxy.scrollTo("radio-mix", anchor: .top) }
                    }
                    if generatedAt != nil,
                        ProcessInfo.processInfo.arguments.contains("-brainz-radio-save-card-demo")
                    {
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(250))
                            withAnimation(.snappy) { proxy.scrollTo("radio-save", anchor: .center) }
                        }
                    }
                    if generatedAt != nil,
                        ProcessInfo.processInfo.arguments.contains("-brainz-radio-save-confirmation-demo")
                    {
                        showsSaveConfirmation = true
                    }
                #endif
            }
        }
        .navigationTitle("LB Radio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { shareToolbar }
        .mediaDestinations(model: listeningModel)
        .navigationDestination(item: $savedPlaylist) { playlist in
            PlaylistDetailView(playlist: playlist, viewer: account)
        }
        .confirmationDialog(
            "Save privately?",
            isPresented: $showsSaveConfirmation,
            titleVisibility: .visible,
            presenting: model.mix
        ) { mix in
            Button("Save playlist") {
                Task { await playlistSaveModel.save(mix) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { mix in
            Text(saveConfirmationMessage(for: mix))
        }
        .alert(
            item: Binding(
                get: { playlistSaveModel.notice },
                set: { if $0 == nil { playlistSaveModel.dismissNotice() } }
            )
        ) { notice in
            playlistSaveAlert(notice)
        }
        .task {
            #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-brainz-radio-demo"),
                    model.mix == nil,
                    let options = resolvedOptions
                {
                    await model.generate(options: options)
                }
            #endif
        }
        .onDisappear {
            generationTask?.cancel()
            model.cancel()
        }
    }

    private var hero: some View {
        HStack(spacing: 18) {
            heroCopy
            Spacer(minLength: 0)
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 72, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }
        }
        .padding(22)
        .background(AppTheme.artworkGradient(seed: "listenbrainz-radio"))
        .clipShape(.rect(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var heroCopy: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                Label("LB Radio", systemImage: "dot.radiowaves.left.and.right")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("Choose a source, then tap Generate. Nothing starts on its own.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.82))
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("LISTENBRAINZ RADIO", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.85))
                Text("Build a mix from your musical world")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Choose a source and how far ListenBrainz should wander. Nothing is generated until you ask.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var recipeBuilder: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Start with")
                    .font(.title3.bold())
                Text(
                    dynamicTypeSize.isAccessibilitySize
                        ? "One source makes one LB Radio recipe."
                        : "Each source becomes one server-side LB Radio recipe."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: sourceColumns, spacing: 10) {
                ForEach(RadioPromptSource.allCases) { item in
                    RadioSourceCard(source: item, isSelected: source == item) {
                        withAnimation(.snappy(duration: 0.22)) { source = item }
                    }
                }
            }

            sourceInput

            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Listening distance")
                        .font(.headline)
                    Spacer()
                    Text(mode.shortExplanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                modePicker
                Text(mode.longExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let prompt = resolvedPrompt {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recipe")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(prompt)
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 12, style: .continuous))
            } else if source.requiresInput {
                Text(inputGuidance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(action: generate) {
                HStack(spacing: 9) {
                    if model.isGenerating {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(
                        model.isGenerating
                            ? "Generating mix…"
                            : model.mix == nil ? "Generate mix" : "Generate a new mix"
                    )
                    .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(AppTheme.accent)
            .disabled(resolvedOptions == nil || model.isGenerating)
            .accessibilityHint(
                "Makes one authenticated ListenBrainz Radio request, then one batched metadata request when mapped recordings are present"
            )
        }
        .padding(18)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private var sourceInput: some View {
        switch source {
        case .listening:
            sourceExplanation(
                icon: "chart.bar.fill",
                title: "Your all-time listening",
                text:
                    "Pulls from your ListenBrainz statistics. Familiarity still changes which part of that ranked history is sampled."
            )
        case .recommendations:
            sourceExplanation(
                icon: "sparkles",
                title: "Unheard recommendations",
                text: "Starts with collaborative-filter recommendations that ListenBrainz has not seen you play."
            )
        case .artist:
            TextField("Exact artist name or MusicBrainz ID", text: $artistInput)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(13)
                .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 13, style: .continuous))
                .accessibilityHint("MusicBrainz identifiers are the most precise artist seeds")
        case .tag:
            TextField("Tag or mood, for example dream pop", text: $tagInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(13)
                .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 13, style: .continuous))
        case .advanced:
            TextField(
                "For example: artist:(Björk):2 tag:(art pop):1::or",
                text: $advancedInput,
                axis: .vertical
            )
            .lineLimit(3...6)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.body.monospaced())
            .padding(13)
            .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 13, style: .continuous))
            Link(
                "Open the LB Radio prompt reference",
                destination: URL(string: "https://troi.readthedocs.io/en/latest/lb_radio.html")!
            )
            .font(.caption)
        }
    }

    private func sourceExplanation(icon: String, title: LocalizedStringResource, text: LocalizedStringResource) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func mixSection(_ mix: RadioMix) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    mixArtwork(mix, side: 142)
                    mixMetadata(mix)
                }
                VStack(alignment: .leading, spacing: 15) {
                    mixArtwork(mix, side: dynamicTypeSize.isAccessibilitySize ? 210 : 220)
                    mixMetadata(mix)
                }
            }

            if !mix.feedback.isEmpty {
                feedbackCard(mix.feedback)
            }
            savePlaylistSection(mix)
                .id("radio-save")
            if mix.metadataEnrichmentFailed {
                Label(
                    "The mix was generated, but optional artwork and detail enrichment did not finish. The original radio tracks are still shown.",
                    systemImage: "photo.badge.exclamationmark"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.12), in: .rect(cornerRadius: 13, style: .continuous))
            }

            if mix.tracks.isEmpty {
                ContentUnavailableView(
                    "No mix this time",
                    systemImage: "radio",
                    description: Text(
                        "ListenBrainz returned no recordings. Try another source, tag, or listening distance.")
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Up next").font(.title3.bold())
                        Spacer()
                        Text("\(mix.tracks.count.formatted()) tracks")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 6)

                    ForEach(mix.tracks) { track in
                        Group {
                            if track.recording.identity.mbid != nil {
                                NavigationLink(value: track.recording) {
                                    PlaylistTrackRow(track: track)
                                }
                                .buttonStyle(.plain)
                            } else {
                                PlaylistTrackRow(track: track)
                            }
                        }
                        if track.id != mix.tracks.last?.id {
                            Divider().padding(.leading, 84)
                        }
                    }
                }
            }

            Label(
                "LB Radio generates a playlist. Playback will appear only when a connected service can resolve a track legally and reliably.",
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private func mixArtwork(_ mix: RadioMix, side: CGFloat) -> some View {
        PlaylistArtworkMosaic(tracks: mix.tracks, title: mix.title)
            .frame(width: side, height: side)
            .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
    }

    private func mixMetadata(_ mix: RadioMix) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("YOUR GENERATED MIX")
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(AppTheme.accent)
            Text(mix.title)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
            if let annotation = mix.annotation {
                Text(annotation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label(modeLabel(for: mix.options.mode), systemImage: "dial.medium")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Generated \(mix.generatedAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func feedbackCard(_ feedback: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("How ListenBrainz built it", systemImage: "quote.bubble")
                .font(.subheadline.weight(.semibold))
            ForEach(Array(feedback.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(AppTheme.accent)
                        .frame(width: 5, height: 5)
                    Text(item)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.accent.opacity(0.08), in: .rect(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func savePlaylistSection(_ mix: RadioMix) -> some View {
        let included = RadioPlaylistSaveModel.recordingMBIDs(in: mix).count
        let excluded = RadioPlaylistSaveModel.excludedTrackCount(in: mix)
        if playlistSaveModel.requiresReview {
            VStack(alignment: .leading, spacing: 10) {
                Label(
                    playlistSaveModel.requiresStorageRecovery
                        ? "Playlist saving is paused"
                        : "Check Owned Playlists first",
                    systemImage: "exclamationmark.shield.fill"
                )
                .font(.headline)
                .foregroundStyle(.orange)
                Text(
                    playlistSaveModel.requiresStorageRecovery
                        ? "Brainz can’t verify its duplicate-prevention record. Load your newest Owned Playlists before resetting it."
                        : "A previous save may have reached ListenBrainz without a response. Load your newest Owned Playlists before trying again."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await playlistSaveModel.reviewOwnedPlaylists() }
                } label: {
                    Label(
                        playlistSaveModel.isReviewing ? "Loading newest playlists…" : "Load newest playlists",
                        systemImage: "list.bullet.rectangle"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(playlistSaveModel.isReviewing)
                if playlistSaveModel.canResetAfterReview {
                    reviewedPlaylistList
                    Button("The previous mix isn’t listed — allow one new save") {
                        playlistSaveModel.resetAfterReview()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.12), in: .rect(cornerRadius: 14, style: .continuous))
        } else if included > 0 {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Keep this mix", systemImage: "plus.rectangle.on.folder")
                        .font(.headline)
                    Spacer()
                    Text("Private")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(saveSummary(included: included, excluded: excluded))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    showsSaveConfirmation = true
                } label: {
                    Label(
                        playlistSaveModel.isSaving ? "Saving playlist…" : "Save as playlist",
                        systemImage: "plus"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(playlistSaveModel.isSaving)
                .accessibilityHint("Creates one private ListenBrainz playlist")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.accent.opacity(0.08), in: .rect(cornerRadius: 14, style: .continuous))
        } else {
            Label(
                "This mix has no canonical recording IDs, so it can’t be saved as a ListenBrainz playlist.",
                systemImage: "music.note.slash"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 14, style: .continuous))
        }
    }

    @ViewBuilder
    private var reviewedPlaylistList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Newest Owned Playlists")
                .font(.subheadline.weight(.semibold))
            if playlistSaveModel.reviewedPlaylists.isEmpty {
                Text("ListenBrainz returned no owned playlists.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(playlistSaveModel.reviewedPlaylists) { playlist in
                    if playlist.playlistMBID != nil {
                        NavigationLink {
                            PlaylistDetailView(playlist: playlist, viewer: account)
                        } label: {
                            reviewedPlaylistRow(playlist)
                        }
                        .buttonStyle(.plain)
                    } else {
                        reviewedPlaylistRow(playlist)
                    }
                }
            }
            Text(
                "These \(playlistSaveModel.reviewedPlaylists.count.formatted()) playlists are newest first. Open a likely match to inspect it, and reset only if the previous mix is not here."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private func reviewedPlaylistRow(_ playlist: SearchPlaylist) -> some View {
        HStack(spacing: 10) {
            Image(systemName: playlist.isPublic ? "globe" : "lock.fill")
                .foregroundStyle(AppTheme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if let createdAt = playlist.createdAt {
                    Text("Created \(createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if playlist.playlistMBID != nil {
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: .rect(cornerRadius: 12, style: .continuous))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private func saveSummary(included: Int, excluded: Int) -> String {
        if excluded == 0 {
            return included == 1
                ? String(localized: "Saves 1 track in this order.")
                : String(localized: "Saves \(included.formatted()) tracks in this order.")
        }
        switch (included == 1, excluded == 1) {
        case (true, true):
            return String(localized: "Saves 1 track in this order. 1 unmapped track is left out.")
        case (true, false):
            return String(localized: "Saves 1 track in this order. \(excluded.formatted()) unmapped tracks are left out.")
        case (false, true):
            return String(localized: "Saves \(included.formatted()) tracks in this order. 1 unmapped track is left out.")
        case (false, false):
            return String(localized: "Saves \(included.formatted()) tracks in this order. \(excluded.formatted()) unmapped tracks are left out.")
        }
    }

    private func saveConfirmationMessage(for mix: RadioMix) -> String {
        let included = RadioPlaylistSaveModel.recordingMBIDs(in: mix).count
        let excluded = RadioPlaylistSaveModel.excludedTrackCount(in: mix)
        var lines = [
            String(localized: "“\(mix.title)”"),
            included == 1
                ? String(localized: "1 track included in order.")
                : String(localized: "\(included.formatted()) tracks included in order."),
        ]
        if excluded > 0 {
            lines.append(
                excluded == 1
                    ? String(localized: "1 unmapped track left out.")
                    : String(localized: "\(excluded.formatted()) unmapped tracks left out.")
            )
        }
        lines.append(String(localized: "One request to ListenBrainz."))
        return lines.joined(separator: "\n")
    }

    private func playlistSaveAlert(_ notice: RadioPlaylistSaveNotice) -> Alert {
        switch notice {
        case .saved(let playlist):
            Alert(
                title: Text("Playlist saved"),
                message: Text("Your private playlist is ready."),
                primaryButton: .default(Text("Open playlist")) { savedPlaylist = playlist },
                secondaryButton: .cancel(Text("Done")) { playlistSaveModel.dismissNotice() }
            )
        case .failed(let message):
            Alert(
                title: Text("Playlist not saved"),
                message: Text(message),
                dismissButton: .default(Text("Done")) { playlistSaveModel.dismissNotice() }
            )
        case .needsReview(let message):
            Alert(
                title: Text("Check Owned Playlists"),
                message: Text(message),
                dismissButton: .default(Text("Done")) { playlistSaveModel.dismissNotice() }
            )
        case .reviewed:
            Alert(
                title: Text("Owned Playlists checked"),
                message: Text("Review the newest playlists below. Reset only if the previous mix is not there."),
                dismissButton: .default(Text("Done")) { playlistSaveModel.dismissNotice() }
            )
        }
    }

    private var beforeGeneration: some View {
        Label(
            "A generation is explicit and may take a moment. Changing the controls does not make a network request.",
            systemImage: "hand.tap"
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 18, style: .continuous))
    }

    private var generatingState: some View {
        VStack(spacing: 13) {
            ProgressView()
            Text("ListenBrainz is arranging your mix…")
                .font(.subheadline.weight(.semibold))
            Text("Generation runs on ListenBrainz and is paced with every other app request.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 190)
        .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var authenticationRequired: some View {
        ContentUnavailableView {
            Label("Sign in to tune LB Radio", systemImage: "lock.fill")
        } description: {
            Text(
                "ListenBrainz protects this expensive generator with an account token. Connect one from Profile, then come back to build a mix."
            )
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private func failureBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Mix not updated").font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Dismiss") { model.clearError() }
                .font(.caption.weight(.semibold))
        }
        .padding(15)
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 16, style: .continuous))
    }

    @ToolbarContentBuilder
    private var shareToolbar: some ToolbarContent {
        if let mix = model.mix, let url = mix.options.listenBrainzURL {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Link(destination: url) {
                        Label("Open on ListenBrainz", systemImage: "safari")
                    }
                    ShareLink(
                        item: url,
                        subject: Text(mix.title),
                        message: Text("Try this ListenBrainz Radio recipe: \(mix.options.prompt)")
                    ) {
                        Label("Share recipe link", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Radio mix options")
            }
        }
    }

    private var sourceColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible(), spacing: 10)]
            : [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    }

    @ViewBuilder
    private var modePicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Picker("Listening distance", selection: $mode) {
                ForEach(LBRadioMode.allCases, id: \.self) { item in
                    Text("\(item.displayTitle) · \(item.shortExplanation)").tag(item)
                }
            }
            .pickerStyle(.menu)
        } else {
            Picker("Listening distance", selection: $mode) {
                ForEach(LBRadioMode.allCases, id: \.self) { item in
                    Text(item.displayTitle).tag(item)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var selectedInput: String {
        switch source {
        case .artist: artistInput
        case .tag: tagInput
        case .advanced: advancedInput
        case .listening, .recommendations: ""
        }
    }

    private var resolvedPrompt: String? {
        source.prompt(username: account.username, input: selectedInput)
    }

    private var resolvedOptions: RadioGenerationOptions? {
        resolvedPrompt.flatMap { RadioGenerationOptions(prompt: $0, mode: mode) }
    }

    private var inputGuidance: String {
        switch source {
        case .artist:
            String(localized: "Use an exact MusicBrainz artist name or MBID. Parentheses belong in Advanced.")
        case .tag:
            String(localized: "Enter at least two characters. Use Advanced for combined tags or options.")
        case .advanced:
            String(localized: "Enter a Troi prompt of at least four characters.")
        case .listening, .recommendations:
            ""
        }
    }

    private func generate() {
        guard let options = resolvedOptions else { return }
        generationTask?.cancel()
        generationTask = Task { await model.generate(options: options) }
    }

    private func modeLabel(for mode: LBRadioMode) -> String {
        String(localized: "\(mode.displayTitle) distance")
    }
}

private struct RadioSourceCard: View {
    let source: RadioPromptSource
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: source.icon)
                    .font(.headline)
                    .foregroundStyle(isSelected ? .white : AppTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(
                        isSelected ? AnyShapeStyle(AppTheme.accent) : AnyShapeStyle(AppTheme.accent.opacity(0.1)),
                        in: Circle()
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(source.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(
                isSelected ? AppTheme.accent.opacity(0.1) : Color.secondary.opacity(0.06),
                in: .rect(cornerRadius: 15, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(isSelected ? AppTheme.accent.opacity(0.7) : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension RadioPromptSource {
    fileprivate var title: String {
        switch self {
        case .listening: String(localized: "My listening")
        case .recommendations: String(localized: "New for me")
        case .artist: String(localized: "Artist")
        case .tag: String(localized: "Tag or mood")
        case .advanced: String(localized: "Advanced")
        }
    }

    fileprivate var subtitle: String {
        switch self {
        case .listening: String(localized: "All-time stats")
        case .recommendations: String(localized: "Unheard picks")
        case .artist: String(localized: "Name or MBID")
        case .tag: String(localized: "One native seed")
        case .advanced: String(localized: "Full Troi recipe")
        }
    }

    fileprivate var icon: String {
        switch self {
        case .listening: "chart.bar.fill"
        case .recommendations: "sparkles"
        case .artist: "music.mic"
        case .tag: "number"
        case .advanced: "slider.horizontal.3"
        }
    }
}

extension LBRadioMode {
    fileprivate var displayTitle: String {
        switch self {
        case .easy: String(localized: "Familiar")
        case .medium: String(localized: "Balanced")
        case .hard: String(localized: "Explore")
        }
    }

    fileprivate var shortExplanation: String {
        switch self {
        case .easy: String(localized: "Easy")
        case .medium: String(localized: "Medium")
        case .hard: String(localized: "Hard")
        }
    }

    fileprivate var longExplanation: String {
        switch self {
        case .easy:
            String(localized: "Leans toward the most relevant and recognizable recordings.")
        case .medium:
            String(localized: "Moves into the middle of ListenBrainz's ranked source lists.")
        case .hard:
            String(localized: "Searches deeper in the tail for a more adventurous mix.")
        }
    }
}
