# Development handoff

Snapshot: 2026-09-25.

## Portable checkpoint

- Branch: `main`
- Last validated product commit: `a7e3a8668b48699e95fadff396b1a7525a46caa8`
- Remote: `https://github.com/nabekhan/ListenBrainzNative.git`
- Remote `main` is verified after this handoff note is pushed.
- No change in this checkpoint is partially applied. The app identity and privacy release foundation is complete for the audited source.

Brainz now has an original opaque 1024×1024 production icon in a native asset catalog. `project.yml` owns the `AppIcon` setting and all four iPad orientations, and the generated Xcode project includes both the catalog and `PrivacyInfo.xcprivacy` as app resources. The root privacy policy explains device storage, signed-in service traffic, residual mutation-safety records, feature-specific content visibility, MetaBrainz logging, and user controls. GitHub private vulnerability reporting is enabled and the policy links directly to it.

The bundled manifest declares no tracking; the app-local `UserDefaults` reason `CA92.1`; linked User ID, Product Interaction, Other User Content, and Search History; and conservatively linked Other Diagnostic Data for MetaBrainz's retained access logs. User ID and Product Interaction include Product Personalization, while Other Diagnostic Data includes Analytics. Signed-in ListenBrainz searches are treated as linked because the client sends the token; MusicBrainz music searches remain token-free.

Final evidence:

- XcodeGen regeneration is stable, and a final unsigned generic-device Release archive succeeds for arm64. Its bundle contains the 1024-point AppIcon renditions, opaque 120×120 phone and 152×152 iPad icons, the generated launch-screen dictionary, and no orientation-validation warning. The only warning is the expected AppIntents metadata skip because the app has no AppIntents dependency.
- The archived privacy manifest is byte-identical to source (`bd70e057eabd5df561467219da1f29a96230ddaa858965aa0db44e79a1c89428`) and parses with the reviewed categories, purposes, and required-reason declaration.
- The installed icon was visually accepted on an iPhone 17 Pro simulator in light and dark Home Screen appearances with the system-applied mask.
- The complete app suite passes 608/608, the vendored ListenBrainzKit passes 146/146 across 20 suites, and `scripts/localizations.sh check` confirms all 1,579 production keys. No live credential, production request, or mutation was used.
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

The next product slice should evaluate the still-missing native Settings/account surface after inspecting the current website and official clients. Prefer a Profile-launched destination rather than another tab; reuse the existing Connected Services, session, privacy, and external-link behavior instead of duplicating them. Keep every new app-authored string in `App/Resources/Localizable.xcstrings` and run the guarded sync/check workflow.

Before release, choose the final bundle identifier, signing team, version/build values, and distribution identity; make a signed archive; reconcile App Store Connect privacy answers with the shipped report; complete TestFlight processing; and perform physical-device, authenticated disposable-account, iPad resizing, network-request, performance, accessibility, non-English, and right-to-left QA. The current checkpoint proves the source-controlled release foundation, not App Store readiness.

Keep noncontiguous multi-track deletion and multi-track moves withheld unless the server gains an atomic operation that avoids replaying several positional mutations against a changing playlist.

Keep saved-match lookup explicit. It must not become an automatic details-screen read, lifecycle refresh, poll, or retry; submitted recording MBID precedence must remain visible and truthful.

Album collage intentionally starts with already-loaded canonical top releases. Arbitrary MusicBrainz search/addition remains separate because it would introduce a new search and identity-resolution request path; do not add it implicitly to draft editing.

Playback/content resolution, MusicKit capture, and Spotify-linked playback remain deliberately separate. Any libspot/librespot experiment starts only on its own branch after the core product is complete and after policy, licensing, account-security, App Store, and maintenance implications are reviewed.

## Local cleanup

This checkpoint installed no package, browser, runtime, host application, or additional skill. It reused Xcode 27, the iOS 27 runtime, ephemeral Nix XcodeGen, `ffmpeg`, `jq`, Apple command-line tools, and the existing UX Writing and image-generation skills. The three project build directories, package build cache, archives, result bundle, logs, screenshots, and generated source image were moved through the dedicated `Brainz-Release-20260925-bjK3FY` Trash bucket; that bucket alone was deleted file-by-file, reclaiming 1.7 GB without inspecting or changing unrelated Trash. `Brainz Release Identity QA` (`4AC26932-A0F4-4E69-BA39-D4E13BD7D16C`) was shut down and deleted. An exact audit found no recorded artifact, cleanup bucket, or simulator afterward.

The source checkout, Git history, tracked Xcode project, `project.yml`, Apple Command Line Tools, shared Nix store, pre-existing developer data, user settings, credentials, personal files, and unrelated Trash contents remain preserved. Exact artifact paths and cleanup commands are recorded in `environment-changes.md`.
