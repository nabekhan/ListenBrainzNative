# Brainz for iOS

Brainz is a native SwiftUI client for exploring a ListenBrainz user's listening history, taste, discovery graph, and music identity. The project is a growing Phase 3 implementation: it connects to real ListenBrainz data and prioritizes a polished read experience before playback and scrobbling work.

## Current vertical slice

- Token authentication with Keychain storage, or read-only public-profile browsing
- Playing Now and recent-listening home screen
- Paginated, date-grouped history with exact local-day navigation and adjacent-day browsing
- Safe authenticated listen deletion with explicit confirmation, asynchronous-status copy, and a durable no-replay barrier for uncertain outcomes
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
- Lazy owned and collaborating Profile playlists with privacy-aware caching, server pagination, authenticated empty-playlist creation, owner metadata/privacy editing, and direct detail navigation
- Safe append from Recording Detail to owned or collaborating playlists, with canonical-MBID gating, duplicate confirmation, and no automatic mutation replay
- Authenticated duplication of any visible playlist, with a fresh source preflight, canonical returned-copy navigation, and a durable no-replay barrier for ambiguous responses
- Canonical MusicBrainz edition pages with release-group links and ordered, multi-disc track lists
- Recording feedback for authenticated users
- Public and multi-recipient personal recording recommendations, with follower-only selection and optional 280-character notes
- Cached snapshots for useful cold starts and degraded-network behavior
- Native iPhone/iPad navigation, Dynamic Type, dark mode, VoiceOver labels, and an iOS 26 bottom accessory with an iOS 18 fallback

## Requirements

- Xcode 27 or newer
- iOS 18 or newer
- XcodeGen 2.44 or newer to regenerate the project
- `jq` 1.7 or newer for the localization sync/check helper

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

## Localization

The app uses one translator-facing source of truth: `App/Resources/Localizable.xcstrings`. It stores an explicit editable English value for every production key, so product copy can be revised or translated in one file. SwiftUI literals are compiler-extracted, while reusable components use `LocalizedStringResource` and rendered model copy uses `String(localized:)` so text does not disappear behind ordinary `String` boundaries. The production UI has been audited for this contract, and the helper rejects common bypass patterns. Server responses, usernames, music metadata, identifiers, and test fixtures remain verbatim rather than becoming translation keys.

After adding or changing interface copy, update and verify the production catalog:

```sh
scripts/localizations.sh sync
scripts/localizations.sh check
```

Both modes perform a Release extraction with Xcode and use `jq` to preserve explicit editable English values and remove compiler-marked stale keys. `check` works on a temporary copy and fails if the committed catalog has missing or stale production keys; DEBUG-only fixture copy is excluded. If `jq` is not installed, run either command through `nix shell nixpkgs#jq -c`.

## Research and provenance

This repository follows an inspect-first, reuse-first workflow. Start with:

- `docs/research/development-handoff.md`
- `docs/research/implementation-plan.md`
- `docs/research/localization.md`
- `docs/research/listenbrainz-feature-map.md`
- `docs/research/listenbrainzkit-gap-analysis.md`
- `docs/research/playlist-mutations.md`
- `docs/research/listen-deletion.md`
- `docs/research/request-policy.md`
- `docs/research/lb-radio.md`
- `docs/research/kmp-status.md`
- `docs/research/repo-reuse-map.md`
- `docs/research/license-map.md`
- `THIRD_PARTY.md`

Temporary clones, installed tooling, and cleanup instructions are recorded in `docs/research/environment-changes.md`.

Spotify-linked in-app playback through a libspot/librespot-family implementation is deliberately deferred until the core read experience is complete. If pursued, it will begin only on a separate branch after the exact project, license, Spotify policy, authentication, maintenance, and App Store implications are audited.

## License

Brainz is licensed under the Mozilla Public License 2.0. See `LICENSE` and `THIRD_PARTY.md`.
