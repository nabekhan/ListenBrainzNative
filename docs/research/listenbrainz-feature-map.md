# ListenBrainz capability map

Snapshot: 2026-09-25. `Y` means source/API evidence exists; `P` means partial or narrower coverage; `—` means no evidence found; `?` means the audit could not establish it. Website evidence combines current production frontend source with targeted live mobile inspection through an isolated temporary browser setup.

| User capability | API | Web | Android | iOS | LBKit | KMP | Priority | Product decision |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|---|
| Token validation/authentication | Y | Y | Y | Y | Y | Y | P0 | Token-first onboarding; Keychain storage |
| Recent and historical listens | Y | Y | Y | Y | Y | Y | P0 | Flagship paginated history with exact server-bounded local-day navigation plus presentation-only search across already-loaded canonical and submitted artist, release, and track metadata; server-wide filtering remains unsupported |
| Playing Now | Y | Y | Y | P | Y | Y | P0 | Home hero and conditional bottom accessory |
| Listen count | Y | Y | Y | Y | Y | Y | P0 | Profile/home summary |
| Delete a listen | Y | Y | Y | — | Y | Y | P1 | Native authenticated History action landed with track-specific confirmation, exact timestamp/MSID identity, durable ambiguous-outcome protection, and no automatic replay |
| Submit/batch-submit/Playing Now | Y | Y | Y | ? | Y | Y | P2 | Separate capture layer; do not block viewer |
| User search and visited-user profiles | Y | Y | Y | Y | Y | Y | P1 | Native scoped search/profile landed with staged overview, independently lazy all-time artist, release, and track sections, plus explicit Playlists and Year in Music destinations; no destination request starts until it is opened |
| Artist/release/recording search | Y* | Y | Y | — | — | Y | P1 | Native MusicBrainz scopes landed; `*` adjacent MB APIs |
| Playlist search | Y | Y | Y | — | Y | Y | P1 | Public search added to LBKit and native scoped search |
| Recording/release-group/artist metadata | Y | Y | Y | P | Y | Y | P0 | MBIDs are canonical identities |
| Release/release-group detail and track listing | Y/P | Y | Y | P | P | Y | P0 | Native group pages plus one-request MusicBrainz edition pages with ordered media/tracks; identities stay distinct |
| Inspect raw listen/mapping state | Y | Y | P | ? | P | P | P2 | Native read-only Listen details sheet preserves returned submitted metadata, MSID, mapping and source fields without a follow-up request |
| Manual metadata mapping | Y | Y | ? | ? | Y | — | P3 | Native advanced flow uses explicit debounced MusicBrainz recording search, preserves submitted-recording-ID precedence, and sends one serialized no-retry save; it performs no mapping-status read, poll, or automatic refresh |
| Recording love/hate/clear feedback | Y | Y | P | P | Y | P | P1 | Optimistic action with rollback |
| Pins/current pin/pin history/blurb | Y | Y | Y | Y | Y | Y | P1 | Home and Profile share one guarded current-pin read; history stays lazy, owner mutations are native, and Following Pins stays aggregate and non-hydrating |
| Top artists | Y | Y | Y | Y | Y | Y | P0 | Vertical slice |
| Top releases/albums | Y | Y | Y | Y | Y | Y | P0 | Vertical slice |
| Top release groups | Y | Y | Y | Y | Y | P | P1 | Lazy native Taste ranking; one cached aggregate read, canonical group routing, no row hydration, and no release-identity conflation |
| Top recordings/tracks | Y | Y | Y | Y | Y | Y | P0 | Home and signed-in Profile reuse already-loaded rankings; visited profiles add one lazy cached aggregate read |
| Listening activity | Y | Y | Y | Y | Y | Y | P0 | Native Swift Charts |
| Daily/hour-of-day activity | Y | Y | Y | Y | Y | — | P1 | Native cached, selectable 7×24 UTC heatmap across the seven server periods |
| Artist activity | Y | Y | Y | P | Y | P | P1 | Native on-demand ranked artist/album report landed; one cached aggregate read per selected range and no row hydration |
| Genre activity | Y | Y | Y | P | Y | P | P1 | Native one-request local-daypart view landed; labels it as incomplete top-per-hour genre-tag matches and explains overlap/time-zone approximation |
| Era activity | Y | Y | Y | P | Y | P | P1 | Native cached Music by Decade chart with server-derived years and decade-to-year drill-down |
| Artist evolution activity | Y | Y | — | — | Y | — | P1 | Native on-demand top-artist timeline with touch inspection; one server request per selected range |
| Artist map / origins | Y | Y | Y | Y | Y | P | P1 | Native on-demand ranked-country report landed with local Artists/Listens ranking and embedded artist detail; geographic map remains optional |
| Sitewide statistics/context | Y | Y | P | ? | P | P | P2 | Use sparingly for context |
| Entity popularity/listener counts | Y | Y | Y | ? | Y | P | P1 | Native global listens/listeners context landed on canonical artist, recording, release, and release-group details; daily cache and no row hydration |
| Artist/release-group top listeners | Y | Y | Y | — | Y | P | P1 | Native all-time rankings landed on canonical artist and release-group details; one cached aggregate read, local expand, and no row hydration |
| Year in Music (2021–2025) | Y | Y | Y | Y | Y | P | P1 | Native current/archive story works for the signed-in or a visited user, reuses one subject-keyed aggregate for identity, evolution, new releases, and read-only Discoveries/Missed playlist snapshots, and adds no row hydration |
| Similar users and compatibility | Y | Y | Y | Y | Y | Y | P1 | Native Social destination landed without row hydration |
| Followers/following | Y | Y | Y | Y | Y | Y | P1 | Complete native lists; typed Kit extension |
| Follow/unfollow | Y | Y | Y | ? | Y | Y | P1 | Optimistic serialized mutation with rollback |
| Social feed/timeline | Y | Y | Y | Y | Y | Y | P1 | Native My Feed read surface; unknown event types survive and malformed nested metadata is tolerated |
| Following/similar-user listen feeds | Y | Y | Y | Y | Y | Y | P1 | Separate modes; exact-oldest cursor, stable dedupe, and stable seven-day recent-window semantics |
| Recommend recording/personal blurb | Y | Y | Y | Y | Y | Y | P1 | Native public and follower-only personal sharing landed with cached multi-select recipients and 280-character notes |
| Reviews/CritiqueBrainz events | Y | Y | Y | Y | — | Y | P2 | Native highlights and a full-text reader landed for every row in the existing five-review page; there is no pagination or all-reviews fetch, and writing/voting remains staged |
| Thanks/hide/unhide/delete feed event | Y | Y | Y | P | Y | Y | P2 | Native eligibility-aware actions landed with stable row IDs, optimistic rollback, hidden-card privacy, and dedicated pin deletion |
| Collaborative-filter recommendations | Y | Y | Y | P | Y | P | P1 | Native For You tracks landed with paginated batch hydration; feedback remains staged |
| Recommendation feedback | Y | Y | P | P | Y | P | P1 | Native Hate/Dislike/Like/Love control with batched state reads, tap-again clear, optimistic rollback, and pending-action serialization |
| Fresh Releases | Y | Y | P | P | Y | — | P1 | Native Discover grid with personalized/sitewide scope, supported 7/30/90-day windows, past/upcoming selection, server-backed ordering, and zero-request local type/tag filters |
| Created For You/recommended playlists | Y | Y | Y | Y | Y | Y | P1 | Lazy native For You list uses server generator/expiry metadata and the shared playlist detail |
| User/collaborator playlists | Y | Y | Y | Y | Y | Y | P1 | Native owned/collaborating pages now open from both self and visited profiles with lazy server pagination, viewer-scoped private access, public fallback, and no row hydration |
| Playlist detail/create/edit/delete | Y | Y | Y | P | P | Y | P2 | Native one-request detail, authenticated empty creation, owner metadata/privacy editing, and fail-closed creator-only deletion landed |
| Add recording to playlist | Y | Y | Y | ? | Y | Y | P2 | Native append-only mapped-recording flow landed for owned/collaborating destinations, with best-effort duplicate preflight and no mutation replay |
| Playlist copy/duplicate | Y | Y | Y | — | Y | Y | P2 | Native one-shot copy of any visible playlist landed with forced preflight, canonical returned-MBID navigation, and a persistent token-free ambiguous-result barrier |
| Playlist item remove/reorder | Y | Y | Y | ? | Y* | Y | P2 | Safe single-item removal and one-track positional reordering landed with fresh whole-order verification, one no-retry POST, durable shared recovery, and exact postflight confirmation; `*` uses local MPL Kit extensions, while multi-item changes remain staged |
| Playlist import/export/service sync | Y | Y | P | ? | — | P | P3 | Advanced feature |
| LB Radio generation/tags/artist radio | Y | Y | P | — | Y | — | P2 | Native explicit recipe generation, ordered canonical-track private-playlist saves, and playlist browsing landed; playback/content resolution remains separate |
| BrainzPlayer queue/content resolution | Y | Y | Y | P | — | P | P2 | Keep modular; viewing is not blocked |
| Apple/Spotify/YouTube/etc. external play | Y/P | Y | P | P | P* | P | P2 | Native zero-request actions now open strict canonical Spotify, YouTube, SoundCloud, Apple Music, Internet Archive, Bandcamp, Deezer, and TIDAL destinations already embedded in listen metadata; one action stays direct and multiple services use one menu. `*` is a small local URL-relationship decoding extension; content search, account linking, and in-app playback remain staged |
| Linked music services | Y (own authenticated account) | Y | Y | P | Y | P | P2 | Lazy native status list and canonical settings handoff; endpoint has no permission detail |
| Shareable art/stat grids/YiM art | Y | Y | P | P | P | P | P1 | Explicit native stats, artist, playlist, and YiM SVG previews/PNG sharing landed; the generic custom-art creator remains staged |
| HueSound/color exploration | Y | Y | — | — | — | — | P3 | Delightful but niche |
| Music Neighborhood/similar artists | Y | Y | P | — | — | P | P2 | Native canonical-artist shelf landed via the guarded public artist-page contract; the experimental Labs graph remains staged |
| AI Brainz | Y | Y | — | — | — | — | P3 | Experimental; not first-release critical |
| Offline listen linking/unmapped-data tools | Y | Y | P | ? | — | P | P3 | Advanced metadata maintenance |
| Timezone, recommendation, player preferences | Y | Y | Y | P | — | P | P2 | Settings after core account experience |
| Account data import/export/delete | Y | Y | P | P | — | P | P3 | Prefer secure web handoff where sensible |
| Flairs/donor identity | Y | Y | — | — | — | — | P3 | Preserve when showing user identity |

## Current product findings

- The website treats **Feed**, **Dashboard**, and **Explore** as its three main areas. User pages add Stats, Taste, Playlists, Recommendations, and Year in Music.
- The server has grown well beyond basic top lists: artist/genre/era/evolution activity, current and legacy Year in Music, social thanks, art generation, playlist import/export, Fresh Releases, Music Neighborhood, and AI Brainz are current surfaces.
- The aggregate social feed currently excludes ordinary listens. Following and Similar are separate listen-only recent feeds, so the native UI keeps those modes distinct instead of implying one unified event stream.
- The iOS product should start with high-value read paths, then add mutations to the same entity screens. Android-only notification-listener scrobbling and foreground playback services have no direct public-iOS equivalent.
- Public API calls were checked against real ListenBrainz data and include messy but useful identity fields: recording MSID, mapped MBIDs, multi-artist credits, Cover Art Archive IDs, service/source metadata, and external URL relations.
- The current Year in Music endpoint is one aggregate request whose 2025 payload can contain totals, UTC day activity, rankings, genres, weekday context, discovery data, release-year counts, similar users, and full JSPF playlists. The native story maps a presence-aware, identity-safe subset—including new artists, weekday, display-only genre tags, release decades, artist evolution, ordered new releases, and the two current annual playlist snapshots—without fanning out into row requests.
- Year in Music reports are public and subject-keyed. The visited-profile destination therefore keeps the authenticated viewer scope for existing transport/cache policy while fetching and attributing the report to the visited username; the shared presentation uses neutral language rather than claiming another person's listening as the viewer's.
- User playlist reads reveal private rows only when the authenticated viewer is the requested profile owner. Visited-profile browsing therefore carries the viewer token for server-authorized visibility but exposes owner-only creation/copy controls only when normalized viewer and subject usernames match.
- LB Radio is an authenticated server-side JSPF generator with a separate five-per-five-second quota. The native slice generates only on an explicit tap, uses the bounded/coalescing shared read lane with global 429 deferral, performs at most one batch metadata enrichment, never auto-retries, and does not imply that an MBID is playable audio. A saved mix becomes one explicit, private populated-playlist POST; nil MBIDs are excluded and duplicate canonical occurrences remain ordered.
- Artist Origins is a public aggregate statistics response built from up to a user's top 1,000 artists that have MusicBrainz country data. The native destination performs one cached user/range read, then ranks by artist or listen count and opens server-embedded country artists locally; it does not issue per-country or per-artist hydration requests.
- Artist Activity is a bounded ranked response derived from mapped release-group statistics: at most 15 leading artists, each with its album/release-group breakdown. The native destination makes one cached user/range read, merges MBID-first identities locally, and opens only identifiers already present in the response; expanding albums makes no request.
- Artist and release-group listener rankings are public, server-computed samples capped at 10 rows. The native detail cards explicitly request `all_time`, cache both content and 204/empty results for five minutes, expand locally, and navigate with embedded usernames without profile hydration.
- Similar Artists on canonical artist pages uses the same public `POST /artist/{artist_mbid}/` payload as the current website and official Android/KMP client, not the experimental authenticated Labs graph. The native shelf makes one lazy anonymous read, preserves the server's ranked order, previews five of at most 18 locally, and mirrors the route's 120-second cache. Exact reads coalesce; empty, missing, malformed, and failed results disappear without breaking Artist Detail; failures renew a short negative/stale cooldown instead of retrying on each revisit; cards use local deterministic artwork and never hydrate rows.
- Popular Tracks and Releases on canonical artist pages reuse that exact combined artist payload rather than starting two documented-but-currently-token-protected, unbounded ranking reads. The native shelf retains the first 10 valid server-ranked recordings and release groups, preserves canonical MusicBrainz identities and embedded global counts, and switches or expands entirely on-device. Recording and release-group taps reuse the app's existing detail destinations.
- Following Pins is a separate public, newest-first aggregate of each followed user's active pin. The native destination makes one bounded request per page, preserves the server count/offset contract, deduplicates by owner plus row ID, caches pages for five minutes, and never hydrates rows individually.
- Generic Art now uses typed public stats/artist reads and the authenticated playlist POST. Every image is created only after a user action, exact requests coalesce through the shared gate, public calls omit the token, private playlist cache entries stay credential-scoped, unavailable results are cached, and raw SVG retention is bounded by both age and 16 MiB total. The shared nonpersistent renderer validates every external SVG resource before loading, blocks all other WebKit traffic, and exports a native PNG; a single public artist smoke rendered the current Archive redirect and placeholder shapes without an account token.
- Ranked recording statistics can carry release identity while the recording itself remains unmapped. Home, signed-in and visited profiles, Taste, Artist Detail, and Year in Music therefore use only a canonical recording MBID to offer Track Detail; release MBIDs and display strings never substitute for recording identity, and this decision requires no hydration request.

## Evidence

- API categories and policy: `References/listenbrainz-server/docs/users/api/`
- Current website routes/screens: `References/listenbrainz-server/frontend/js/src/`
- Current server endpoint implementations: `References/listenbrainz-server/listenbrainz/webserver/views/`
- Android/KMP: `References/listenbrainz-android/shared/src/` and `app/src/`
- Official iOS: `References/listenbrainz-ios/Listenbrainz/`
- Swift wrapper: `References/ListenBrainzKit/Sources/ListenBrainzKit/`
