# Development handoff

Snapshot: 2026-09-26.

## Portable checkpoint

- Branch: `main`
- Last validated product commit: `b0d1a62841b0d83faa134d55eeaca3e37e4c6f49`
- Remote: `https://github.com/nabekhan/ListenBrainzNative.git`
- Remote `main` is verified after this handoff note is pushed.
- No change in this checkpoint is partially applied. The playlist-export, release-layout, request-audit, and simulator accessibility slices are complete for the audited source.

Directional navigation now uses semantic forward/backward SF Symbols, including correctly mirrored History controls and disclosures. The Feed hero ornament and avatar badge use semantic RTL placement rather than physical offsets. A generated UI-test bundle covers iPad portrait, device rotation/landscape survival, RTL History, RTL Feed, RTL Profile playlists, expanded pseudo-localization, private-playlist export, Home metric semantics, and Recording feedback state.

The Home and Profile metrics now expose intentional VoiceOver label/value pairs instead of a visual em dash, combined media rows suppress duplicate artwork and chevron announcements, Profile album rows announce artist and localized listen count, and the pinned-history action meets the 44-point target. Recording feedback exposes selected/not-selected values plus the selected trait. The two new deterministic fixtures run native hit-region, sufficient-description, trait, and element-detection audits with request-gated transport denied; a local popularity provider removed an unintended fixture-only read discovered by that guard.

The process-wide ListenBrainz gate now provides a Release-enabled, in-memory audit snapshot containing only closed feature categories, lifecycle totals, and current/maximum read and mutation transport counts. It never stores identity, username, token, URL, parameters, bodies, errors, or responses and starts no request. Every visual regression launch enables a DEBUG-only fail-fast guard immediately before shared-gate transport. That guard exposed and removed a live Fresh Releases provider behind Feed plus a persisted-Discover-tab preload before History; the final suite passes under the guard. It covers shared-gate transports, not hypothetical future networking that bypasses the required gate.

Profile now opens a native Settings destination rather than retaining account controls at the end of the profile feed or adding another tab. The screen distinguishes authenticated and public-profile sessions, provides local System/Light/Dark appearance, reuses the existing Connected Services destination only after an explicit authenticated tap, and links to canonical ListenBrainz account/data controls plus project privacy, source, notices, issue, and confidential-report pages. Opening Settings performs no provider read or credential validation. Disconnect uses the existing fail-closed teardown, never displays the token, and accurately explains both removed data and retained mutation-safety records.

Brainz now has an original opaque 1024×1024 production icon in a native asset catalog. `project.yml` owns the `AppIcon` setting and all four iPad orientations, and the generated Xcode project includes both the catalog and `PrivacyInfo.xcprivacy` as app resources. The root privacy policy explains device storage, signed-in service traffic, residual mutation-safety records, feature-specific content visibility, MetaBrainz logging, and user controls. GitHub private vulnerability reporting is enabled and the policy links directly to it.

Loaded playlists can now be exported as normalized `.jspf.json` files without a provider call, token access, refresh, or other network request. Export preserves the loaded track order and duplicates, includes canonical ListenBrainz and MusicBrainz identifiers only when valid, and warns before sharing a private playlist. Bounded preflight rejects oversized data before document encoding, filenames are path-safe and byte-bounded, protected UUID-scoped staging writes atomically, and completed staging directories are pruned after 24 hours. The format is an interoperable snapshot rather than a raw server-response archive.

`project.yml` now declares the app target's `productName: Brainz`, keeping regenerated product and scheme references aligned with the shipping name. Two consecutive XcodeGen generations produced the same project-and-scheme hash.

The bundled manifest declares no tracking; the app-local `UserDefaults` reason `CA92.1`; linked User ID, Product Interaction, Other User Content, and Search History; and conservatively linked Other Diagnostic Data for MetaBrainz's retained access logs. User ID and Product Interaction include Product Personalization, while Other Diagnostic Data includes Analytics. Signed-in ListenBrainz searches are treated as linked because the client sends the token; MusicBrainz music searches remain token-free.

Final evidence:

- The complete app suite passes 628/628 with no failure, skip, or expected failure. The final guarded UI suite passes 9/9, including direct VoiceOver label/value/selected-state assertions and native accessibility audits; all launches deny request-gated transport and no guard violation occurs.
- The focused playlist-export suite passes 12/12, covering deterministic encoding, order and duplicates, canonical metadata, empty playlists, provenance rejection, byte-bounded Unicode filenames, adversarial scalar counts, track and artist-cardinality limits, control-heavy text, protected staging, and stale cleanup.
- Deterministic request-audit coverage includes read/mutation success, failure, pre-start and in-flight cancellation, exact coalescing, queued cancellation, mutation serialization, and the maximum of two independent read transports.
- `scripts/localizations.sh check` compiler-verifies all 1,618 production keys in the sole string catalog, including the new accessibility values.
- A clean generic Release simulator build succeeds and its executable contains both `x86_64` and `arm64`. Its sole packaging warning is the expected AppIntents metadata skip because the app has no AppIntents dependency. XcodeGen regeneration is byte-stable.
- Independent correctness, security, request-safety, and final-diff reviews report READY. The export review confirms local-only behavior, bounded encoding and staging, canonical identifiers, duplicate preservation, centralized localization, and truthful privacy documentation.
- The earlier final unsigned generic-device Release archive remains valid for the unchanged packaging surface. Its bundle contains the 1024-point AppIcon renditions, opaque 120×120 phone and 152×152 iPad icons, the generated launch-screen dictionary, and no orientation-validation warning.
- The archived privacy manifest is byte-identical to source (`bd70e057eabd5df561467219da1f29a96230ddaa858965aa0db44e79a1c89428`) and parses with the reviewed categories, purposes, and required-reason declaration.
- The installed icon was visually accepted on an iPhone 17 Pro simulator in light and dark Home Screen appearances with the system-applied mask.
- The prior release-foundation checkpoint passed the unchanged vendored ListenBrainzKit baseline at 146/146 across 20 suites. No live credential, production request, or mutation was used for this export checkpoint.
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

The immediate distribution target is sideloading, not TestFlight. The next bounded work is a deterministic repository script that produces and validates an unsigned, re-signable IPA containing only `Payload/Brainz.app`; the unsigned artifact is not directly installable. After an external signing workflow supplies a compatible provisioning identity, perform isolated physical-device, authenticated disposable-account, physical-iPad, Stage Manager/resizable-window, translated-locale, VoiceOver, performance, and crash checks. A paired iPhone with Developer Mode was available at this checkpoint, but Xcode had no configured developer account, team, or Apple Development identity, so no physical build or install was attempted.

After those foundations, evaluate current public MusicKit playback and content-resolution APIs as a separate researched slice; keep service playlist import/export, automatic capture, background submission, and offline retry distinct from the read-first product. Do not begin the proposed libspot/librespot experiment until the core client is complete, and then only on its own branch after licensing, Spotify policy, authentication, maintenance, and App Store review.

Before the sideload release, re-sign the validated IPA, install it on physical hardware, and perform physical-device, authenticated disposable-account, Stage Manager/resizing, direct-network-bypass, request-volume, performance, accessibility, and translated-locale QA. The current checkpoint proves the source-controlled release foundation and guarded simulator pass, not an installable IPA. Final App Store identity, signed archive export, App Store Connect privacy reconciliation, metadata, and TestFlight processing remain later distribution work.

Keep noncontiguous multi-track deletion and multi-track moves withheld unless the server gains an atomic operation that avoids replaying several positional mutations against a changing playlist.

Keep saved-match lookup explicit. It must not become an automatic details-screen read, lifecycle refresh, poll, or retry; submitted recording MBID precedence must remain visible and truthful.

Album collage intentionally starts with already-loaded canonical top releases. Arbitrary MusicBrainz search/addition remains separate because it would introduce a new search and identity-resolution request path; do not add it implicitly to draft editing.

Playback/content resolution, MusicKit capture, and Spotify-linked playback remain deliberately separate. Any libspot/librespot experiment starts only on its own branch after the core product is complete and after policy, licensing, account-security, App Store, and maintenance implications are reviewed.

## Local cleanup

This checkpoint installed no package, browser, runtime, host application, or additional skill. It reused Xcode 27, the iOS 27 runtime, ephemeral Nix XcodeGen, `jq`, the existing UX-writing skill, and Apple command-line tools. The accepted accessibility slice's seven exact Derived Data directories and one crash report were moved through a dedicated Trash bucket and that bucket alone was deleted, reclaiming 2,947,928 KiB. The disposable `Brainz Accessibility QA` simulator was shut down and deleted, and no matching artifact, localization working directory, crash report, or simulator remains. Earlier playlist-export cleanup reclaimed 3,559,916 KiB and removed its own exact simulator and artifacts.

The source checkout, Git history, tracked Xcode project, `project.yml`, Apple Command Line Tools, shared Nix store, pre-existing developer data, user settings, credentials, personal files, and unrelated Trash contents remain preserved. Exact artifact paths and cleanup commands are recorded in `environment-changes.md`.
