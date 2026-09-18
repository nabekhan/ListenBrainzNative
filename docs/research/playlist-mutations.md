# Playlist mutation checkpoint

Snapshot: 2026-09-18.

## Current behavior

- `POST /1/playlist/create` and `POST /1/playlist/edit/{playlist_mbid}` require authentication and use the normal ListenBrainz rate limiter.
- An empty playlist is valid. Brainz creates an empty, private playlist from the Profile Owned section; track insertion is a later workflow.
- Edit is owner-only and overwrites playlist metadata. The app therefore sends a complete title, optional annotation, privacy value, and collaborator list rather than a partial patch.
- Collaborators are trimmed, de-duplicated case-insensitively, and never include the owner. Existing collaborators remain read-only in this first slice so editing another field cannot erase them.
- Neither endpoint exposes an idempotency key. Each tap is serialized, enters `RequestGate.shared` exactly once, and is never retried automatically. A 429 defers later work using the server delay and remains visible to the user.
- A lost transport/decoding response is not reported as a definite failure: create/edit become indeterminate, another save is disabled, relevant caches are cleared, and the UI asks the user to reconcile with the server before trying again. Cancellation while queued behind the request gate remains an ordinary no-op; cancellation after transport begins is conservatively indeterminate because the server may already have committed the POST.
- Private or unavailable playlists may produce a not-found response. Server authorization is authoritative; the owner-only Edit button is only a convenience.

## Reuse decision

- Current server/API source defines the payload and overwrite semantics.
- Official Android/KMP supplies mature behavior evidence: new playlists default private, collaborators are normalized/exclude the owner, and successful operations refresh playlist state. Its GPL code was not copied.
- The vendored MPL-2.0 ListenBrainzKit now owns generic exact-JSPF create/edit requests and endpoint error mapping. This is an upstream candidate.
- App-owned Swift code owns draft normalization, the gated no-retry mutation boundary, UI state, cache reconciliation, and the native SwiftUI form.
- Official KMP remains a behavior reference; adding it as an iOS framework would add disproportionate build/interoperability weight for these two calls.

## Native slice

- Authenticated users can create an empty playlist from their Owned playlists section.
- Owners can edit a playlist name, description, and public/private status from playlist detail.
- Editing bypasses fresh caches before the form opens and again immediately before POST. If title, annotation, privacy, or collaborators changed on the server while the form was open, the save is stopped instead of overwriting the newer snapshot. A server without conditional updates still leaves a small unavoidable race between that final GET and POST.
- A confirmed edit clears every public/authenticated playlist-detail scope and every profile playlist-page cache before restoring the authenticated confirmed value. A process-local, token-free journal also reconciles already-loaded Profile rows across tabs. This prevents a public-to-private change from leaking the formerly public detail through cache.
- The confirmed edit is then checked against one best-effort server refetch. A refetch failure retains the confirmed state and reports that fresh data could not be checked.
- Creation clears the owner-list page cache and reloads it. Duplicate submissions are blocked while a mutation is pending; failures preserve the draft and appear inline.
- Playlist detail cache keys include the normalized authenticated viewer (or public-only scope) so private data cannot cross accounts.

## Verification

- ListenBrainzKit: 118 tests across 20 suites, including exact create/edit payload snapshots and endpoint error handling.
- App: 210 tests pass. Focused mutation/detail/profile coverage includes normalization, duplicate-tap serialization, no automatic retry, 429 deferral, pre- versus post-transport cancellation, indeterminate-result handling, stale-snapshot conflict refusal, owner authorization presentation, full collaborator preservation, public-to-private cache eviction, account-scoped cache keys, create refresh, and cross-screen edit reconciliation.
- Fixture-only simulator inspection: standard light/dark, accessibility-extra-extra-large, and smaller-device layouts. Fixtures made no production request and used no real token.

## Deferred

Track add/remove/reorder, copy, delete, collaborator management, import/export, and service synchronization remain separate milestones. Track mutations need an explicit position/duplicate/reconciliation audit before implementation; destructive deletion needs its own confirmation and cache-removal design.
