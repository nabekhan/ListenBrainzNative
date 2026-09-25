# Custom album artwork

Snapshot: 2026-09-25. Authoritative server source: `metabrainz/listenbrainz-server` `71f92e100b938801da19cd9639cd78401b2c9a6c`.

## Current contract

- `POST /1/art/grid/` is public, rate-limited, and returns a raw `image/svg+xml` document.
- The JSON body chooses either ordered `release_mbids` or ordered `release_group_mbids`, a `1...5` grid dimension, a valid built-in layout, `128...1024` output size, background, captions, missing-cover behavior, and 250px or 500px source art.
- The server accepts at most the first 100 identifiers and UUID-validates them. If both identifier arrays are present, concrete releases win.
- Successful POST responses are `no-store`; the app may keep an exact-request local cache but must not assume shared HTTP caching.
- The current website Art Creator customizes statistics artwork. It does not provide a user-facing selector for the generic ordered-MBID POST, so its source is API-behavior evidence rather than a UI donor.

## Native product decision

Ship an **Album collage** composer in Taste:

- Candidate covers come only from the already-loaded all-time top-album snapshot and require canonical release MBIDs.
- Opening, selecting, ordering, changing layout, changing background, and toggling captions perform zero requests.
- The draft candidate type deliberately carries titles, artists, and canonical release MBIDs but no artwork URL. Local title-derived placeholders preserve a music-first selection surface without allowing Cover Art Archive loads to bypass the request-free editing boundary.
- Supported presets expose the server's useful built-in grids and mosaics with their exact cover counts; unavailable presets stay out of the picker.
- The draft starts with the highest-ranked eligible albums, preserves chosen order, and lets the user rearrange that order locally.
- Missing cover art keeps its position using the ListenBrainz placeholder rather than silently changing the chosen order.
- **Create** freezes the draft and makes one anonymous, coalesced, no-auto-retry POST. Explicit retry remains in the existing preview sheet.
- The existing bounded SVG validator, 24-hour exact-request cache, nonpersistent JavaScript-free renderer, PNG exporter, and native share sheet remain the only preview/export path.

Searching MusicBrainz for arbitrary additions is intentionally separate. It would add search traffic and identity-resolution work to a composer that can already be useful from loaded data.

## Reuse and licensing

- Extend the vendored MPL-2.0 ListenBrainzKit art client with one typed request; preserve its file notices and upstreamable shape.
- Reuse the app-owned `GeneratedArtworkProvider`, `GeneratedArtworkSheet`, SVG policy, cache, request gate, and Taste media models.
- Use native SwiftUI `Form`, `Picker`, `Toggle`, `List.onMove`, sheets, and accessibility behavior. No donor component is needed.
- The GPL-2.0-or-later ListenBrainz server and website are contract/behavior references only; copy no source or UI.

## Validation

- ListenBrainzKit tests cover the exact POST path, method, MIME handling, JSON keys, identifier order, bounds, and invalid-input rejection; all 145 package tests pass.
- App tests cover preset availability, seeded selection, limits, layout changes, reordering, request construction, anonymous scope, and exact ordered cache/gate identity; all 581 app tests pass.
- The compiler-backed localization guard confirms that the sole catalog exactly matches all 1,546 production keys.
- A universal `x86_64`/`arm64` Release simulator build succeeds.
- Fixture-only light, dark, maximum-Dynamic-Type, iPhone SE, and rendered-preview checks pass. Scoped simulator logs contain no ListenBrainz, MusicBrainz, Cover Art Archive, Archive.org, Spotify, or HTTP(S) service-host activity.
- Independent correctness and security re-reviews report READY. The renderer's existing low-risk privacy boundary remains disclosed: after explicit creation, approved cover and font resources can load from Internet Archive and Google without a token, cookie, or referrer.
