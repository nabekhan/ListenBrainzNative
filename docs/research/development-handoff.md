# Development handoff

Snapshot: 2026-09-26.

## Portable checkpoint

- Branch: `main`
- Last validated product commit: `4412848dc2d22ee7363a33771ef37d69c27335b6`
- Remote: `https://github.com/nabekhan/ListenBrainzNative.git`
- Remote `main` is verified after this handoff note is pushed.
- No change in this checkpoint is partially applied. Web-assisted authentication, Fresh Releases request supersession, playlist export, release layout, request auditing, simulator accessibility, and the high-value plural/RTL foundation are complete for the audited source, except for the explicitly pending manual credentialed sign-in trial and native-language translation QA.

The sole String Catalog now contains 1,588 Release-extracted production keys and 31 native English plural resources. High-value counts no longer branch into separate translator-facing singular/plural literals, compound VoiceOver phrases interpolate an already-resolved count phrase, and the validator requires nonempty `one`/`other` leaves while permitting only CLDR plural categories. English `0`/`1`/`2` tests catch singular regressions. Forced Arabic direction validates layout with English fallback; it does not claim Arabic translations that do not yet exist.

Authentication now leads with a native sheet that keeps username/password entry inside the exact official MetaBrainz pages, shares only an ephemeral WebKit data store with a hidden ListenBrainz Settings extractor, and validates the resulting canonical token exactly once through the existing provider. A stateful allowlist binds scheme, host, port, path, method, OAuth parameters, and callback state; popups, downloads, file selection, media capture, and JavaScript dialogs fail closed. The manual-token route remains available. Keychain persistence is `WhenUnlockedThisDeviceOnly`, occurs only after cancellation/generation checks, and cannot suspend across the final commit boundary. A credential-free live route reached the current official MetaBrainz login page; a complete account/token/Keychain trial still requires manual secret entry that does not cross automation logs.

Fresh Releases now gives the visible exact query sole ownership of active work. Equal requests still coalesce and loaded query states remain cached, while a scope/window/status change cancels distinct superseded work and prevents a late success, failure, or cancellation from publishing stale state. Type/tag filtering stays local and makes no request.

Directional navigation now uses semantic forward/backward SF Symbols, including correctly mirrored History controls and disclosures. The Feed hero ornament and avatar badge use semantic RTL placement rather than physical offsets. A generated UI-test bundle covers iPad portrait, device rotation/landscape survival, RTL History, Feed, Profile playlists, Home metrics, Artist Highlights, Artist Origins, and Year in Music; expanded pseudo-localization, private-playlist export, Home metric semantics, and Recording feedback state remain covered.

The Home and Profile metrics now expose intentional VoiceOver label/value pairs instead of a visual em dash, combined media rows suppress duplicate artwork and chevron announcements, Profile album rows announce artist and localized listen count, and the pinned-history action meets the 44-point target. Recording feedback exposes selected/not-selected values plus the selected trait. The two new deterministic fixtures run native hit-region, sufficient-description, trait, and element-detection audits with request-gated transport denied; a local popularity provider removed an unintended fixture-only read discovered by that guard.

The process-wide ListenBrainz gate now provides a Release-enabled, in-memory audit snapshot containing only closed feature categories, lifecycle totals, and current/maximum read and mutation transport counts. It never stores identity, username, token, URL, parameters, bodies, errors, or responses and starts no request. Every visual regression launch enables a DEBUG-only fail-fast guard immediately before shared-gate transport. That guard exposed and removed a live Fresh Releases provider behind Feed plus a persisted-Discover-tab preload before History; the final suite passes under the guard. It covers shared-gate transports, not hypothetical future networking that bypasses the required gate.

A direct source audit found no ListenBrainz transport outside that gate, no lifecycle polling loop, no per-row hydration, and no obvious N+1 request path. It did find that overlapping Home toolbar and pull-to-refresh actions could fall out of endpoint-level coalescing and replay the complete six-read sequence. Home now owns one model-level refresh flight spanning recent listens, Playing Now, listen count, and all three rankings. Every overlapping caller awaits it, and cancellation of one waiter does not cancel the shared work. Explicit later refreshes remain fresh user intent; no broad TTL or cadence change was added.

Profile now opens a native Settings destination rather than retaining account controls at the end of the profile feed or adding another tab. The screen distinguishes authenticated and public-profile sessions, provides local System/Light/Dark appearance, reuses the existing Connected Services destination only after an explicit authenticated tap, and links to canonical ListenBrainz account/data controls plus project privacy, source, notices, issue, and confidential-report pages. Opening Settings performs no provider read or credential validation. Disconnect uses the existing fail-closed teardown, never displays the token, and accurately explains both removed data and retained mutation-safety records.

Brainz now has an original opaque 1024×1024 production icon in a native asset catalog. `project.yml` owns the `AppIcon` setting and all four iPad orientations, and the generated Xcode project includes both the catalog and `PrivacyInfo.xcprivacy` as app resources. The root privacy policy explains device storage, signed-in service traffic, residual mutation-safety records, feature-specific content visibility, MetaBrainz logging, and user controls. GitHub private vulnerability reporting is enabled and the policy links directly to it.

Loaded playlists can now be exported as normalized `.jspf.json` files without a provider call, token access, refresh, or other network request. Export preserves the loaded track order and duplicates, includes canonical ListenBrainz and MusicBrainz identifiers only when valid, and warns before sharing a private playlist. Bounded preflight rejects oversized data before document encoding, filenames are path-safe and byte-bounded, protected UUID-scoped staging writes atomically, and completed staging directories are pruned after 24 hours. The format is an interoperable snapshot rather than a raw server-response archive.

`project.yml` now declares the app target's `productName: Brainz`, keeping regenerated product and scheme references aligned with the shipping name. Two consecutive XcodeGen generations produced the same project-and-scheme hash.

`scripts/package-ipa.sh` now supplies the immediate sideload artifact boundary. It uses only pinned Apple/BSD tools and an isolated temporary Derived Data/archive root, verifies the arm64 executable, unsigned nested code, and exact reviewed resources, rejects profiles/signatures/symlinks, normalizes staged payload timestamps, compares two packages from the same archive, and atomically publishes without replacing an existing path. Repository-wide ignores cover generated IPAs and common private signing formats. Signing credentials, profiles, entitlements, and device installation remain deliberately external.

The bundled manifest declares no tracking; the app-local `UserDefaults` reason `CA92.1`; linked User ID, Product Interaction, Other User Content, and Search History; and conservatively linked Other Diagnostic Data for MetaBrainz's retained access logs. User ID and Product Interaction include Product Personalization, while Other Diagnostic Data includes Analytics. Signed-in ListenBrainz searches are treated as linked because the client sends the token; MusicBrainz music searches remain token-free.

Final evidence:

- The complete app suite passes 642/642 with no failure, skip, expected failure, or runtime warning. The focused Home refresh-flight regression passes with a cancelled first waiter and a surviving second waiter while every one of the six endpoints is called exactly once. The final guarded UI suite passes 14/14 with the opt-in live-auth route test explicitly excluded; all fixture launches deny request-gated transport and no guard violation occurs. The focused post-sync plural suite passes 6/6.
- The focused playlist-export suite passes 12/12, covering deterministic encoding, order and duplicates, canonical metadata, empty playlists, provenance rejection, byte-bounded Unicode filenames, adversarial scalar counts, track and artist-cardinality limits, control-heavy text, protected staging, and stale cleanup.
- Deterministic request-audit coverage includes read/mutation success, failure, pre-start and in-flight cancellation, exact transport coalescing, complete Home refresh coalescing, queued cancellation, mutation serialization, and the maximum of two independent read transports. A direct source audit found no ungated ListenBrainz call.
- `scripts/localizations.sh check` compiler-verifies all 1,588 production keys in the sole string catalog, including 31 English plural resources and every authentication label, disclosure, progress state, and error.
- A clean generic Release simulator build succeeds and its executable contains both `x86_64` and `arm64`. Its sole packaging warning is the expected AppIntents metadata skip because the app has no AppIntents dependency. XcodeGen regeneration is byte-stable.
- Independent correctness, security, request-safety, plural-correctness, and final-diff reviews report READY. The authentication review confirms ephemeral browser isolation, exact route/state enforcement, bounded local DOM extraction, one validation read, cancellation-safe persistence, complete trust-banner accessibility, and no credential logging or clipboard handling. The credential-free live route, light/dark, iPhone SE, and maximum-Dynamic-Type checks pass; the full credentialed flow remains an explicitly unclaimed release check.
- The earlier final unsigned generic-device Release archive remains valid for the unchanged packaging surface. Its bundle contains the 1024-point AppIcon renditions, opaque 120×120 phone and 152×152 iPad icons, the generated launch-screen dictionary, and no orientation-validation warning.
- The archived privacy manifest is byte-identical to source (`bd70e057eabd5df561467219da1f29a96230ddaa858965aa0db44e79a1c89428`) and parses with the reviewed categories, purposes, and required-reason declaration.
- The installed icon was visually accepted on an iPhone 17 Pro simulator in light and dark Home Screen appearances with the system-applied mask.
- The prior release-foundation checkpoint passed the unchanged vendored ListenBrainzKit baseline at 146/146 across 20 suites. No live credential, production request, or mutation was used for this export checkpoint.
- Independent packaging and security reviews report READY after correcting authenticated Search History linkage, personalization purposes, retained-log disclosure, disconnect-retention wording, and the confidential-reporting route.
- The final unsigned sideload workflow produced a 7,007,793-byte IPA with SHA-256 `4b2fb1370750eca6bba1436dea56bfea0bcd72593c21c8cb8e8a0e9b549c2ad8`. Its two internal packages were byte-identical; independent extraction verified exactly 11 entries under `Payload/Brainz.app`, one unsigned arm64 Mach-O object, bundle `dev.nabekhan.listenbrainznative`, version `0.1.0 (1)`, the source privacy hash, and no symlink, profile, signature, extra top-level entry, overwrite, or surviving temporary root. Independent correctness and security re-reviews report READY for the default/user-owned output boundary.

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

The immediate distribution target is sideloading, not TestFlight, and the deterministic unsigned IPA workflow is complete. Native catalog plurals, English-fallback RTL geometry review, direct request-boundary inspection, and deterministic Home refresh-volume coverage are now complete. The next authenticated release check is manual web sign-in, token extraction, Keychain restore, one account read, and a request-audit snapshot on an isolated simulator; native-language translation QA remains separate. External signing, physical-device installation, physical iPad/Stage Manager, performance, and crash checks follow without blocking simulator product work. A paired iPhone with Developer Mode was available at this checkpoint, but no signing identity or profile was used and no physical install was attempted.

After those foundations, evaluate current public MusicKit playback and content-resolution APIs as a separate researched slice; keep service playlist import/export, automatic capture, background submission, and offline retry distinct from the read-first product. Do not begin the proposed libspot/librespot experiment until the core client is complete, and then only on its own branch after licensing, Spotify policy, authentication, maintenance, and App Store review.

Before the sideload release, re-sign the validated IPA, install it on physical hardware, and perform physical-device, authenticated disposable-account, Stage Manager/resizing, direct-network-bypass, request-volume, performance, accessibility, and translated-locale QA. The current checkpoint proves the source-controlled release foundation and guarded simulator pass, not an installable IPA. Final App Store identity, signed archive export, App Store Connect privacy reconciliation, metadata, and TestFlight processing remain later distribution work.

Keep noncontiguous multi-track deletion and multi-track moves withheld unless the server gains an atomic operation that avoids replaying several positional mutations against a changing playlist.

Keep saved-match lookup explicit. It must not become an automatic details-screen read, lifecycle refresh, poll, or retry; submitted recording MBID precedence must remain visible and truthful.

Album collage intentionally starts with already-loaded canonical top releases. Arbitrary MusicBrainz search/addition remains separate because it would introduce a new search and identity-resolution request path; do not add it implicitly to draft editing.

Playback/content resolution, MusicKit capture, and Spotify-linked playback remain deliberately separate. Any libspot/librespot experiment starts only on its own branch after the core product is complete and after policy, licensing, account-security, App Store, and maintenance implications are reviewed.

## Local cleanup

This localization checkpoint installed no package, browser, runtime, host application, or additional skill. It reused Xcode 27, the iOS 27 runtime, `jq`, the existing UX-writing skill, and Apple command-line tools. Its 15 exact Derived Data, result-bundle, screenshot, validation, and log artifacts were moved through one dedicated Trash bucket and that bucket alone was deleted, reclaiming 2,183,232 KiB. Both exact disposable simulators were shut down and deleted; an exact audit found no matching artifact, bucket, or simulator.

The web-auth/Fresh Releases slice's 35 exact Derived Data, log, screenshot, sample, and result-bundle artifacts were moved through one dedicated Trash bucket and that bucket alone was deleted path by path, reclaiming 4,008,232 KiB. Its iPhone 17 Pro and iPhone SE simulators were terminated, shut down, and deleted; an exact audit found no matching artifact, bucket, or simulator. The earlier accessibility cleanup reclaimed 2,947,928 KiB, and playlist-export cleanup reclaimed 3,559,916 KiB.

The sideload slice's validated unsigned IPA and the exact project Derived Data cache touched by the first diagnostic run were moved through a dedicated Trash bucket and that bucket alone was deleted, reclaiming 1,141,732 KiB. Interrupted isolated roots, inspection roots, publication roots, and a failed link-test directory were removed by exact path. No generated IPA, project cache, archive root, signing material, profile, certificate, or new tool remains.

The Home request-audit slice's nine exact Derived Data, result-bundle, and UDID-record paths were moved through one dedicated Trash bucket and that bucket alone was deleted, reclaiming 1,770,676 KiB. Its disposable iPhone 17 Pro simulator was shut down and deleted. The slice installed no package, browser, runtime, host application, credential, or skill, and an exact audit found no matching artifact, bucket, or simulator afterward.

The source checkout, Git history, tracked Xcode project, `project.yml`, Apple Command Line Tools, shared Nix store, pre-existing developer data, user settings, credentials, personal files, and unrelated Trash contents remain preserved. Exact artifact paths and cleanup commands are recorded in `environment-changes.md`.
