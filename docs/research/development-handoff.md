# Development handoff

Snapshot: 2026-09-24.

## Portable checkpoint

- Branch: `main`
- Last validated product commit: `4a80d4ddbf553b7f794c58a4f41a30a87d6392be`
- Remote: `https://github.com/nabekhan/ListenBrainzNative.git`
- Remote `main` is verified after this handoff note is pushed.
- No product feature is left partially applied. A user-requested localization-catalog migration is the next bounded engineering milestone.

That checkpoint adds the signed-in user's current pin to Home by reusing the root-owned `PinsModel` already shared with Profile. Initial Home/Profile appearances admit one guarded current-pin read, explicit Home refresh updates current state without loading pin history, and embedded metadata renders without row hydration. Nullable absence, inline failure/retry, owner context, and the existing recording/history destinations stay native.

Final evidence:

- the restored ListenBrainzKit package baseline passed 140 tests across 20 suites;
- nine focused pin-model tests passed, including repeat-load, current-only refresh, and inline initial failure;
- the complete app suite passed 552/552 with no failures or skips on an iPhone 17 Pro simulator;
- the final Release simulator executable contains both `arm64` and `x86_64`;
- populated, empty, failure, light, dark, accessibility, and iPhone SE fixture states were inspected; and
- independent re-review returned READY after fixture-only tab and authentication escape hatches were closed.

The Home fixture is tokenless, uses local providers and nil artwork/canonical media IDs, and locks selection to Home. It cannot start ListenBrainz, MusicBrainz, or artwork traffic through its reachable routes. No production mutation was exercised.

## Resume on another Mac

Requirements and project generation remain authoritative in the root `README.md` and tracked `project.yml`.

```sh
git clone https://github.com/nabekhan/ListenBrainzNative.git
cd ListenBrainzNative
nix shell nixpkgs#xcodegen -c xcodegen generate
open ListenBrainzNative.xcodeproj
```

Install Xcode and a compatible iOS simulator runtime before building. Reinstall the MIT `content-designer/ux-writing-skill` before adding or revising user-facing strings. Donor clones can be recreated from the URLs recorded in the research documents; do not copy local build products, simulator devices, or credentials. No ListenBrainz token or other secret is stored in the repository.

## Next unstarted product work

Centralize interface copy in one `Localizable.xcstrings` catalog. The inventory found no existing localization resources and roughly 800 SwiftUI-facing literals, including computed/plural/accessibility copy that needs more care than a blind text replacement. Introduce compiler-backed extraction and validation first, migrate shared components plus Home, then move through feature hotspots in reviewable passes while keeping server content, identifiers, and fixture data out of the catalog.

After localization, the separately researched advanced manual-mapping workflow remains a strong adjacent product candidate.

Playback/content resolution, MusicKit capture, and Spotify-linked playback remain deliberately separate. Any libspot/librespot experiment starts only on its own branch after the core product is complete and after policy, licensing, account-security, App Store, and maintenance implications are reviewed.

## Local cleanup

The 2026-09-22 portable cleanup removed prior donor clones, browser tooling, builds, runtimes, skill installation, simulators, and other disposable artifacts. Development was rebuilt on 2026-09-24: Xcode 27 was already present; the iOS 27 runtime, UX-writing skill, ephemeral Nix XcodeGen paths, package/build caches, two disposable QA simulators, logs, and screenshots now exist again.

The source checkout, Git history, tracked Xcode project, `project.yml`, Apple Command Line Tools, shared Nix store, pre-existing developer data, user settings, credentials, personal files, and unrelated Trash contents remain preserved. Exact artifact paths and cleanup commands are recorded in `environment-changes.md`.
