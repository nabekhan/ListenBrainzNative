# Sideload readiness

Snapshot: 2026-10-01.

## Distribution contract

The immediate release target is a re-signable IPA for sideloading. `scripts/package-ipa.sh` builds a fresh unsigned arm64 Release archive and packages exactly:

```text
Payload/
└── Brainz.app/
```

The output is deliberately unsigned. It is not directly installable and is not a substitute for a signed release candidate. A compatible signing workflow must supply the provisioning profile, entitlements, and final signature.

## Build and validation

Run from the repository root:

```sh
scripts/package-ipa.sh
```

The default ignored output is `dist/Brainz-<version>-<build>-unsigned.ipa`. An explicit new output path may be supplied as the sole argument. The script refuses to overwrite any existing path and rejects a group- or world-writable output directory unless sticky-bit protection prevents other users from replacing its entries.

Use the default `dist/` location or another directory you own and trust. The mode check does not make a custom path beneath attacker-controlled ancestors, ownership, or ACLs safe.

Before publishing the artifact, the script verifies:

- a generic iOS Release archive succeeds with signing disabled;
- the app bundle reports a nonempty bundle identifier, version, build, and `Brainz` executable;
- the device executable contains arm64 and no simulator architecture;
- `Assets.car`, the 120×120 iPhone icon, the 152×152 iPad icon, the `AppIcon` declarations, and the generated launch-screen declaration are present;
- `PrivacyInfo.xcprivacy` is valid and byte-identical to the reviewed source manifest;
- no provisioning profile or `_CodeSignature` directory is embedded;
- the app contains no symbolic links, and `codesign` reports that the app bundle and every nested Mach-O object are unsigned;
- every ZIP entry is inside `Payload/Brainz.app`, core files are present, and the archive passes an integrity check; and
- packaging the same archive twice produces identical bytes.

The terminal prints the artifact path, identity, version/build, architecture, byte size, and SHA-256 digest. It does not print signing identities or credentials.

## Signing boundary

Signing is intentionally outside this repository workflow. Do not commit certificates, private keys, provisioning profiles, signed IPAs, account session material, or verbose signing logs. A signer must use a profile compatible with `dev.nabekhan.listenbrainznative`, or consistently rewrite the identifier and any identifier-bound metadata.

The app's Keychain service is currently `dev.nabekhan.listenbrainznative`. Re-signing under a different application identifier or access group may make credentials stored by an earlier build unavailable; authenticate again after installing the newly signed app instead of assuming Keychain continuity.

SideStore- or AltStore-style tooling may be used as the external signer, but compatibility must be proven with the exact signed artifact and device. Repository validation stops at the unsigned payload boundary.

## Release evidence still required

- re-sign the validated IPA without adding unexpected entitlements or changing reviewed resources;
- inspect the signed app's identifiers, entitlements, profile, signature, privacy manifest, and executable architecture;
- install it on a physical iPhone and confirm clean launch, authentication, Keychain persistence, app icon, and network behavior;
- run authenticated disposable-account and request-volume checks without real user data or replaying mutations; and
- complete physical accessibility, performance, crash, offline, and regression passes.

TestFlight and App Store Connect remain a later distribution path. This workflow avoids depending on them without deliberately making the source incompatible with them.

## Validated checkpoint

The prior 2026-09-28 run packaged clean product checkpoint `c6fdc27` as `Brainz-0.1.0-3-c6fdc27-unsigned.ipa`. It was 7,514,682 bytes with SHA-256 `076eca4ee222fc46230142b64afba8153ddedf38fada5330c84df212f8fd6d7a`. Independent extraction found 12 unique entries beneath `Payload/`, one expected unencrypted unsigned arm64 iOS executable, bundle `dev.nabekhan.listenbrainznative`, version `0.1.0 (3)`, minimum iOS 18, both iPhone and iPad device families, only Apple system dependencies, and a privacy manifest byte-identical to source with SHA-256 `bd70e057eabd5df561467219da1f29a96230ddaa858965aa0db44e79a1c89428`. It found no unsafe ZIP path, duplicate, symlink, profile, entitlement, code-signature command or directory, nested code, unexpected executable, encryption, packaged test product, key, or credential file. Build 3 binds the payload to the accessibility-size Home fix and tracked guarded-matrix checkpoint; runtime XCResults remain the authoritative evidence for that behavior. Independent security review reports SHIP for this unsigned re-signing boundary. The reproducible IPA was removed after recording evidence; external signing and signed physical-device checks remain required.

The latest 2026-09-29 run packaged clean documentation checkpoint `c419b88`, including product commit `e0b684f`, as `Brainz-0.1.0-3-c419b88-unsigned.ipa`. It was 8,170,266 bytes with SHA-256 `53357b7c890c5a0886ce811bed0f2af9c1e0c96e183fa6ef913764cb0ce14c83`. Independent inspection found 16 safe entries beneath `Payload/Brainz.app`, one unencrypted unsigned arm64 executable, bundle `dev.nabekhan.listenbrainznative`, version `0.1.0 (3)`, minimum iOS 18, both device families, only Apple/system dynamic dependencies, and source-identical privacy and third-party-notice files. It found no unsafe or duplicate path, symlink, profile, signature or entitlement residue, nested/unexpected executable, encryption, test product, private key, credential-like file, source/build path, or DEBUG fixture route. Independent review reports SHIP for the unsigned re-signing boundary. The IPA was removed after evidence was recorded; external signing and signed physical-device checks remain required.

The 2026-10-01 viewer/explorer checkpoint `5bb86dd`, containing product commit `7e8977b`, packages reproducibly as `Brainz-0.1.0-3-5bb86dd-unsigned.ipa`. It is 8,404,229 bytes with SHA-256 `91211c17bb001ab9a7cd8b6fe4e180a1c94db2954a00dcf9ad83ede1062da03d`. Local extraction finds 16 unique safe entries beneath `Payload/Brainz.app`, one unencrypted unsigned arm64 executable, bundle `dev.nabekhan.listenbrainznative`, version `0.1.0 (3)`, minimum iOS 18, device families 1 and 2, only Apple/system dynamic dependencies, and source-identical privacy and third-party-notice files. It finds no unsafe or duplicate path, symlink, profile, signature command or directory, nested/unexpected executable, packaged test product, DEBUG fixture/live-route marker, or absolute workspace path. External signing and signed physical-device checks remain required.

## Cleanup

Derived Data, archive, and staging data live under one unique temporary directory and are removed automatically. Generated IPAs live under ignored `dist/` by default. Remove only the exact generated IPA when its evidence is recorded; never delete certificates, profiles, unrelated archives, or unrelated Trash contents as part of this workflow.
