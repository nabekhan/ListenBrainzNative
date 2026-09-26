# Development handoff

Snapshot: 2026-09-25.

## Portable checkpoint

- Branch: `main`
- Last validated product commit: `eca40fbb03a0f26bfc192fa2fe3755b1ada125f0`
- Remote: `https://github.com/nabekhan/ListenBrainzNative.git`
- Remote `main` is verified after this handoff note is pushed.
- No change in this checkpoint is partially applied. The native Settings/account slice is complete for the audited source.

Profile now opens a native Settings destination rather than retaining account controls at the end of the profile feed or adding another tab. The screen distinguishes authenticated and public-profile sessions, provides local System/Light/Dark appearance, reuses the existing Connected Services destination only after an explicit authenticated tap, and links to canonical ListenBrainz account/data controls plus project privacy, source, notices, issue, and confidential-report pages. Opening Settings performs no provider read or credential validation. Disconnect uses the existing fail-closed teardown, never displays the token, and accurately explains both removed data and retained mutation-safety records.

Brainz now has an original opaque 1024×1024 production icon in a native asset catalog. `project.yml` owns the `AppIcon` setting and all four iPad orientations, and the generated Xcode project includes both the catalog and `PrivacyInfo.xcprivacy` as app resources. The root privacy policy explains device storage, signed-in service traffic, residual mutation-safety records, feature-specific content visibility, MetaBrainz logging, and user controls. GitHub private vulnerability reporting is enabled and the policy links directly to it.

The bundled manifest declares no tracking; the app-local `UserDefaults` reason `CA92.1`; linked User ID, Product Interaction, Other User Content, and Search History; and conservatively linked Other Diagnostic Data for MetaBrainz's retained access logs. User ID and Product Interaction include Product Personalization, while Other Diagnostic Data includes Analytics. Signed-in ListenBrainz searches are treated as linked because the client sends the token; MusicBrainz music searches remain token-free.

Final evidence:

- The Settings/session focused set passes 11/11, including a hosted-view lifecycle regression proving that rendering Settings leaves the Connected Services provider untouched. The complete app suite passes 613/613 with no failure, skip, or expected failure.
- `scripts/localizations.sh check` compiler-verifies all 1,607 production keys in the sole string catalog. The UX Writing review kept the destructive-action text plain, specific, and consistent with `PRIVACY.md`.
- A generic Release simulator build succeeds and its executable contains both `x86_64` and `arm64`. Fixture-only QA covers authenticated and public sessions, light/dark mode, maximum Dynamic Type, iPhone SE, app-forced appearance, and the disconnect confirmation. The final scoped app log contains no service hostname, URL request, or fatal-failure match.
- Independent correctness and security re-reviews report READY after the disconnect copy was narrowed to the data the app actually removes and the catalog was resynchronized.
- XcodeGen regeneration is stable, and a final unsigned generic-device Release archive succeeds for arm64. Its bundle contains the 1024-point AppIcon renditions, opaque 120×120 phone and 152×152 iPad icons, the generated launch-screen dictionary, and no orientation-validation warning. The only warning is the expected AppIntents metadata skip because the app has no AppIntents dependency.
- The archived privacy manifest is byte-identical to source (`bd70e057eabd5df561467219da1f29a96230ddaa858965aa0db44e79a1c89428`) and parses with the reviewed categories, purposes, and required-reason declaration.
- The installed icon was visually accepted on an iPhone 17 Pro simulator in light and dark Home Screen appearances with the system-applied mask.
- The prior release-foundation checkpoint passed the unchanged vendored ListenBrainzKit baseline at 146/146 across 20 suites. No live credential, production request, or mutation was used for either that checkpoint or this Settings slice.
- Independent packaging and security reviews report READY after correcting authenticated Search History linkage, personalization purposes, retained-log disclosure, disconnect-retention wording, and the confidential-reporting route.

## Resume on another Mac

Requirements and project generation remain authoritative in the root `README.md` and tracked `project.yml`.

```sh
git clone https://github.com/nabekhan/ListenBrainzNative.git
cd ListenBrainzNative
nix shell nixpkgs#xcodegen -c xcodegen generate
open ListenBrainzNative.xcodeproj
```

Install Xcode and a compatible iOS simulator runtime before building. Reinstall the MIT `content-designer/ux-writing-skill` before adding or revising user-facing strings. Donor clones can be recreated from the URLs recorded in the research documents; do not copy local build products, simulator devices, or credentials. No ListenBrainz token or other secret is stored in the repository.

## Next product work

The next bounded work should harden a release candidate without inventing new server traffic: interactive iPad rotation/resizing, right-to-left and non-English layouts, performance/request instrumentation, and physical-device testing where a disposable account and device are available. After those foundations, evaluate current public MusicKit playback and content-resolution APIs as a separate researched slice; keep automatic capture, background submission, and offline retry distinct from the read-first product. Do not begin the proposed libspot/librespot experiment until the core client is complete, and then only on its own branch after licensing, Spotify policy, authentication, maintenance, and App Store review.

Before release, choose the final bundle identifier, signing team, version/build values, and distribution identity; make a signed archive; reconcile App Store Connect privacy answers with the shipped report; complete TestFlight processing; and perform physical-device, authenticated disposable-account, iPad resizing, network-request, performance, accessibility, non-English, and right-to-left QA. The current checkpoint proves the source-controlled release foundation, not App Store readiness.

Keep noncontiguous multi-track deletion and multi-track moves withheld unless the server gains an atomic operation that avoids replaying several positional mutations against a changing playlist.

Keep saved-match lookup explicit. It must not become an automatic details-screen read, lifecycle refresh, poll, or retry; submitted recording MBID precedence must remain visible and truthful.

Album collage intentionally starts with already-loaded canonical top releases. Arbitrary MusicBrainz search/addition remains separate because it would introduce a new search and identity-resolution request path; do not add it implicitly to draft editing.

Playback/content resolution, MusicKit capture, and Spotify-linked playback remain deliberately separate. Any libspot/librespot experiment starts only on its own branch after the core product is complete and after policy, licensing, account-security, App Store, and maintenance implications are reviewed.

## Local cleanup

This checkpoint installed no package, browser, runtime, host application, or additional skill. It reused Xcode 27, the iOS 27 runtime, ephemeral Nix XcodeGen, `jq`, Apple command-line tools, and the existing UX Writing skill. The three Settings build directories, result bundles, logs, screenshots, and one interrupted localization extraction were moved through the dedicated `Brainz-Settings-20260925.wyOhYE` Trash bucket; that bucket alone was permanently deleted, reclaiming 1.5 GB without inspecting or changing unrelated Trash. `Brainz Settings QA` (`E8278EBC-8BEA-4037-88C5-5D5696B9C981`) and `Brainz Settings SE QA` (`616F18C7-927A-4E28-BE8F-71B2633A94A6`) were terminated, shut down, and deleted. An exact audit found no matching artifact, cleanup bucket, or simulator afterward.

The source checkout, Git history, tracked Xcode project, `project.yml`, Apple Command Line Tools, shared Nix store, pre-existing developer data, user settings, credentials, personal files, and unrelated Trash contents remain preserved. Exact artifact paths and cleanup commands are recorded in `environment-changes.md`.
