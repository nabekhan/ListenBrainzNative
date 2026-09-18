# LB Radio working note

Snapshot: 2026-09-18.

## Current product contract

- The canonical generator is authenticated `GET /1/explore/lb-radio` with required `prompt` and `mode=easy|medium|hard` query items.
- Success returns one JSPF playlist plus human-readable query feedback. Empty generation is valid and must not be presented as a transport failure.
- The endpoint has a separate five-requests-per-five-seconds token quota. Brainz remains stricter: every ListenBrainz operation enters the process-wide one-request-per-second gate, 429 timing defers the queue, and generation is never automatically retried.
- Troi's prompt language supports artist, tag, MusicBrainz collection, ListenBrainz playlist, user statistics, recommendations, and country sources; weights and per-term options can be combined. The language is powerful but not a stable typed API, so the first UI offers safe native presets plus an advanced prompt field rather than attempting to model the entire grammar.
- LB Radio generates identities and metadata, not guaranteed playable audio. A track is not labeled playable merely because it has a recording MBID.

## Source comparison

- The current website requires login, offers a prompt and familiarity mode, generates only on explicit submission, batch-enriches the returned recording MBIDs, shows query feedback, and places resolved tracks into BrainzPlayer's ambient queue.
- The official Android app has artist-radio affordances that deep-link to the website, but no native LB Radio repository or generator. Its shared network stack maps 429 after the fact and has no proactive global scheduler.
- The official iOS app has no LB Radio implementation. Its old Spotify App Remote work is incomplete and not a playback foundation.
- KMP `commonMain` has playback/content-resolution contracts but no LB Radio generator. The iOS implementation opens YouTube Music search results and leaves Spotify/player operations unimplemented.
- The upstream ListenBrainzKit snapshot had lower-level artist/tag radio dataset calls and `LBRadioMode`, but lacked `/1/explore/lb-radio`. The local MPL extension adds that generator while reusing its existing JSPF track parser.

## Implemented native slice

1. An MPL-2.0 ListenBrainzKit generator client provides tolerant JSPF/feedback decoding and canonical error mapping.
2. The app-owned provider performs generation and at most one recording-metadata batch lookup, with both operations independently admitted by `RequestGate.shared`.
3. Authenticated presets cover the current user's history, unheard recommendations, an artist, a tag/mood, and an advanced Troi prompt. Easy, medium, and hard are presented as Familiar, Balanced, and Explore without changing their wire values.
4. The native result displays the generated title, annotation, server feedback, artwork-first rows, mapped recording navigation, and honest empty/error states.
5. The screen does not preload, regenerate on control changes, hydrate rows individually, or claim playback. A second explicit generation intentionally creates a fresh mix rather than serving a cached random result.
6. Optional metadata failure leaves the generated JSPF visible. A metadata-stage 429 also defers subsequent shared-gate work, while cancellation before admission prevents the transport call.

## Validation

- ListenBrainzKit: 114 tests pass, including generated-radio schema, query encoding, empty-prompt, plural-empty fallback, and malformed-response coverage.
- App: 192 tests pass, including explicit generation, single-batch enrichment, cancellation, preserved mixes, generation-stage 429 mapping, and metadata-stage gate deferral.
- The Release simulator build passes.
- Light, dark, accessibility-extra-large, and compact-phone visual checkpoints use a local fixture. They make no ListenBrainz request and use no account token.
- No authenticated production generation was claimed because no disposable radio QA token was available.

## Reuse and license decision

- Reuse ListenBrainzKit's MPL JSPF and metadata models; upstream the generic generator client there.
- Reuse the app's `RequestGate`, recording domain model, artwork resolver, canonical recording destination, and playlist-row hierarchy.
- Adapt only the visual concept of Minidisc's MPL `ArtistStationCard`/Discover shelf if seed cards improve the screen; no internet-radio playback code applies to generated tracks.
- Treat GPL ListenBrainz server/web/Android code as behavior and schema evidence only. No GPL UI or implementation code is copied.
- Libspot/librespot-family Spotify playback stays deferred until the core client is complete and then only begins in a separate branch after license, account-policy, authentication, maintenance, and App Store review.

## Deferred

- Automatic content resolution and playback queueing.
- Saving/copying/exporting a generated mix as a ListenBrainz playlist.
- A complete visual editor for every Troi entity, weight, and option.
- Radio entry points from artist, release, recording, playlist, and map screens until the destination is stable.
