# Localization

Updated: 2026-09-26

## Decision

Use one translator-facing file: `App/Resources/Localizable.xcstrings`.

- Xcode's compiler extraction owns production-key discovery.
- The catalog keeps an explicit editable English value for every nonempty key.
- Product copy can therefore be translated or revised in this one catalog; Swift source literals act as lookup keys, not a second translator-facing copy file.
- `LocalizedStringResource` crosses reusable-view and computed-copy boundaries.
- `String(localized:)` is appropriate when app-owned copy must become a rendered `String` before presentation.
- Server responses, usernames, artist/release/recording names, playlist text, identifiers, URLs, and fixture data stay verbatim.
- The `Brainz` bundle display name is a non-translated brand constant in generated Info.plist metadata, not interface copy. If localized app names are ever required, Apple requires a separate InfoPlist localization resource, so that would be an explicit exception to this one-file policy.
- Do not create a hand-maintained `AppStrings.swift` mirror. Generated catalog symbols are enabled for future manually managed semantic keys.

## Workflow

```sh
scripts/localizations.sh sync
scripts/localizations.sh check
```

Both modes first reject additional `.xcstrings`, `.strings`, or `.stringsdict` resources and high-confidence ordinary-`String` UI-copy bypasses across all of `App`, including literal `Text(verbatim:)` and direct `LocalizedStringKey` construction, then build the app in Release configuration and collect only the app target's production `.stringsdata`. Xcode supplies the extraction tools; `jq` removes compiler-marked stale keys, fills and validates explicit English source values, and can be supplied ephemerally with `nix shell nixpkgs#jq -c`. `sync` deliberately updates the committed catalog. `check` updates a temporary copy, compares it byte-for-byte with the committed catalog, and removes its temporary build directory. A Debug extraction is never authoritative because it includes visual-QA fixture copy.

## Current checkpoint

- The single catalog contains 1,594 exact Release-extracted production keys, no empty key, no stale entry, and an editable English value for every key.
- The audited production UI, including computed/model notices and accessibility descriptions, uses compiler-extracted literals, `LocalizedStringResource`, or `String(localized:)` as appropriate.
- Thirty-one high-value count phrases now use native String Catalog plural variants with required English `one` and `other` forms. The catalog validator accepts only valid CLDR categories and checks every plural leaf; direct and composed labels cover listens, listeners, artists, releases, tracks, ratings, playlists, albums, minutes, hours, active days, reviews, and related actions.
- Usernames, server responses, artist/release/recording names, playlist text, identifiers, URLs, and fixture data remain explicit verbatim values.
- Calendar years use a non-grouping localized number style, avoiding output such as `2,021` while preserving locale digits.
- Runtime tests verify English `0`, `1`, and `2` selection. Request-denied iPad fixtures cover Home, Artist Highlights, Artist Origins, and Year in Music under forced Arabic right-to-left geometry; expanded pseudo-localization additionally stress-tests Home and Year in Music. Because the catalog does not yet contain Arabic translations, this proves mirroring and layout survival with English fallback, not Arabic wording or Arabic plural rules.
- `scripts/localizations.sh check` matches all 1,594 keys. The latest complete checkpoint passes 667 unit tests and 16 guarded UI tests; the aggregate is 683 passed, one opt-in live-auth route skipped, zero failed, and zero runtime warnings. Independent source re-review found no remaining count regression or concrete production-copy bypass; the Release extraction and byte comparison guard compiler-recognized UI APIs, while the all-`App` source-boundary scan catches common ordinary-`String` escapes.

Before shipping a non-English locale, add and review that locale's plural categories, dates, durations, possessives, capitalization, right-to-left behavior, screenshots, and translations with native-language QA. Continue converting lower-priority count-sensitive phrases as they become translation scope; do not mistake forced layout direction for translated-locale validation.
