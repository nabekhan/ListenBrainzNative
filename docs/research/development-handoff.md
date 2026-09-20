# Development handoff

Snapshot: 2026-09-19.

## Portable checkpoint

- Branch: `main`
- Last validated product commit: `e2ae8c93ad737d73df6882afeca5ae9bee92398b`
- Remote: `https://github.com/nabekhan/ListenBrainzNative.git`
- Matching checkpoint branch: `codex/checkpoint-yim-evolution-2026-09-19`
- Worktree was clean before this handoff note was added. No feature implementation was in progress or left partially applied.

That checkpoint includes the request-free Year in Music artist-evolution chapter. Its final evidence was 14 focused tests, 545 complete app tests, a universal `x86_64`/`arm64` Release simulator binary, responsive light/dark/Dynamic Type/small-device fixture QA, and an independent ready review. The disposable QA simulators were reset and shut down after acceptance.

## Resume on another Mac

Requirements and project generation remain authoritative in the root `README.md` and tracked `project.yml`.

```sh
git clone https://github.com/nabekhan/ListenBrainzNative.git
cd ListenBrainzNative
nix shell nixpkgs#xcodegen -c xcodegen generate
open ListenBrainzNative.xcodeproj
```

Do not copy local build products, reference clones, simulator devices, or credentials. No ListenBrainz token or other secret is stored in the repository.

## Next unstarted product slice

The completed audit recommends a **request-free Year in Music discovery chapter for new releases from the listener's top artists**. No source change for this slice was started.

Authoritative behavior:

- Reuse `newReleasesOfTopArtists` from the one annual aggregate already loaded by `YearInMusicModel`; do not add a provider call, row hydration, or artwork preload.
- Current rows represent MusicBrainz release groups and provide title, artist credits, optional release-group MBID, and optional Cover Art Archive release identity. A CAA release MBID is artwork identity, not release-group identity.
- Use a dedicated presentation model rather than `YearInMusicReport.Release`, preserve server order, deduplicate MBID-first, and keep unmapped rows visible but non-navigable.
- Route only a valid release-group MBID through the existing `SearchReleaseGroup` destination. Do not invent dates, types, confidence, or listen counts.
- Legacy 2021 data uses a different concrete-release shape. If it cannot be represented without conflating release and release-group identity, keep it readable without navigation or omit the section.
- Reuse `ArtworkView` and existing Year in Music grid/shelf patterns. Suggested concise copy: **New from top artists** / **Albums and singles released in {year}**.
- Focused coverage should include malformed and missing IDs, multi-artist credits, CAA fallback, stable deduplication/order, unmapped navigation policy, and proof that rendering schedules no ListenBrainz request.

Current primary references:

- `Packages/ListenBrainzKit/Sources/ListenBrainzKit/Statistics/Models/LBYearInMusic.swift`
- `App/Domain/YearInMusicModels.swift`
- `App/Features/Taste/YearInMusicView.swift`
- `Tests/YearInMusicModelTests.swift`
- [ListenBrainz Year in Music API](https://listenbrainz.readthedocs.io/en/latest/users/api/statistics.html#get-1-stats-user-mb-username-user-name-year-in-music-int-year)
- [Official website new-releases component](https://github.com/metabrainz/listenbrainz-server/blob/master/frontend/js/src/user/year-in-music/components/YIMNewReleases.tsx)

After that slice, the strongest remaining candidates are embedded annual discovery/missed playlists, a shared Home current-pin section, and the separately researched advanced manual-mapping workflow. Playback/content resolution, MusicKit capture, and Spotify-linked playback remain deliberately separate; any libspot/librespot experiment starts only on its own branch after the core product and policy/license review are complete.

## Local cleanup

The old machine's build products, temporary reference clones/browser, and project-specific Xcode DerivedData were moved to Trash during handoff, so they remain recoverable until Trash is emptied. Disposable QA simulator devices were deleted. The tracked generated Xcode project, host-wide installations, and shared caches were intentionally retained; exact provenance and optional removal guidance remain in `environment-changes.md`.
