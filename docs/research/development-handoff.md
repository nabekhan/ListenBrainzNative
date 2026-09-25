# Development handoff

Snapshot: 2026-09-25.

## Portable checkpoint

- Branch: `main`
- Last validated product commit: `d851ad5e217f452be87268a6df1ed6091790ac41`
- Remote: `https://github.com/nabekhan/ListenBrainzNative.git`
- Remote `main` is verified after this handoff note is pushed.
- No product feature is left partially applied. The production UI localization migration and the native manual MusicBrainz matching slice are complete for the audited source.

That checkpoint gives product writers and translators one source of truth: `App/Resources/Localizable.xcstrings`. It combines explicit editable English values, compiler-backed Release extraction, generated-symbol support, stale-key removal, and a reproducible guarded sync/check helper. Computed/model notices and reusable boundaries use the appropriate localized resource or rendered-string API; server/user/music metadata and fixtures remain verbatim. The catalog is production-only, so DEBUG visual-QA sample text does not leak into translation work. New mapping labels, explanations, recovery states, and errors follow the same boundary.

Listen Details now offers an advanced native MusicBrainz matching flow for eligible authenticated historical listens. Opening details is request-free; explicitly entering the mapper starts one debounced MusicBrainz candidate search, selection is local, and confirmation sends one serialized no-auto-retry ListenBrainz POST through the existing Kit. Submitted recording MBIDs retain precedence. Indeterminate writes remain visible across candidate changes and require a separately confirmed resend; the app performs no automatic mapping-status read, poll, History refresh, or replay.

Final evidence:

- the single catalog contains 1,501 exact Release-extracted keys, has no empty or stale key, and gives every key an explicit English value;
- `scripts/localizations.sh check` rebuilt both simulator architectures and confirmed the committed catalog matches production compiler output;
- the focused mapping suite passed 12/12, the complete app suite passed 574/574 with no failures, skips, or runtime warnings, and the unchanged vendored Kit passed 143 tests;
- local mapping fixtures were inspected in light, dark, normal, accessibility, and smaller-device layouts; a UUID wrapping defect was corrected before acceptance, and scoped logs contain no service hostname or fatal failure; and
- independent correctness and security re-reviews report READY.

The mapping fixtures remain tokenless and use local search/mutation providers. QA therefore made no ListenBrainz, MusicBrainz, or artwork request and exercised no production mutation.

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

Playback/content resolution, MusicKit capture, and Spotify-linked playback remain deliberately separate. Any libspot/librespot experiment starts only on its own branch after the core product is complete and after policy, licensing, account-security, App Store, and maintenance implications are reviewed.

## Local cleanup

The 2026-09-22 portable cleanup removed prior donor clones, browser tooling, builds, runtimes, skill installation, simulators, and other disposable artifacts. Xcode 27, the iOS 27 runtime, and the UX-writing skill remain available. The manual-mapping reconnaissance clones, project/package build caches, and screenshots were moved to Trash after acceptance; the two disposable mapping simulators were shut down and deleted. Empty only the exact mapping entries recorded in `environment-changes.md` when their recoverability is no longer useful.

The source checkout, Git history, tracked Xcode project, `project.yml`, Apple Command Line Tools, shared Nix store, pre-existing developer data, user settings, credentials, personal files, and unrelated Trash contents remain preserved. Exact artifact paths and cleanup commands are recorded in `environment-changes.md`.
