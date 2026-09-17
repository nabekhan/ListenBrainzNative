# Official Kotlin Multiplatform status

Snapshot: 2026-09-16, Android checkout `3a0e4ef`.

## What is shared now

- `shared/src/commonMain` is substantial (278 files): Ktor/Ktorfit networking, serialization, repositories, models, resources/errors, Koin DI, Room/SQLite, DataStore, sockets, paging, metadata, listens, users, social/feed, playlists, recommendations, stats, pins, and some Compose code.
- Service coverage includes recent/Playing Now/submit/delete, listen count and similarity, pins and feedback, user/sitewide activity, Created For You, followers/following, recommendations/reviews, full playlist mutation, feed actions, MusicBrainz search, CritiqueBrainz, and Cover Art Archive.
- `androidMain` (14 files) and `iosMain` (12 files) supply platform clients, persistence factories, file/image/log utilities, preferences, listen repository details, and remote-playback adapters.

## iOS target and export reality

- Gradle defines `iosArm64` and `iosSimulatorArm64` frameworks named `sharedKit`; there is no Intel simulator target.
- Room KSP is configured for both iOS targets, indicating intent to compile the database layer.
- No checked-in XCFramework, Swift wrapper, generated API guide, sample iOS consumer, or native iOS app integration exists in the Android repository.
- The shared graph includes Compose UI, Koin, Room, Ktorfit, paging, sockets, Coil, and palette dependencies. That makes binary size, build integration, Swift API ergonomics, and lifecycle behavior materially more complex than ListenBrainzKit.
- Framework compilation/export could not be independently verified before full Xcode became available; it remains a follow-up build check.

## Still Android-specific

- Navigation and nearly all product UI.
- Notification-listener/media-session automatic scrobbling.
- Foreground BrainzPlayer service, ExoPlayer, MediaSessionCompat, and notifications.
- Spotify App Remote, YouTube intents, app updates, WorkManager/background scheduling, and Android permission flows.
- Some Year in Music and app-update view models/services remain in the app module.

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

Ship native SwiftUI over an app-facing provider using the fixed Swift package now. Keep provider models independent from both LBKit and KMP. Re-evaluate KMP only when MetaBrainz publishes a stable XCFramework, documents Swift interop, demonstrates an iOS consumer, and can be adopted per domain without pulling the full Compose/app graph.

Evidence: `References/listenbrainz-android/shared/build.gradle.kts`, `shared/src/{commonMain,androidMain,iosMain}`, and official iOS/Android application source.

