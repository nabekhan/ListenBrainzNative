# Year in Music working note

Snapshot: 2026-09-18.

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

## Generated artwork slice

- Canonical report-link sharing remains immediate and independent of image generation.
- “Preview official artwork…” is the only UI path that requests art; opening the report itself performs no art preload.
- The typed MPL Kit extension models all seven current variants, 204-as-unavailable, response MIME/SVG validation, encoded usernames, and a 4 MiB payload ceiling. The first UI intentionally exposes only the overview variant.
- The complete transport operation enters `RequestGate.shared`, feeds 429 timing back into the gate, coalesces identical in-flight work, and uses a bounded 24-hour memory cache. If every waiter leaves before admission, the queued gated task is cancelled so a dismissed sheet cannot consume a later ListenBrainz request slot.
- A nonpersistent, noninteractive `WKWebView` embeds the SVG as a real document object with JavaScript disabled and link/form navigation rejected. Content rules reject arbitrary HTTP(S) subresources and admit only the current generated-art dependencies: Archive.org cover downloads plus Google Fonts CSS/font hosts. This preserves the server art's external cover images/fonts without allowing a server-provided SVG to call back into ListenBrainz or a tracker; a 924-pixel snapshot is shared as PNG, matching the current website/Android product flow.
- Snapshot preparation has a recoverable error state. Retrying a failed render reuses the already-fetched SVG rather than issuing a second ListenBrainz request.
- Light, dark, accessibility-size, and small-device QA use a local fixture and therefore make no production request. Two separate production reconnaissance probes were issued six seconds apart; no burst or parallel ListenBrainz request was used.

## Deferred

- Legacy 2021–2024 schema adapters.
- Secondary current-payload chapters such as genres, discovery playlists, similar users, and new releases after their value and duplication with existing app surfaces are reviewed.
