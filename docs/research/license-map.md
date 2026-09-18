# License map

Intended application license: **MPL-2.0**. This keeps the whole project open, is compatible with the primary Swift API and media-component donors, and permits use alongside MIT/BSD/Apache code while retaining file-level provenance. This is a working choice and can be changed before public release if no MPL donor files are copied.

| Repository | License evidence | Copy/adapt policy | Attribution / compatibility |
|---|---|---|---|
| ListenBrainz server | GPL-2.0 license file | No code copying | Product/API reference only |
| Official Android | README: GPL-3+; some Apache-2.0 sections | No copying without verifying per-file boundary | Behavior reference only |
| Official iOS | README: GPL-3+; some Apache-2.0 sections | No copying without verifying per-file boundary | Behavior reference only |
| ListenBrainzKit | MPL-2.0, file headers | Local fork permitted; modified covered files remain MPL | Preserve license, notices, source availability |
| first.fm | MIT | Selected copying/adaptation permitted | Preserve copyright/license in `THIRD_PARTY.md` and adapted files where appropriate |
| AppleMusicBottombarSwiftUI | No license found | Do not copy | Reimplement documented Apple-API behavior independently |
| Cassette | MPL-2.0 | Selected file reuse permitted | Preserve notices; modified files remain MPL |
| Minidisc | MPL-2.0; pre-commit history once GPL | Only current MPL HEAD files; record exact commit | Preserve Cassette/Minidisc notices |
| Volta | GPL-3.0 | Do not copy into MPL app | Visual/behavior inspiration only |
| Autohop | MIT, except four named MPL-2.0 files | MIT stats files okay; avoid named audio/sync exception files unless tracked as MPL | Preserve MIT notice; inspect `NOTICE` per file |
| Beans Music | MIT | Permitted selectively | Preserve notice |
| Bòcan Music | Apache-2.0 | Permitted selectively | Preserve LICENSE/NOTICE and mark changes |
| FastScrobbler | No license found | Do not copy | Behavior reference only |
| Finale | BSD-3-Clause | Permitted selectively | Preserve BSD notice |
| Discrobble | MIT | Permitted | Documentation/ADR reference only so far |
| Spotify playback experiment | TBD pending exact repository identification | No code copied or dependency added | Separate branch only; audit license, Spotify Developer Terms, authentication, App Store eligibility, and maintenance before implementation |

## Planned tracked reuse

- `Packages/ListenBrainzKit/`: upstream MPL-2.0 source at `c06b12f`, with reliability fixes and typed recommendation-read/feedback, social/feed-read/feed-mutation, detail, era-activity, and artist-evolution extensions isolated into reviewable commits.
- The personal-recommendation sheet adapts Cassette's general MPL-2.0 selection-sheet interaction (searchable full-row multi-select and toolbar commit state) using independently written app types and source; no Cassette file was copied.
- The concrete release page independently implements the inspected Minidisc/Cassette album hierarchy and ordered-row behavior with app-owned types and components; no donor file was copied or adapted.
- The listening-hours heatmap independently implements the inspected ListenBrainz behavior and Autohop-style period/heatmap interaction with app-owned SwiftUI; no donor file was copied or adapted.
- Music by Decade independently implements the inspected ListenBrainz era behavior with native Swift Charts, informed by Autohop's statistics hierarchy and Minidisc/first.fm presentation concepts; no donor UI file was copied or adapted.
- Artist Evolution independently adapts the website's server-ranked timeline behavior to a native, touch-inspectable Swift Charts presentation. The GPL React/Nivo component was not copied; Autohop informed only the general statistics hierarchy.
- `App/Features/Taste/YearInMusicView.swift` is an MPL-covered adaptation of Cassette's Wrapped hero/ranking composition, mesh gradient implementation, and 2025 palette at commit `49da821`. Its file header preserves Cassette's copyright and MPL notice; ListenBrainz's GPL website supplied behavior only and no frontend code was copied.
- The Profile playlist tabs independently implement API and official-client behavior with app-owned models and SwiftUI; no GPL official-client or donor UI source was copied.
- App UI is original code informed by donor behavior except for the explicitly tracked Year in Music adaptation. Any future copied/adapted Cassette, Minidisc, first.fm, Autohop, Beans, Bòcan, or Finale file must be entered in `THIRD_PARTY.md` before merge.
- GPL and unlicensed projects remain reference-only.
