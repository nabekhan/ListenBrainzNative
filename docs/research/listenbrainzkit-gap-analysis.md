# ListenBrainzKit gap analysis

Snapshot: 2026-09-17. Server `e83a7ab`; ListenBrainzKit base `c06b12f` (2025-02-05) plus the local audited extensions.

| Area | Classification | Current finding | Decision |
|---|---|---|---|
| User search/token validation | SUPPORTED | Typed public API | Reuse |
| Recent listens/count/Playing Now | SUPPORTED | Timestamp pagination and listen submission included | Reuse after transport fix |
| Delete/submit/batch submit | SUPPORTED | Correct product operations exist | Reuse; keep capture separate |
| Similar users/pairwise similarity | SUPPORTED | Typed models | Reuse |
| Followers/following/follow/unfollow | SUPPORTED | Typed social client with endpoint-specific status handling | Reuse native Social slice; upstream candidate |
| Connected services/latest import | SUPPORTED | Core client methods | Reuse later |
| Metadata lookup/manual mapping | SUPPORTED | Recording, release group, artist, bulk/fuzzy mapping | Reuse behind metadata resolver |
| Top artist/release/release-group/recording | SUPPORTED | User and sitewide | Reuse |
| Listening activity | SUPPORTED | User and sitewide | Reuse |
| Recording feedback | SUPPORTED | Love/hate/clear and lookup | Reuse |
| Playlist lists/search/detail | SUPPORTED | User/created-for/collaborator/recommendation listings, public search, and complete typed JSPF detail/track payloads | Reuse; detail extension is an upstream candidate |
| LB Radio | PARTIALLY_SUPPORTED | Tags and artist seed only | Re-evaluate against current prompt-generation API |
| New activity/identity statistics | MISSING | Daily, artist, era, genre, evolution, map, listeners absent | Add in a focused upstream extension |
| Year in Music | MISSING | Current and legacy endpoints absent | App extension first; upstream candidate |
| Pins | PARTIALLY_SUPPORTED | Current pin, paginated history, create, unpin, note update, and delete are typed; following pins remain absent | Reuse native slice; add following pins with Social; upstream candidate |
| Social feed/thanks | MISSING | Relationship endpoints are now covered; feed events and actions remain absent | Focused extension in Phase 3 |
| Recommendations and feedback | MISSING | CF retrieval/feedback absent | App extension in Discover phase |
| Popularity | MISSING | Entity counts and artist top entities absent | App extension for detail screens |
| Fresh Releases/explore | SUPPORTED | Personalized and sitewide Fresh Releases, tolerant models, explicit 204 empty result | Discover slice; Music Neighborhood and AI Brainz remain missing |
| Art/share endpoints | MISSING | Grid/stat/YiM/playlist art absent | Small typed art service |
| Playlist mutations/import/export | MISSING | Create/edit/delete, items, ordering, copy, import/export absent | Focused playlist extension after browse paths |
| Player/JSPF resolution | MISSING | Instant-play endpoints absent | Delay until read paths are strong |
| Settings/status/data tools | MISSING | Preferences and maintenance endpoints absent | Add only when UI requires them |

## Blocking defects to fix in a local MPL-preserving fork

1. `APIClient` uses `URL.appending(component:)` with request strings such as `/1/user/...`; Foundation percent-encodes the slashes into one component. Use path-safe URL construction and cover it with a URL test.
2. Requests omit the API-required contactable `User-Agent`.
3. HTTP 429 is surfaced but rate-limit response headers are discarded and there is no one-request-per-second scheduler.
4. `MbidMapping` requires identifiers that current responses can omit/null; app-facing mapping must be tolerant.
5. Most unexpected HTTP statuses collapse to `unknownError`, losing useful recovery information.

## Build result

The development-only SwiftLint plugin was removed from the vendored package target because it prevented clean consumers from building under Command Line Tools. Under Xcode 27, `swift test` builds successfully and runs 68 tests with the token-dependent and opt-in live suites skipped. A separate, explicitly paced `LISTENBRAINZ_PUBLIC_SMOKE=1` run passes against current production recent-listen, count, Playing Now, top-artist, listening-activity, current/history Pins, sitewide Fresh Releases, public-playlist search, and canonical user-search endpoints.

The local fork also now verifies path-safe endpoint construction, endpoint-required trailing slashes (including release-group metadata), required User-Agent behavior, omission of empty authorization, explicit authorization before a custom API origin receives a token, rejection of insecure roots and cross-origin authenticated redirects, conservative interpretation of `Retry-After` / `X-RateLimit-Reset-In`, tolerant playlist timestamps, complete JSPF identity decoding, the Pins API's distinct string versus Boolean mutation responses, and exact social relationship paths/status contracts.

## Recommendation

Use an MPL-2.0 local fork for P0 core listens, metadata, basic stats, and feedback; make only the transport/policy/model fixes needed to become reliable. Keep `ListeningProvider` as the app-facing boundary. Add missing generic endpoint groups as small extensions and prepare them as upstreamable commits. Do not adopt KMP merely to fill API gaps today.

Evidence: `References/ListenBrainzKit/Package.swift`, `Sources/ListenBrainzKit/API/APIClient.swift`, the public client files, and current server views/docs.
