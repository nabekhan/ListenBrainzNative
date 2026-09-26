# Playlist file export

Snapshot: 2026-09-25.

## Product contract

- Export begins only after an explicit action on a successfully loaded Playlist Detail screen.
- It snapshots that immutable in-memory detail. It performs no provider call, refresh, row hydration, token access, or mutation.
- Track order and duplicates are preserved. Canonical MusicBrainz identifiers are reconstructed only from validated UUID models; missing optional metadata stays missing.
- The file is normalized app-owned JSPF JSON, not a claim to preserve the server response byte for byte.
- Private playlists show a disclosure before the system share sheet because every recipient can read the exported contents.

## Format and compatibility

The encoder follows the [MusicBrainz JSPF specification](https://musicbrainz.org/doc/jspf) and current [ListenBrainz playlist API](https://listenbrainz.readthedocs.io/en/latest/users/api/playlist.html). MusicBrainz documents `copied_from`; the current ListenBrainz payload/client uses `copied_from_mbid`. A valid canonical source is emitted under both names so the portable file remains useful across those consumers. The truthful filename is `*.jspf.json`, and the system receives it as JSON. Interoperability with extension-only third-party importers is not yet claimed.

## Safety and lifecycle

- Encoder input and output are bounded before sharing; oversized or hostile metadata fails closed.
- The same preflight runs before the share control is rendered. If the limit is exceeded, the sheet shows the localized explanation instead of offering an action that will fail later.
- Share filenames are path-safe and bounded by UTF-8 bytes.
- Each transfer uses a UUID-isolated temporary directory with complete file protection. Old export directories are pruned after 24 hours at launch and before a new export.
- Files can outlive the immediate share action long enough for recipients to finish reading them; the operating system may also purge the app temporary directory.

## Reuse decision

No donor source was copied. The implementation combines the public JSPF schema, observed ListenBrainz payload semantics, and Apple's native `Transferable`/`ShareLink` APIs. Service import/export remains a separate authenticated networking feature and belongs in ListenBrainzKit only when a concrete workflow is selected.

## Validation

- 12/12 focused export tests and the complete 628/628 app suite pass with no failure or skip.
- All 7/7 guarded layout tests pass; the export fixture verifies private-file disclosure and a reachable share action without admitting a request-gated transport.
- The sole localization catalog matches all 1,616 production keys, including the export labels, disclosure, and size-limit explanation.
- A generic Release simulator build succeeds for both `x86_64` and `arm64`.
- Independent correctness and security re-reviews report READY after bounded-filename, conservative-size-preflight, error-presentation, staging-lifecycle, and provenance tests were added.
- Fixture validation used no real token, production request, or mutation. Platform-level receiving-app interoperability and physical-device file-protection behavior remain release-candidate evidence rather than claims of this checkpoint.
