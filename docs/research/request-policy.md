# ListenBrainz request policy

Snapshot: 2026-09-18. Project-specific API permission allows behavior comparable to the official clients, provided requests remain selective, intentional, and free of lifecycle or retry storms. The audited reference heads matched upstream at Android/KMP `3a0e4eff249cb52b9369d150e3210679294f8362` and iOS `a0eb10444ba9af5a8408355c63b1405ad7b447d5`.

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

## Brainz decision

The existing one-request-per-second gate remains in place until a tested replacement lands. The next networking milestone should:

1. admit at most two independent ListenBrainz reads at once initially;
2. coalesce identical in-flight reads by endpoint, normalized account, and parameters;
3. retain feature-specific guards: one history/feed page at a time, debounced cancellable search, cached one-shot profile/stat loads, and realtime Playing Now where supported;
4. cancel work whose view/model intent has ended and prevent stale results from publishing;
5. apply server reset timing globally after 429 and surface read failures without automatic replay; any future bounded retry requires endpoint-specific proof and tests;
6. keep mutations on one serialized lane with no automatic retry;
7. record privacy-safe DEBUG/test telemetry for closed endpoint category, coalescing, cancellation, status class, and in-flight count—never request identity, token, parameters, headers, error descriptions, or response payload;
8. prove that repeated SwiftUI lifecycle events, duplicate page triggers, stale searches, and 429 responses cannot create request storms.

Relaxation is complete only when those tests and telemetry demonstrate fewer unnecessary calls than the current implementation. Official iOS fan-out is product evidence, not the traffic-safety model.

## Inspected source

- Android/KMP transport and error mapping: `References/listenbrainz-android/shared/src/commonMain/kotlin/org/listenbrainz/shared/di/SharedNetworkServiceModule.kt` and `References/listenbrainz-android/shared/src/commonMain/kotlin/org/listenbrainz/shared/util/Utils.kt`.
- Android/KMP paging, search, bounded artwork work, and realtime lifecycle: `References/listenbrainz-android/shared/src/commonMain/kotlin/org/listenbrainz/shared/viewmodel/UserViewModel.kt`, `FeedViewModel.kt`, `SearchViewModel.kt`, `ListeningNowViewModel.kt`, and `References/listenbrainz-android/shared/src/commonMain/kotlin/org/listenbrainz/shared/repository/socket/SocketRepositoryImpl.kt`.
- Android-only networking/job references: `References/listenbrainz-android/app/src/main/java/org/listenbrainz/android/di/KoinModules.kt` and `References/listenbrainz-android/app/src/main/java/org/listenbrainz/android/util/JobQueue.kt`.
- Official iOS search, pagination, dashboard fan-out, and artwork cache: `References/listenbrainz-ios/Listenbrainz/ViewModel/SearchViewModel.swift`, `References/listenbrainz-ios/Listenbrainz/ViewModel/FeedViewModel.swift`, `References/listenbrainz-ios/Listenbrainz/UI/Screens/DashboardComponents/Listens/ListensView.swift`, `References/listenbrainz-ios/Listenbrainz/UI/Screens/DashboardComponents/Statistics/StatisticsView.swift`, and `References/listenbrainz-ios/Listenbrainz/Utils/ImageLoader.swift`.
