# Implementation plan

## Research verdict

Build a native SwiftUI application around a small app-owned domain/provider boundary. Start from the fixed ListenBrainzKit fork for P0, reuse current media interaction patterns selectively from MPL/MIT donors, and keep KMP replaceable rather than foundational. The app targets iOS 18 for broad modern API coverage, with iOS 26 enhancements (`tabViewBottomAccessory`, minimized tab bar, zoom transitions) behind availability checks.

## Architecture recommendation

```text
SwiftUI Features + shared Components
              ↓
@Observable feature models
              ↓
App-owned provider boundaries
  ├─ ListeningProvider → ListenBrainzProvider
  ├─ SearchProviding → ListenBrainz + MusicBrainz
  └─ PinProviding → ListenBrainzKit pins extension
  ├─ fixed ListenBrainzKit core/metadata/stats/feedback
  ├─ focused endpoint extensions (only when Kit is missing them)
  └─ per-service request gates + response/metadata caches
              ↓
ListenBrainz / MusicBrainz / Cover Art Archive
```

- Organize concrete feature folders only as screens land: Authentication, Home, History, Recording, Artist, Profile, then Stats/Discover/Social/Playlists.
- UI never imports API response models directly. Stable app models preserve MBID/MSID/release/release-group distinctions and tolerate incomplete mapping.
- One process-shared actor handles the one-request-per-second ListenBrainz policy, serial request ownership, cancellation, and rate-limit reset. MusicBrainz has an independent process-shared gate so unrelated hosts do not block one another. A small typed disk cache supplies stale-while-revalidate snapshots without persisting authenticated HTTP responses.
- Keychain owns the token. No token in defaults/logs/previews.
- Native SwiftUI/Charts/NavigationStack/search/context menus/accessibility first. No third-party architecture framework.

## Vertical slice

1. Token onboarding, validation, Keychain persistence, and explicit demo/public-profile mode for previews.
2. Home: Playing Now or latest listen hero, recent shelf, short listening snapshot, current pin placeholder hook.
3. History: date-grouped paginated recent listens, artwork, exact time/source, pull to refresh, loading/error/empty states.
4. Recording detail: identity, artwork, release/artist links, counts where available, love/hate/pin/recommend hooks.
5. Artist detail: artwork hero, personal count, top recordings and releases.
6. Profile: identity/listen count and top artists/releases/recordings.
7. Real API smoke tests, model fixtures for unmapped/multi-artist/missing-art data, simulator screenshots at two sizes and dark/light modes.

## Staging after the slice

- Phase 3: full history/date jump, release pages, users/follows/similarity, feed, recommendations, and richer playlist browsing. Statistics, Fresh Releases, scoped search, and Pins now have initial native slices.
- Phase 4: Year in Music, shareable art, LB Radio, playlist editing, playback/content resolution, MusicKit-scoped capture, offline submit queue, inspect/mapping tools.

## Next implementation sequence

1. Turn user-search results into a cached native user detail surface without Android's eager multi-call waterfall.
2. Add lazy followers/following/similar-user sections and optimistic follow state.
3. Build native release-group/release and playlist detail screens on the identities already established by search.
4. Continue recommendations and feed only after those reusable destinations are real.

## Constraints recorded

- Production website interactive inspection was blocked by the unavailable configured browser; current frontend source/routes and public API calls were inspected instead.
- Xcode 27, the iOS 27 runtime, app build, test bundle, real simulator tests, and live public data have now been exercised. Visual checkpoints cover onboarding plus real-data Home in light/dark mode; smaller-device validation is recorded with the build evidence.
- The verified checkpoint currently passes 60 vendored-package tests and 34 app tests, plus the deliberately paced opt-in production public API smoke suite.
- Phase 3 statistics now includes on-demand server activity for the website's seven primary ranges, per-period request caching, accessible native charts, and explicit empty/retry behavior. Real-data visual checks covered all-time activity on large and small simulators in dark and light modes.
- Fresh Releases now uses an upstreamable ListenBrainzKit extension. Personalized results are the default and an HTTP 204 becomes an honest empty state; selecting All is the only route that makes a sitewide request. The native slice follows the website's one-week window and newest-first presentation, while distinguishing upcoming releases and concrete release versus release-group identity. The API client preserves the sitewide endpoint's required terminal slash, with regression coverage.
- Search now exposes Users, Artists, Albums (release groups), Tracks, and public Playlists in one native sheet. It sends only the selected scope after a 500 ms debounce, caches per normalized query, cancels abandoned/stale work, preserves release-group identity, and reuses the native artist/recording destinations. ListenBrainz and MusicBrainz have independent process-shared gates; canonical paths avoid hidden redirect requests. Real MusicBrainz results were visually checked in dark/light mode and XXL Dynamic Type.
- Pins now includes a current-profile card, lazy paginated history, recording-detail pin/unpin, 280-character notes, and owner-only edit/delete actions. Mutations are optimistic with rollback, and the ListenBrainzKit extension follows the endpoint-specific response contracts (including the Boolean update result). Public-profile empty-state presentation was visually checked in the simulator; production mutations were deliberately not exercised.
- Official KMP framework export was attempted and currently fails at the native Room KSP step; it remains a behavior reference rather than an app dependency.

## Rate-limit behavior decision

- The current API documentation is authoritative: ListenBrainz clients should start no more than one API request per second and honor server rate-limit timing.
- The official Android/KMP client maps HTTP 429 but has no global scheduler or reset-header handling. The official iOS client likewise has no pacing/retry interceptor. These are implementation gaps, not product behavior to copy.
- This app begins operations inside a serialized gate and conservatively spaces each next operation from completion, so scheduling cannot reorder admitted calls. It propagates cancellation and installs `Retry-After` or `X-RateLimit-Reset-In` deferrals before queued ownership transfers. Canonical endpoint URLs prevent a redirect from becoming a hidden second request. Mutations are not blindly retried. MusicBrainz uses its own equivalent gate; Cover Art Archive remains outside both until its resolver lands.
