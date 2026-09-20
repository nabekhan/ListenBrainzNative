# Year in Music working note

Snapshot: 2026-09-19.

## Current product contract

- Current aggregate API: `GET /1/stats/user/{username}/year-in-music/{year}`; omitting the year currently defaults to 2025. Current server bounds are 2002 through 2025.
- A single current-schema payload may include totals, UTC listens per day, artist evolution, genres, top artists/release groups/recordings, artist map, new releases, similar users, and complete JSPF playlists.
- Production currently returns `200 {"data": {}}` for some unavailable reports even though the docs also describe `204`; the app handles 204, 404, and empty data honestly.
- Generated SVG art is a separate rate-limited route with overview, stats, artist, album, track, discovery-playlist, and missed-playlist variants. It must be fetched only after an explicit preview/share action.
- Frozen reports use `GET /1/stats/user/{username}/year-in-music/legacy/{year}` for 2021–2024. The route is public, the schema varies by year, and a payload can be much larger because it may embed playlists and artwork maps.
- 2021 uses plural artist MBIDs and concrete `top_releases`, plus separate `top_releases_coverart`; 2022 still ranks concrete releases; 2023–2024 use current-style release groups. Missing legacy totals are unavailable, not zero.

## Source comparison

- The live 2025 website is a very long fixed-chart story with a persistent player; its data hierarchy is authoritative, but its GPL React/Sass was not copied.
- Official Android and iOS implementations are older, hard-coded 2022/2023 references and remain behavior references only.
- No usable current Year in Music implementation exists in KMP `commonMain`; there is no iOS-export advantage for this feature today.
- ListenBrainzKit was the simplest reliable path. The local MPL extension now supplies tolerant current and archival decoding, per-segment username encoding, and a 16 MiB archival ceiling enforced while receiving and again before JSON decoding.

## Native first slice

- Taste exposes a teaser and makes no Year in Music call until the user opens it.
- One `RequestGate.shared` operation retrieves the whole report; there is no per-row hydration or art preload.
- A native year menu exposes 2025 and archives from 2024 back to 2021. Only the selected year loads: there is no archive prefetch. Replacing the selection cancels the old waiter, and the gate prevents an equal request from overlapping while its transport drains.
- The current report keeps its authenticated request scope and 30-minute cache. Frozen archives use an empty-token client, anonymous gate/cache scope, and a separate 24-hour cache. Neither path retries automatically.
- The native story shows listening-time/listen totals, a Monday-first UTC annual heatmap, annual identity context, ranked artists, release groups, and recordings.
- The identity chapter reuses the same aggregate response: it preserves the presence of `total_new_artists_discovered` (including a truthful zero), normalizes only canonical weekday names, presents genre strings explicitly as ListenBrainz tags, and groups positive release-year counts from 1850 through the report year into decades. Missing or invalid fields are omitted rather than invented, and no secondary request or row hydration is introduced.
- The annual artist-evolution chapter also stays inside that aggregate. Documented English months and defensive numeric 1–12 buckets feed the existing `ArtistEvolutionActivity` identity/ordering normalizer; malformed or non-positive rows disappear, sparse months remain truthful zeroes, and the render-only native chart/legend is shared with Taste without importing its request-owning lifecycle. Mapped artists retain the existing Artist Detail route only after a tap, while unmapped names remain readable.
- Existing artist, release-group, release, and recording destinations are reused. The archive adapter preserves concrete releases for 2021–2022, uses the supplied safe HTTPS 2021 artwork map when present, and never collapses a release MBID into a release-group identity.
- Cache keys include normalized user, request scope, and year; stale content survives refresh failures, and late/cancelled responses cannot overwrite newer state.
- Cassette's MPL-2.0 Wrapped composition supplies the adapted mesh hero, artist shelf, album grid, track list, and 2025 palette. The annual heatmap and ListenBrainz state handling are app-specific.

## Generated artwork slice

- Canonical report-link sharing remains immediate and independent of image generation.
- “Preview official artwork…” is the only UI path that requests art; opening the report itself performs no art preload.
- The typed MPL Kit extension models all seven current variants, 204-as-unavailable, response MIME/SVG validation, encoded usernames, and a 4 MiB payload ceiling. The UI exposes the current overview, the supported 2022 stats image, and 2023–2024 legacy overviews; 2021 has no compatible generated-art route and therefore offers link sharing only.
- The complete transport operation enters `RequestGate.shared`, feeds 429 timing back into the gate, coalesces identical in-flight work, and uses a bounded 24-hour memory cache. If every waiter leaves before admission, the queued gated task is cancelled so a dismissed sheet cannot consume a later ListenBrainz request slot.
- A nonpersistent, noninteractive `WKWebView` embeds the SVG as a real document object with JavaScript disabled and link/form navigation rejected. Content rules reject arbitrary HTTP(S) subresources and admit only the current generated-art dependencies: Archive.org cover downloads plus Google Fonts CSS/font hosts. This preserves the server art's external cover images/fonts without allowing a server-provided SVG to call back into ListenBrainz or a tracker; a 924-pixel snapshot is shared as PNG, matching the current website/Android product flow.
- Snapshot preparation has a recoverable error state. Retrying a failed render reuses the already-fetched SVG rather than issuing a second ListenBrainz request.
- Light, dark, accessibility-size, and small-device QA use a local fixture and therefore make no production request. Two separate production reconnaissance probes were issued six seconds apart; no burst or parallel ListenBrainz request was used.

## Deferred

- Secondary payload chapters such as artist-map context, discovery playlists, similar users, and new releases remain deferred until their value and duplication with existing app surfaces are reviewed.
- The full year-specific website animations and layouts remain reference-only GPL behavior; the native story deliberately normalizes the highest-value chapters instead of copying them.
