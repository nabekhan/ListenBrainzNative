# Localization

Updated: 2026-09-24

## Decision

Use one translator-facing file: `App/Resources/Localizable.xcstrings`.

- Xcode's compiler extraction owns production-key discovery.
- The catalog keeps an explicit editable English value for every nonempty key.
- `LocalizedStringResource` crosses reusable-view and computed-copy boundaries.
- `String(localized:)` is appropriate when app-owned copy must become a rendered `String` before presentation.
- Server responses, usernames, artist/release/recording names, playlist text, identifiers, URLs, and fixture data stay verbatim.
- Do not create a hand-maintained `AppStrings.swift` mirror. Generated catalog symbols are enabled for future manually managed semantic keys.

## Workflow

```sh
scripts/localizations.sh sync
scripts/localizations.sh check
```

Both modes build the app in Release configuration and collect only the app target's production `.stringsdata`. Xcode supplies the extraction tools; `jq` fills and validates explicit English source values and can be supplied ephemerally with `nix shell nixpkgs#jq -c`. `sync` deliberately updates the committed catalog. `check` updates a temporary copy, compares it byte-for-byte with the committed catalog, and removes its temporary build directory. A Debug extraction is never authoritative because it includes visual-QA fixture copy.

## Current checkpoint

- One catalog contains 914 Release-extracted production keys.
- `SectionHeader`, `FeaturedListenCard`, `LoadingStateView`, current-pin presentation, and Home's greetings, metrics, count labels, and accessibility wrapper now carry localizable resources instead of opaque `String` copy.
- Section-header call sites preserve dynamic interpolation as localizable copy; genuinely user/server-authored values remain explicit verbatim text.
- The prior blanket one-request-per-second loading sentence was replaced with accurate neutral progress copy.
- An accented pseudolocalization check confirms app-owned copy localizes while fixture usernames and music metadata remain unchanged.

This is the foundation and first migration slice, not a claim that every older computed string has already been converted. Remaining compiler-invisible copy should move feature by feature, starting with Playlist Detail, Year in Music, Taste, Radio, History, Discover, model-authored notices, computed accessibility descriptions, and count/unit formatting. Before shipping a non-English locale, consolidate count strings into catalog plural variants and review date, duration, possessive, capitalization, and right-to-left behavior with native-language QA.
