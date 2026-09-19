# ListenBrainzKit gap analysis

Snapshot: 2026-09-19. Server `e83a7ab`; ListenBrainzKit base `c06b12f` (2025-02-05) plus the local audited extensions.

| Area | Classification | Current finding | Decision |
|---|---|---|---|
| User search/token validation | SUPPORTED | Typed public API | Reuse |
| Recent listens/count/Playing Now | SUPPORTED | Strict `min_ts`/`max_ts` bounds, timestamp pagination, and listen submission included | Reuse through the shared gate; app-owned History state supplies DST-safe local-day bounds and overlap de-duplication |
| Delete listen | SUPPORTED | Exact authenticated timestamp/MSID request exists; local regression coverage now fixes the path, method, body, status map, and truncated-second encoding | Reuse through the shared mutation gate; native History flow adds account validation and durable accepted/uncertain replay protection |
| Submit/batch submit | SUPPORTED | Typed single, batch, and Playing Now submission operations exist | Reuse later; keep capture separate from the viewer |
| Similar users/pairwise similarity | SUPPORTED | Typed models | Reuse |
| Followers/following/follow/unfollow | SUPPORTED | Typed social client with endpoint-specific status handling | Reuse native Social slice; upstream candidate |
| Connected services/latest import | SUPPORTED | Core client methods | Reuse later |
| Metadata lookup/manual mapping | SUPPORTED | Recording, release group, artist, bulk/fuzzy mapping | Reuse behind metadata resolver |
| Concrete release/ordered track lookup | MISSING | Kit `releaseGroup` metadata does not model a MusicBrainz edition or its media/tracks | Use one separately gated MusicBrainz release lookup; do not mislabel group metadata or hydrate tracks individually |
| Top artist/release/release-group/recording | SUPPORTED | User and sitewide | Reuse |
| Listening activity | SUPPORTED | User and sitewide | Reuse |
| Daily/hour-of-day activity | SUPPORTED | Typed user daily-activity response, optional server range, 7×24 UTC buckets, and honest 204 handling | Reuse through the shared gate; local extension is an upstream candidate |
| Era activity | SUPPORTED | Typed user era-activity response, optional server range, release-year counts, and honest 204 handling | Reuse through the shared gate; local extension is an upstream candidate |
| Artist evolution activity | SUPPORTED | Typed user response accepts documented string and real numeric time buckets, optional/missing artist MBIDs, all statistics ranges, and honest 204 handling | Reuse on demand through the shared gate; local extension is an upstream candidate |
| Genre activity | SUPPORTED | Typed top-genre-per-UTC-hour aggregate, optional server range, tolerant rows, and honest 204 handling | Reuse on demand through the shared gate; do not misrepresent it as a complete genre distribution; local extension is an upstream candidate |
| Artist map / origins | SUPPORTED | Typed user and sitewide routes preserve country artist/listen totals, optional embedded artists/MBIDs, all statistics ranges, tolerant legacy numbers, and honest 204 handling | Reuse on demand through one exact user/range gate key; local extension is an upstream candidate |
| Recording feedback | SUPPORTED | Love/hate/clear and lookup | Reuse |
| Playlist lists/search/detail | SUPPORTED | Typed paginated user/created-for/collaborator listings preserve server count/offset/total metadata; public search and complete JSPF detail/track payloads are also typed | Reuse; page/detail extensions are upstream candidates and now power native Profile/For You/search paths |
| LB Radio | SUPPORTED | Existing tag/artist datasets plus a typed authenticated `/1/explore/lb-radio` generator with tolerant JSPF/feedback decoding, exact mode/query semantics, and malformed-response protection | Reuse through the shared gate; generated-radio extension is an upstream candidate |
| Other activity/identity statistics | MISSING | Artist activity and ranked listener counts remain absent | Add in focused upstream extensions |
| Year in Music | SUPPORTED | Typed current-schema aggregate endpoint with explicit-year path, partial/empty tolerance, 204 handling, and flexible identifiers/evolution buckets; legacy routes remain absent | Reuse through one gated request; local extension is an upstream candidate |
| Pins | PARTIALLY_SUPPORTED | Current pin, paginated history, create, unpin, note update, and delete are typed; following pins remain absent | Reuse native slice; add following pins with Social; upstream candidate |
| Social feed reads | SUPPORTED | Typed aggregate, following, and similar feed pages; tolerant nested metadata; one request per page | Reuse native feed slice; upstream candidate |
| Feed mutations (thanks/hide/unhide/delete/recommendations) | SUPPORTED | Typed public/personal recommendation creation plus thanks, hide, unhide, and generic deletion with endpoint-specific bodies/status maps | Reuse native social-action slices; upstream candidate |
| Recommendations and feedback | SUPPORTED | Typed paginated CF retrieval plus submit/delete, paginated, and batched recommendation-feedback APIs | Reuse native For You slice; upstream candidate |
| Popularity | PARTIALLY_SUPPORTED | Typed batch counts for artist, recording, concrete release, and release group; nullable missing data and max-1000 validation preserved; artist-ranked entities remain absent | Reuse through the shared gate and 24-hour entity cache; ranked artist shelves remain staged |
| Fresh Releases/explore | SUPPORTED | Personalized and sitewide Fresh Releases, tolerant models, explicit 204 empty result | Discover slice; Music Neighborhood and AI Brainz remain missing |
| Art/share endpoints | PARTIALLY_SUPPORTED | Typed Year in Music SVG generation covers all seven current variants, encoded paths, 204, MIME/root validation, and bounded payloads; grid/stat/custom/playlist art remains absent | Reuse the gated YiM overview slice; extend only when another native surface needs it |
| Playlist create/edit/add items/copy | SUPPORTED | Typed exact-JSPF create (empty or ordered populated canonical recording MBIDs), full-snapshot metadata edit, append for 1...100 canonical recording MBIDs, and empty-body copy returning the new MBID, including endpoint-specific errors and strict success-envelope validation | Reuse through the shared gate; local MPL extensions are upstream candidates; native UI creates private Radio playlists, appends one item, and duplicates visible playlists |
| Playlist single-item removal | SUPPORTED (local extension) / DUPLICATED_IN_KMP | Local MPL-preserving Kit extension now sends the current `POST /1/playlist/{mbid}/item/delete` body `{index, count: 1}` with exact status handling; official shared Android/KMP code has the same endpoint shape | Reuse the small Kit extension today. Native SwiftUI owns fresh preflight, durable no-replay/review state, and canonical reconciliation; keep KMP optional |
| Playlist delete/reorder/import/export | MISSING | Whole-playlist deletion, positional movement, import, and export remain absent | Add only with a concrete native workflow and mutation-specific reconciliation |
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

The development-only SwiftLint plugin was removed from the vendored package target because it prevented clean consumers from building under Command Line Tools. Under Xcode 27, `swift test` builds successfully and runs 122 tests with the token-dependent and opt-in live suites skipped. A separate, explicitly paced `LISTENBRAINZ_PUBLIC_SMOKE=1` run passes against current production recent-listen, count, Playing Now, top-artist, artist-popularity, listening-activity, current/history Pins, sitewide Fresh Releases, public-playlist search, and canonical user-search endpoints.

The local fork also now verifies path-safe endpoint construction, endpoint-required trailing slashes (including release-group and recording metadata), default JSON content types for encoded bodies, required User-Agent behavior, omission of empty authorization, explicit authorization before a custom API origin receives a token, rejection of insecure roots and cross-origin authenticated redirects, conservative interpretation of `Retry-After` / `X-RateLimit-Reset-In`, tolerant playlist timestamps, complete JSPF identity decoding, exact playlist create/edit/append payloads and append bounds/status envelopes, the exact empty-body copy path/response/status map, generated-radio query/schema/error handling, typed CF recommendation paging, typed daily-activity, era-activity, artist-evolution, genre-activity, current Year in Music, Year in Music SVG variants/response validation, and four-entity popularity decoding/path/body/null/limit semantics, the Pins API's distinct string versus Boolean mutation responses, exact social relationship and feed-mutation paths/body keys/status contracts, and tolerant typed feed reads. Artist evolution tolerates both string and numeric server buckets plus absent/null MBIDs. Genre Activity accepts safe numeric strings but filters malformed hours and never invents a canonical identity for free-text genre names. Year in Music tolerates partial/empty report objects, non-UUID identifiers, and both numeric/string evolution buckets. Its art client preserves raw validated SVG, maps 204 to unavailable, and rejects malformed, wrong-MIME, empty, and oversized responses. Generated radio accepts the server's singular JSPF track collection and plural empty fallback without turning malformed payloads into empty mixes. Each CF page uses one recommendation request and, only when it contains MBIDs, one batch metadata request rather than per-row hydration. Each feed page is one request with embedded metadata; the aggregate feed currently excludes ordinary listens, while Following and Similar are listen-only recent windows.

## Recommendation

Use an MPL-2.0 local fork for P0 core listens, metadata, basic stats, and feedback; make only the transport/policy/model fixes needed to become reliable. Keep `ListeningProvider` as the app-facing boundary. Add missing generic endpoint groups as small extensions and prepare them as upstreamable commits. Do not adopt KMP merely to fill API gaps today.

Evidence: `References/ListenBrainzKit/Package.swift`, `Sources/ListenBrainzKit/API/APIClient.swift`, the public client files, and current server views/docs.
