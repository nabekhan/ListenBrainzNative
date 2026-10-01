# Linked-service playlist import

Updated: 2026-09-30

## Evidence snapshot

- ListenBrainz server: `6ce23a24ee58cd76c23d2c1375584bf3e78b7d4b` (2026-09-29).
- Official Android: `3a0e4eff249cb52b9369d150e3210679294f8362` (2026-08-07).
- Official iOS: `a0eb10444ba9af5a8408355c63b1405ad7b447d5` (2025-07-07).
- Server-pinned Troi source distribution: `2026.9.1.0`, SHA-256 `cd501fbde0813f6021114a22d302615a351f5b794df66de6caef4228cd0b0af3`.
- Current server routes and website import modals are authoritative. The official native clients and current shared KMP sources contain no reusable playlist-import flow.
- The server/web/official clients are GPL behavior references only. No source or UI is copied.

## Current contract

| Capability | Current behavior | Native decision |
| --- | --- | --- |
| List Spotify playlists | Authenticated `GET /1/playlist/import/spotify`; refreshes the linked Spotify token, requires all four playlist read/write scopes, follows every Spotify page server-side, and returns one raw array | One explicit, cached/coalesced read; hard byte and retained-row limits; local search only; disclose when more rows were returned than retained |
| Import Spotify playlist | `GET /1/playlist/spotify/{playlist_id}/tracks` invokes Troi with upload enabled, traverses Spotify in 100-item pages with no declared total-track cap, creates a ListenBrainz playlist, and returns the complete generated JSPF plus its new `identifier` | Treat as a non-idempotent mutation despite GET; serialize it, reject redirects, accept at most 32 MiB, decode only the new MBID, and never automatically retry |
| Reconciliation | No idempotency key, operation/status endpoint, duplicate lookup, or sync relationship | Persist a token-free barrier before dispatch; any post-dispatch non-success is indeterminate until the listener checks Owned Playlists and explicitly allows another attempt |
| Other services | Apple Music, SoundCloud, and local JSPF import exist on the website/server | Reuse the same app boundary later; ship Spotify first because its list and identifier shapes are now typed and bounded |

## Product slice

1. Add **Import from Spotify** only to the authenticated owner’s Owned Playlists actions.
2. Opening the sheet makes no request. **Load Spotify playlists** starts the only list read.
3. Present artwork, title, owner, and track count from the aggregate response; do not hydrate rows.
4. Search and filtering are local. If the retained-row ceiling was reached, explain that only the first results are shown.
5. Selecting a playlist opens an explicit confirmation: ListenBrainz creates a separate copy and later Spotify changes do not sync.
6. Confirmation dispatches exactly one serialized import call after the replay barrier is durably stored.
7. A confirmed MBID clears the barrier and refreshes Owned Playlists once. If local barrier cleanup fails, the UI still says the playlist was imported and keeps another attempt paused. An uncertain result stays blocked across launches/scenes and offers review plus an explicitly warned reset.
8. Fixture providers cover every UI state without a token, request, or mutation. No live import mutation is required for acceptance.

## Request budget and safety

- No automatic load from Profile, no query-as-you-type traffic, no row hydration, and no polling.
- List results use a short account-scoped cache and one exact in-flight coalescing key.
- A model-level in-flight guard plus a three-second post-read cooldown prevents repeated Refresh taps from turning one expensive server-side Spotify traversal into request amplification.
- The creation call uses the process-wide serialized mutation lane, not the read lane.
- The creating GET uses a dedicated no-redirect URL session so an HTTP redirect cannot replay it. Foundation transport-level retry behavior remains outside the public API's control, which is another reason every post-dispatch failure remains indeterminate.
- Pre-admission cancellation is the only safe automatic reset. Cancellation, rate limiting, network loss, decoding failure, and server errors after transport begins are all indeterminate.
- The journal key is a SHA-256 digest of normalized account, service, and opaque external playlist ID. Stored payloads contain only an attempt timestamp.
- Import-list artwork accepts only credential-free standard-port HTTPS URLs on Spotify CDN subdomains (`*.scdn.co` or `*.spotifycdn.com`). The dedicated loader applies the same allowlist to every redirect target and disables both memory and disk cache storage so private playlist covers do not survive the sheet.

## Reuse plan

- Reuse the app’s `RequestGate`, account-scoped cache, Profile playlist refresh, artwork component, and service-export journal/provider interaction pattern.
- Extend the vendored MPL-2.0 ListenBrainzKit with small typed Spotify list/import requests.
- Independently implement the SwiftUI sheet and app-facing models. Use the current website only to establish semantics and terminology.
- Keep the boundary service-shaped so Apple Music and SoundCloud can follow without changing the native presentation architecture.

## Validation

- The final app suite passes 845/845 with no failure, skip, or runtime warning. The vendored ListenBrainzKit passes 178 tests across 24 suites; 22 live/integration cases remain intentionally skipped.
- Guarded fixture transport denies production requests. The UI matrix passes 41 iPhone cases with two explicitly opt-in account cases skipped, 9/9 responsive/RTL iPad checks, and 7/7 dark/maximum-Dynamic-Type checks. Visual review confirms the recovery warning fits at the maximum accessibility size.
- The sole catalog matches all 1,965 production keys. The universal Release simulator binary contains `x86_64` and `arm64`, and Release analysis produces no diagnostic.
- The final deterministic unsigned IPA is 8,400,634 bytes with SHA-256 `21c7f95355036564a101b65c92d59902af95006358b8ad8509f514a451a4745d`. Independent static inspection reports SHIP to a trusted signer with no P0–P3 finding after verifying the safe 16-entry payload, exact identity, thin arm64 unsigned code, compiled import routes and corrected recovery copy, source-identical privacy manifest and notices, and absence of signing or development residue.
- Correctness, request-safety, source-security, privacy, and packaged-artifact reviews have no remaining P0–P3 finding. The original release checkpoint used no credential, live API request, artwork request, or production import mutation.
- A later isolated authenticated smoke pressed **Load Spotify playlists** exactly once and stopped before selecting a row, showing a confirmation, or importing. The current account returned **Reconnect Spotify on ListenBrainz, then try again** because the linked account lacks the required playlist permissions. The test did not retry, poll, or mutate anything. This validates the production recovery path and one-shot request boundary; a populated live playlist list remains unverified until Spotify is reconnected with the required scopes.
