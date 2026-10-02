# App Store readiness

Checked against current Apple and MetaBrainz documentation and the ListenBrainz server through 2026-10-01.

## Immediate distribution target

The first release target is a **re-signable sideload IPA**, not TestFlight. The repository produces and inspects an unsigned IPA payload that a compatible signing workflow can re-sign with the user's own provisioning identity. The unsigned artifact is not directly installable and must never be described as a finished signed release.

This changes release sequencing, not product quality: the first signed sideload build still needs physical-device, authenticated disposable-account, accessibility, performance, crash, privacy, and request-safety checks. TestFlight and App Store Connect remain a later distribution path and should stay compatible where that does not complicate the sideload workflow.

## Completed release foundation

| Requirement | Current evidence |
| --- | --- |
| App identity | `AppIcon.appiconset` contains one opaque 1024×1024 universal iOS source. Xcode 27 generates phone and iPad renditions, and `project.yml` owns the `AppIcon` build setting. |
| Device archive | An unsigned generic-iOS Release archive succeeds for arm64. Its app bundle contains `Assets.car`, opaque 120×120 and 152×152 icon files, and `CFBundleIconName = AppIcon`. |
| Unsigned IPA workflow | `scripts/package-ipa.sh` isolates Derived Data and the archive in a temporary root, validates bundle identity/resources/privacy/unsigned nested code, rejects symlinks and unsafe output paths, packages only `Payload/Brainz.app`, and proves byte-identical output from the same archive before publishing without overwrite. The app bundles its tracked third-party notices so static dependency attribution travels with the binary. |
| Privacy manifest | `PrivacyInfo.xcprivacy` is copied byte-for-byte to the app-bundle root. It declares no tracking, the app-local UserDefaults reason `CA92.1`, the app-container file-timestamp reason `C617.1` used by the size-managed artwork cache, and conservative core-functionality data categories. |
| iPad resizing | iPad declares portrait, upside-down portrait, and both landscape orientations. The earlier archive warning is gone; `UIRequiresFullScreen` is not used. |
| Simulator layout and accessibility regression | The tracked wrapper now runs 42 deterministic guarded fixtures on iPhone while three explicitly opt-in live-account cases skip, an established 10-case responsive/RTL/pseudo-localization subset on an actual iPad simulator, and eight high-value dark/maximum-Dynamic-Type variants. The selected final XCResults record 42/42, 10/10, and 8/8 executions passing. Visual review covers the self-Profile Social graph on iPhone, iPad, and maximum text. The guard covers required shared ListenBrainz transport, not arbitrary future networking outside that boundary. |
| Request diagnostics | The process-wide ListenBrainz gate exposes a Release-enabled in-memory snapshot containing only fixed feature categories, lifecycle counters, and current/maximum transport counts. Guarded visual fixtures fail before any request-gated transport can start. A direct source audit found no ListenBrainz bypass, and Home now coalesces its complete six-endpoint refresh sequence at the model boundary as well as each exact transport. A credentialed simulator smoke recorded one validation, intentional Home/History/Discover/Taste/Profile reads, peak read concurrency of two, zero mutations, and no polling or repeated post-settle request; URL-session cancellation is normalized and audited as cancellation rather than failure. |
| Artwork transport | Every ordinary remote cover uses one app-owned Nuke 13.2.0 pipeline with pre-transport redirect admission, public HTTPS/image validation, disabled cookie/credential storage, two data-load slots, exact-task coalescing, cancellation, an 8 MiB response cap, a 1,024-pixel decode target, bounded memory, and a 128 MiB LRU disk-cleanup threshold. A repeated-row Cover Art Archive fixture rendered the real redirected image and persisted one public artwork object without a credential or ListenBrainz API request. |
| Simulator release diagnostics | The final static analyzer is clean; AddressSanitizer and ThreadSanitizer report no app fault in their complete/focused coverage; a normally signed Release simulator build launches with Keychain access; Time Profiler reports no potential hang; App Launch reports no file-system antipattern; and the final crash scan finds no new Brainz report. The guarded credentialed smoke additionally proves real sign-in, authenticated content, Keychain restore, expected-account disconnect, and a signed-out relaunch. The current complete app unit suite passes 846/846, the vendored Kit passes 178/178, the compiler-backed catalog matches 1,967/1,967 keys, the universal generic Release simulator contains `arm64` and `x86_64`, and fresh Release analysis exits cleanly. The Leaks trace contains one historical unclassified 32-byte allocation with a truncated stack and no app attribution, retained as a physical-candidate recheck rather than claimed away. |
| Physical-device preflight | A paired current iPhone is reachable and has Developer Mode enabled. The Mac has no configured Xcode developer account, development team, or Apple Development signing identity, so no app was built for or installed on the phone. The intended first device run uses the isolated QA bundle, local fixtures, and fail-fast request guard. |
| Launch screen | Xcode's generated launch-screen dictionary is present in the archived `Info.plist`. |
| Public policy | Root `PRIVACY.md` explains local storage, direct service traffic, tracking, MetaBrainz logging, and user controls in plain language. |
| In-app user controls | Profile opens a request-free native Settings surface with the same privacy policy, canonical ListenBrainz data controls, local appearance, and a confirmed disconnect action that removes the saved credential and listening snapshot without overstating residual safety-record cleanup. |
| Confidential reports | GitHub private vulnerability reporting is enabled for the public repository, and the policy links directly to a new private advisory. |

Apple permits iOS and iPadOS to generate icon variants from one 1024×1024 image and requires the App Store image in the 1024-point slot. Apple also requires every used Required Reason API category to be present in a bundled privacy manifest; `CA92.1` covers app-only UserDefaults and `C617.1` covers file timestamps used inside the app container. Current iPad guidance favors all orientations and resizable layouts rather than the deprecated `UIRequiresFullScreen` compatibility mode.

Sources: [app icon configuration](https://developer.apple.com/documentation/xcode/configuring-your-app-icon), [privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files), [Required Reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api), [approved UserDefaults reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons), and [iPad full-screen migration](https://developer.apple.com/documentation/technotes/tn3192-migrating-your-app-from-the-deprecated-uirequiresfullscreen-key).

## Manifest rationale

The app and its dependencies contain no analytics, advertising, tracking, or crash-reporting SDK. Source inspection found no IDFA, AppTrackingTransparency, system-uptime, disk-space, or active-keyboard Required Reason API. App-owned UserDefaults and `@AppStorage` hold only session mode, local preferences, and mutation-recovery state, so `NSPrivacyAccessedAPICategoryUserDefaults` uses `CA92.1`. Nuke's app-container artwork cache reads and updates access timestamps for LRU cleanup, so `NSPrivacyAccessedAPICategoryFileTimestamp` uses `C617.1`.

The collected-data entries intentionally err toward disclosure:

- **User ID**, linked: a ListenBrainz username identifies the account used for requests and selects personalized results.
- **Product interaction**, linked: music-listening data and account actions can be stored by ListenBrainz and used for personalized recommendations.
- **Other user content**, linked: playlist titles/annotations and recommendation, pin, or thanks text can be submitted.
- **Search history**, conservatively linked: current ListenBrainz user/playlist and MusicBrainz music searches are deliberately token-free. The manifest still uses the linked classification because MetaBrainz says its access logs retain request parameters and IP addresses, and one conservative category must cover the complete app rather than only the current search adapter.
- **Other diagnostic data**, linked: MetaBrainz retains IP address, user agent, endpoint, and request parameters in access logs for seven days and publishes aggregate traffic statistics. The declaration conservatively covers app functionality and analytics.

None of these categories is used for tracking. User ID and Product Interaction additionally declare Product Personalization; Other Diagnostic Data additionally declares Analytics. App Store Connect answers must match this manifest and the public policy. MetaBrainz documents request-parameter and IP logging in its [privacy policy](https://metabrainz.org/privacy); ListenBrainz describes the public treatment of listening data in its [terms](https://listenbrainz.org/terms-of-service/).

## Icon provenance

The icon is original project artwork generated with OpenAI's built-in image-generation tool, then resized to 1024×1024 and flattened to opaque RGB with the pre-existing `ffmpeg` installation. No donor asset or official ListenBrainz mark was copied. The production prompt was:

> Create a distinctive, premium icon for Brainz, a native iOS app for exploring personal ListenBrainz listening history, taste, discovery, and social music data. Use one bold abstract mark combining a flowing audio waveform with musical history or layered listening paths; use the app's deep aubergine, coral-orange, and restrained teal palette; keep it legible at 29 points; include no text, letters, musical-note glyph, headphones, brain illustration, vinyl cliché, official service marks, rounded-corner mask, or watermark.

The single source deliberately omits hand-authored dark and tinted variants. Apple documents that the system can generate those treatments; the installed icon was visually accepted in both light and dark Home Screen appearances.

## Still required before the sideload release

- re-sign the validated unsigned payload with an appropriate provisioning identity and keep certificates, profiles, and signing logs out of source control;
- install the signed IPA on a physical iPhone and repeat authenticated QA on the signed physical candidate without replaying mutations; authenticated simulator validation is complete;
- repeat rotation, Stage Manager/resizable-window, RTL, and VoiceOver checks on physical iPad hardware where available, and test actual translations once they exist; and
- repeat final accessibility, performance, crash, direct-network-bypass, request-volume, and regression passes on the signed physical candidate; simulator analyzer, sanitizer, performance, and crash diagnostics are already complete.

## Later App Store distribution work

- configure the final Apple Developer team, bundle identifier, version/build sequence, and distribution identity;
- make a signed archive, inspect Apple's generated privacy report, and complete TestFlight processing;
- enter App Store metadata, screenshots, review notes, support and privacy URLs, age rating, and category; and
- reconcile the App Store privacy questionnaire with the shipped binary and observed service behavior.

The source-level release foundation, guarded credential-free matrix, credentialed simulator validation, and shared artwork pipeline are complete. Clean viewer/explorer checkpoint `5bb86dd`, containing product commit `7e8977b`, packages into an 8,404,229-byte unsigned build-3 payload with SHA-256 `91211c17bb001ab9a7cd8b6fe4e180a1c94db2954a00dcf9ad83ede1062da03d`; local extraction verifies a safe 16-entry arm64 payload, source-identical privacy and third-party notices, unencrypted unsigned code, Apple-system-only dependencies, and no DEBUG fixture/live-route or absolute workspace marker. This does not yet claim an installable signed sideload IPA, physical-device behavior, TestFlight readiness, or App Store readiness.
