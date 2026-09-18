# Third-party software and design provenance

This project is intended to be licensed under MPL-2.0. This file is updated whenever source is copied or adapted.

## Included source

- ListenBrainzKit, commit `c06b12f8c35bfee8fcf11dc973b5d78e23719cdf`, is vendored at `Packages/ListenBrainzKit/` and locally patched for transport correctness, public model access, tolerant identifier decoding, and typed social, social feed-read/feed-mutation, Pins, detail, Fresh Releases, recommendation-read, recommendation-feedback, era-activity, artist-evolution, current Year in Music, Year in Music art, popularity, generated LB Radio, and playlist create/edit APIs. It is licensed under MPL-2.0; its original license and per-file notices are preserved.
- `App/Features/Taste/YearInMusicView.swift` adapts the composition and selected implementation patterns from Cassette's `WrappedStatHero.swift`, `WrappedTopArtistsSection.swift`, `WrappedTopAlbumsSection.swift`, `WrappedTopTracksSection.swift`, `MeshGradientBackground.swift`, and `WrappedYearPalette.swift` at commit `49da821`. Cassette is MPL-2.0, copyright Mathieu Dubart; the covered app file retains the MPL notice and attribution.

All other application UI remains independently implemented from inspected behavior and visual references unless this file states otherwise.

## Design and behavior references

- ListenBrainz server, official Android client, and official iOS client: authoritative product/API behavior; no code copied.
- first.fm: information architecture, listening-history personality, and paired personal/global metric hierarchy; MIT. The current History and entity-popularity screens remain independently implemented.
- Cassette and Minidisc: current native media interaction patterns; MPL-2.0. Their album hierarchy and ordered-row behavior informed the independently written release screen, and Cassette's searchable multi-selection pattern informed the independently written personal-recommendation sheet.
- Official ListenBrainz Android/iOS clients, KMP shared code, current server, and website: playlist grouping/paging plus full-snapshot editing, private creation defaults, and collaborator-normalization behavior informed the independently written Profile playlist and mutation interfaces; no GPL source was copied.
- The current ListenBrainz website and Android client informed the independently written generated-art preview and PNG-sharing flow. No GPL source was copied; the app uses system WebKit/CoreTransferable APIs and the server-provided SVG.
- The current ListenBrainz server/website and official Android/KMP/iOS clients informed LB Radio prompt, mode, request-policy, and playback-boundary behavior. The native builder and provider are independently written, and no GPL source was copied.
- Volta: artist-page visual reference only; GPL-3.0 code is not copied.
- AppleMusicBottombarSwiftUI and FastScrobbler: behavior reference only; no license found, so code is not copied.
- Autohop: statistics/history interaction reference for the heatmap, era hierarchy, and artist-evolution information hierarchy; MIT overall with named MPL-2.0 exceptions. No Autohop UI file was copied.
- Beans Music, Bòcan Music, Finale, and Discrobble: secondary UI/architecture references.

See `docs/research/license-map.md` and `docs/research/repo-reuse-map.md` for the working audit.
