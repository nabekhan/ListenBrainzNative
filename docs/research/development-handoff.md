# Development handoff

Snapshot: 2026-09-22.

## Portable checkpoint

- Branch: `main`
- Last validated product commit: `418f7c4be1abf12ee736c760c58d6e9fce5a26ae`
- Remote: `https://github.com/nabekhan/ListenBrainzNative.git`
- Matching checkpoint branch: `codex/checkpoint-yim-new-releases-2026-09-22`
- Worktree was clean before this handoff note was added. No feature implementation was in progress or left partially applied.

That checkpoint includes the request-free Year in Music **New from top artists** chapter. Current release groups navigate only through their canonical MBID; concrete legacy releases remain static, and CAA release IDs remain artwork-only. Its final evidence was 16 focused Year in Music tests, 547 complete app tests, a universal `x86_64`/`arm64` Release simulator binary, responsive light/dark/maximum-Dynamic-Type/iPhone SE fixture QA, a scoped no-service-host log, and an independent READY review.

## Resume on another Mac

Requirements and project generation remain authoritative in the root `README.md` and tracked `project.yml`.

```sh
git clone https://github.com/nabekhan/ListenBrainzNative.git
cd ListenBrainzNative
nix shell nixpkgs#xcodegen -c xcodegen generate
open ListenBrainzNative.xcodeproj
```

Do not copy local build products, reference clones, simulator devices, or credentials. No ListenBrainz token or other secret is stored in the repository.

## Next unstarted product research

The strongest adjacent candidate is a request-free Year in Music playlist chapter using the JSPF playlists already embedded in the annual aggregate. No source change or final product decision for this candidate has started.

Before implementation, establish:

- Which of `playlist-top-discoveries-for-year`, `playlist-top-missed-recordings-for-year`, `playlist-top-new-recordings-for-year`, and `playlist-top-recordings-for-year` the current website and official clients actually present, and whether a native chapter adds value beyond existing For You and playlist surfaces.
- Whether each embedded JSPF `identifier` is a canonical ListenBrainz playlist MBID that can reuse Playlist Detail without a lookup. Never infer playlist identity from title or creator.
- Whether the embedded ordered tracks alone are sufficient for a compact native preview. Rendering must not hydrate every recording or imply that an MBID is playable audio.
- Current/archive schema differences, absence behavior, deduplication, and the smallest truthful UI. Continue to use the one loaded annual response; do not add preloading, polling, row hydration, or a second Year in Music provider call.
- Existing reusable playlist mosaic/row components and official wording. Apply the UX Writing skill before introducing any visible copy.

Current primary references:

- `Packages/ListenBrainzKit/Sources/ListenBrainzKit/Statistics/Models/LBYearInMusic.swift`
- `App/Domain/YearInMusicModels.swift`
- `App/Features/Taste/YearInMusicView.swift`
- `App/Features/Playlist/PlaylistDetailView.swift`
- [ListenBrainz Year in Music API](https://listenbrainz.readthedocs.io/en/latest/users/api/statistics.html#get-1-stats-user-mb-username-user-name-year-in-music-int-year)

If annual playlists do not add enough distinct value, the next candidates remain a shared Home current-pin section and the separately researched advanced manual-mapping workflow. Playback/content resolution, MusicKit capture, and Spotify-linked playback remain deliberately separate; any libspot/librespot experiment starts only on its own branch after the core product and policy/license review are complete.

## Local cleanup

The new-release milestone's exact DerivedData and screenshots were moved to Trash, so they remain recoverable until Trash is emptied. Its disposable iPhone SE simulator was deleted; the standard iPhone 18 Pro was restored to light/large, the fixture app was uninstalled, and the device was shut down. The tracked generated Xcode project, Xcode/iOS runtime, host-wide installations, and shared caches were intentionally retained; exact provenance and optional removal guidance remain in `environment-changes.md`.
