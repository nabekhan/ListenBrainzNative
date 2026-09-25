# Development handoff

Snapshot: 2026-09-25.

## Portable checkpoint

- Branch: `main`
- Last validated product commit: `9bd1e09f31bbfac2805284544349b677b974d802`
- Remote: `https://github.com/nabekhan/ListenBrainzNative.git`
- Remote `main` is verified after this handoff note is pushed.
- No product feature is left partially applied. The production UI localization migration, native manual MusicBrainz matching, and custom top-album collage slice are complete for the audited source.

That checkpoint gives product writers and translators one source of truth: `App/Resources/Localizable.xcstrings`. It combines explicit editable English values, compiler-backed Release extraction, generated-symbol support, stale-key removal, and a reproducible guarded sync/check helper. Computed/model notices and reusable boundaries use the appropriate localized resource or rendered-string API; server/user/music metadata and fixtures remain verbatim. The catalog is production-only, so DEBUG visual-QA sample text does not leak into translation work. New collage labels, explanations, states, and accessibility copy follow the same boundary.

Taste now offers a native **Album collage** composer using canonical releases from the already-loaded all-time ranking. Opening, selecting, arranging, changing layout/background/captions, and dismissing are request-free; the draft model cannot carry a remote artwork URL. **Create** freezes one exact anonymous `POST /1/art/grid/`, with shared coalescing, a bounded 24-hour cache, and no automatic retry. Preview, secure SVG rendering, PNG export, and native sharing reuse the existing Generic Art pipeline.

Final evidence:

- the single catalog contains 1,546 exact Release-extracted keys, has no empty or stale key, and gives every key an explicit English value;
- `scripts/localizations.sh check` rebuilt both simulator architectures and confirmed the committed catalog matches production compiler output;
- the complete app suite passed 581/581 and the complete vendored Kit passed 145/145, both with no failure or skip;
- the generic Release simulator build succeeded with `x86_64` and `arm64` slices;
- local composer fixtures were inspected in light, dark, normal, maximum-accessibility, and iPhone SE layouts, and the rendered preview was inspected after its WebKit snapshot completed; scoped logs contain no service hostname or HTTP(S) activity; and
- independent correctness and security re-reviews report READY.

The custom-art fixtures remain tokenless and use local candidates/providers. QA therefore made no ListenBrainz, MusicBrainz, or artwork request and exercised no production mutation. The feature's server contract was verified from a temporary official-server checkout; no GPL source or UI was copied.

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

Manual mapping is now implemented without a status-read or polling path. A future explicit **Check saved mapping** action can be evaluated separately if it proves useful; it must not become an automatic details-screen request.

Album collage intentionally starts with already-loaded canonical top releases. Arbitrary MusicBrainz search/addition remains separate because it would introduce a new search and identity-resolution request path; do not add it implicitly to draft editing.

Playback/content resolution, MusicKit capture, and Spotify-linked playback remain deliberately separate. Any libspot/librespot experiment starts only on its own branch after the core product is complete and after policy, licensing, account-security, App Store, and maintenance implications are reviewed.

## Local cleanup

The 2026-09-22 portable cleanup removed prior donor clones, browser tooling, builds, runtimes, skill installation, simulators, and other disposable artifacts. Xcode 27, the iOS 27 runtime, and the UX-writing skill remain available. The custom-art server clone, project/package build caches, interrupted localization builds, logs, and screenshots were removed after acceptance; their dedicated Trash bucket alone was permanently deleted, reclaiming about 4.8 GB. Both disposable custom-art simulators were shut down and deleted.

The source checkout, Git history, tracked Xcode project, `project.yml`, Apple Command Line Tools, shared Nix store, pre-existing developer data, user settings, credentials, personal files, and unrelated Trash contents remain preserved. Exact artifact paths and cleanup commands are recorded in `environment-changes.md`.
