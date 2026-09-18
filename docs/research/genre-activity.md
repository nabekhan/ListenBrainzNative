# Genre Activity working note

Snapshot: 2026-09-18.

## Current product contract

- Current endpoint: `GET /1/stats/user/{username}/genre-activity?range={range}`.
- The payload contains free-text genre, UTC hour, and listen-count rows plus range and timestamp metadata. HTTP 204 means statistics are not ready.
- Server aggregation keeps only the leading genres for each hour (currently top 10 per user/hour). Missing or unmapped genre metadata is excluded, and one recording may contribute more than one genre.
- It is therefore not a complete genre distribution and has no honest whole-period percentage denominator.
- There is no current sitewide Genre Activity endpoint.

## Source comparison

- The website rounds the browser's current UTC offset to an hour, groups rows into Night/Morning/Afternoon/Evening, and renders top-five-with-ties slices in a radial pie. Its terminology and daypart convention are useful; the percentages and dense mobile radial presentation are not reused.
- Official Android/KMP has no reusable current genre-statistics implementation. ListenBrainzKit previously exposed only Year in Music genre fields, so the standalone endpoint was a genuine Swift API gap.
- Cassette, first.fm, and Autohop offered hierarchy/personality references, but no donor contained a direct ListenBrainz genre screen. The native view is app-owned code.

## Native decision

- Taste shows a teaser only; opening Genre Activity makes exactly one `RequestGate.shared` request and no per-row metadata calls.
- The app presents four selectable local dayparts and proportional leading-genre bars rather than a pie chart or fabricated share.
- UTC hour buckets are placed by their midpoint using the device time zone at the report's end date, which handles fractional offsets. The UI explains that a range crossing daylight-saving changes remains approximate because the aggregate has no per-listen dates.
- Free-text whitespace/case variants coalesce for display only. No genre MBID, taxonomy, navigation, or recommendation explanation is invented.
- Results cache for 10 minutes per normalized user/period, preserve stale content on refresh failure, and reject late/cancelled responses.
