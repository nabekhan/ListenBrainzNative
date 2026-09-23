# Development handoff

Snapshot: 2026-09-22.

## Portable checkpoint

- Branch: `main`
- Last validated product commit: `6ccbf13dc4670ee12aea4f1354c2aec4e82ddb98`
- Remote: `https://github.com/nabekhan/ListenBrainzNative.git`
- Remote `main` was verified at the product commit before this handoff note was added.
- No feature implementation is in progress or left partially applied.

That checkpoint adds request-free Year in Music playlist snapshots for the current official **Top discoveries** and **Tracks you missed** reports. It decodes current direct JSPF and the archival 2021 nested shape, accepts scalar or array identifiers, preserves playlist order and duplicates, filters links to canonical ListenBrainz playlist and MusicBrainz recording URLs, and never exposes raw annotation HTML. Snapshot cards and the local detail view perform no playlist, artwork, metadata, or row-hydration request; navigation to mapped Recording detail or the canonical external playlist happens only after an explicit tap.

Final evidence before cleanup:

- 29 focused ListenBrainzKit statistics tests passed;
- 18 focused app Year in Music tests passed;
- the complete app suite passed 549/549 with no failures or skips;
- subsequent final Debug builds succeeded;
- light, dark, local-detail, maximum-accessibility, and iPhone SE-sized fixture layouts were inspected; and
- an independent re-review returned READY after the visible descriptions were corrected.

A regular-width iPad visual pass for this addition was interrupted before cleanup and remains a narrow follow-up, not completed evidence.

## Resume on another Mac

Requirements and project generation remain authoritative in the root `README.md` and tracked `project.yml`.

```sh
git clone https://github.com/nabekhan/ListenBrainzNative.git
cd ListenBrainzNative
nix shell nixpkgs#xcodegen -c xcodegen generate
open ListenBrainzNative.xcodeproj
```

Install Xcode and a compatible iOS simulator runtime before building. Reinstall the MIT `content-designer/ux-writing-skill` before adding or revising user-facing strings. Donor clones can be recreated from the URLs recorded in the research documents; do not copy local build products, simulator devices, or credentials. No ListenBrainz token or other secret is stored in the repository.

## Next unstarted product work

The annual-playlist candidate is complete. The strongest adjacent candidates are a shared Home current-pin section and the separately researched advanced manual-mapping workflow. Reassess their user value against the current implementation plan before selecting one.

Playback/content resolution, MusicKit capture, and Spotify-linked playback remain deliberately separate. Any libspot/librespot experiment starts only on its own branch after the core product is complete and after policy, licensing, account-security, App Store, and maintenance implications are reviewed.

## Local cleanup

Disposable development downloads and generated artifacts were permanently removed after the product commit was pushed. This includes donor clones, Playwright/Chromium, project build products and result bundles, accumulated project Trash, Xcode and its downloaded simulator runtimes/support data, project-created Gradle/Kotlin toolchains, the local UX-writing skill, disposable simulators, fixture apps, logs, and screenshots. The cleanup reclaimed well over 100 GB by measured artifact sizes.

The source checkout, Git history, tracked Xcode project, `project.yml`, Apple Command Line Tools, the shared Nix store, pre-existing developer data, user settings, credentials, personal files, and unrelated Trash contents were retained. Exact provenance is recorded in `environment-changes.md`.
