# Development handoff

Snapshot: 2026-09-25.

## Portable checkpoint

- Branch: `main`
- Last validated product commit: `c95559c959361fac2f1c93b8b6a706bcf1a4098f`
- Remote: `https://github.com/nabekhan/ListenBrainzNative.git`
- Remote `main` is verified after this handoff note is pushed.
- No change in this checkpoint is partially applied. The explicit saved-manual-mapping lookup and strengthened production-localization boundary are complete for the audited source.

Listen Details remains request-free on open. An authenticated historical listen with a recording MSID now offers **Check saved match**; only that tap admits one credential-scoped, exact-request-coalesced `get_manual_mapping` read through the bounded shared lane. The canonical trailing-slash request has a 64 KiB response ceiling, treats 404 as no saved match, maps 401 to account recovery, shares server-directed 429 deferral, and never polls or automatically retries. Terminal results suppress another request. A confirmed manual-mapping save invalidates any older in-flight lookup generation, and a submitted recording MBID may coexist with a visible saved mapping without falsely claiming that refresh will override the submitted identifier.

The translator-facing source remains only `App/Resources/Localizable.xcstrings`. Compiler-backed Release extraction, explicit editable English values, stale-key removal, and the guarded sync/check helper now scan all of `App` for high-confidence ordinary-`String` escapes, including literal `Text(verbatim:)` and direct `LocalizedStringKey` construction. Server/user/music metadata and DEBUG fixtures remain verbatim and outside the production catalog.

Final evidence:

- the single catalog contains 1,579 exact Release-extracted keys, has no empty or stale key, and gives every key an explicit English value;
- `scripts/localizations.sh check` rebuilt both simulator architectures and confirmed the committed catalog matches production compiler output;
- the focused mapping suite passed 24/24 and the complete app suite passed 608/608 with no failure, skip, or runtime warning; the complete vendored Kit passed 146/146 while its token-dependent and opt-in live tests remained skipped;
- the generic Release simulator build succeeded with `x86_64` and `arm64` slices;
- local-only idle and saved fixtures were inspected in light, dark, normal, and maximum-Dynamic-Type layouts; the accepted fixture suppresses remote artwork and scoped logs contain no service hostname, HTTP response, or fatal failure; and
- independent correctness and security re-reviews report READY.

The fixtures use an injected local lookup provider, fake token, and no remote artwork. QA therefore made no production request or mutation. Current API/docs and server source supplied contract and precedence evidence only; no GPL source or UI was copied. The MPL-covered Kit changes expose the existing response identifiers and harden only the lookup's path, response bound, and status mapping.

## Resume on another Mac

Requirements and project generation remain authoritative in the root `README.md` and tracked `project.yml`.

```sh
git clone https://github.com/nabekhan/ListenBrainzNative.git
cd ListenBrainzNative
nix shell nixpkgs#xcodegen -c xcodegen generate
open ListenBrainzNative.xcodeproj
```

Install Xcode and a compatible iOS simulator runtime before building. Reinstall the MIT `content-designer/ux-writing-skill` before adding or revising user-facing strings. Donor clones can be recreated from the URLs recorded in the research documents; do not copy local build products, simulator devices, or credentials. No ListenBrainz token or other secret is stored in the repository.

## Next product work

Keep new app-authored copy on the existing catalog path and let the boundary guard fail closed on common ordinary-`String` escapes. Before shipping the first non-English locale, consolidate count strings into catalog plural variants and test dates, durations, possessives, capitalization, right-to-left layout, Dynamic Type, screenshots, and real translations with native-language review.

Keep noncontiguous multi-track deletion and multi-track moves withheld unless the server gains an atomic operation that avoids replaying several positional mutations against a changing playlist.

Keep saved-match lookup explicit. It must not become an automatic details-screen read, lifecycle refresh, poll, or retry; submitted recording MBID precedence must remain visible and truthful.

Album collage intentionally starts with already-loaded canonical top releases. Arbitrary MusicBrainz search/addition remains separate because it would introduce a new search and identity-resolution request path; do not add it implicitly to draft editing.

Playback/content resolution, MusicKit capture, and Spotify-linked playback remain deliberately separate. Any libspot/librespot experiment starts only on its own branch after the core product is complete and after policy, licensing, account-security, App Store, and maintenance implications are reviewed.

## Local cleanup

The 2026-09-22 portable cleanup removed prior donor clones, browser tooling, builds, runtimes, skill installation, simulators, and other disposable artifacts. Xcode 27, the iOS 27 runtime, and the UX-writing skill remain available. This checkpoint's three project build directories, package build cache, result bundles, logs, and screenshots were moved through the dedicated `Brainz-Saved-Match-20260925-1829` Trash bucket; that bucket alone was permanently deleted file-by-file, reclaiming 1.4 GB without touching unrelated Trash. `Brainz Saved Match QA` (`DF5AEA7F-990F-4989-BAE1-0A54A0F21141`) was terminated, shut down, and deleted. An exact audit found no matching artifact, bucket, or simulator afterward.

The source checkout, Git history, tracked Xcode project, `project.yml`, Apple Command Line Tools, shared Nix store, pre-existing developer data, user settings, credentials, personal files, and unrelated Trash contents remain preserved. Exact artifact paths and cleanup commands are recorded in `environment-changes.md`.
