# ListenBrainzKit gap analysis

Snapshot: 2026-09-17. Server `e83a7ab`; ListenBrainzKit base `c06b12f` (2025-02-05) plus the local audited extensions.

| Area | Classification | Current finding | Decision |
|---|---|---|---|
| User search/token validation | SUPPORTED | Typed public API | Reuse |
| Recent listens/count/Playing Now | SUPPORTED | Strict `min_ts`/`max_ts` bounds, timestamp pagination, and listen submission included | Reuse through the shared gate; app-owned History state supplies DST-safe local-day bounds and overlap de-duplication |
| Delete/submit/batch submit | SUPPORTED | Correct product operations exist | Reuse; keep capture separate |
| Similar users/pairwise similarity | SUPPORTED | Typed models | Reuse |
| Followers/following/follow/unfollow | SUPPORTED | Typed social client with endpoint-specific status handling | Reuse native Social slice; upstream candidate |
| Connected services/latest import | SUPPORTED | Core client methods | Reuse later |
| Metadata lookup/manual mapping | SUPPORTED | Recording, release group, artist, bulk/fuzzy mapping | Reuse behind metadata resolver |
| Concrete release/ordered track lookup | MISSING | Kit `releaseGroup` metadata does not model a MusicBrainz edition or its media/tracks | Use one separately gated MusicBrainz release lookup; do not mislabel group metadata or hydrate tracks individually |
| Top artist/release/release-group/recording | SUPPORTED | User and sitewide | Reuse |
| Listening activity | SUPPORTED | User and sitewide | Reuse |
| Daily/hour-of-day activity | SUPPORTED | Typed user daily-activity response, optional server range, 7×24 UTC buckets, and honest 204 handling | Reuse through the shared gate; local extension is an upstream candidate |
| Recording feedback | SUPPORTED | Love/hate/clear and lookup | Reuse |
| Playlist lists/search/detail | SUPPORTED | Typed paginated user/created-for/collaborator listings preserve server count/offset/total metadata; public search and complete JSPF detail/track payloads are also typed | Reuse; page/detail extensions are upstream candidates and now power native Profile/For You/search paths |
| LB Radio | PARTIALLY_SUPPORTED | Tags and artist seed only | Re-evaluate against current prompt-generation API |
| Other activity/identity statistics | MISSING | Artist, era, genre, evolution, map, listeners absent | Add in focused upstream extensions |
| Year in Music | MISSING | Current and legacy endpoints absent | App extension first; upstream candidate |
| Pins | PARTIALLY_SUPPORTED | Current pin, paginated history, create, unpin, note update, and delete are typed; following pins remain absent | Reuse native slice; add following pins with Social; upstream candidate |
| Social feed reads | SUPPORTED | Typed aggregate, following, and similar feed pages; tolerant nested metadata; one request per page | Reuse native feed slice; upstream candidate |
| Feed mutations (thanks/hide/unhide/delete/recommendations) | SUPPORTED | Typed public/personal recommendation creation plus thanks, hide, unhide, and generic deletion with endpoint-specific bodies/status maps | Reuse native social-action slices; upstream candidate |
| Recommendations and feedback | SUPPORTED | Typed paginated CF retrieval plus submit/delete, paginated, and batched recommendation-feedback APIs | Reuse native For You slice; upstream candidate |
| Popularity | MISSING | Entity counts and artist top entities absent | App extension for detail screens |
| Fresh Releases/explore | SUPPORTED | Personalized and sitewide Fresh Releases, tolerant models, explicit 204 empty result | Discover slice; Music Neighborhood and AI Brainz remain missing |
| Art/share endpoints | MISSING | Grid/stat/YiM/playlist art absent | Small typed art service |
| Playlist mutations/import/export | MISSING | Create/edit/delete, items, ordering, copy, import/export absent | Focused playlist extension after browse paths |
| Player/JSPF resolution | MISSING | Instant-play endpoints absent | Delay until read paths are strong |
| Settings/status/data tools | MISSING | Preferences and maintenance endpoints absent | Add only when UI requires them |

## Defects audited in the local MPL-preserving fork

1. `APIClient` uses `URL.appending(component:)` with request strings such as `/1/user/...`; Foundation percent-encodes the slashes into one component. Use path-safe URL construction and cover it with a URL test.
2. Requests omit the API-required contactable `User-Agent`.
3. HTTP 429 is surfaced but rate-limit response headers are discarded and there is no one-request-per-second scheduler.
4. `MbidMapping` requires identifiers that current responses can omit/null; app-facing mapping must be tolerant.
5. Most unexpected HTTP statuses collapse to `unknownError`, losing useful recovery information.
6. Some encoded request bodies omit `Content-Type: application/json`, producing HTTP 415 responses on current endpoints.

## Build result

The development-only SwiftLint plugin was removed from the vendored package target because it prevented clean consumers from building under Command Line Tools. Under Xcode 27, `swift test` builds successfully and runs 88 tests with the token-dependent and opt-in live suites skipped. A separate, explicitly paced `LISTENBRAINZ_PUBLIC_SMOKE=1` run passes against current production recent-listen, count, Playing Now, top-artist, listening-activity, current/history Pins, sitewide Fresh Releases, public-playlist search, and canonical user-search endpoints.

The local fork also now verifies path-safe endpoint construction, endpoint-required trailing slashes (including release-group and recording metadata), default JSON content types for encoded bodies, required User-Agent behavior, omission of empty authorization, explicit authorization before a custom API origin receives a token, rejection of insecure roots and cross-origin authenticated redirects, conservative interpretation of `Retry-After` / `X-RateLimit-Reset-In`, tolerant playlist timestamps, complete JSPF identity decoding, typed CF recommendation paging, typed daily-activity decoding/path/query/204 semantics, the Pins API's distinct string versus Boolean mutation responses, exact social relationship and feed-mutation paths/body keys/status contracts, and tolerant typed feed reads. Each CF page uses one recommendation request and, only when it contains MBIDs, one batch metadata request rather than per-row hydration. Each feed page is one request with embedded metadata; the aggregate feed currently excludes ordinary listens, while Following and Similar are listen-only recent windows.

## Recommendation

Use an MPL-2.0 local fork for P0 core listens, metadata, basic stats, and feedback; make only the transport/policy/model fixes needed to become reliable. Keep `ListeningProvider` as the app-facing boundary. Add missing generic endpoint groups as small extensions and prepare them as upstreamable commits. Do not adopt KMP merely to fill API gaps today.

Evidence: `References/ListenBrainzKit/Package.swift`, `Sources/ListenBrainzKit/API/APIClient.swift`, the public client files, and current server views/docs.
