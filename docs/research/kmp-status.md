# Official Kotlin Multiplatform status

Snapshot: 2026-09-18, Android checkout `3a0e4ef`.

## What is shared now

- `shared/src/commonMain` is substantial (278 files): Ktor/Ktorfit networking, serialization, repositories, models, resources/errors, Koin DI, Room/SQLite, DataStore, sockets, paging, metadata, listens, users, social/feed, playlists, recommendations, stats, pins, and some Compose code.
- Service coverage includes recent/Playing Now/submit/delete, listen count and similarity, pins and feedback, user/sitewide activity, Created For You, followers/following, recommendations/reviews, full playlist mutation, feed actions, MusicBrainz search, CritiqueBrainz, Cover Art Archive, and larger artist/album payloads carrying popularity context.
- `ArtistService` and `ArtistPayload` already model the public `POST artist/{artist_mbid}` page response, including artist identity, `coverArt`, all-time `listeningStats`/top listeners, `popularRecordings`, popularity-ranked `releaseGroups`, and ranked `similarArtists`. The shared `ArtistViewModel` projects those fields into one screen state. This confirms that one response should own the native artist page, but the response is a broad internal page contract rather than a small documented API and does not justify importing the KMP framework for it.
- `androidMain` (14 files) and `iosMain` (12 files) supply platform clients, persistence factories, file/image/log utilities, preferences, listen repository details, and remote-playback adapters.

## iOS target and export reality

- Gradle defines `iosArm64` and `iosSimulatorArm64` frameworks named `sharedKit`; there is no Intel simulator target.
- Room KSP is configured for both iOS targets, indicating intent to compile the database layer.
- No checked-in XCFramework, Swift wrapper, generated API guide, sample iOS consumer, or native iOS app integration exists in the Android repository.
- The shared graph includes Compose UI, Koin, Room, Ktorfit, paging, sockets, Coil, and palette dependencies. That makes binary size, build integration, Swift API ergonomics, and lifecycle behavior materially more complex than ListenBrainzKit.
- Framework compilation/export was attempted under Xcode 27 with the repository's current Gradle 9.4.1 wrapper and JDK 17. `linkDebugFrameworkIosSimulatorArm64` fails in `kspKotlinIosSimulatorArm64`: Room rejects multiple non-suspending DAO methods in `PendingListensDao`, `SongDao`, `AlbumDao`, and `ArtistDao` for a non-Android target. No `sharedKit` framework was produced.
- The same build reports incompatible Skiko versions between Coil (`0.9.22.2`) and resolved Compose/Skiko (`0.144.6`), another current iOS-integration risk even after the Room errors are addressed.

## Still Android-specific

- Navigation and nearly all product UI.
- Notification-listener/media-session automatic scrobbling.
- Foreground BrainzPlayer service, ExoPlayer, MediaSessionCompat, and notifications.
- Spotify App Remote, YouTube intents, app updates, WorkManager/background scheduling, and Android permission flows.
- Some Year in Music and app-update view models/services remain in the app module.
- Shared KMP currently exposes authenticated playlist-art transport/repository logic, but no generic stats-grid or artist-grid domain API. The native app therefore keeps the smaller typed Swift extension behind its provider boundary; KMP remains a behavior reference for playlist art rather than an iOS dependency.
- Shared KMP does not currently expose a manual-mapping transport or native-ready workflow. The app therefore reuses the existing Swift ListenBrainzKit POST and keeps candidate search, precedence, and recovery behavior behind its app-facing provider.

## UI migration status

The KMP module uses Compose dependencies and has migrated meaningful supporting UI/state, but it is not a ready-made native iOS domain SDK. The official Android app remains the mature behavioral reference; the separate official SwiftUI client does not consume `sharedKit`.

## ListenBrainzKit comparison

| Dimension | ListenBrainzKit | Official KMP shared |
|---|---|---|
| Coverage | Narrower, strong P0 core | Broad social/playlist/feed/domain coverage |
| Swift use | Native typed Swift API | Generated Obj-C/Swift bridge, unproven ergonomics |
| Build weight | Small SwiftPM package | Large Gradle/KMP graph |
| Persistence/caching | Minimal | Room/DataStore repositories |
| Current defects | URL/User-Agent/rate-policy fixes needed | Packaging/integration/maturity unverified |
| UI coupling | None | Includes Compose dependencies |
| Best role now | P0 Swift API foundation | Behavior reference/future selective domain source |

## Recommendation

Ship native SwiftUI over an app-facing provider using the fixed Swift package now. Keep provider models independent from both LBKit and KMP. The current upstream shared module demonstrably does not link for the iOS Simulator without source changes, so it cannot be a present dependency. Re-evaluate only when MetaBrainz publishes a stable XCFramework, fixes the native Room/Skiko build, documents Swift interop, demonstrates an iOS consumer, and can be adopted per domain without pulling the full Compose/app graph.

Creator-only playlist deletion follows that division: the app uses a small typed ListenBrainzKit empty-body request today, while app-owned Swift code supplies the durable no-replay barrier, privacy-safe cache invalidation, and native recovery UI. The official KMP implementation remains behavior evidence and a future replacement candidate, not an iOS build dependency.

Playlist item movement reaches the same conclusion. Shared KMP already models the official positional move route and helped confirm product behavior, but importing the unbuildable full shared graph would be disproportionate to one request. The app therefore uses a small typed MPL-preserving ListenBrainzKit extension; app-owned Swift retains the non-atomic-operation safeguards, whole-order reconciliation, request budget, and native reorder sheet behind provider boundaries that can accept a future official implementation.

Playlist item deletion's shared request model already carries `index` and `count`, but the current official Android ViewModel and UI always submit `count: 1`; the website also deletes one row at a time. The native app consumes the stable server count contract through its smaller Swift transport and exposes only one contiguous range per explicit action, with app-owned preflight, no-replay, and postflight safeguards. This does not justify importing the currently unbuildable shared framework.

Evidence: `References/listenbrainz-android/shared/build.gradle.kts`, `shared/src/{commonMain,androidMain,iosMain}`, and official iOS/Android application source.
