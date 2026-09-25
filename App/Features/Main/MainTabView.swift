import SwiftUI

struct MainTabView: View {
    private enum Destination: String, Hashable {
        case home
        case history
        case discover
        case taste
        case profile
    }

    let account: Account
    @Bindable var session: SessionModel
    @State private var model: ListeningModel
    @State private var pins: PinsModel
    @State private var presentedListen: Listen?
    @AppStorage("main.selectedTab") private var selectedTab: Destination = .home

    init(account: Account, session: SessionModel) {
        self.account = account
        _session = Bindable(wrappedValue: session)
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-brainz-home-pin-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-home-pin-empty-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-home-pin-failure-demo")
            {
                let visualAccount = Account(username: "visual-home", token: "")
                _model = State(
                    initialValue: ListeningModel(
                        account: visualAccount,
                        provider: VisualQAHomePinListeningProvider()
                    ))
                _pins = State(
                    initialValue: PinsModel(
                        account: visualAccount,
                        provider: VisualQAHomePinProvider(
                            result: ProcessInfo.processInfo.arguments.contains("-brainz-home-pin-empty-demo")
                                ? .empty
                                : ProcessInfo.processInfo.arguments.contains("-brainz-home-pin-failure-demo")
                                    ? .failure
                                    : .populated
                        )
                    ))
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-brainz-profile-playlists-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-profile-playlists-collab-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-profile-playlists-visitor-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-playlist-edit-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-playlist-add-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-playlist-copy-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-playlist-delete-confirmation-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-playlist-delete-confirmed-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-playlist-delete-review-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-playlist-remove-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-playlist-remove-review-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-playlist-reorder-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-playlist-reorder-review-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-following-pins-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-following-pins-empty-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-following-pins-failure-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-connected-services-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-connected-services-empty-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-connected-services-failure-demo")
            {
                let visualAccount = Account(username: "visual-listener", token: "visual-token")
                _model = State(
                    initialValue: ListeningModel(
                        account: visualAccount,
                        provider: VisualQATasteProvider()
                    ))
                _pins = State(
                    initialValue: PinsModel(
                        account: visualAccount,
                        provider: VisualQAPinProvider()
                    ))
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-brainz-artist-evolution-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-artist-evolution-all-time-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-genre-activity-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-artist-origins-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-artist-origins-country-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-artist-activity-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-artist-activity-expanded-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-user-defining-artists-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-user-profile-albums-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-user-profile-tracks-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-home-tracks-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-fresh-releases-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-fresh-releases-filters-demo")
            {
                let visualAccount = Account(username: "visual-taste", token: "visual-taste")
                _model = State(
                    initialValue: ListeningModel(
                        account: visualAccount,
                        provider: VisualQATasteProvider()
                    ))
                _pins = State(
                    initialValue: PinsModel(
                        account: visualAccount,
                        provider: VisualQAPinProvider()
                    ))
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-brainz-popularity-detail-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-artist-tracks-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-artist-context-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-artist-context-failure-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-artist-highlights-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-artist-highlights-releases-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-artist-highlights-failure-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-top-listeners-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-top-listeners-expanded-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-critiquebrainz-reviews-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-critiquebrainz-reader-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-critiquebrainz-reviews-unavailable-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-critiquebrainz-reviews-failure-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-similar-artists-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-similar-artists-expanded-demo")
            {
                let visualAccount = Account(username: "visual-popularity", token: "visual-popularity")
                _model = State(
                    initialValue: ListeningModel(
                        account: visualAccount,
                        provider: VisualQAPopularityListeningProvider()
                    ))
                _pins = State(
                    initialValue: PinsModel(
                        account: visualAccount,
                        provider: VisualQAPinProvider()
                    ))
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-brainz-year-in-music-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-year-in-music-tracks-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-year-in-music-identity-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-year-in-music-evolution-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-year-in-music-new-releases-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-year-in-music-playlists-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-year-in-music-playlist-detail-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-year-in-music-visited-demo")
            {
                let visualAccount = Account(username: "visual-taste", token: "visual-taste")
                _model = State(
                    initialValue: ListeningModel(
                        account: visualAccount,
                        provider: VisualQATasteProvider()
                    ))
                _pins = State(
                    initialValue: PinsModel(
                        account: visualAccount,
                        provider: VisualQAPinProvider()
                    ))
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-brainz-radio-demo") {
                let visualAccount = Account(username: "visual-radio", token: "visual-radio")
                _model = State(
                    initialValue: ListeningModel(
                        account: visualAccount,
                        provider: VisualQATasteProvider()
                    ))
                _pins = State(
                    initialValue: PinsModel(
                        account: visualAccount,
                        provider: VisualQAPinProvider()
                    ))
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-brainz-history-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-history-day-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-history-delete-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-history-delete-long-title-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-history-delete-recovery-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-inspect-listen-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-inspect-listen-unmapped-demo")
            {
                let isInspectionDemo = ProcessInfo.processInfo.arguments.contains("-brainz-inspect-listen-demo")
                    || ProcessInfo.processInfo.arguments.contains("-brainz-inspect-listen-unmapped-demo")
                let visualAccount = isInspectionDemo
                    ? Account(username: "visual-inspection", token: "visual-inspection")
                    : Account(username: "visual-history", token: "visual-history")
                _model = State(
                    initialValue: ListeningModel(
                        account: visualAccount,
                        provider: VisualQAHistoryProvider()
                    ))
                _pins = State(
                    initialValue: PinsModel(
                        account: visualAccount,
                        provider: VisualQAPinProvider()
                    ))
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-brainz-taste-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-taste-heatmap-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-taste-release-groups-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-taste-tracks-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-year-in-music-teaser-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-taste-era-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-taste-era-zoom-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-taste-era-card-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-user-explore-demo")
            {
                let visualAccount = Account(username: "visual-taste", token: "visual-taste")
                _model = State(
                    initialValue: ListeningModel(
                        account: visualAccount,
                        provider: VisualQATasteProvider()
                    ))
                _pins = State(
                    initialValue: PinsModel(
                        account: visualAccount,
                        provider: VisualQAPinProvider()
                    ))
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-brainz-external-source-demo") {
                let visualAccount = Account(username: "visual-qa", token: "visual-qa")
                _model = State(
                    initialValue: ListeningModel(
                        account: visualAccount,
                        provider: VisualQAHistoryProvider()
                    ))
                _pins = State(
                    initialValue: PinsModel(
                        account: visualAccount,
                        provider: VisualQAPinProvider()
                    ))
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-brainz-recording-share-demo") {
                let visualAccount = Account(username: "visual-qa", token: "visual-qa")
                _model = State(initialValue: ListeningModel(account: visualAccount))
                _pins = State(
                    initialValue: PinsModel(
                        account: visualAccount,
                        provider: VisualQAPinProvider()
                    ))
                return
            }
        #endif
        _model = State(initialValue: ListeningModel(account: account))
        _pins = State(initialValue: PinsModel(account: account))
    }

    var body: some View {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-brainz-log-listen-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-log-listen-success-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-log-listen-indeterminate-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-log-listen-error-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-log-listen-recovery-demo")
            {
                LogListenVisualQAScreen(mode: .listen)
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-log-listen-playing-now-demo") {
                LogListenVisualQAScreen(mode: .playingNow)
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-inspect-listen-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-inspect-listen-unmapped-demo")
            {
                ListenInspectionVisualQAScreen(listen: VisualQAHistoryProvider.inspectionPreview())
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-manual-mapping-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-manual-mapping-review-demo")
            {
                ManualMappingVisualQAScreen()
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-generic-art-demo") {
                GenericArtVisualQAScreen(fixture: .populated)
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-generic-art-unavailable-demo") {
                GenericArtVisualQAScreen(fixture: .unavailable)
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-generic-art-failure-demo") {
                GenericArtVisualQAScreen(fixture: .failure)
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-playlist-copy-demo") {
                PlaylistCopyVisualQAScreen()
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-playlist-delete-confirmation-demo") {
                PlaylistDeletionVisualQAScreen(mode: .confirmation)
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-playlist-delete-confirmed-demo") {
                PlaylistDeletionVisualQAScreen(mode: .confirmed)
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-playlist-delete-review-demo") {
                PlaylistDeletionVisualQAScreen(mode: .needsReview)
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-playlist-remove-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-playlist-remove-review-demo")
            {
                PlaylistRemovalVisualQAScreen(
                    showsReview: ProcessInfo.processInfo.arguments.contains("-brainz-playlist-remove-review-demo")
                )
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-playlist-reorder-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-playlist-reorder-review-demo")
            {
                PlaylistReorderVisualQAScreen(
                    showsReview: ProcessInfo.processInfo.arguments.contains("-brainz-playlist-reorder-review-demo")
                )
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-playlist-edit-demo") {
                PlaylistMutationVisualQAScreen()
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-playlist-add-demo") {
                PlaylistAddVisualQAScreen()
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-profile-playlists-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-profile-playlists-collab-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-profile-playlists-visitor-demo")
            {
                ProfilePlaylistVisualQAScreen(
                    selection: ProcessInfo.processInfo.arguments.contains("-brainz-profile-playlists-collab-demo")
                        ? .collaborating
                        : .owned,
                    isVisitedProfile: ProcessInfo.processInfo.arguments.contains(
                        "-brainz-profile-playlists-visitor-demo"
                    )
                )
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-fresh-releases-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-fresh-releases-filters-demo")
            {
                DiscoverView(
                    account: model.account,
                    listeningModel: model,
                    freshReleasesProvider: VisualQATasteProvider()
                )
                .environment(pins)
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-taste-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-taste-heatmap-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-taste-release-groups-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-taste-tracks-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-year-in-music-teaser-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-taste-era-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-taste-era-zoom-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-taste-era-card-demo")
            {
                TasteView(model: model)
                    .task { await model.load() }
                    .environment(pins)
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-user-explore-demo") {
                UserProfileExploreVisualQAScreen(listeningModel: model)
                    .environment(pins)
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-user-defining-artists-demo") {
                UserDefiningArtistsVisualQAScreen(model: model)
                    .environment(pins)
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-user-profile-albums-demo") {
                UserProfileAlbumsVisualQAScreen(model: model)
                    .environment(pins)
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-user-profile-tracks-demo") {
                UserProfileTracksVisualQAScreen(model: model)
                    .environment(pins)
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-home-tracks-demo") {
                HomeTopRecordingsVisualQAScreen(model: model)
                    .environment(pins)
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-artist-evolution-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-artist-evolution-all-time-demo")
            {
                NavigationStack {
                    ArtistEvolutionView(
                        model: model,
                        period: .constant(
                            ProcessInfo.processInfo.arguments.contains("-brainz-artist-evolution-all-time-demo")
                                ? .allTime
                                : .thisYear
                        )
                    )
                    .mediaDestinations(model: model)
                }
                .environment(pins)
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-genre-activity-demo") {
                NavigationStack {
                    GenreActivityView(model: model, period: .constant(.thisMonth))
                }
                .environment(pins)
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-artist-origins-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-artist-origins-country-demo")
            {
                NavigationStack {
                    ArtistOriginsView(model: model, period: .constant(.thisYear))
                        .mediaDestinations(model: model)
                }
                .environment(pins)
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-artist-activity-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-artist-activity-expanded-demo")
            {
                NavigationStack {
                    ArtistActivityView(model: model, period: .constant(.thisYear))
                        .mediaDestinations(model: model)
                }
                .environment(pins)
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-top-listeners-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-top-listeners-expanded-demo")
            {
                NavigationStack {
                    ScrollView {
                        TopListenersSummaryView(
                            entity: TopListenersEntity(
                                kind: .artist,
                                mbid: Self.popularityPreviewArtist.mbid!
                            ),
                            viewer: model.account,
                            initiallyExpanded: ProcessInfo.processInfo.arguments.contains(
                                "-brainz-top-listeners-expanded-demo"
                            )
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }
                    .navigationTitle("Always")
                    .navigationDestination(for: SearchUser.self) { user in
                        UserDetailView(user: user, viewer: model.account)
                    }
                }
                .environment(pins)
                .environment(\.topListenersProvider, VisualQATopListenersProvider())
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-similar-artists-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-similar-artists-expanded-demo")
            {
                NavigationStack {
                    ScrollView {
                        SimilarArtistsSummaryView(
                            artistMBID: Self.popularityPreviewArtist.mbid!,
                            initiallyExpanded: ProcessInfo.processInfo.arguments.contains(
                                "-brainz-similar-artists-expanded-demo"
                            )
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }
                    .navigationTitle("Alvvays")
                    .navigationBarTitleDisplayMode(.inline)
                    .mediaDestinations(model: model)
                }
                .environment(pins)
                .environment(\.similarArtistsProvider, VisualQASimilarArtistsProvider())
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-critiquebrainz-reader-demo") {
                NavigationStack {
                    CritiqueBrainzReviewReaderView(
                        summary: VisualQACritiqueBrainzReviewsProvider.readerDemo(
                            entity: .init(kind: .artist, mbid: Self.popularityPreviewArtist.mbid!)
                        )
                    )
                }
                .environment(pins)
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-critiquebrainz-reviews-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-critiquebrainz-reviews-unavailable-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-critiquebrainz-reviews-failure-demo")
            {
                NavigationStack {
                    ScrollView {
                        CritiqueBrainzReviewSummaryView(
                            entity: .init(kind: .artist, mbid: Self.popularityPreviewArtist.mbid!)
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }
                    .navigationTitle("Alvvays")
                }
                .environment(pins)
                .environment(\.critiqueBrainzReviewsProvider, VisualQACritiqueBrainzReviewsProvider(
                    result: ProcessInfo.processInfo.arguments.contains("-brainz-critiquebrainz-reviews-unavailable-demo")
                        ? .unavailable
                        : ProcessInfo.processInfo.arguments.contains("-brainz-critiquebrainz-reviews-failure-demo")
                            ? .failure
                            : .populated
                ))
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-artist-highlights-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-artist-highlights-releases-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-artist-highlights-failure-demo")
            {
                NavigationStack {
                    ScrollView {
                        ArtistHighlightsSummaryView(artistMBID: Self.popularityPreviewArtist.mbid!)
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                    }
                    .navigationTitle("Alvvays")
                    .navigationBarTitleDisplayMode(.inline)
                    .mediaDestinations(model: model)
                }
                .environment(pins)
                .environment(\.artistHighlightsProvider, VisualQAArtistHighlightsProvider(
                    fails: ProcessInfo.processInfo.arguments.contains("-brainz-artist-highlights-failure-demo")
                ))
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-popularity-detail-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-artist-tracks-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-artist-context-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-artist-context-failure-demo")
            {
                NavigationStack {
                    ArtistDetailView(
                        artist: Self.popularityPreviewArtist,
                        model: model,
                        pageContextProvider: VisualQAArtistPageContextProvider(
                            fails: ProcessInfo.processInfo.arguments.contains(
                                "-brainz-artist-context-failure-demo"
                            )
                        )
                    )
                        .mediaDestinations(model: model)
                }
                .task { await model.load() }
                .environment(pins)
                .environment(
                    \.critiqueBrainzReviewsProvider,
                    VisualQACritiqueBrainzReviewsProvider(result: .populated)
                )
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-year-in-music-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-year-in-music-tracks-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-year-in-music-identity-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-year-in-music-evolution-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-year-in-music-new-releases-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-year-in-music-playlists-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-year-in-music-playlist-detail-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-year-in-music-2021-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-year-in-music-2024-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-year-in-music-visited-demo") {
                NavigationStack {
                    let visualYear = ProcessInfo.processInfo.arguments.contains("-brainz-year-in-music-2021-demo") ? 2021 : ProcessInfo.processInfo.arguments.contains("-brainz-year-in-music-2024-demo") ? 2024 : 2025
                    let visualSubject = ProcessInfo.processInfo.arguments.contains("-brainz-year-in-music-visited-demo")
                        ? "music-friend"
                        : account.username
                    if ProcessInfo.processInfo.arguments.contains("-brainz-year-in-music-art-demo") {
                        YearInMusicView(
                            account: account,
                            subjectUsername: visualSubject,
                            listeningModel: model,
                            year: visualYear,
                            provider: VisualQAYearInMusicProvider(),
                            artworkProvider: VisualQAYearInMusicArtworkProvider(),
                            cache: EntityDetailCache()
                        )
                    } else {
                        YearInMusicView(
                            account: account,
                            subjectUsername: visualSubject,
                            listeningModel: model,
                            year: visualYear,
                            provider: VisualQAYearInMusicProvider(),
                            cache: EntityDetailCache()
                        )
                    }
                }
                .environment(pins)
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-radio-demo") {
                NavigationStack {
                    RadioView(
                        account: model.account,
                        listeningModel: model,
                        provider: VisualQARadioProvider(),
                        playlistSaveJournal: Self.visualRadioSaveJournal()
                    )
                }
                .environment(pins)
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-release-detail-demo") {
                NavigationStack {
                    ReleaseDetailView(
                        release: Self.releasePreviewSeed,
                        provider: VisualQAReleaseDetailProvider(),
                        cache: EntityDetailCache()
                    )
                }
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-following-pins-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-following-pins-empty-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-following-pins-failure-demo")
            {
                NavigationStack {
                    FollowingPinsView(account: model.account, listeningModel: model)
                }
                .environment(pins)
            } else if ProcessInfo.processInfo.arguments.contains("-brainz-connected-services-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-connected-services-empty-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-connected-services-failure-demo")
            {
                NavigationStack {
                    ConnectedServicesView(
                        account: model.account,
                        provider: VisualQAConnectedServicesProvider(
                            result: ProcessInfo.processInfo.arguments.contains("-brainz-connected-services-empty-demo")
                                ? .empty
                                : ProcessInfo.processInfo.arguments.contains("-brainz-connected-services-failure-demo")
                                    ? .failure
                                    : .populated
                        ),
                        cache: EntityDetailCache()
                    )
                }
                .environment(pins)
            } else {
                mainContent
            }
        #else
            mainContent
        #endif
    }

    private var mainContent: some View {
        accessoryTabs
            .task {
                #if DEBUG
                    let arguments = ProcessInfo.processInfo.arguments
                    guard !arguments.contains("-brainz-recording-share-demo"),
                        !arguments.contains("-brainz-external-source-demo"),
                        !arguments.contains("-brainz-feed-demo"),
                        !arguments.contains("-brainz-recommendations-demo")
                    else { return }
                #endif
                await model.load()
                #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-brainz-history-day-demo"),
                        let day = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -2, to: .now)
                    {
                        await model.selectHistoryDay(day)
                    }
                #endif
            }
            .onAppear {
                #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-brainz-open-recommendations")
                        || ProcessInfo.processInfo.arguments.contains("-brainz-open-feed")
                    {
                        selectedTab = .discover
                    }
                    if isHomePinFixture {
                        selectedTab = .home
                    }
                    if ProcessInfo.processInfo.arguments.contains("-brainz-history-demo")
                        || ProcessInfo.processInfo.arguments.contains("-brainz-history-day-demo")
                        || ProcessInfo.processInfo.arguments.contains("-brainz-history-delete-demo")
                        || ProcessInfo.processInfo.arguments.contains("-brainz-history-delete-long-title-demo")
                        || ProcessInfo.processInfo.arguments.contains("-brainz-history-delete-recovery-demo")
                        || ProcessInfo.processInfo.arguments.contains("-brainz-inspect-listen-demo")
                        || ProcessInfo.processInfo.arguments.contains("-brainz-inspect-listen-unmapped-demo")
                    {
                        selectedTab = .history
                    }
                    if ProcessInfo.processInfo.arguments.contains("-brainz-recording-share-demo"),
                        presentedListen == nil
                    {
                        presentedListen = Self.recommendationPreviewListen
                    }
                    if ProcessInfo.processInfo.arguments.contains("-brainz-external-source-demo"),
                        presentedListen == nil
                    {
                        presentedListen = Self.externalSourcePreviewListen
                    }
                #endif
            }
            .onDisappear {
                model.cancelArtistActivityLoads()
                model.cancelReleaseGroupRankingLoad()
            }
            .environment(pins)
            .sheet(item: $presentedListen) { listen in
                NavigationStack {
                    RecordingDetailView(recording: listen.recording, model: model)
                }
                .environment(pins)
            }
            .alert(
                "ListenBrainz",
                isPresented: Binding(
                    get: { model.actionError != nil || pins.actionError != nil },
                    set: {
                        if !$0 {
                            model.actionError = nil
                            pins.actionError = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    model.actionError = nil
                    pins.actionError = nil
                }
            } message: {
                Text(pins.actionError ?? model.actionError ?? "")
            }
    }

    @ViewBuilder
    private var accessoryTabs: some View {
        if let nowPlaying = model.snapshot.playingNow {
            if #available(iOS 26.0, *) {
                tabs
                    .tabBarMinimizeBehavior(.onScrollDown)
                    .tabViewBottomAccessory {
                        MiniListenBar(listen: nowPlaying) { presentedListen = nowPlaying }
                    }
            } else {
                tabs.safeAreaInset(edge: .bottom, spacing: 0) {
                    MiniListenBar(listen: nowPlaying) { presentedListen = nowPlaying }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.bar)
                }
            }
        } else {
            tabs
        }
    }

    private var tabs: some View {
        TabView(selection: tabSelection) {
            Tab("Home", systemImage: "house.fill", value: .home) {
                HomeView(model: model)
            }
            Tab("History", systemImage: "clock.arrow.circlepath", value: .history) {
                HistoryView(model: model)
            }
            Tab("Discover", systemImage: "sparkles", value: .discover) {
                DiscoverView(account: account, listeningModel: model)
            }
            Tab("Taste", systemImage: "chart.bar.xaxis", value: .taste) {
                TasteView(model: model)
            }
            Tab("Profile", systemImage: "person.crop.circle", value: .profile) {
                ProfileView(model: model, session: session)
            }
        }
    }

    private var tabSelection: Binding<Destination> {
        #if DEBUG
            if isHomePinFixture {
                return .constant(.home)
            }
        #endif
        return $selectedTab
    }

    #if DEBUG
        private var isHomePinFixture: Bool {
            ProcessInfo.processInfo.arguments.contains("-brainz-home-pin-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-home-pin-empty-demo")
                || ProcessInfo.processInfo.arguments.contains("-brainz-home-pin-failure-demo")
        }

        private static func visualRadioSaveJournal() -> RadioPlaylistSaveJournal {
            let journal = RadioPlaylistSaveJournal()
            if ProcessInfo.processInfo.arguments.contains("-brainz-radio-save-review-demo") {
                _ = journal.begin(username: "visual-radio", at: .now)
            }
            return journal
        }

        private static let recommendationPreviewListen = Listen(
            recording: Recording(
                identity: RecordingIdentity(
                    mbid: UUID(uuidString: "526bd613-fddd-4bd6-9137-ab709ac74cab"),
                    msid: nil
                ),
                title: "Dreams Tonite",
                artistName: "Alvvays",
                artistMBIDs: [],
                releaseTitle: "Antisocialites",
                releaseMBID: nil,
                releaseGroupMBID: nil,
                artworkReleaseMBID: nil,
                durationMilliseconds: 196_000,
                source: "ListenBrainz"
            ),
            listenedAt: .now,
            insertedAt: .now,
            isPlayingNow: false
        )

        private static let externalSourcePreviewListen = Listen(
            recording: Recording(
                identity: RecordingIdentity(
                    mbid: nil,
                    msid: UUID(uuidString: "70000000-0000-0000-0000-000000000001")
                ),
                title: "Dreams Tonite",
                artistName: "Alvvays",
                artistMBIDs: [],
                releaseTitle: "Antisocialites",
                releaseMBID: nil,
                releaseGroupMBID: nil,
                artworkReleaseMBID: nil,
                durationMilliseconds: 196_000,
                source: "Spotify",
                externalLinks: ExternalMediaLink.resolve(
                    urlRelationships: [
                        ExternalMediaRelationship(
                            type: "free streaming",
                            url: "https://www.deezer.com/track/3135556"
                        ),
                        ExternalMediaRelationship(
                            type: "streaming",
                            url: "https://tidal.com/track/123456"
                        ),
                        ExternalMediaRelationship(
                            type: "streaming",
                            url: "https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC"
                        ),
                    ],
                    spotifyID: nil,
                    originURL: "https://youtu.be/dQw4w9WgXcQ"
                )
            ),
            listenedAt: .now,
            insertedAt: .now,
            isPlayingNow: false
        )

        private static let releasePreviewSeed = ReleaseSeed(
            mbid: UUID(uuidString: "1390f1b7-7851-48ae-983d-eb8a48f78048")!,
            title: "Four You",
            artistName: "Karan Aujla, Ikky",
            artistMBIDs: [
                UUID(uuidString: "4a779683-5404-4b90-a0d7-242495158265")!,
                UUID(uuidString: "3ea12c3c-8596-4d70-b327-208b0a459a97")!,
            ],
            releaseGroupMBID: UUID(uuidString: "eb8734c9-127d-495e-b908-9194cdbac45d"),
            releaseDate: "2023-02-04",
            primaryType: "EP",
            artworkReleaseMBID: UUID(uuidString: "1390f1b7-7851-48ae-983d-eb8a48f78048"),
            discoveryContext: ReleaseDiscoveryContext(
                tags: ["punjabi pop", "hip hop", "desi"],
                confidence: 2,
                listenCount: 4_312
            )
        )

        private static let popularityPreviewArtist = RankedArtist(
            mbid: UUID(uuidString: "526bd613-fddd-4bd6-9137-ab709ac74cab"),
            name: "Alvvays",
            listenCount: 1_283
        )
    #endif
}

#if DEBUG
    private struct VisualQAReleaseDetailProvider: ConcreteReleaseDetailProviding {
        func release(seed: ReleaseSeed) async throws -> ReleaseDetail {
            ReleaseDetail(
                mbid: seed.mbid,
                title: seed.title,
                artistCreditName: seed.artistName,
                releaseDate: seed.releaseDate,
                country: "IN",
                status: "Official",
                barcode: "859770181552",
                packaging: "None",
                labels: ["Rehaan Records"],
                releaseGroupMBID: seed.releaseGroupMBID,
                releaseGroupPrimaryType: "EP",
                media: [
                    ReleaseMedium(
                        position: 1,
                        format: "Digital Media",
                        title: nil,
                        tracks: [
                            track(seed: seed, position: 1, title: "52 Bars", duration: 214_024, mapped: true),
                            track(seed: seed, position: 2, title: "Take It Easy", duration: 210_361, mapped: true),
                            track(seed: seed, position: 3, title: "Fallin Apart", duration: 198_000, mapped: false),
                            track(seed: seed, position: 4, title: "Yeah Naah", duration: 182_375, mapped: true),
                        ]
                    )
                ]
            )
        }

        private func track(
            seed: ReleaseSeed,
            position: Int,
            title: String,
            duration: Int,
            mapped: Bool
        ) -> ReleaseTrack {
            ReleaseTrack(
                position: position,
                number: String(position),
                recording: Recording(
                    identity: .init(mbid: mapped ? UUID() : nil, msid: nil),
                    title: title,
                    artistName: seed.artistName,
                    artistMBIDs: seed.artistMBIDs,
                    releaseTitle: seed.title,
                    releaseMBID: seed.mbid,
                    releaseGroupMBID: seed.releaseGroupMBID,
                    artworkReleaseMBID: seed.artworkReleaseMBID,
                    durationMilliseconds: duration,
                    source: nil
                )
            )
        }
    }

    private struct VisualQAPinProvider: PinProviding {
        func currentPin(username: String) async throws -> PinnedRecording? { nil }
        func pin(_ recording: Recording, blurb: String?) async throws -> PinnedRecording {
            throw PinProviderError.pinNeedsIdentifier
        }
        func pinHistory(username: String, count: Int, offset: Int) async throws -> (
            pins: [PinnedRecording], totalCount: Int
        ) {
            ([], 0)
        }
        func unpin() async throws {}
        func updatePinBlurb(rowID: Int, blurb: String) async throws {}
        func deletePin(rowID: Int) async throws {}
    }

    private struct VisualQAHomePinProvider: PinProviding {
        enum Result { case populated, empty, failure }

        let result: Result

        func currentPin(username: String) async throws -> PinnedRecording? {
            switch result {
            case .populated:
                return PinnedRecording(
                    rowID: 1,
                    created: .now.addingTimeInterval(-3_600),
                    pinnedUntil: .now.addingTimeInterval(7 * 86_400),
                    blurb: "A small favorite for the week.",
                    username: username,
                    recording: VisualQAHomePinListeningProvider.recording,
                    isCurrent: true
                )
            case .empty:
                return nil
            case .failure:
                throw VisualQAHomePinError.unavailable
            }
        }

        func pin(_ recording: Recording, blurb: String?) async throws -> PinnedRecording {
            throw PinProviderError.pinNeedsIdentifier
        }

        func pinHistory(username: String, count: Int, offset: Int) async throws -> (
            pins: [PinnedRecording], totalCount: Int
        ) { ([], 0) }
        func unpin() async throws {}
        func updatePinBlurb(rowID: Int, blurb: String) async throws {}
        func deletePin(rowID: Int) async throws {}
    }

    private enum VisualQAHomePinError: LocalizedError {
        case unavailable
        var errorDescription: String? { String(localized: "The preview pin is unavailable.") }
    }

    private struct VisualQARadioProvider: RadioProviding {
        private static let artworkReleaseMBID = UUID(uuidString: "1390f1b7-7851-48ae-983d-eb8a48f78048")!
        private static let secondArtworkReleaseMBID = UUID(uuidString: "5fbea312-0b73-4e2d-9e42-e25f972f6041")!

        func generate(options: RadioGenerationOptions) async throws -> RadioMix {
            try await ContinuousClock().sleep(for: .milliseconds(180))
            let rows: [(String, String, String?, UUID?, UUID?)] = [
                (
                    "After the Earthquake", "Alvvays", "Blue Rev",
                    UUID(uuidString: "39ad19e5-c0b0-454a-985b-201fb92898a0"), Self.artworkReleaseMBID
                ),
                (
                    "Be Sweet", "Japanese Breakfast", "Jubilee",
                    UUID(uuidString: "42d36a20-621a-4c34-b2fe-01c85447f9e8"), Self.secondArtworkReleaseMBID
                ),
                (
                    "Only in My Dreams", "The Marías", "Superclean, Vol. I",
                    UUID(uuidString: "9b84f25f-c7a4-4b60-8c59-0d5774f5d568"), Self.artworkReleaseMBID
                ),
                (
                    "Andromeda", "Weyes Blood", "Titanic Rising",
                    UUID(uuidString: "173fc72a-efb8-4e58-a15e-86eecf7ac58d"), Self.secondArtworkReleaseMBID
                ),
                (
                    "Show Me How", "Men I Trust", "Oncle Jazz",
                    UUID(uuidString: "5a7d9f53-44d0-492c-9c63-dce87d467424"), Self.artworkReleaseMBID
                ),
                (
                    "A very long recording title that still belongs in a calm late-night mix",
                    "An Artist With a Longer Credit", nil, nil, nil
                ),
                (
                    "Your Best American Girl", "Mitski", "Puberty 2",
                    UUID(uuidString: "8348bd91-4b34-4bfc-bfaa-e9d958e5fc2f"), Self.secondArtworkReleaseMBID
                ),
                (
                    "Space Song", "Beach House", "Depression Cherry",
                    UUID(uuidString: "25a575ec-570f-4a27-9bd6-634026add2a7"), Self.artworkReleaseMBID
                ),
            ]
            let tracks = rows.enumerated().map { index, row in
                PlaylistTrack(
                    position: index + 1,
                    recording: Recording(
                        identity: .init(mbid: row.3, msid: nil),
                        title: row.0,
                        artistName: row.1,
                        artistMBIDs: [],
                        releaseTitle: row.2,
                        releaseMBID: row.4,
                        releaseGroupMBID: nil,
                        artworkReleaseMBID: row.4,
                        durationMilliseconds: index.isMultiple(of: 2) ? 198_000 + index * 3_000 : nil,
                        source: "LB Radio"
                    ),
                    addedAt: nil,
                    addedBy: nil
                )
            }
            return RadioMix(
                options: options,
                title: "Familiar corners, new turns",
                annotation: "A late-night mix drawn from your listening history and nearby artists.",
                feedback: [
                    "Using all-time statistics for visual-radio.",
                    "Easy mode favors the most relevant recordings in the source.",
                ],
                tracks: tracks,
                metadataEnrichmentFailed: false,
                generatedAt: .now
            )
        }
    }

    private struct VisualQAPopularityProvider: PopularityProviding {
        func popularity(for entity: PopularityEntity) async throws -> GlobalPopularity {
            await Task.yield()
            return GlobalPopularity(
                entity: entity,
                totalListenCount: 2_418_731,
                totalUserCount: 148_206
            )
        }
    }

    private struct VisualQAArtistPageContextProvider: ArtistPageContextProviding {
        let fails: Bool

        init(fails: Bool = false) {
            self.fails = fails
        }

        func context(for artistMBID: UUID, forceRefresh: Bool) async throws -> ArtistPageContext? {
            await Task.yield()
            if fails { throw VisualQAArtistHighlightsError.unavailable }
            let highlights = try await VisualQAArtistHighlightsProvider()
                .highlights(for: artistMBID, forceRefresh: forceRefresh)
                ?? ArtistHighlights(artistMBID: artistMBID, recordings: [], releaseGroups: [])
            let similarArtists = try await VisualQASimilarArtistsProvider()
                .similarArtists(to: artistMBID)
            let popularity = try await VisualQAPopularityProvider().popularity(
                for: PopularityEntity(kind: .artist, mbid: artistMBID)
            )
            let topListeners = try await VisualQATopListenersProvider().topListeners(
                for: TopListenersEntity(kind: .artist, mbid: artistMBID)
            )
            return ArtistPageContext(
                artistMBID: artistMBID,
                identity: ArtistPageIdentity(
                    artistMBID: artistMBID,
                    name: "Alvvays",
                    type: "Group",
                    area: "Toronto, Ontario, Canada",
                    beginYear: 2011,
                    endYear: nil
                ),
                coverArtSVG: """
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400">
                  <rect width="200" height="200" fill="#274060"/>
                  <rect x="200" width="200" height="200" fill="#d9a5b3"/>
                  <rect y="200" width="200" height="200" fill="#f3c969"/>
                  <rect x="200" y="200" width="200" height="200" fill="#6a7f5b"/>
                  <circle cx="100" cy="100" r="58" fill="#f7f4ed" opacity=".76"/>
                  <path d="M225 42h150v116H225z" fill="#192231" opacity=".38"/>
                  <path d="M25 360 105 230l70 130z" fill="#37505c" opacity=".58"/>
                  <circle cx="300" cy="300" r="70" fill="#eef0e8" opacity=".42"/>
                </svg>
                """,
                popularity: popularity,
                topListeners: topListeners,
                highlights: highlights,
                similarArtists: similarArtists
            )
        }
    }

    private struct VisualQATopListenersProvider: TopListenersProviding {
        func topListeners(for entity: TopListenersEntity) async throws -> TopListeners? {
            await Task.yield()
            return TopListeners(
                entity: entity,
                listeners: [
                    .init(username: "marina-listens-to-everything", listenCount: 2_184),
                    .init(username: "quietlycataloguing", listenCount: 1_744),
                    .init(username: "astral_tape_archive", listenCount: 982),
                    .init(username: "sound-and-vision", listenCount: 401),
                    .init(username: "bluehour", listenCount: 188),
                    .init(username: "a-very-long-listenbrainz-username-for-layout", listenCount: 75),
                    .init(username: "late_night_side_b", listenCount: 31),
                ],
                totalListenCount: 5_605
            )
        }
    }

    private struct VisualQASimilarArtistsProvider: SimilarArtistsProviding {
        func similarArtists(to artistMBID: UUID) async throws -> SimilarArtists? {
            await Task.yield()
            let rows: [(String, String)] = [
                ("39ad19e5-c0b0-454a-985b-201fb92898a0", "Japanese Breakfast"),
                ("42d36a20-621a-4c34-b2fe-01c85447f9e8", "The Beths"),
                ("9b84f25f-c7a4-4b60-8c59-0d5774f5d568", "Men I Trust"),
                ("173fc72a-efb8-4e58-a15e-86eecf7ac58d", "Beach House"),
                ("5a7d9f53-44d0-492c-9c63-dce87d467424", "Snail Mail"),
                ("8348bd91-4b34-4bfc-bfaa-e9d958e5fc2f", "Mitski"),
                ("25a575ec-570f-4a27-9bd6-634026add2a7", "Weyes Blood"),
                ("4a779683-5404-4b90-a0d7-242495158265", "Japanese Breakfast With a Deliberately Long Name"),
                ("3ea12c3c-8596-4d70-b327-208b0a459a97", "Soccer Mommy"),
                ("1390f1b7-7851-48ae-983d-eb8a48f78048", "Slow Pulp"),
                ("5fbea312-0b73-4e2d-9e42-e25f972f6041", "MUNA"),
                ("eb8734c9-127d-495e-b908-9194cdbac45d", "Wednesday"),
            ]
            return SimilarArtists(
                sourceArtistMBID: artistMBID,
                artists: rows.enumerated().compactMap { index, row in
                    guard let mbid = UUID(uuidString: row.0) else { return nil }
                    return SimilarArtist(mbid: mbid, name: row.1, score: Double(100 - index))
                }
            )
        }
    }

    private struct VisualQAArtistHighlightsProvider: ArtistHighlightsProviding {
        let fails: Bool

        init(fails: Bool = false) {
            self.fails = fails
        }

        func highlights(for artistMBID: UUID, forceRefresh: Bool) async throws -> ArtistHighlights? {
            await Task.yield()
            if fails { throw VisualQAArtistHighlightsError.unavailable }
            let recordingRows: [(String, String, String?, Int, Int)] = [
                ("11111111-1111-4111-8111-111111111111", "Dreams Tonite", "Antisocialites", 2_418_731, 148_206),
                ("22222222-2222-4222-8222-222222222222", "Archie, Marry Me", "Alvvays", 2_104_992, 137_844),
                ("33333333-3333-4333-8333-333333333333", "Belinda Says", "Blue Rev", 1_792_310, 109_248),
                ("44444444-4444-4444-8444-444444444444", "In Undertow", "Antisocialites", 1_501_042, 97_510),
                ("55555555-5555-4555-8555-555555555555", "Adult Diversion", "Alvvays", 1_218_004, 88_200),
                ("66666666-6666-4666-8666-666666666666", "Very Online Guy", "Blue Rev", 884_729, 61_400),
                ("77777777-7777-4777-8777-777777777777", "A Deliberately Long Recording Title for Layout Testing", nil, 420_018, 30_042),
            ]
            let recordings = recordingRows.compactMap { row -> ArtistPopularRecording? in
                guard let recordingMBID = UUID(uuidString: row.0) else { return nil }
                return ArtistPopularRecording(
                    recordingMBID: recordingMBID,
                    title: row.1,
                    artistName: "Alvvays",
                    artistMBIDs: [artistMBID],
                    releaseTitle: row.2,
                    releaseMBID: nil,
                    artworkReleaseMBID: nil,
                    durationMilliseconds: 210_000,
                    totalListenCount: row.3,
                    totalUserCount: row.4
                )
            }

            let releaseGroupRows: [(String, String, String, String, Int, Int)] = [
                ("81111111-1111-4111-8111-111111111111", "Blue Rev", "Album", "2022-10-07", 7_845_210, 184_005),
                ("82222222-2222-4222-8222-222222222222", "Antisocialites", "Album", "2017-09-08", 6_320_144, 171_210),
                ("83333333-3333-4333-8333-333333333333", "Alvvays", "Album", "2014-07-22", 5_812_901, 166_402),
                ("84444444-4444-4444-8444-444444444444", "Party Police", "Single", "2014", 908_442, 57_120),
                ("85555555-5555-4555-8555-555555555555", "Pharmacist", "Single", "2022-07-06", 814_084, 49_022),
                ("86666666-6666-4666-8666-666666666666", "Belinda Says / Very Online Guy", "Single", "2022-09-22", 612_704, 41_801),
                ("87777777-7777-4777-8777-777777777777", "A Very Long Release Group Title for Accessibility Layout Testing", "EP", "2020", 210_300, 18_921),
            ]
            let releaseGroups = releaseGroupRows.compactMap { row -> ArtistPopularReleaseGroup? in
                guard let mbid = UUID(uuidString: row.0) else { return nil }
                return ArtistPopularReleaseGroup(
                    mbid: mbid,
                    title: row.1,
                    artistName: "Alvvays",
                    primaryType: row.2,
                    firstReleaseDate: row.3,
                    artworkReleaseMBID: nil,
                    totalListenCount: row.4,
                    totalUserCount: row.5
                )
            }
            return ArtistHighlights(
                artistMBID: artistMBID,
                recordings: recordings,
                releaseGroups: releaseGroups
            )
        }
    }

    private enum VisualQAArtistHighlightsError: LocalizedError {
        case unavailable
        var errorDescription: String? { String(localized: "Fixture artist highlights unavailable.") }
    }

    private struct VisualQACritiqueBrainzReviewsProvider: CritiqueBrainzReviewsProviding {
        enum Result { case populated, unavailable, failure }
        let result: Result

        static func readerDemo(entity: CritiqueBrainzEntity) -> CritiqueBrainzReviewSummary {
            CritiqueBrainzReviewSummary(
                entity: entity,
                reviews: [
                    .init(
                        id: UUID(uuidString: "a4c81c31-0e10-4ee0-bd37-842c5dcdf7ad")!,
                        author: "Avery Chen",
                        licenseID: "CC BY-SA 3.0",
                        licenseURL: URL(string: "https://creativecommons.org/licenses/by-sa/3.0/"),
                        rating: 5,
                        text: "A sharply observed record that keeps opening up with each listen. Its hooks arrive softly, then stay with you for days. The arrangements keep shifting at the edges without losing their center, and the final song reframes everything that came before it. Even the smallest transitions feel deliberate.",
                        publishedAt: .now.addingTimeInterval(-14 * 86_400)
                    ),
                    .init(
                        id: UUID(uuidString: "4602e98e-61f1-456b-85d0-a0fe0167d659")!,
                        author: "Samira",
                        licenseID: nil,
                        licenseURL: nil,
                        rating: 4,
                        text: "Bright melodies, precise details, and a lovely sense of motion.",
                        publishedAt: .now.addingTimeInterval(-93 * 86_400)
                    ),
                    .init(
                        id: UUID(uuidString: "5e9ee8e7-85d9-4216-956c-8d699a5bd2e0")!,
                        author: nil,
                        licenseID: "CC0-1.0",
                        licenseURL: nil,
                        rating: nil,
                        text: "The quiet details make this one worth returning to.",
                        publishedAt: nil
                    ),
                    .init(
                        id: UUID(uuidString: "b5d2f714-c340-4924-9ee3-2a13d4b7c0d1")!,
                        author: "Mina",
                        licenseID: "CC BY 4.0",
                        licenseURL: URL(string: "https://creativecommons.org/licenses/by/4.0/"),
                        rating: 3,
                        text: "A beautiful first half, though the final stretch feels less certain.",
                        publishedAt: .now.addingTimeInterval(-181 * 86_400)
                    ),
                    .init(
                        id: UUID(uuidString: "39ad19e5-c0b0-454a-985b-201fb92898a0")!,
                        author: "Rowan",
                        licenseID: nil,
                        licenseURL: nil,
                        rating: 2,
                        text: "The production is polished, but the songs never quite settle into a shape of their own.",
                        publishedAt: .now.addingTimeInterval(-260 * 86_400)
                    )
                ],
                averageRating: 3.8,
                ratingCount: 19
            )
        }

        func reviews(for entity: CritiqueBrainzEntity) async throws -> CritiqueBrainzReviewSummary? {
            await Task.yield()
            switch result {
            case .unavailable: return nil
            case .failure: throw VisualQACritiqueBrainzError.unavailable
            case .populated:
                return CritiqueBrainzReviewSummary(
                    entity: entity,
                    reviews: [
                        .init(
                            id: UUID(uuidString: "a4c81c31-0e10-4ee0-bd37-842c5dcdf7ad")!,
                            author: "Avery Chen",
                            licenseID: "CC BY-SA 3.0",
                            licenseURL: URL(string: "https://creativecommons.org/licenses/by-sa/3.0/"),
                            rating: 5,
                            text: "A sharply observed record that keeps opening up with each listen.",
                            publishedAt: .now.addingTimeInterval(-14 * 86_400)
                        ),
                        .init(
                            id: UUID(uuidString: "4602e98e-61f1-456b-85d0-a0fe0167d659")!,
                            author: "Samira",
                            licenseID: "CC BY-SA 3.0",
                            licenseURL: URL(string: "https://creativecommons.org/licenses/by-sa/3.0/"),
                            rating: 4,
                            text: "Bright melodies, precise details, and a lovely sense of motion.",
                            publishedAt: .now.addingTimeInterval(-93 * 86_400)
                        ),
                    ],
                    averageRating: 4.6,
                    ratingCount: 12
                )
            }
        }
    }

    private struct VisualQAConnectedServicesProvider: ConnectedServicesProviding {
        enum Result {
            case populated
            case empty
            case failure
        }

        let result: Result

        func connectedServices(username: String) async throws -> ConnectedServices {
            switch result {
            case .populated:
                return ConnectedServices(identifiers: ["spotify", "musicbrainz-prod", "unlisted-service"])
            case .empty:
                return ConnectedServices(identifiers: [])
            case .failure:
                throw VisualQAConnectedServicesError.unavailable
            }
        }
    }

    private enum VisualQAConnectedServicesError: LocalizedError {
        case unavailable

        var errorDescription: String? { String(localized: "The preview service is unavailable.") }
    }

    private enum VisualQACritiqueBrainzError: LocalizedError {
        case unavailable
        var errorDescription: String? { String(localized: "Check your connection, then try again.") }
    }

    private struct VisualQAPopularityListeningProvider: ListeningProvider {
        private static let artistMBID = UUID(uuidString: "526bd613-fddd-4bd6-9137-ab709ac74cab")!
        private static let recordingMBID = UUID(uuidString: "39ad19e5-c0b0-454a-985b-201fb92898a0")!

        func validateToken() async throws -> String { "visual-popularity" }
        func recentListens(username: String, before: Date?, after: Date?, count: Int) async throws -> [Listen] { [] }
        func playingNow(username: String) async throws -> Listen? { nil }
        func listenCount(username: String) async throws -> Int { 48_271 }
        func topArtists(username: String, count: Int) async throws -> [RankedArtist] {
            [.init(mbid: Self.artistMBID, name: "Alvvays", listenCount: 1_283)]
        }
        func topReleases(username: String, count: Int) async throws -> [RankedRelease] { [] }
        func topRecordings(username: String, count: Int) async throws -> [RankedRecording] {
            [
                .init(
                    mbid: Self.recordingMBID,
                    releaseMBID: nil,
                    title: "After the Earthquake",
                    artistName: "Alvvays",
                    artistMBIDs: [Self.artistMBID],
                    releaseTitle: "Blue Rev",
                    listenCount: 96
                ),
                .init(
                    mbid: nil,
                    releaseMBID: nil,
                    title: "A Very Long Unmapped Recording Title for Layout Inspection",
                    artistName: "Alvvays",
                    artistMBIDs: [Self.artistMBID],
                    releaseTitle: nil,
                    listenCount: 61
                )
            ]
        }
        func listenActivity(username: String, period: ListeningActivityPeriod) async throws -> ListeningActivity {
            .init(period: period, from: .distantPast, to: .distantPast, lastUpdated: .now, buckets: [])
        }
        func freshReleases(username: String, scope: FreshReleaseScope) async throws -> [FreshRelease] { [] }
        func submitFeedback(_ feedback: RecordingFeedback, for recording: Recording) async throws {}
    }

    /// A complete local Home fixture: every artwork-bearing identifier is nil,
    /// so previews cannot start remote artwork requests.
    private struct VisualQAHomePinListeningProvider: ListeningProvider {
        static let recording = Recording(
            identity: .init(mbid: nil, msid: nil),
            title: "Slow Morning",
            artistName: "Harbor Lights",
            artistMBIDs: [],
            releaseTitle: "Window Seat",
            releaseMBID: nil,
            releaseGroupMBID: nil,
            artworkReleaseMBID: nil,
            durationMilliseconds: 227_000,
            source: "Preview"
        )

        func validateToken() async throws -> String { "visual-home" }
        func recentListens(username: String, before: Date?, after: Date?, count: Int) async throws -> [Listen] {
            [Listen(recording: Self.recording, listenedAt: .now.addingTimeInterval(-420), insertedAt: nil, isPlayingNow: false)]
        }
        func playingNow(username: String) async throws -> Listen? { nil }
        func listenCount(username: String) async throws -> Int { 1_284 }
        func topArtists(username: String, count: Int) async throws -> [RankedArtist] {
            [.init(mbid: nil, name: "Harbor Lights", listenCount: 84)]
        }
        func topReleases(username: String, count: Int) async throws -> [RankedRelease] { [] }
        func topRecordings(username: String, count: Int) async throws -> [RankedRecording] { [] }
        func listenActivity(username: String, period: ListeningActivityPeriod) async throws -> ListeningActivity {
            .init(period: period, from: .distantPast, to: .distantPast, lastUpdated: .now, buckets: [])
        }
        func freshReleases(username: String, scope: FreshReleaseScope) async throws -> [FreshRelease] { [] }
        func submitFeedback(_ feedback: RecordingFeedback, for recording: Recording) async throws {}
    }

    private struct VisualQAHistoryProvider: ListeningProvider {
        private static let artworkReleaseMBID = UUID(uuidString: "1390f1b7-7851-48ae-983d-eb8a48f78048")!
        private static let titles = [
            "Night Drive", "Wildflower", "Parallel Lines", "Between the Bars",
            "Soft Focus", "Silver Lining", "Afterimage", "Northbound",
            "Quiet Hours", "All My Friends", "Blue Rev",
            "Everything We Heard Through the Open Windows on the Long Way Home",
        ]
        private static let artists = ["The Marías", "Alvvays", "Japanese Breakfast", "Radiohead"]

        func validateToken() async throws -> String { "visual-history" }

        func recentListens(username: String, before: Date?, after: Date?, count: Int) async throws -> [Listen] {
            if after != nil, let before {
                return (0..<12).map { index in
                    Self.makeListen(
                        index: index + 30,
                        listenedAt: before.addingTimeInterval(-1_800 - Double(index * 2_820))
                    )
                }
            }
            guard before == nil else { return [] }
            return Self.makeListens(around: .now, count: 22)
        }

        func playingNow(username: String) async throws -> Listen? {
            Self.makeListen(index: 22, listenedAt: .now, isPlayingNow: true)
        }

        func listenCount(username: String) async throws -> Int { 48_271 }
        func topArtists(username: String, count: Int) async throws -> [RankedArtist] { [] }
        func topReleases(username: String, count: Int) async throws -> [RankedRelease] { [] }
        func topRecordings(username: String, count: Int) async throws -> [RankedRecording] { [] }
        func listenActivity(username: String, period: ListeningActivityPeriod) async throws -> ListeningActivity {
            .init(period: period, from: .distantPast, to: .distantPast, lastUpdated: .now, buckets: [])
        }
        func freshReleases(username: String, scope: FreshReleaseScope) async throws -> [FreshRelease] { [] }
        func submitFeedback(_ feedback: RecordingFeedback, for recording: Recording) async throws {}

        static func inspectionPreview() -> Listen {
            makeListen(index: 0, listenedAt: .now.addingTimeInterval(-2_400))
        }

        private static func makeListens(around newest: Date, count: Int) -> [Listen] {
            (0..<count).map { index in
                let dayOffset = index < 7 ? 0 : (index < 15 ? 1 : 2)
                let minuteOffset = (index * 47) % 360
                let listenedAt =
                    Calendar.autoupdatingCurrent.date(
                        byAdding: DateComponents(day: -dayOffset, minute: -minuteOffset),
                        to: newest
                    ) ?? newest.addingTimeInterval(TimeInterval(-index * 2_820))
                return makeListen(index: index, listenedAt: listenedAt)
            }
            .sorted { $0.listenedAt > $1.listenedAt }
        }

        private static func makeListen(index: Int, listenedAt: Date, isPlayingNow: Bool = false) -> Listen {
            let msid = UUID(uuidString: String(format: "70000000-0000-0000-0000-%012x", index + 1))
            let artist = artists[index % artists.count]
            return Listen(
                recording: Recording(
                    identity: .init(mbid: nil, msid: isPlayingNow ? nil : msid),
                    title: titles[index % titles.count],
                    artistName: artist,
                    artistMBIDs: [],
                    releaseTitle: index.isMultiple(of: 3) ? "Listening Room" : "Midnight Editions",
                    releaseMBID: artworkReleaseMBID,
                    releaseGroupMBID: nil,
                    artworkReleaseMBID: artworkReleaseMBID,
                    durationMilliseconds: 180_000 + index * 1_700,
                    source: index.isMultiple(of: 2) ? "Apple Music" : "Spotify"
                ),
                listenedAt: listenedAt,
                insertedAt: listenedAt.addingTimeInterval(3),
                isPlayingNow: isPlayingNow,
                inspection: fixtureInspection(
                    mapped: !ProcessInfo.processInfo.arguments.contains("-brainz-inspect-listen-unmapped-demo"),
                    listenMSID: isPlayingNow ? nil : msid,
                    submittedMSID: msid
                )
            )
        }

        private static func fixtureInspection(mapped: Bool, listenMSID: UUID?, submittedMSID: UUID?) -> ListenInspection {
            ListenInspection(
                submittedArtist: "The Marías",
                submittedTrack: "Night Drive",
                submittedRelease: "Listening Room",
                recordingMSID: listenMSID,
                submittedRecordingMSID: submittedMSID,
                submittedArtistMBIDs: [],
                submittedRecordingMBID: nil,
                submittedReleaseMBID: nil,
                submittedReleaseGroupMBID: nil,
                submittedTrackMBID: nil,
                submittedWorkMBIDs: [],
                resolvedArtistMBIDs: mapped ? [UUID(uuidString: "934c97a5-3d4d-4c8b-a4ea-7bde1bd6f4cc")!] : [],
                resolvedRecordingMBID: mapped ? UUID(uuidString: "4262dc8a-97b3-4db7-8ea0-e4fbba9264bb")! : nil,
                resolvedReleaseMBID: mapped ? artworkReleaseMBID : nil,
                resolvedReleaseGroupMBID: nil,
                resolvedRecordingName: mapped ? "Night Drive" : nil,
                trackNumber: 2,
                isrc: "USXXX2600001",
                spotifyID: "4uLU6hMCjMI75M1A2tKUQC",
                tags: ["indie pop", "dream pop"],
                mediaPlayer: "Apple Music",
                mediaPlayerVersion: "1.0",
                submissionClient: "Brainz",
                submissionClientVersion: "0.1",
                musicService: "apple_music",
                musicServiceName: "Apple Music",
                originURL: "https://example.invalid/listen/fixture",
                durationMilliseconds: 243_000
            )
        }
    }

    private struct VisualQATasteProvider: ListeningProvider {
        private static let artistMBIDs = [
            UUID(uuidString: "526bd613-fddd-4bd6-9137-ab709ac74cab")!,
            UUID(uuidString: "6c0b31f3-2e41-4d70-bd16-5fa8551bd59b")!,
            UUID(uuidString: "a1d4c987-9c07-4c71-8f75-6505e2e8f554")!,
        ]
        private static let releaseMBID = UUID(uuidString: "1390f1b7-7851-48ae-983d-eb8a48f78048")!
        private static let recordingMBID = UUID(uuidString: "39ad19e5-c0b0-454a-985b-201fb92898a0")!

        func validateToken() async throws -> String { "visual-taste" }
        func recentListens(username: String, before: Date?, after: Date?, count: Int) async throws -> [Listen] { [] }
        func playingNow(username: String) async throws -> Listen? { nil }
        func listenCount(username: String) async throws -> Int { 48_271 }
        func topArtists(username: String, count: Int) async throws -> [RankedArtist] {
            [
                .init(mbid: Self.artistMBIDs[0], name: "Alvvays", listenCount: 1_283),
                .init(mbid: Self.artistMBIDs[1], name: "Japanese Breakfast", listenCount: 947),
                .init(mbid: Self.artistMBIDs[2], name: "The Marías", listenCount: 781),
            ]
        }
        func topReleases(username: String, count: Int) async throws -> [RankedRelease] {
            [
                .init(
                    mbid: Self.releaseMBID, name: "Blue Rev", artistName: "Alvvays", artistMBIDs: [Self.artistMBIDs[0]],
                    listenCount: 423),
                .init(
                    mbid: nil, name: "Jubilee", artistName: "Japanese Breakfast", artistMBIDs: [Self.artistMBIDs[1]],
                    listenCount: 287),
            ]
        }
        func topReleaseGroups(username: String, count: Int) async throws -> [RankedReleaseGroup] {
            [
                .init(
                    mbid: UUID(uuidString: "a2b2d7d1-2d17-4c1d-b736-2fba43f0f609")!,
                    name: "Blue Rev: The Anniversary Collection",
                    artistName: "Alvvays",
                    artistMBIDs: [Self.artistMBIDs[0]],
                    listenCount: 423
                ),
                .init(
                    mbid: nil,
                    name: "Jubilee (Expanded Edition)",
                    artistName: "Japanese Breakfast",
                    artistMBIDs: [Self.artistMBIDs[1]],
                    listenCount: 287
                ),
            ]
        }
        func topRecordings(username: String, count: Int) async throws -> [RankedRecording] {
            [
                .init(
                    mbid: Self.recordingMBID, releaseMBID: Self.releaseMBID,
                    title: "After the Earthquake", artistName: "Alvvays",
                    artistMBIDs: [Self.artistMBIDs[0]], releaseTitle: "Blue Rev", listenCount: 96),
                .init(
                    mbid: nil, releaseMBID: nil, title: "Be Sweet", artistName: "Japanese Breakfast",
                    artistMBIDs: [Self.artistMBIDs[1]], releaseTitle: "Jubilee", listenCount: 83),
            ]
        }
        func listenActivity(username: String, period: ListeningActivityPeriod) async throws -> ListeningActivity {
            let now = Date.now
            return .init(
                period: period,
                from: now.addingTimeInterval(-7 * 86_400),
                to: now,
                lastUpdated: now,
                buckets: [
                    .init(label: "Mon", from: now.addingTimeInterval(-7 * 86_400), to: now, listenCount: 112),
                    .init(label: "Tue", from: now.addingTimeInterval(-6 * 86_400), to: now, listenCount: 176),
                    .init(label: "Wed", from: now.addingTimeInterval(-5 * 86_400), to: now, listenCount: 94),
                    .init(label: "Thu", from: now.addingTimeInterval(-4 * 86_400), to: now, listenCount: 203),
                    .init(label: "Fri", from: now.addingTimeInterval(-3 * 86_400), to: now, listenCount: 138),
                    .init(label: "Sat", from: now.addingTimeInterval(-2 * 86_400), to: now, listenCount: 232),
                    .init(label: "Sun", from: now.addingTimeInterval(-86_400), to: now, listenCount: 156),
                ]
            )
        }
        func dailyActivity(username: String, period: ListeningActivityPeriod) async throws -> DailyActivity? {
            let values = Dictionary(
                uniqueKeysWithValues: ListeningWeekday.allCases.map { weekday in
                    (
                        weekday.rawValue,
                        (0..<24).map { hour in
                            DailyActivity.Hour(hour: hour, listenCount: tasteCount(weekday: weekday, hour: hour))
                        }
                    )
                })
            return DailyActivity(
                period: period, from: .now.addingTimeInterval(-7 * 86_400), to: .now, lastUpdated: .now,
                dailyActivity: values)
        }
        func eraActivity(username: String, period: ListeningActivityPeriod) async throws -> EraActivity? {
            EraActivity(
                period: period,
                from: .now.addingTimeInterval(-365 * 86_400),
                to: .now,
                lastUpdated: .now,
                years: [
                    .init(year: 1967, listenCount: 12),
                    .init(year: 1971, listenCount: 41),
                    .init(year: 1977, listenCount: 67),
                    .init(year: 1983, listenCount: 54),
                    .init(year: 1989, listenCount: 88),
                    .init(year: 1994, listenCount: 132),
                    .init(year: 1997, listenCount: 176),
                    .init(year: 2001, listenCount: 119),
                    .init(year: 2007, listenCount: 143),
                    .init(year: 2011, listenCount: 157),
                    .init(year: 2018, listenCount: 214),
                    .init(year: 2020, listenCount: 189),
                    .init(year: 2022, listenCount: 268),
                    .init(year: 2024, listenCount: 231),
                    .init(year: 2025, listenCount: 204),
                ]
            )
        }
        func artistEvolutionActivity(
            username: String,
            period: ListeningActivityPeriod
        ) async throws -> ArtistEvolutionActivity? {
            let artistNames = ["Alvvays", "Japanese Breakfast", "The Marías", "Mitski", "Men I Trust"]
            let timeUnits: [String]
            switch period {
            case .thisWeek, .lastWeek:
                timeUnits = ListeningWeekday.allCases.map(\.rawValue)
            case .thisMonth, .lastMonth:
                timeUnits = (1...31).map(String.init)
            case .thisYear, .lastYear:
                timeUnits = ArtistEvolutionActivity.monthNames
            case .allTime:
                timeUnits = (2011...2026).map(String.init)
            }
            let yearCounts = [
                [34, 46, 39, 61, 72, 58, 84, 91, 75, 67, 88, 102],
                [21, 30, 42, 37, 55, 69, 63, 76, 82, 70, 61, 79],
                [18, 26, 19, 34, 41, 53, 49, 57, 46, 64, 72, 68],
                [28, 22, 31, 40, 36, 29, 45, 51, 59, 48, 43, 55],
                [12, 17, 24, 20, 29, 38, 35, 42, 50, 47, 58, 62],
            ]
            let rows = artistNames.enumerated().flatMap { artistIndex, name in
                timeUnits.enumerated().map { unitIndex, timeUnit in
                    let listenCount: Int
                    if period == .thisYear || period == .lastYear {
                        listenCount = yearCounts[artistIndex][unitIndex]
                    } else {
                        listenCount =
                            10
                            + ((unitIndex * (artistIndex + 2) * 7 + artistIndex * 11) % 48)
                            + unitIndex * 2
                    }
                    return ArtistEvolutionActivity.Row(
                        timeUnit: timeUnit,
                        artistMBID: artistIndex < Self.artistMBIDs.count ? Self.artistMBIDs[artistIndex] : nil,
                        artistName: name,
                        listenCount: listenCount
                    )
                }
            }
            return ArtistEvolutionActivity(
                period: period,
                from: period == .allTime
                    ? Calendar(identifier: .gregorian).date(from: DateComponents(year: 2011, month: 1, day: 1))!
                    : .now.addingTimeInterval(-365 * 86_400),
                to: .now,
                lastUpdated: .now,
                rows: rows
            )
        }
        func genreActivity(username: String, period: ListeningActivityPeriod) async throws -> GenreActivity? {
            let now = Date.now
            let rows: [GenreActivity.Row] = [
                .init(genre: "Ambient", hour: 0, listenCount: 42),
                .init(genre: "Electronic", hour: 0, listenCount: 31),
                .init(genre: "Dream Pop", hour: 2, listenCount: 38),
                .init(genre: "Shoegaze", hour: 3, listenCount: 29),
                .init(genre: "Indie Pop", hour: 7, listenCount: 51),
                .init(genre: "Alternative Rock", hour: 8, listenCount: 37),
                .init(genre: "Art Pop", hour: 10, listenCount: 28),
                .init(genre: "Neo-Psychedelia", hour: 12, listenCount: 46),
                .init(genre: "Indie Rock", hour: 14, listenCount: 63),
                .init(genre: "Synthpop", hour: 16, listenCount: 35),
                .init(genre: "Dream Pop", hour: 18, listenCount: 71),
                .init(genre: "Indie Pop", hour: 20, listenCount: 58),
                .init(genre: "Electronic", hour: 22, listenCount: 49),
                .init(genre: "Ambient", hour: 23, listenCount: 33),
            ]
            return GenreActivity(
                period: period,
                from: now.addingTimeInterval(-30 * 86_400),
                to: now,
                lastUpdated: now,
                rows: rows
            )
        }
        func artistOrigins(username: String, period: ListeningActivityPeriod) async throws -> ArtistOrigins? {
            let now = Date.now
            return ArtistOrigins(
                period: period,
                from: now.addingTimeInterval(-365 * 86_400),
                to: now,
                lastUpdated: now,
                rows: [
                    .init(
                        countryCode: "CAN", artistCount: 18, listenCount: 1_426,
                        artists: [
                            .init(mbid: Self.artistMBIDs[0], name: "Alvvays", listenCount: 612),
                            .init(mbid: nil, name: "Men I Trust", listenCount: 438),
                            .init(mbid: nil, name: "A Canadian Artist With an Especially Long Name", listenCount: 176),
                        ]
                    ),
                    .init(
                        countryCode: "USA", artistCount: 46, listenCount: 1_218,
                        artists: [
                            .init(mbid: Self.artistMBIDs[1], name: "Japanese Breakfast", listenCount: 391),
                            .init(mbid: Self.artistMBIDs[2], name: "The Marías", listenCount: 284),
                        ]
                    ),
                    .init(countryCode: "GBR", artistCount: 31, listenCount: 984, artists: []),
                    .init(countryCode: "JPN", artistCount: 22, listenCount: 731, artists: []),
                    .init(countryCode: "IND", artistCount: 15, listenCount: 654, artists: []),
                    .init(countryCode: "BRA", artistCount: 12, listenCount: 408, artists: []),
                    .init(countryCode: "KOR", artistCount: 9, listenCount: 372, artists: []),
                    .init(countryCode: "MEX", artistCount: 7, listenCount: 246, artists: []),
                    .init(countryCode: "?", artistCount: 3, listenCount: 84, artists: []),
                ]
            )
        }
        func artistActivity(username: String, period: ListeningActivityPeriod) async throws -> ArtistActivity? {
            let now = Date.now
            return ArtistActivity(period: period, from: now.addingTimeInterval(-365 * 86_400), to: now, lastUpdated: now, rows: [
                .init(creditedName: "Alvvays", canonicalName: "Alvvays", artistMBID: Self.artistMBIDs[0], listenCount: 612, albums: [
                    .init(name: "Blue Rev", releaseGroupMBID: Self.releaseMBID, listenCount: 323),
                    .init(name: "Antisocialites", releaseGroupMBID: nil, listenCount: 118),
                    .init(name: "Alvvays", releaseGroupMBID: nil, listenCount: 76),
                    .init(name: "Adult Diversion", releaseGroupMBID: nil, listenCount: 31),
                    .init(name: "Dreams Tonite", releaseGroupMBID: nil, listenCount: 24),
                    .init(name: "Belinda Says", releaseGroupMBID: nil, listenCount: 18),
                    .init(name: "Pharmacist", releaseGroupMBID: nil, listenCount: 13),
                    .init(name: "Archie, Marry Me", releaseGroupMBID: nil, listenCount: 9)
                ]),
                .init(creditedName: "Japanese Breakfast", canonicalName: nil, artistMBID: Self.artistMBIDs[1], listenCount: 391, albums: [
                    .init(name: "Jubilee", releaseGroupMBID: nil, listenCount: 287), .init(name: "Soft Sounds from Another Planet", releaseGroupMBID: nil, listenCount: 104)]),
                .init(creditedName: "The Marías", canonicalName: "The Marías", artistMBID: Self.artistMBIDs[2], listenCount: 284, albums: [.init(name: "Submarine", releaseGroupMBID: nil, listenCount: 284)])
            ])
        }
        func freshReleases(username: String, scope: FreshReleaseScope) async throws -> [FreshRelease] {
            try await freshReleases(username: username, query: .default(for: scope))
        }

        func freshReleases(username: String, query: FreshReleaseQuery) async throws -> [FreshRelease] {
            let releases: [FreshRelease] = [
                .init(
                    releaseMBID: UUID(uuidString: "f0000000-0000-4000-8000-000000000001"),
                    releaseGroupMBID: UUID(uuidString: "f1000000-0000-4000-8000-000000000001"),
                    title: "The Long Way Home",
                    artistName: "Japanese Breakfast",
                    artistMBIDs: [Self.artistMBIDs[1]],
                    releaseDate: Self.freshReleaseDate(dayOffset: 4),
                    primaryType: "Album",
                    secondaryType: nil,
                    tags: ["indie pop", "dream pop"],
                    confidence: 0.96,
                    listenCount: 2_841,
                    artworkReleaseMBID: nil,
                    sourcePosition: 0
                ),
                .init(
                    releaseMBID: UUID(uuidString: "f0000000-0000-4000-8000-000000000002"),
                    releaseGroupMBID: UUID(uuidString: "f1000000-0000-4000-8000-000000000002"),
                    title: "Night Drive",
                    artistName: "The Marías",
                    artistMBIDs: [Self.artistMBIDs[2]],
                    releaseDate: Self.freshReleaseDate(dayOffset: 10),
                    primaryType: "EP",
                    secondaryType: nil,
                    tags: ["dream pop", "indie pop"],
                    confidence: 0.88,
                    listenCount: 1_704,
                    artworkReleaseMBID: nil,
                    sourcePosition: 1
                ),
                .init(
                    releaseMBID: UUID(uuidString: "f0000000-0000-4000-8000-000000000003"),
                    releaseGroupMBID: UUID(uuidString: "f1000000-0000-4000-8000-000000000003"),
                    title: "Blue Rev: Live at Massey Hall",
                    artistName: "Alvvays",
                    artistMBIDs: [Self.artistMBIDs[0]],
                    releaseDate: Self.freshReleaseDate(dayOffset: -2),
                    primaryType: "Album",
                    secondaryType: "Live",
                    tags: ["indie rock", "live"],
                    confidence: 0.79,
                    listenCount: 986,
                    artworkReleaseMBID: nil,
                    sourcePosition: 2
                ),
                .init(
                    releaseMBID: nil,
                    releaseGroupMBID: UUID(uuidString: "f1000000-0000-4000-8000-000000000004"),
                    title: "A Very Long Release Title for Small-Screen Layout Inspection",
                    artistName: "Fixture Ensemble",
                    artistMBIDs: [],
                    releaseDate: Self.freshReleaseDate(dayOffset: -5),
                    primaryType: "Single",
                    secondaryType: nil,
                    tags: ["electronic", "ambient"],
                    confidence: 0.64,
                    listenCount: 412,
                    artworkReleaseMBID: nil,
                    sourcePosition: 3
                ),
                .init(
                    releaseMBID: nil,
                    releaseGroupMBID: nil,
                    title: "Unmapped Morning",
                    artistName: "Community Radio",
                    artistMBIDs: [],
                    releaseDate: Self.freshReleaseDate(dayOffset: 7),
                    primaryType: "EP",
                    secondaryType: nil,
                    tags: ["ambient"],
                    confidence: 0.42,
                    listenCount: 83,
                    artworkReleaseMBID: nil,
                    sourcePosition: 4
                ),
            ]

            return releases.filter { release in
                (query.includesPast && !release.isUpcoming)
                    || (query.includesUpcoming && release.isUpcoming)
            }
        }
        func submitFeedback(_ feedback: RecordingFeedback, for recording: Recording) async throws {}

        private static func freshReleaseDate(dayOffset: Int) -> String {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .autoupdatingCurrent
            let date = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: .now)) ?? .now
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: date)
        }

        private func tasteCount(weekday: ListeningWeekday, hour: Int) -> Int {
            let weekdayOffset = ListeningWeekday.allCases.firstIndex(of: weekday) ?? 0
            if (19...23).contains(hour) { return 5 + ((weekdayOffset * 3 + hour) % 12) }
            if (12...15).contains(hour) { return 1 + ((weekdayOffset + hour) % 5) }
            return (weekdayOffset + hour).isMultiple(of: 11) ? 2 : 0
        }
    }
#endif

private struct MiniListenBar: View {
    let listen: Listen
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ArtworkView(url: listen.recording.artworkURL, title: listen.recording.title, cornerRadius: 7)
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(listen.recording.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(listen.recording.artistName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "waveform")
                    .foregroundStyle(AppTheme.accent)
                    .symbolEffect(.variableColor.iterative)
                Image(systemName: "chevron.up")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Playing now: \(listen.recording.title) by \(listen.recording.artistName)")
        .contextMenu {
            ExternalMediaDestinationActions.menuItems(listen.recording.externalMediaLinks)
        }
    }
}
