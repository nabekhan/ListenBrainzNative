# Development handoff

Snapshot: 2026-09-24.

## Portable checkpoint

- Branch: `main`
- Last validated product commit: `60211cae8072ca2879b6ae98eb3078f5891728f3`
- Remote: `https://github.com/nabekhan/ListenBrainzNative.git`
- Remote `main` is verified after this handoff note is pushed.
- No product feature is left partially applied. The production UI localization migration is complete for the audited source.

That checkpoint gives product writers and translators one source of truth: `App/Resources/Localizable.xcstrings`. It combines explicit editable English values, compiler-backed Release extraction, generated-symbol support, stale-key removal, and a reproducible guarded sync/check helper. Computed/model notices and reusable boundaries now use the appropriate localized resource or rendered-string API; server/user/music metadata and fixtures remain verbatim. The catalog is production-only, so DEBUG visual-QA sample text does not leak into translation work.

Final evidence:

- the single catalog contains 1,452 exact Release-extracted keys, has no empty or stale key, and gives every key an explicit English value;
- `scripts/localizations.sh check` rebuilt both simulator architectures and confirmed the committed catalog matches production compiler output;
- the complete app suite passed 552/552 with no failures or skips on the final source;
- normal and accented-pseudolocalized small-device Home fixtures were inspected; app-owned copy transforms and wraps while usernames and music metadata remain verbatim; and
- independent re-review found no remaining app-authored visible-copy bypass after playlist notices, calendar-year formatting, stale-key pruning, and the source-boundary guard were corrected.

The Home fixture remains tokenless, uses local providers and nil artwork/canonical media IDs, and locks selection to Home. Localization QA therefore made no ListenBrainz, MusicBrainz, or artwork request and exercised no production mutation.

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

After localization, the separately researched advanced manual-mapping workflow remains a strong adjacent product candidate.

Playback/content resolution, MusicKit capture, and Spotify-linked playback remain deliberately separate. Any libspot/librespot experiment starts only on its own branch after the core product is complete and after policy, licensing, account-security, App Store, and maintenance implications are reviewed.

## Local cleanup

The 2026-09-22 portable cleanup removed prior donor clones, browser tooling, builds, runtimes, skill installation, simulators, and other disposable artifacts. Development was rebuilt on 2026-09-24: Xcode 27 was already present; the iOS 27 runtime, UX-writing skill, ephemeral Nix XcodeGen paths, package/build caches, two disposable QA simulators, logs, and screenshots now exist again.

The source checkout, Git history, tracked Xcode project, `project.yml`, Apple Command Line Tools, shared Nix store, pre-existing developer data, user settings, credentials, personal files, and unrelated Trash contents remain preserved. Exact artifact paths and cleanup commands are recorded in `environment-changes.md`.
