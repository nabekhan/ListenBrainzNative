# ListenBrainz request policy

Snapshot: 2026-09-19. Project-specific API permission allows behavior comparable to the official clients, provided requests remain selective, intentional, and free of lifecycle or retry storms. The audited reference heads matched upstream at Android/KMP `3a0e4eff249cb52b9369d150e3210679294f8362` and iOS `a0eb10444ba9af5a8408355c63b1405ad7b447d5`.

## Official-client findings

| Concern | Official Android/KMP | Official iOS |
|---|---|---|
| Global request rate/concurrency gate | None found | None found |
| HTTP 429 | Typed error; no automatic retry or `Retry-After` replay | No dedicated handling found |
| History/feed | Bounded Paging sources cached in view-model scope | `isLoading`/end guards and fixed pages |
| Search | 500 ms debounce, duplicate suppression, per-query/type cache | 500 ms debounce and duplicate suppression |
| Artwork | Cache plus concurrency limit of two for playlist covers | In-memory `NSCache` |
| Playing Now | One initial read followed by lifecycle-owned WebSocket updates | Ordinary HTTP reads |
| Dashboard/stats | Independent requests without a global gate | Broad concurrent fan-out on appearance |

The useful precedent is not unbounded traffic. It is endpoint-specific intent: bounded pages, debounced search, cache reuse, limited artwork work, and realtime updates instead of polling.

## Brainz request policy

The tested replacement is active. It deliberately separates reads from mutations:

1. at most two independent ListenBrainz reads may run at once;
2. identical in-flight reads coalesce only when credential scope, endpoint, and shaped wire parameters match exactly;
3. cancelled final waiters cancel queued work and reserve an already-started request key until its transport drains;
4. feature-level guards remain in place: bounded history/feed pages, debounced cancellable search, cached one-shot profile/stat loads, and no lifecycle-owned polling loops;
5. an HTTP 429 reset defers both lanes globally, while the original failure is surfaced without automatic replay;
6. mutations remain on one serialized lane with a one-second minimum interval and are never retried automatically;
7. DEBUG/test telemetry records only a closed endpoint category, lifecycle, coalesced-waiter count, and in-flight count—never request identity, token, parameters, headers, error descriptions, or response payload;
8. credential-derived scopes are process-local HMAC values. Raw tokens are never placed in request keys, telemetry, or cache keys.
9. Year in Music makes one aggregate read only after a year is opened or selected. Frozen 2021–2024 reports use an empty-token client, an anonymous 24-hour cache, cancellation on selection replacement, and a 16 MiB receive/decode ceiling; no archive, artwork, or ranking row is preloaded.
10. External service actions resolve only already-loaded `spotify_id` or `origin_url` locally. They perform zero ListenBrainz, metadata, search, or playback-resolution requests and accept only strict HTTPS provider destinations.

This is intentionally stricter than copying the official clients' unconstrained fan-out. The conditional API allowance is used for selective concurrency, while coalescing, pagination guards, cancellation, caching, shared 429 deferral, and tests prevent erroneous traffic. Any future retry or concurrency increase requires endpoint-specific evidence and new tests first.

## Inspected source

- Android/KMP transport and error mapping: `References/listenbrainz-android/shared/src/commonMain/kotlin/org/listenbrainz/shared/di/SharedNetworkServiceModule.kt` and `References/listenbrainz-android/shared/src/commonMain/kotlin/org/listenbrainz/shared/util/Utils.kt`.
- Android/KMP paging, search, bounded artwork work, and realtime lifecycle: `References/listenbrainz-android/shared/src/commonMain/kotlin/org/listenbrainz/shared/viewmodel/UserViewModel.kt`, `FeedViewModel.kt`, `SearchViewModel.kt`, `ListeningNowViewModel.kt`, and `References/listenbrainz-android/shared/src/commonMain/kotlin/org/listenbrainz/shared/repository/socket/SocketRepositoryImpl.kt`.
- Android-only networking/job references: `References/listenbrainz-android/app/src/main/java/org/listenbrainz/android/di/KoinModules.kt` and `References/listenbrainz-android/app/src/main/java/org/listenbrainz/android/util/JobQueue.kt`.
- Official iOS search, pagination, dashboard fan-out, and artwork cache: `References/listenbrainz-ios/Listenbrainz/ViewModel/SearchViewModel.swift`, `References/listenbrainz-ios/Listenbrainz/ViewModel/FeedViewModel.swift`, `References/listenbrainz-ios/Listenbrainz/UI/Screens/DashboardComponents/Listens/ListensView.swift`, `References/listenbrainz-ios/Listenbrainz/UI/Screens/DashboardComponents/Statistics/StatisticsView.swift`, and `References/listenbrainz-ios/Listenbrainz/Utils/ImageLoader.swift`.
