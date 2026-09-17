# Implementation plan

## Research verdict

Build a native SwiftUI application around a small app-owned domain/provider boundary. Start from the fixed ListenBrainzKit fork for P0, reuse current media interaction patterns selectively from MPL/MIT donors, and keep KMP replaceable rather than foundational. The app targets iOS 18 for broad modern API coverage, with iOS 26 enhancements (`tabViewBottomAccessory`, minimized tab bar, zoom transitions) behind availability checks.

## Architecture recommendation

```text
SwiftUI Features + shared Components
              ↓
@Observable feature models
              ↓
ListeningProvider (app-owned domain models)
              ↓
ListenBrainzProvider
  ├─ fixed ListenBrainzKit core/metadata/stats/feedback
  ├─ focused endpoint extensions (only when Kit is missing them)
  └─ request gate + response/metadata cache
              ↓
ListenBrainz / MusicBrainz / Cover Art Archive
```

- Organize concrete feature folders only as screens land: Authentication, Home, History, Recording, Artist, Profile, then Stats/Discover/Social/Playlists.
- UI never imports API response models directly. Stable app models preserve MBID/MSID/release/release-group distinctions and tolerate incomplete mapping.
- One actor handles the one-request-per-second ListenBrainz policy, serial request ownership, cancellation, and rate-limit reset. A small typed disk cache supplies stale-while-revalidate snapshots without persisting authenticated HTTP responses.
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

- Phase 3: full history/date jump, stats, search, release pages, users/follows/similarity, feedback, pins, feed, recommendations, Fresh Releases, playlist browsing.
- Phase 4: Year in Music, shareable art, LB Radio, playlist editing, playback/content resolution, MusicKit-scoped capture, offline submit queue, inspect/mapping tools.

## Immediate implementation sequence

1. Vendor ListenBrainzKit under MPL and repair/test URL construction and User-Agent behavior.
2. Generate a minimal Xcode project from tracked `project.yml` (XcodeGen via temporary Nix shell).
3. Implement domain models/provider and fixture provider first, then the real provider.
4. Build the visible Home → History → Recording → Artist → Profile navigation before expanding infrastructure.
5. Run with real public data, then authenticated data when a user token is supplied locally.

## Constraints recorded

- Production website interactive inspection was blocked by the unavailable configured browser; current frontend source/routes and public API calls were inspected instead.
- Xcode 27, the iOS 27 runtime, app build, test bundle, real simulator tests, and live public data have now been exercised. Visual checkpoints cover onboarding plus real-data Home in light/dark mode; smaller-device validation is recorded with the build evidence.
- The verified checkpoint currently passes 45 vendored-package tests, 14 app tests with no runtime warnings, and the paced opt-in production public API smoke suite.
- Phase 3 statistics now includes on-demand server activity for the website's seven primary ranges, per-period request caching, accessible native charts, and explicit empty/retry behavior. Real-data visual checks covered all-time activity on large and small simulators in dark and light modes.
- Official KMP framework export was attempted and currently fails at the native Room KSP step; it remains a behavior reference rather than an app dependency.

## Rate-limit behavior decision

- The current API documentation is authoritative: ListenBrainz clients should start no more than one API request per second and honor server rate-limit timing.
- The official Android/KMP client maps HTTP 429 but has no global scheduler or reset-header handling. The official iOS client likewise has no pacing/retry interceptor. These are implementation gaps, not product behavior to copy.
- This app begins operations inside a serialized gate and conservatively spaces each next operation from completion, so scheduling cannot reorder admitted calls. It propagates cancellation and installs `Retry-After` or `X-RateLimit-Reset-In` deferrals before queued ownership transfers. Mutations are not blindly retried. Cover Art Archive and other non-ListenBrainz hosts remain outside this gate.
