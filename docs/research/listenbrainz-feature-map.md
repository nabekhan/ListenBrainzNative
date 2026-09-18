# ListenBrainz capability map

Snapshot: 2026-09-17. `Y` means source/API evidence exists; `P` means partial or narrower coverage; `—` means no evidence found; `?` means the audit could not establish it. Website evidence comes from the current production frontend source because the production site requires JavaScript and the configured interactive browser was unavailable.

| User capability | API | Web | Android | iOS | LBKit | KMP | Priority | Product decision |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|---|
| Token validation/authentication | Y | Y | Y | Y | Y | Y | P0 | Token-first onboarding; Keychain storage |
| Recent and historical listens | Y | Y | Y | Y | Y | Y | P0 | Flagship paginated, date-grouped history |
| Playing Now | Y | Y | Y | P | Y | Y | P0 | Home hero and conditional bottom accessory |
| Listen count | Y | Y | Y | Y | Y | Y | P0 | Profile/home summary |
| Delete a listen | Y | Y | Y | ? | Y | Y | P1 | Context action with confirmation/rollback |
| Submit/batch-submit/Playing Now | Y | Y | Y | ? | Y | Y | P2 | Separate capture layer; do not block viewer |
| User search and visited-user profiles | Y | Y | Y | Y | Y | Y | P1 | Native scoped search/profile landed with staged reads, bounded cache, and no N+1 hydration |
| Artist/release/recording search | Y* | Y | Y | — | — | Y | P1 | Native MusicBrainz scopes landed; `*` adjacent MB APIs |
| Playlist search | Y | Y | Y | — | Y | Y | P1 | Public search added to LBKit and native scoped search |
| Recording/release-group/artist metadata | Y | Y | Y | P | Y | Y | P0 | MBIDs are canonical identities |
| Release/release-group detail and track listing | Y/P | Y | Y | P | P | Y | P0 | Native release-group enrichment landed; full concrete-release track listing remains |
| Inspect raw listen/mapping state | Y | Y | P | ? | P | P | P2 | Advanced detail sheet |
| Manual metadata mapping | Y | Y | ? | ? | Y | ? | P3 | Advanced workflow only |
| Recording love/hate/clear feedback | Y | Y | P | P | Y | P | P1 | Optimistic action with rollback |
| Pins/current pin/pin history/blurb | Y | Y | Y | Y | Y | Y | P1 | Native current/history and owner mutations landed; following pins remain for Social |
| Top artists | Y | Y | Y | Y | Y | Y | P0 | Vertical slice |
| Top releases/albums | Y | Y | Y | Y | Y | Y | P0 | Vertical slice |
| Top release groups | Y | Y | Y | P | Y | P | P1 | Preserve release/release-group distinction |
| Top recordings/tracks | Y | Y | Y | Y | Y | Y | P0 | Vertical slice |
| Listening activity | Y | Y | Y | Y | Y | Y | P0 | Native Swift Charts |
| Daily/hour-of-day activity | Y | Y | Y | Y | — | P | P1 | Heatmap/histogram |
| Artist activity | Y | Y | Y | P | — | P | P1 | Explain listening mix |
| Genre activity | Y | Y | Y | P | — | P | P1 | Show only with adequate mapped metadata |
| Era activity | Y | Y | Y | P | — | P | P1 | Server-derived; group decades in UI |
| Artist evolution activity | Y | Y | Y | P | — | P | P1 | Taste-over-time view |
| Artist map | Y | Y | Y | Y | — | P | P2 | Map only when data is meaningful |
| Sitewide statistics/context | Y | Y | P | ? | P | P | P2 | Use sparingly for context |
| Entity popularity/listener counts | Y | Y | Y | ? | — | P | P1 | Artist/release/track context |
| Year in Music (2021–2025) | Y | Y | Y | Y | — | P | P1 | First-class native story; 2025 is current |
| Similar users and compatibility | Y | Y | Y | Y | Y | Y | P1 | Native Social destination landed without row hydration |
| Followers/following | Y | Y | Y | Y | Y | Y | P1 | Complete native lists; typed Kit extension |
| Follow/unfollow | Y | Y | Y | ? | Y | Y | P1 | Optimistic serialized mutation with rollback |
| Social feed/timeline | Y | Y | Y | Y | Y | Y | P1 | Native My Feed read surface; unknown event types survive and malformed nested metadata is tolerated |
| Following/similar-user listen feeds | Y | Y | Y | Y | Y | Y | P1 | Separate modes; exact-oldest cursor, stable dedupe, and stable seven-day recent-window semantics |
| Recommend recording/personal blurb | Y | Y | Y | Y | — | Y | P1 | Read/event presentation landed; action remains staged |
| Reviews/CritiqueBrainz events | Y | Y | Y | Y | — | Y | P2 | Link/write where useful |
| Thanks/hide/unhide/delete feed event | Y | Y | Y | P | — | Y | P2 | Read-only event presentation landed; mutations remain staged |
| Collaborative-filter recommendations | Y | Y | Y | P | Y | P | P1 | Native For You tracks landed with paginated batch hydration; feedback remains staged |
| Recommendation feedback | Y | Y | P | P | — | P | P1 | Train server recommendations |
| Fresh Releases | Y | Y | P | P | Y | — | P1 | Native Discover grid; personalized default and explicit sitewide scope |
| Created For You/recommended playlists | Y | Y | Y | Y | Y | Y | P1 | Lazy native For You list uses server generator/expiry metadata and the shared playlist detail |
| User/collaborator playlists | Y | Y | Y | Y | P | Y | P1 | Browse before edit |
| Playlist detail/create/edit/delete | Y | Y | Y | P | P | Y | P2 | Native one-request detail landed; mutations remain staged |
| Playlist add/remove/reorder/copy | Y | Y | Y | ? | — | Y | P2 | Stage after playlist detail |
| Playlist import/export/service sync | Y | Y | P | ? | — | P | P3 | Advanced feature |
| LB Radio tags/artist radio | Y | Y | ? | — | P | ? | P2 | Native prompt/generation only when stable |
| BrainzPlayer queue/content resolution | Y | Y | Y | P | — | P | P2 | Keep modular; viewing is not blocked |
| Apple/Spotify/YouTube/etc. external play | Y/P | Y | P | P | — | P | P2 | Resolve/open externally before full player |
| Linked music services | Y | Y | Y | ? | Y | Y | P2 | Settings visibility/connection handoff |
| Shareable art/stat grids/YiM art | Y | Y | P | P | — | ? | P1 | Prefer server-generated SVG |
| HueSound/color exploration | Y | Y | — | — | — | — | P3 | Delightful but niche |
| Music Neighborhood/similar artists | Y | Y | P | — | — | P | P2 | Discovery graph/list, not a heavy graph UI |
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

## Evidence

- API categories and policy: `References/listenbrainz-server/docs/users/api/`
- Current website routes/screens: `References/listenbrainz-server/frontend/js/src/`
- Current server endpoint implementations: `References/listenbrainz-server/listenbrainz/webserver/views/`
- Android/KMP: `References/listenbrainz-android/shared/src/` and `app/src/`
- Official iOS: `References/listenbrainz-ios/Listenbrainz/`
- Swift wrapper: `References/ListenBrainzKit/Sources/ListenBrainzKit/`
