# Development handoff

Snapshot: 2026-09-25.

## Portable checkpoint

- Branch: `main`
- Last validated product commit: `c14776176ff7c215f83bb15afdcff400abb1c7b3`
- Remote: `https://github.com/nabekhan/ListenBrainzNative.git`
- Remote `main` is verified after this handoff note is pushed.
- No change in this checkpoint is partially applied. The production UI localization boundary and contiguous playlist-removal slice are complete for the audited source.

That checkpoint gives product writers and translators one source of truth: `App/Resources/Localizable.xcstrings`. It combines explicit editable English values, compiler-backed Release extraction, generated-symbol support, stale-key removal, and a reproducible guarded sync/check helper. Computed/model notices and reusable boundaries use the appropriate localized resource or rendered-string API; server/user/music metadata and fixtures remain verbatim. The catalog is production-only, so DEBUG visual-QA sample text does not leak into translation work. New range-selection labels, confirmations, states, errors, and accessibility copy follow the same boundary.

Playlist owners and collaborators can now select one track or an adjacent range for removal in a native multi-selection sheet. Selection is request-free and noncontiguous groups remain disabled locally. After explicit confirmation, a fresh non-coalesced inspection must preserve the exact playlist, authorization, canonical positions, frozen tracks, index, and count before one serialized `{index,count}` POST. The request is never automatically retried. A shared durable playlist-mutation barrier clears only after a second canonical read equals the inspected playlist minus precisely that range; partial, truncated, ambiguous, stale, or unverifiable outcomes remain blocked for review. The positional API still has an unavoidable external-edit race, so postflight can prevent a false success claim but cannot undo a server-side deletion. Multi-track move remains withheld because the current server operation is non-atomic.

Final evidence:

- the single catalog contains 1,573 exact Release-extracted keys, has no empty or stale key, and gives every key an explicit English value;
- `scripts/localizations.sh check` rebuilt both simulator architectures and confirmed the committed catalog matches production compiler output;
- the focused playlist mutation suite passed 74/74, the complete app suite passed 596/596, and the complete vendored Kit passed 145/145, all with no failure or skip;
- the generic Release simulator build succeeded with `x86_64` and `arm64` slices;
- local range-selection and confirmation fixtures were inspected in light, dark, normal, and maximum-accessibility layouts; scoped logs contain no service hostname, HTTP(S) activity, or fatal failure; and
- independent correctness and security reviews found no material issue.

The range-removal fixtures use local data and no real token or remote artwork. QA therefore made no production request or mutation. The current server, website, Android/KMP, and iOS sources supplied contract and behavior evidence only; no GPL source or UI was copied.

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

Manual mapping is now implemented without a status-read or polling path. A future explicit **Check saved mapping** action can be evaluated separately if it proves useful; it must not become an automatic details-screen request.

Album collage intentionally starts with already-loaded canonical top releases. Arbitrary MusicBrainz search/addition remains separate because it would introduce a new search and identity-resolution request path; do not add it implicitly to draft editing.

Playback/content resolution, MusicKit capture, and Spotify-linked playback remain deliberately separate. Any libspot/librespot experiment starts only on its own branch after the core product is complete and after policy, licensing, account-security, App Store, and maintenance implications are reviewed.

## Local cleanup

The 2026-09-22 portable cleanup removed prior donor clones, browser tooling, builds, runtimes, skill installation, simulators, and other disposable artifacts. Xcode 27, the iOS 27 runtime, and the UX-writing skill remain available. This checkpoint's shallow official-source clones, project/package build caches, result bundles, logs, and screenshots were removed after acceptance; their dedicated Trash bucket alone was permanently deleted, reclaiming 3.3 GB. The disposable playlist-range simulator was terminated, shut down, and deleted, and an exact audit found no matching path or device.

The source checkout, Git history, tracked Xcode project, `project.yml`, Apple Command Line Tools, shared Nix store, pre-existing developer data, user settings, credentials, personal files, and unrelated Trash contents remain preserved. Exact artifact paths and cleanup commands are recorded in `environment-changes.md`.
