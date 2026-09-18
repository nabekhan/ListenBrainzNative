# Repository reuse map

Snapshot: 2026-09-17. Repository/source inspection, Xcode 27 builds, simulator runs, and live public-data checks are complete for the implemented slices.

| Repository | Purpose / state | License | Best reusable value | Modernization / difficulty | Decision |
|---|---|---|---|---|---|
| ListenBrainz server | Authoritative API + production web, active today | GPL-2.0 | Product semantics, current API, UI relationships | Never transplant frontend code | Reference only |
| ListenBrainz Android/KMP | Mature official client; active | GPL-3+ with stated Apache sections | Edge cases, feature behavior, shared service shapes | KMP framework/export weight is high | Reference now; re-evaluate sharedKit |
| ListenBrainz iOS | Official SwiftUI beta, iOS 16.2 | GPL-3+ with stated Apache sections | Apple constraints, feed/YiM/profile behavior | Combine/Alamofire architecture and uneven feature depth | Reference; independently implement |
| ListenBrainzKit | Swift 6 API wrapper, iOS 16+, last commit 2025-02 | MPL-2.0 | P0 core, metadata, stats, feedback, playlist, and typed CF recommendation calls | Fix transport/rate policy; fill gaps incrementally | Vendor/fork under MPL |
| first.fm | Last.fm SwiftUI client, iOS 15.5, 2024 | MIT | Overall IA/personality; profile, scrobbles, rankings, entity pages, search | Replace callbacks/ObservableObject and Spotify artwork N+1 | Adapt concepts and selected MIT components |
| AppleMusicBottombarSwiftUI | iOS 26 accessory/transition demo, active 2026 | No license | `tabViewBottomAccessory`, minimized bar, zoom transition behavior | Small, current, but legally non-reusable | Independently reproduce with Apple APIs |
| Cassette | Full SwiftUI music app, iOS 18, active 2026 | MPL-2.0 | Media rows/cards/shelves, entity/detail VMs, empty/loading UI, Fresh Releases, LB behavior | Large but clean; preserve file notices | Selectively adapt MPL files |
| Minidisc | Cassette fork, iPhone-first iOS 26, active 2026 | MPL-2.0 | Polished tab/accessory behavior, home shelves, palette, quick actions, offline queue | iOS 26-only source; inherited attribution | Primary current interaction donor |
| Volta | Rich SwiftUI player, iOS 16, active 2026 | GPL-3.0 | Artist hero, artwork-derived background, top songs, transitions | GPL incompatible with intended MPL app unless whole app GPL | Visual reference only |
| Autohop | Native podcast/history/stats app, iOS 17, active 2026 | MIT; four named MPL files | Stats coordinator/store, heatmap/trends/period interaction | Translate time metrics to listen counts; avoid exception files | Adapt MIT stats patterns |
| Beans Music | SwiftUI multi-service player, iOS 15, active 2026 | MIT | Compact root/tab/history/cache patterns | Service-specific; less cohesive than Cassette | Secondary component reference |
| Bòcan Music | Very large Swift 6 desktop media app, active 2026 | Apache-2.0 | Cache/persistence and Now Playing strip patterns | Desktop-first and oversized | Selective reference/Apache reuse only |
| FastScrobbler | Apple Music + ListenBrainz/Last.fm behavior, active 2026 | No license | Retry/backlog/duplicate avoidance, MusicKit constraints | Legally reference-only | Scrobbling behavior reference |
| Finale | Cross-platform Last.fm app | BSD-3-Clause | Widgets, story/collage ideas | Flutter core, not native presentation | Inspiration/selective BSD widget ideas |
| Discrobble | KMP + SwiftUI architecture docs | MIT | ADRs for shared-core/native UI boundary | No meaningful Swift implementation | Architecture reference only |

## Component ownership

| Requirement | Best donor | What can be reused | What is written here |
|---|---|---|---|
| Overall information architecture | first.fm + current LB web | Profile/history/ranking hierarchy and LB product grouping | Native tab/search flow for Home, History, Discover, Stats, Profile |
| API/domain | ListenBrainzKit | Existing P0 clients/models | Reliability fixes, app adapters, typed CF/social/pins/detail extensions |
| Product behavior | LB API/web + Android | Semantics, event types, pagination, edge cases | Native iOS interaction |
| Bottom accessory | Apple native APIs + Minidisc behavior | System API behavior; MPL patterns where needed | Conditional Playing Now/latest-listen accessory |
| History/listen row | first.fm + LB website + official clients | Dense scrobble hierarchy and website date-jump behavior; no GPL UI copied | MSID-stable paginated rows, exact local-day bounds, adjacent-day navigation, transient filtered state, feedback/context menu, and accessibility-responsive layout |
| Home shelves | Cassette/Minidisc | Shelf sizing, section headers, loading/empty states | LB-specific curation |
| Artist screen | Volta visual reference + first.fm | Concept only from GPL Volta; MIT structure from first.fm | Independent stretchy artwork/stat/entity implementation |
| Release/recording detail | Minidisc/Cassette + first.fm + current LB/MusicBrainz behavior | Album hierarchy, compact facts, ordered-row patterns, and release/release-group semantics; no donor UI copied | Independent native edition/group pages, one gated MusicBrainz track-list request, stable canonical identities, and bounded stale-while-revalidate caches |
| Playlist detail | Current LB JSPF API + Android behavior + Cassette media patterns | Payload semantics and native artwork/list hierarchy; no GPL UI copied | One-request typed detail, mosaic, creator/metadata summary, lazy non-hydrating track rows, and Created For You entry points |
| For You recommendations | Current LB API/web + Android/KMP behavior | CF paging, feedback semantics, generated-playlist taxonomy, and empty-state behavior; no donor UI copied | Independent native SwiftUI tracks/playlists surface, one batched metadata hydration request per nonempty page, one batched feedback read, and optimistic four-valued feedback controls |
| Stats/heatmap | Autohop MIT patterns + current LB API/web behavior + native Swift Charts | Period/history interaction concepts; no donor code copied | Typed daily-activity adapter, normalized cached UTC 7×24 heatmap, server activity charts, and music wording |
| Scoped search | Official Android behavior + first.fm structure + Minidisc limiter concept | One-scope debounce/cache behavior and cancellation-safe pacing concepts; no donor UI copied | Native search sheet, separate LB/MB gates, MBID-aware routing, compact truthful fallbacks |
| Visited-user profile | Current LB web + official Android/iOS behavior + first.fm personality | Profile hierarchy and ListenBrainz semantics; no GPL UI copied | Staged native overview, latest context, pin, listens, lazy stats, section-aware bounded cache |
| User social graph | Current LB API/web + official Android/KMP behavior | Relationship semantics and similarity direction; no GPL UI copied | Lazy native destination, isolated viewer/public caches, non-hydrating rows, optimistic follow rollback |
| Social feed and actions | Current LB API/web + official Android/KMP behavior + Cassette selection/dialog patterns | Event/action taxonomy, server eligibility, cursor semantics, and native multi-select/confirmation interaction; no GPL or donor UI copied | Native My Feed/Following/Similar cards, stable-ID thanks/hide/delete, and public/personal recording sharing through one shared request gate |
| Pins | Current LB API/web + official Android/iOS behavior | Product semantics and response contracts; no GPL UI copied | Typed MPL Kit extension, profile card, lazy history, owner actions, optimistic rollback |
| Auth/Keychain | first.fm/Cassette patterns | Small MIT/MPL patterns | Token validation and onboarding copy |
| Caching | Cassette/Minidisc + URLCache | Actor/service patterns | Small stale-while-revalidate cache boundary |
| Scrobbling/offline retry | FastScrobbler behavior + Cassette/Minidisc | MPL queue code only if later adopted | Deferred capture module |

## Additional discovery verdict

The strongest newly discovered candidates are Minidisc (current iPhone/iOS 26 polish), Bòcan (cache/robust scrobbling reference), FastScrobbler (Apple Music limitation evidence), and Finale (widgets/share concepts). None displaces first.fm for personality/IA or Cassette/Minidisc for current native media components.
