# Third-party software and design provenance

This project is intended to be licensed under MPL-2.0. This file is updated whenever source is copied or adapted.

## Included source

- ListenBrainzKit, commit `c06b12f8c35bfee8fcf11dc973b5d78e23719cdf`, is vendored at `Packages/ListenBrainzKit/` and locally patched for transport correctness, public model access, tolerant identifier decoding, and typed social, social feed-read/feed-mutation, Pins, detail, Fresh Releases, recommendation-read, and recommendation-feedback APIs. It is licensed under MPL-2.0; its original license and per-file notices are preserved.

No UI source from the design-reference repositories has been copied into the application. Their inspected behavior and visual ideas informed an independent native SwiftUI implementation.

## Design and behavior references

- ListenBrainz server, official Android client, and official iOS client: authoritative product/API behavior; no code copied.
- first.fm: information architecture and listening-history personality; MIT.
- Cassette and Minidisc: current native media interaction patterns; MPL-2.0. Cassette's searchable multi-selection and confirmation patterns informed the independently written personal-recommendation sheet.
- Volta: artist-page visual reference only; GPL-3.0 code is not copied.
- AppleMusicBottombarSwiftUI and FastScrobbler: behavior reference only; no license found, so code is not copied.
- Autohop: statistics/history interaction reference; MIT overall with named MPL-2.0 exceptions.
- Beans Music, Bòcan Music, Finale, and Discrobble: secondary UI/architecture references.

See `docs/research/license-map.md` and `docs/research/repo-reuse-map.md` for the working audit.
