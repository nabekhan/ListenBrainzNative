# Playlist mutation checkpoint

Snapshot: 2026-09-18.

## Current behavior

- `POST /1/playlist/create`, `POST /1/playlist/edit/{playlist_mbid}`, `POST /1/playlist/{playlist_mbid}/item/add`, and `POST /1/playlist/{playlist_mbid}/copy` require authentication and use the normal ListenBrainz rate limiter.
- An empty playlist is valid. Brainz creates an empty, private playlist from the Profile Owned section; track insertion is a later workflow.
- Edit is owner-only and overwrites playlist metadata. The app therefore sends a complete title, optional annotation, privacy value, and collaborator list rather than a partial patch.
- Collaborators are trimmed, de-duplicated case-insensitively, and never include the owner. Existing collaborators remain read-only in this first slice so editing another field cannot erase them.
- Add-item accepts owner or collaborator authority. It appends JSPF tracks by canonical MusicBrainz recording URL, permits duplicates, accepts at most 100 tracks, and has a separate optional zero-based offset route. Brainz deliberately submits one recording with no offset so the operation is append-only.
- Copy accepts any playlist visible to the authenticated caller: public playlists plus private playlists they own or collaborate on. The server creates `Copy of <title>`, assigns the caller as owner, preserves visibility, description, track order, and provenance, and removes collaborators and generated-for metadata.
- None of these endpoints exposes an idempotency key. Each tap is serialized, enters `RequestGate.shared` exactly once, and is never retried automatically. A 429 defers later work using the server delay and remains visible to the user.
- A lost transport/decoding response is not reported as a definite failure: create/edit become indeterminate, another save is disabled, relevant caches are cleared, and the UI asks the user to reconcile with the server before trying again. Cancellation while queued behind the request gate remains an ordinary no-op; cancellation after transport begins is conservatively indeterminate because the server may already have committed the POST.
- An add first reads canonical playlist detail and counts matching recording MBIDs. An existing occurrence requires an explicit **Add Another Copy** decision, whose baseline is re-read immediately before POST. After the one POST, the app fetches detail again and accepts only an increased occurrence count as confirmation. An ambiguous transport result follows the same reconciliation path without replaying the mutation; an unresolved result disables another attempt and asks the user to inspect the playlist.
- Copy is transactionally non-destructive on the server but not replay-safe: every committed request creates a new playlist and no idempotency key exists. Brainz persists a token-free account/source attempt before dispatch and records the returned destination immediately. It then fetches that MBID canonically and verifies the returned UUID, normalized owner, and `copied_from` source before showing or inserting exact metadata. A lost response clears owned-list caches and leaves a durable lock across navigation and relaunch. **Check Again** performs a fresh Owned request; only a recent row whose `copied_from` matches the source can advance to canonical destination verification, and an absent match never unlocks replay.
- Private or unavailable playlists may produce a not-found response. Server authorization is authoritative; the owner-only Edit button is only a convenience.

## Reuse decision

- Current server/API source defines the payload and overwrite semantics.
- Official Android/KMP supplies mature behavior evidence: new playlists default private, collaborators are normalized/exclude the owner, and successful item additions refresh playlist state. Its GPL code was not copied.
- Current server, web, and official Android/KMP behavior supplied copy eligibility, inherited-visibility, collaborator-removal, and confirmation semantics. Their GPL code was not copied.
- Minidisc supplies the native destination-sheet, search, and explicit duplicate-decision interaction. `PlaylistAddSheet.swift` adapts that MPL-2.0 interaction with ListenBrainz-specific paging and reconciliation; provenance is recorded in `THIRD_PARTY.md`.
- The vendored MPL-2.0 ListenBrainzKit now owns generic exact-JSPF create/edit/append requests plus typed empty-body copy and endpoint error mapping. These additions are upstream candidates.
- App-owned Swift code owns draft normalization, the gated no-retry mutation boundary, UI state, cache reconciliation, and the native SwiftUI form.
- Official KMP remains a behavior reference; adding it as an iOS framework would add disproportionate build/interoperability weight for these calls.

## Native slice

- Authenticated users can create an empty playlist from their Owned playlists section.
- Owners can edit a playlist name, description, and public/private status from playlist detail.
- Authenticated users can add an MBID-mapped recording from Recording Detail to either an owned or collaborating playlist. The searchable sheet loads and pages both categories independently; unmapped recordings never present the action.
- Authenticated users can duplicate any visible canonical playlist from Playlist Detail after a forced source refresh. Because the server has no conditional version token, confirmation says that source privacy is preserved at copy time rather than promising a cached public/private value. The returned MBID is fetched canonically; the success alert names the actual resulting visibility, offers direct navigation, and reconciles an already-loaded Owned Playlists list without synthesizing metadata from the source.
- Editing bypasses fresh caches before the form opens and again immediately before POST. If title, annotation, privacy, or collaborators changed on the server while the form was open, the save is stopped instead of overwriting the newer snapshot. A server without conditional updates still leaves a small unavoidable race between that final GET and POST.
- A confirmed edit clears every public/authenticated playlist-detail scope and every profile playlist-page cache before restoring the authenticated confirmed value. A process-local, token-free journal also reconciles already-loaded Profile rows across tabs. This prevents a public-to-private change from leaking the formerly public detail through cache.
- The confirmed edit is then checked against one best-effort server refetch. A refetch failure retains the confirmed state and reports that fresh data could not be checked.
- Creation clears the owner-list page cache and reloads it. Duplicate submissions are blocked while a mutation is pending; failures preserve the draft and appear inline.
- Playlist detail cache keys include the normalized authenticated viewer (or public-only scope) so private data cannot cross accounts.
- Authentication or visibility loss during copy clears all playlist caches before an ordered, process-local mutation journal advances. It replaces the rendered detail with a generic unavailable state and then clears all Profile playlist state for revoked authentication or removes only the inaccessible source row. The latter invalidates in-flight responses and resets pagination until an explicit refresh, so an older response cannot restore private data or skip a shifted row. The immutable navigation seed is never used as a visible fallback after access loss.

## Verification

- ListenBrainzKit: 120 tests across 20 suites, including exact create/edit/append payload snapshots, the empty-body copy path/response, the 1...100 item boundary, success-envelope validation, and endpoint error handling.
- App: 248 tests pass. Focused mutation/detail/profile coverage includes normalization, duplicate-tap and rapid-destination serialization, no automatic retry, 429 deferral, pre- versus post-transport cancellation, indeterminate-result handling without attributing a collaborator's occurrence, explicit duplicate confirmation with baseline revalidation, preflight/reconciliation access-loss purging, stale-snapshot conflict refusal, owner/collaborator destination loading, authentication/MBID gating, full collaborator preservation, cache eviction, account-scoped cache keys, create refresh, and cross-screen edit reconciliation.
- The focused copy/profile suite has 43 passing tests covering exact-one-call copy, definite versus indeterminate errors, pre/post-dispatch cancellation, canonical destination owner/provenance verification, persisted relaunch recovery, forced Owned provenance checks, rejection of old matches, ordered journal delivery, cache-first access-loss publication, in-flight response invalidation, pagination reset, and already-loaded versus newly-created Profile reconciliation.
- Independent correctness and security re-reviews report no remaining material issue. The intentionally fail-closed residuals are a conservative lock if the process dies after recording an attempt but before dispatch, and an unresolved copy that falls outside the newest 100 Owned playlists.
- Fixture-only simulator inspection covers the native confirmation in standard light/dark, accessibility-extra-extra-large, and smaller-device layouts. The first accessibility pass exposed clipped confirmation-dialog content; the final alert uses concise complete copy at the largest checked size. Fixtures make no production request and use no real token.

## Deferred

Remove/reorder, playlist deletion, collaborator management, import/export, and service synchronization remain separate milestones. The server's remove route addresses a zero-based position/count rather than a stable playlist-item ID, so stale state could delete the wrong duplicate. Move similarly depends on positions and is currently a non-atomic remove followed by add. Those operations need stronger concurrency/recovery design before native UI; destructive playlist deletion needs its own confirmation and cache-removal design.
