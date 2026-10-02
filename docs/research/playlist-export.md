# Playlist export

Snapshot: 2026-09-28.

## Local file contract

- Export begins only after an explicit action on a successfully loaded Playlist Detail screen.
- It snapshots that immutable in-memory detail. It performs no provider call, refresh, row hydration, token access, or mutation.
- Track order and duplicates are preserved. Canonical MusicBrainz identifiers are reconstructed only from validated UUID models; missing optional metadata stays missing.
- The file is normalized app-owned JSPF JSON, not a claim to preserve the server response byte for byte.
- Private playlists show a disclosure before the system share sheet because every recipient can read the exported contents.

## Linked-service contract

- An authenticated user can export any successfully loaded playlist to Spotify, Apple Music, or SoundCloud when that service appears in their own ListenBrainz connected-services response. This matches the current website; the endpoint itself does not impose creator ownership.
- Opening the sheet performs no request. **Show linked services** explicitly makes one cached/coalesced eligibility read; users who only share a local file never trigger that read.
- The user chooses public or private, selects one linked service, and confirms that ListenBrainz will create a separate copy that does not stay in sync.
- Confirmation admits exactly one serialized mutation. There is no polling, automatic retry, post-success refresh, or background continuation.
- A successful response opens only an HTTPS playlist URL with the exact provider host and provider-specific path shape. User information, custom ports, fragments, encoded separators, non-playlist paths, and cross-provider URLs fail closed.
- Apple Music/SoundCloud import and viewer-side service-track retrieval remain separate staged workflows; in-app playback and content resolution are out of scope.

## Format and compatibility

The encoder follows the [MusicBrainz JSPF specification](https://musicbrainz.org/doc/jspf) and current [ListenBrainz playlist API](https://listenbrainz.readthedocs.io/en/latest/users/api/playlist.html). MusicBrainz documents `copied_from`; the current ListenBrainz payload/client uses `copied_from_mbid`. A valid canonical source is emitted under both names so the portable file remains useful across those consumers. The truthful filename is `*.jspf.json`, and the system receives it as JSON. Interoperability with extension-only third-party importers is not yet claimed.

## Safety and lifecycle

- Encoder input and output are bounded before sharing; oversized or hostile metadata fails closed.
- The same preflight runs before the share control is rendered. If the limit is exceeded, the sheet shows the localized explanation instead of offering an action that will fail later.
- Share filenames are path-safe and bounded by UTF-8 bytes.
- Each transfer uses a UUID-isolated temporary directory with complete file protection. Old export directories are pruned after 24 hours at launch and before a new export.
- Files can outlive the immediate share action long enough for recipients to finish reading them; the operating system may also purge the app temporary directory.
- Before service transport begins, Brainz durably stores a timestamp-only recovery record under an opaque account/playlist/service digest. The record contains no token, username, playlist identifier, provider name, or music metadata.
- A process-wide claim prevents another window or model from clearing an in-flight reservation. Only a typed cancellation known to occur before transport may clear automatically.
- Every status, transport, decoding, or cancellation error after dispatch is treated as indeterminate because the provider may already contain the playlist. Another attempt stays blocked until the user checks that provider and explicitly allows it.

## Reuse decision

No donor source was copied. Local files combine the public JSPF schema, observed ListenBrainz payload semantics, and Apple's native `Transferable`/`ShareLink` APIs. Linked-service export uses current API/server/website behavior as reference only, a small independently written MPL-preserving ListenBrainzKit transport extension, and original native SwiftUI/state. GPL source and UI were not copied.

## Validation

- The full vendored Kit suite passes 169 tests across 23 suites. The complete app suite passes 772/772 with no failure, skip, expected failure, or runtime warning; 13 focused service-export safety tests cover durable storage, corruption, cross-window claims, cancellation boundaries, and every post-dispatch status class.
- Guarded file and linked-service UI tests pass in ordinary light mode and true dark mode at maximum Dynamic Type. The visual checkpoint exposed and corrected a clipped confirmation; the final native alert keeps the privacy, provider, non-sync consequence, confirmation, and Cancel action visible.
- The sole localization catalog matches all 1,814 production keys. Two XcodeGen generations are byte-stable.
- The universal Release simulator extraction succeeds for `x86_64` and `arm64`; final static analysis is recorded in the development handoff.
- Independent correctness and security reviews report PASS after validating no-replay recovery, exact URL admission, timestamp-only persistence, explicit confirmation, and one request with no retry or poll.
- A guarded credentialed simulator smoke verifies the supplied account and real read surfaces without invoking export. No live external playlist was created; production mutation remains deliberately untested because it would create user data. Physical-device file-protection behavior remains release-candidate evidence.
