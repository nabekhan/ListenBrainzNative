# ListenBrainzKit gap analysis

Snapshot: 2026-09-16. Server `e83a7ab`; ListenBrainzKit `c06b12f` (2025-02-05).

| Area | Classification | Current finding | Decision |
|---|---|---|---|
| User search/token validation | SUPPORTED | Typed public API | Reuse |
| Recent listens/count/Playing Now | SUPPORTED | Timestamp pagination and listen submission included | Reuse after transport fix |
| Delete/submit/batch submit | SUPPORTED | Correct product operations exist | Reuse; keep capture separate |
| Similar users/pairwise similarity | SUPPORTED | Typed models | Reuse |
| Connected services/latest import | SUPPORTED | Core client methods | Reuse later |
| Metadata lookup/manual mapping | SUPPORTED | Recording, release group, artist, bulk/fuzzy mapping | Reuse behind metadata resolver |
| Top artist/release/release-group/recording | SUPPORTED | User and sitewide | Reuse |
| Listening activity | SUPPORTED | User and sitewide | Reuse |
| Recording feedback | SUPPORTED | Love/hate/clear and lookup | Reuse |
| Playlist lists | PARTIALLY_SUPPORTED | User/created-for/collaborator/recommendation listings only | Reuse list calls; add generic endpoints upstream |
| LB Radio | PARTIALLY_SUPPORTED | Tags and artist seed only | Re-evaluate against current prompt-generation API |
| New activity/identity statistics | MISSING | Daily, artist, era, genre, evolution, map, listeners absent | Add in a focused upstream extension |
| Year in Music | MISSING | Current and legacy endpoints absent | App extension first; upstream candidate |
| Pins | MISSING | No current/history/following/mutation support | App extension; upstream candidate |
| Social/follow/feed/thanks | MISSING | Entire category absent | App extension in Phase 3 |
| Recommendations and feedback | MISSING | CF retrieval/feedback absent | App extension in Discover phase |
| Popularity | MISSING | Entity counts and artist top entities absent | App extension for detail screens |
| Fresh Releases/explore | MISSING | Fresh Releases, Music Neighborhood, AI Brainz absent | App extension in Discover phase |
| Art/share endpoints | MISSING | Grid/stat/YiM/playlist art absent | Small typed art service |
| Full playlist CRUD/import/export | MISSING | Detail, items, ordering, copy, import/export absent | Focused playlist extension |
| Player/JSPF resolution | MISSING | Instant-play endpoints absent | Delay until read paths are strong |
| Settings/status/data tools | MISSING | Preferences and maintenance endpoints absent | Add only when UI requires them |

## Blocking defects to fix in a local MPL-preserving fork

1. `APIClient` uses `URL.appending(component:)` with request strings such as `/1/user/...`; Foundation percent-encodes the slashes into one component. Use path-safe URL construction and cover it with a URL test.
2. Requests omit the API-required contactable `User-Agent`.
3. HTTP 429 is surfaced but rate-limit response headers are discarded and there is no one-request-per-second scheduler.
4. `MbidMapping` requires identifiers that current responses can omit/null; app-facing mapping must be tolerant.
5. Most unexpected HTTP statuses collapse to `unknownError`, losing useful recovery information.

## Build result

`swift test` downloaded dependencies but did not reach compilation under Command Line Tools: the SwiftLint build plugin could not load `sourcekitdInProc.framework`. Re-run under the installed full Xcode. The SwiftLint plugin is a development-only build dependency worth removing from the library target if it continues to harm consumers.

## Recommendation

Use an MPL-2.0 local fork for P0 core listens, metadata, basic stats, and feedback; make only the transport/policy/model fixes needed to become reliable. Keep `ListeningProvider` as the app-facing boundary. Add missing generic endpoint groups as small extensions and prepare them as upstreamable commits. Do not adopt KMP merely to fill API gaps today.

Evidence: `References/ListenBrainzKit/Package.swift`, `Sources/ListenBrainzKit/API/APIClient.swift`, the public client files, and current server views/docs.

