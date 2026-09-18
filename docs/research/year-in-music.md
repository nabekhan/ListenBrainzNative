# Year in Music working note

Snapshot: 2026-09-17.

## Current product contract

- Current aggregate API: `GET /1/stats/user/{username}/year-in-music/{year}`; omitting the year currently defaults to 2025. Current server bounds are 2002 through 2025.
- A single current-schema payload may include totals, UTC listens per day, artist evolution, genres, top artists/release groups/recordings, artist map, new releases, similar users, and complete JSPF playlists.
- Production currently returns `200 {"data": {}}` for some unavailable reports even though the docs also describe `204`; the app handles 204, 404, and empty data honestly.
- Generated SVG art is a separate rate-limited route with overview, stats, artist, album, track, discovery-playlist, and missed-playlist variants. It must be fetched only after an explicit preview/share action.
- Legacy reports use year-specific 2021–2024 schemas. They are deliberately outside the first native slice.

## Source comparison

- The live 2025 website is a very long fixed-chart story with a persistent player; its data hierarchy is authoritative, but its GPL React/Sass was not copied.
- Official Android and iOS implementations are older, hard-coded 2022/2023 references and remain behavior references only.
- No usable current Year in Music implementation exists in KMP `commonMain`; there is no iOS-export advantage for this feature today.
- ListenBrainzKit was the simplest reliable path. The local MPL extension now supplies tolerant typed current-schema decoding and one optional-year client call.

## Native first slice

- Taste exposes a teaser and makes no Year in Music call until the user opens it.
- One `RequestGate.shared` operation retrieves the whole report; there is no per-row hydration or art preload.
- The native story shows listening-time/listen totals, a Monday-first UTC annual heatmap, ranked artists, release groups, and recordings.
- Existing artist, release-group, and recording destinations are reused. Release-group MBIDs and concrete release artwork MBIDs remain distinct.
- Reports cache for 30 minutes by normalized user/year, stale content survives refresh failures, and late/cancelled responses cannot overwrite newer state.
- Cassette's MPL-2.0 Wrapped composition supplies the adapted mesh hero, artist shelf, album grid, track list, and 2025 palette. The annual heatmap and ListenBrainz state handling are app-specific.

## Deferred

- Explicit generated-art preview/share workflow.
- Legacy 2021–2024 schema adapters.
- Secondary current-payload chapters such as genres, discovery playlists, similar users, and new releases after their value and duplication with existing app surfaces are reviewed.
