# Development handoff

Snapshot: 2026-09-24.

## Portable checkpoint

- Branch: `main`
- Last validated product commit: `367eb2f8fdfbc3038908515cfed8e9f35b7657d8`
- Remote: `https://github.com/nabekhan/ListenBrainzNative.git`
- Remote `main` is verified after this handoff note is pushed.
- No product feature is left partially applied. The localization foundation and its first shared/Home migration slice are complete; legacy computed-copy migration remains explicitly staged.

That checkpoint adds one translator-facing `Localizable.xcstrings` catalog with explicit editable English source values, compiler-backed Release extraction, generated-symbol support, and a reproducible sync/check helper. Shared section/loading/featured-listen boundaries plus Home/current-pin copy now use `LocalizedStringResource`; server/user/music metadata and fixtures remain verbatim. The catalog is production-only, so DEBUG visual-QA sample text does not leak into translation work.

Final evidence:

- the single catalog contains 914 exact Release-extracted keys, has no empty key, and gives every key an explicit English source value;
- `scripts/localizations.sh check` rebuilt both simulator architectures and confirmed the committed catalog matches production compiler output;
- the complete app suite passed 552/552 with no failures or skips on the final source;
- normal and accented-pseudolocalized Home fixtures were inspected; app-owned copy transforms while usernames and music metadata remain verbatim; and
- independent re-review returned READY after the full VoiceOver template, truthful loading copy, `jq` requirement, and empty-key handling were corrected.

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

Continue the catalog migration in reviewable feature passes. Prioritize Playlist Detail, Year in Music, Taste, Radio, History, Discover, model-authored notices, computed accessibility descriptions, and count/unit formatting. Keep server content, identifiers, and fixture data verbatim. Before shipping the first non-English locale, consolidate count strings into catalog plural variants and test dates, durations, possessives, capitalization, right-to-left layout, Dynamic Type, and real translations with native-language review.

After localization, the separately researched advanced manual-mapping workflow remains a strong adjacent product candidate.

Playback/content resolution, MusicKit capture, and Spotify-linked playback remain deliberately separate. Any libspot/librespot experiment starts only on its own branch after the core product is complete and after policy, licensing, account-security, App Store, and maintenance implications are reviewed.

## Local cleanup

The 2026-09-22 portable cleanup removed prior donor clones, browser tooling, builds, runtimes, skill installation, simulators, and other disposable artifacts. Development was rebuilt on 2026-09-24: Xcode 27 was already present; the iOS 27 runtime, UX-writing skill, ephemeral Nix XcodeGen paths, package/build caches, two disposable QA simulators, logs, and screenshots now exist again.

The source checkout, Git history, tracked Xcode project, `project.yml`, Apple Command Line Tools, shared Nix store, pre-existing developer data, user settings, credentials, personal files, and unrelated Trash contents remain preserved. Exact artifact paths and cleanup commands are recorded in `environment-changes.md`.
