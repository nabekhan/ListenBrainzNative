# App Store readiness

Checked against current Apple and MetaBrainz documentation on 2026-09-25.

## Immediate distribution target

The first release target is a **re-signable sideload IPA**, not TestFlight. The repository will produce and inspect an unsigned IPA payload that a compatible signing workflow can re-sign with the user's own provisioning identity. The unsigned artifact is not directly installable and must never be described as a finished signed release.

This changes release sequencing, not product quality: the first signed sideload build still needs physical-device, authenticated disposable-account, accessibility, performance, crash, privacy, and request-safety checks. TestFlight and App Store Connect remain a later distribution path and should stay compatible where that does not complicate the sideload workflow.

## Completed release foundation

| Requirement | Current evidence |
| --- | --- |
| App identity | `AppIcon.appiconset` contains one opaque 1024×1024 universal iOS source. Xcode 27 generates phone and iPad renditions, and `project.yml` owns the `AppIcon` build setting. |
| Device archive | An unsigned generic-iOS Release archive succeeds for arm64. Its app bundle contains `Assets.car`, opaque 120×120 and 152×152 icon files, and `CFBundleIconName = AppIcon`. |
| Privacy manifest | `PrivacyInfo.xcprivacy` is copied byte-for-byte to the app-bundle root. It declares no tracking, the app-local UserDefaults reason `CA92.1`, and conservative core-functionality data categories. |
| iPad resizing | iPad declares portrait, upside-down portrait, and both landscape orientations. The earlier archive warning is gone; `UIRequiresFullScreen` is not used. |
| Simulator layout and accessibility regression | Nine guarded XCUITests exercise iPad portrait, device rotation/landscape survival, RTL History controls, RTL Feed, RTL Profile playlists, expanded pseudo-localization, private-playlist export, Home metric semantics, and Recording feedback state. The two semantic fixtures run native hit-region, description, trait, and element-detection audits, and directional navigation uses semantic SF Symbols. |
| Request diagnostics | The process-wide ListenBrainz gate exposes a Release-enabled in-memory snapshot containing only fixed feature categories, lifecycle counters, and current/maximum transport counts. Guarded visual fixtures fail before any request-gated transport can start. |
| Physical-device preflight | A paired current iPhone is reachable and has Developer Mode enabled. The Mac has no configured Xcode developer account, development team, or Apple Development signing identity, so no app was built for or installed on the phone. The intended first device run uses the isolated QA bundle, local fixtures, and fail-fast request guard. |
| Launch screen | Xcode's generated launch-screen dictionary is present in the archived `Info.plist`. |
| Public policy | Root `PRIVACY.md` explains local storage, direct service traffic, tracking, MetaBrainz logging, and user controls in plain language. |
| In-app user controls | Profile opens a request-free native Settings surface with the same privacy policy, canonical ListenBrainz data controls, local appearance, and a confirmed disconnect action that removes the saved credential and listening snapshot without overstating residual safety-record cleanup. |
| Confidential reports | GitHub private vulnerability reporting is enabled for the public repository, and the policy links directly to a new private advisory. |

Apple permits iOS and iPadOS to generate icon variants from one 1024×1024 image and requires the App Store image in the 1024-point slot. Apple also requires every used Required Reason API category to be present in a bundled privacy manifest; `CA92.1` is the accepted reason for app-only UserDefaults. Current iPad guidance favors all orientations and resizable layouts rather than the deprecated `UIRequiresFullScreen` compatibility mode.

Sources: [app icon configuration](https://developer.apple.com/documentation/xcode/configuring-your-app-icon), [privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files), [Required Reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api), [approved UserDefaults reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons), and [iPad full-screen migration](https://developer.apple.com/documentation/technotes/tn3192-migrating-your-app-from-the-deprecated-uirequiresfullscreen-key).

## Manifest rationale

The app and vendored ListenBrainzKit contain no analytics, advertising, tracking, or crash-reporting SDK. Source inspection found no IDFA, AppTrackingTransparency, system-uptime, disk-space, active-keyboard, or file-timestamp Required Reason API. App-owned UserDefaults and `@AppStorage` hold only session mode, local preferences, and mutation-recovery state, so `NSPrivacyAccessedAPICategoryUserDefaults` with `CA92.1` is the sole accessed-API declaration.

The collected-data entries intentionally err toward disclosure:

- **User ID**, linked: a ListenBrainz username identifies the account used for requests and selects personalized results.
- **Product interaction**, linked: music-listening data and account actions can be stored by ListenBrainz and used for personalized recommendations.
- **Other user content**, linked: playlist titles/annotations and recommendation, pin, or thanks text can be submitted.
- **Search history**, linked: signed-in ListenBrainz user and playlist searches include the account token. MusicBrainz artist, album, and track searches do not include that token, but the manifest uses the more conservative linked classification for the category as a whole.
- **Other diagnostic data**, linked: MetaBrainz retains IP address, user agent, endpoint, and request parameters in access logs for seven days and publishes aggregate traffic statistics. The declaration conservatively covers app functionality and analytics.

None of these categories is used for tracking. User ID and Product Interaction additionally declare Product Personalization; Other Diagnostic Data additionally declares Analytics. App Store Connect answers must match this manifest and the public policy. MetaBrainz documents request-parameter and IP logging in its [privacy policy](https://metabrainz.org/privacy); ListenBrainz describes the public treatment of listening data in its [terms](https://listenbrainz.org/terms-of-service/).

## Icon provenance

The icon is original project artwork generated with OpenAI's built-in image-generation tool, then resized to 1024×1024 and flattened to opaque RGB with the pre-existing `ffmpeg` installation. No donor asset or official ListenBrainz mark was copied. The production prompt was:

> Create a distinctive, premium icon for Brainz, a native iOS app for exploring personal ListenBrainz listening history, taste, discovery, and social music data. Use one bold abstract mark combining a flowing audio waveform with musical history or layered listening paths; use the app's deep aubergine, coral-orange, and restrained teal palette; keep it legible at 29 points; include no text, letters, musical-note glyph, headphones, brain illustration, vinyl cliché, official service marks, rounded-corner mask, or watermark.

The single source deliberately omits hand-authored dark and tinted variants. Apple documents that the system can generate those treatments; the installed icon was visually accepted in both light and dark Home Screen appearances.

## Still required before the sideload release

- create a deterministic unsigned IPA containing only `Payload/Brainz.app`, validate its bundle metadata, arm64 executable, resources, privacy manifest, and unsigned state, then verify that the same archive packages identically;
- re-sign that payload with an appropriate provisioning identity and keep certificates, profiles, and signing logs out of source control;
- install the signed IPA on a physical iPhone and run authenticated disposable-account QA without real user data or replaying mutations;
- repeat rotation, Stage Manager/resizable-window, RTL, and VoiceOver checks on physical iPad hardware where available, and test actual translations once they exist; and
- complete final accessibility, performance, crash, direct-network-bypass, request-volume, and regression passes on the signed candidate.

## Later App Store distribution work

- configure the final Apple Developer team, bundle identifier, version/build sequence, and distribution identity;
- make a signed archive, inspect Apple's generated privacy report, and complete TestFlight processing;
- enter App Store metadata, screenshots, review notes, support and privacy URLs, age rating, and category; and
- reconcile the App Store privacy questionnaire with the shipped binary and observed service behavior.

The source-level release foundation and guarded simulator pass are complete; this does not yet claim an installable sideload IPA, TestFlight readiness, or App Store readiness.
