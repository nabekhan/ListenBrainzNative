# Localization

Updated: 2026-09-25

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

Both modes first reject additional `.xcstrings`, `.strings`, or `.stringsdict` resources and high-confidence ordinary-`String` UI-copy bypasses, then build the app in Release configuration and collect only the app target's production `.stringsdata`. Xcode supplies the extraction tools; `jq` removes compiler-marked stale keys, fills and validates explicit English source values, and can be supplied ephemerally with `nix shell nixpkgs#jq -c`. `sync` deliberately updates the committed catalog. `check` updates a temporary copy, compares it byte-for-byte with the committed catalog, and removes its temporary build directory. A Debug extraction is never authoritative because it includes visual-QA fixture copy.

## Current checkpoint

- The single catalog contains 1,573 exact Release-extracted production keys, no empty key, no stale entry, and an editable English value for every key.
- The audited production UI, including computed/model notices and accessibility descriptions, uses compiler-extracted literals, `LocalizedStringResource`, or `String(localized:)` as appropriate.
- Usernames, server responses, artist/release/recording names, playlist text, identifiers, URLs, and fixture data remain explicit verbatim values.
- Calendar years use a non-grouping localized number style, avoiding output such as `2,021` while preserving locale digits.
- Normal and accented-pseudolocalized small-device checks confirm app-owned copy transforms and wraps while fixture usernames and music metadata remain unchanged.
- `scripts/localizations.sh check` matches all 1,573 keys, and the latest complete app checkpoint passes 596/596 with no failure, skip, or runtime warning. Independent source re-review found no concrete production-copy bypass; the Release extraction and byte comparison guard compiler-recognized UI APIs, while the source-boundary scan catches common ordinary-`String` escapes.

Before shipping a non-English locale, consolidate count strings into catalog plural variants and review dates, durations, possessives, capitalization, right-to-left behavior, screenshots, and translations with native-language QA.
