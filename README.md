# Brainz for iOS

Brainz is a native SwiftUI client for exploring a ListenBrainz user's listening history, taste, discovery graph, and music identity. The project is a growing Phase 3 implementation: it connects to real ListenBrainz data and prioritizes a polished read experience before playback and scrobbling work.

## Current vertical slice

- Guided web-assisted ListenBrainz sign-in with device-only Keychain storage, a manual-token fallback, or read-only public-profile browsing
- Playing Now and recent-listening home screen
- Paginated, date-grouped history with exact local-day navigation and adjacent-day browsing
- Safe authenticated listen deletion with explicit confirmation, asynchronous-status copy, and a durable no-replay barrier for uncertain outcomes
- Native manual MusicBrainz matching from Listen Details, with an explicit saved-match check, recording search, side-by-side review, submitted-ID precedence, and a one-shot no-retry save
- Recording and artist detail views
- Zero-request **Listen elsewhere** actions for strict canonical service links already embedded in ListenBrainz metadata; one service opens directly and multiple services use one native menu
- Global ListenBrainz listen/listener context on canonical artist, recording, release, and release-group pages
- Listen count and top artist, album, and recording rankings
- Server-calculated listening-activity charts, a selectable 7×24 UTC listening heatmap, local-daypart Genre Activity, Music by Decade with year drill-down, and on-demand Artist Evolution across seven ListenBrainz periods
- A native 2025 Year in Music story with totals, annual listening calendar, artist/album/track rankings, entity navigation, canonical report sharing, and explicit official-artwork PNG preview/sharing
- A request-free top-album collage editor with native layout, order, background, caption, preview, and PNG sharing controls
- Fresh Releases discovery with deliberate personalized and sitewide scopes
- Native LB Radio recipe generation from listening history, unheard recommendations, artists, tags, or advanced Troi prompts, with one batched metadata enrichment and honest browse-only playback state
- For You recording recommendations with native feedback, plus Daily/Weekly generated playlists
- Music-first My Feed, Following, and Similar listening feeds with cached pagination, thanks, hide/unhide, and owner deletion
- Native single-page user search plus explicit paginated artist, album, track, and public-playlist search, with cancellation, bounded caching, and no speculative loading
- Visited-user profiles, followers/following, similar listeners, and compatibility
- Pin history and owner pin actions; complete playlist detail
- Request-free export of an already-loaded playlist as a bounded, protected JSPF JSON file, with private-playlist disclosure before sharing
- Lazy owned and collaborating Profile playlists with privacy-aware caching, server pagination, authenticated empty-playlist creation, owner metadata/privacy editing, and direct detail navigation
- Safe append from Recording Detail to owned or collaborating playlists, with canonical-MBID gating, duplicate confirmation, and no automatic mutation replay
- Authenticated duplication of any visible playlist, with a fresh source preflight, canonical returned-copy navigation, and a durable no-replay barrier for ambiguous responses
- Canonical MusicBrainz edition pages with release-group links and ordered, multi-disc track lists
- Authenticated recording feedback actions plus a public, lazy Loved/Hated library on own and visited profiles
- Native public CritiqueBrainz review publishing from Artist, Recording, and Release Group pages, with optional rating, language selection, explicit licensing consent, and durable duplicate-safe recovery
- Public and multi-recipient personal recording recommendations, with follower-only selection and optional 280-character notes
- Cached snapshots for useful cold starts and degraded-network behavior
- Shared, size-managed cover-art loading with request coalescing, cancellation, and a credential-free offline cache
- Native Profile-launched Settings with local System/Light/Dark appearance, lazy Connected Services, secure ListenBrainz account and privacy handoffs, project information, and transparent disconnect controls
- Native iPhone/iPad navigation, Dynamic Type, dark mode, VoiceOver labels, and an iOS 26 bottom accessory with an iOS 18 fallback
- Semantic right-to-left navigation plus a credential-free iPad UI regression suite covering portrait, rotation, RTL, and expanded pseudo-localization under a fail-fast request guard

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

No token or secret belongs in source control. For authenticated use, follow the in-app official web sign-in flow or use the manual-token fallback; the resulting token is stored in the system Keychain.

## Project structure

- `App/`: native presentation, app-facing domain models, provider boundary, persistence, and feature state
- `Packages/ListenBrainzKit/`: vendored MPL-2.0 API package with focused local repairs
- `docs/research/`: feature, KMP, API-wrapper, donor, licensing, and phased implementation research
- `project.yml`: authoritative XcodeGen project definition

The SwiftUI presentation depends on the small `ListeningProvider` boundary rather than on API-library types. This keeps today's implementation straightforward while preserving a path to adopt stronger official Kotlin Multiplatform domain logic later without replacing the native UI.

## Localization

The app uses exactly one translator-facing source of truth: `App/Resources/Localizable.xcstrings`. Every app-authored production UI string has an explicit editable English value there, so product copy can be revised or translated in one file. SwiftUI literals are compiler-extracted, while reusable components use `LocalizedStringResource` and rendered model copy uses `String(localized:)` so text does not disappear behind ordinary `String` boundaries. The production UI has been audited for this contract, and the helper rejects extra catalogs, missing or stale keys, empty English values, and common bypass patterns. Server responses, usernames, music metadata, identifiers, URLs, technical constants, and test fixtures remain verbatim rather than becoming translation keys.

After adding or changing interface copy, update and verify the production catalog:

```sh
scripts/localizations.sh sync
scripts/localizations.sh check
```

Both modes perform a Release extraction with Xcode and use `jq` to preserve explicit editable English values and remove compiler-marked stale keys. `check` works on a temporary copy and fails if the committed catalog has missing or stale production keys; DEBUG-only fixture copy is excluded. If `jq` is not installed, run either command through `nix shell nixpkgs#jq -c`.

## Sideload IPA

Build and validate an unsigned, re-signable device IPA:

```sh
scripts/package-ipa.sh
```

The default output is `dist/Brainz-<version>-<build>-unsigned.ipa`. The script checks the arm64 executable, bundle metadata, icons, launch screen, privacy manifest, unsigned state, exact `Payload/Brainz.app` layout, ZIP integrity, and deterministic packaging from the same archive.

The generated IPA is **not directly installable**. A compatible external signer must add the provisioning profile, entitlements, and signature before sideloading. Do not commit signing credentials, profiles, or generated IPAs. See `docs/research/sideload-readiness.md` for the signing boundary and remaining physical-device checks.

## Guarded simulator UI matrix

Run the deterministic fixture matrix against explicit existing simulators only:

```sh
scripts/test-ui-matrix.sh \
  --iphone-udid <IPHONE_SIMULATOR_UDID> \
  --ipad-udid <IPAD_SIMULATOR_UDID>
```

Pass `--output-root /absolute/path` to retain results somewhere specific. The script refuses an existing output directory, builds test products once, and retains three separate XCResult bundles: the full guarded iPhone fixture suite, the established six-test iPad responsive/RTL/pseudo-localization subset, and a focused dark-mode maximum-Dynamic-Type iPhone subset. It always excludes the opt-in live MetaBrainz sign-in route and each fixture denies shared request-gate transport, so it is credential-free and fails before any guarded ListenBrainz transport. That guard does not claim to intercept arbitrary future networking outside the required gate; fixture data and artwork must remain local when new cases are added.

The matrix temporarily boots supplied simulators when needed, sets their appearance and content size, verifies those settings, then restores the original appearance, Dynamic Type category, and boot/shutdown state on normal exit or interruption. It does not replace physical-device, signed-build, real-authentication, or translated-language QA.

## Opt-in authenticated simulator smoke test

The repository includes one intentionally skipped, read-only production smoke test: `ReleaseLayoutUITests/testOptInLiveAuthenticationSmokeIsReadOnlyAndRestoresSession`. It is excluded unless the UI-test runner has `BRAINZ_LIVE_AUTH_SMOKE=1`. Before running it, copy a disposable ListenBrainz token directly into the target simulator clipboard. The test opens the normal app, uses the system Paste menu when signed out, visits only Home, History, Discover, Taste, and Profile, then relaunches once to verify the Keychain-backed session restores. It does not press refresh, feedback, pin, follow, playlist, deletion, or submission controls.

Do not put a token in launch arguments, environment variables, scripts, source, screenshots, or XCResult attachments. An optional `BRAINZ_LIVE_EXPECTED_USERNAME` runner environment value can verify the signed-in account; it is not required for the smoke test. A live XCResult can contain UI metadata and must be treated as temporary private test evidence, then removed rather than committed or shared.

The smoke test clears the simulator pasteboard immediately after using Paste and again on exit. If the Mac clipboard was used to transfer the token, clear it immediately after provisioning and verify both clipboards before and after the run:

```sh
: | pbcopy
test "$(pbpaste | wc -c | tr -d ' ')" = 0
: | xcrun simctl pbcopy <SIMULATOR_UDID>
test "$(xcrun simctl pbpaste <SIMULATOR_UDID> | wc -c | tr -d ' ')" = 0
```

Launch the one test through Xcode or an explicit simulator destination after provisioning the clipboard. While it runs, inspect only the sanitized DEBUG lifecycle stream with:

```sh
xcrun simctl spawn <SIMULATOR_UDID> log stream --style compact --level debug \
  --predicate 'subsystem == "dev.nabekhan.listenbrainznative" AND category == "request-audit"'
```

The test launches the app with `-brainz-request-audit`. Those DEBUG records contain only an endpoint-family label, lifecycle, aggregate counts, and read/mutation concurrency. They intentionally omit tokens, usernames, request identity components, URLs, queries, payloads, and response data. The deterministic fixture matrix remains credential-free and does not run this test.

After retaining the evidence you need, run the separately guarded `testOptInLiveAuthenticationCleanupRemovesLocalSession` with `BRAINZ_LIVE_AUTH_CLEANUP=1` and the exact expected account in `BRAINZ_LIVE_EXPECTED_USERNAME`. The identity assertion runs before the destructive confirmation. The test uses the app's normal disconnect flow to remove only that simulator's saved credential and private local data, then confirms a relaunch stays signed out. It does not change the ListenBrainz account or server-side music data.

## Research and provenance

This repository follows an inspect-first, reuse-first workflow. Start with:

- `docs/research/development-handoff.md`
- `docs/research/implementation-plan.md`
- `docs/research/localization.md`
- `docs/research/app-store-readiness.md`
- `docs/research/sideload-readiness.md`
- `docs/research/listenbrainz-feature-map.md`
- `docs/research/listenbrainzkit-gap-analysis.md`
- `docs/research/playlist-export.md`
- `docs/research/playlist-mutations.md`
- `docs/research/listen-deletion.md`
- `docs/research/request-policy.md`
- `docs/research/lb-radio.md`
- `docs/research/kmp-status.md`
- `docs/research/repo-reuse-map.md`
- `docs/research/license-map.md`
- `THIRD_PARTY.md`

The public data-handling summary is in [`PRIVACY.md`](PRIVACY.md).

Temporary clones, installed tooling, and cleanup instructions are recorded in `docs/research/environment-changes.md`.

Spotify-linked in-app playback through a libspot/librespot-family implementation is deliberately deferred until the core read experience is complete. If pursued, it will begin only on a separate branch after the exact project, license, Spotify policy, authentication, maintenance, and App Store implications are audited.

## License

Brainz is licensed under the Mozilla Public License 2.0. See `LICENSE` and `THIRD_PARTY.md`.
