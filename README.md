# Brainz for iOS

Brainz is a native SwiftUI client for exploring a ListenBrainz user's listening history, taste, discovery graph, and music identity. The project is a growing Phase 3 implementation: it connects to real ListenBrainz data and prioritizes a polished read experience before playback and scrobbling work.

## Current vertical slice

- Token authentication with Keychain storage, or read-only public-profile browsing
- Playing Now and recent-listening home screen
- Paginated, date-grouped history with exact local-day navigation and adjacent-day browsing
- Recording and artist detail views
- Global ListenBrainz listen/listener context on canonical artist, recording, release, and release-group pages
- Listen count and top artist, album, and recording rankings
- Server-calculated listening-activity charts, a selectable 7×24 UTC listening heatmap, local-daypart Genre Activity, Music by Decade with year drill-down, and on-demand Artist Evolution across seven ListenBrainz periods
- A native 2025 Year in Music story with totals, annual listening calendar, artist/album/track rankings, entity navigation, canonical report sharing, and explicit official-artwork PNG preview/sharing
- Fresh Releases discovery with deliberate personalized and sitewide scopes
- Native LB Radio recipe generation from listening history, unheard recommendations, artists, tags, or advanced Troi prompts, with one batched metadata enrichment and honest browse-only playback state
- For You recording recommendations with native feedback, plus Daily/Weekly generated playlists
- Music-first My Feed, Following, and Similar listening feeds with cached pagination, thanks, hide/unhide, and owner deletion
- Native user search, visited-user profiles, followers/following, similar listeners, and compatibility
- Pin history and owner pin actions; public playlist search and complete playlist detail
- Lazy owned and collaborating Profile playlists with privacy-aware caching, server pagination, and direct detail navigation
- Canonical MusicBrainz edition pages with release-group links and ordered, multi-disc track lists
- Recording feedback for authenticated users
- Public and multi-recipient personal recording recommendations, with follower-only selection and optional 280-character notes
- Cached snapshots for useful cold starts and degraded-network behavior
- Native iPhone/iPad navigation, Dynamic Type, dark mode, VoiceOver labels, and an iOS 26 bottom accessory with an iOS 18 fallback

## Requirements

- Xcode 27 or newer
- iOS 18 or newer
- XcodeGen 2.44 or newer to regenerate the project

Generate and open the project:

```sh
nix shell nixpkgs#xcodegen -c xcodegen generate
open ListenBrainzNative.xcodeproj
```

No token or secret belongs in source control. For authenticated use, copy the user token from ListenBrainz settings into the app; it is stored in the system Keychain.

## Project structure

- `App/`: native presentation, app-facing domain models, provider boundary, persistence, and feature state
- `Packages/ListenBrainzKit/`: vendored MPL-2.0 API package with focused local repairs
- `docs/research/`: feature, KMP, API-wrapper, donor, licensing, and phased implementation research
- `project.yml`: authoritative XcodeGen project definition

The SwiftUI presentation depends on the small `ListeningProvider` boundary rather than on API-library types. This keeps today's implementation straightforward while preserving a path to adopt stronger official Kotlin Multiplatform domain logic later without replacing the native UI.

## Research and provenance

This repository follows an inspect-first, reuse-first workflow. Start with:

- `docs/research/implementation-plan.md`
- `docs/research/listenbrainz-feature-map.md`
- `docs/research/listenbrainzkit-gap-analysis.md`
- `docs/research/lb-radio.md`
- `docs/research/kmp-status.md`
- `docs/research/repo-reuse-map.md`
- `docs/research/license-map.md`
- `THIRD_PARTY.md`

Temporary clones, installed tooling, and cleanup instructions are recorded in `docs/research/environment-changes.md`.

Spotify-linked in-app playback through a libspot/librespot-family implementation is deliberately deferred until the core read experience is complete. If pursued, it will begin only on a separate branch after the exact project, license, Spotify policy, authentication, maintenance, and App Store implications are audited.

## License

Brainz is licensed under the Mozilla Public License 2.0. See `LICENSE` and `THIRD_PARTY.md`.
