# Sideload readiness

Snapshot: 2026-09-26.

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

The current 2026-09-26 run packaged clean checkpoint `f81d1b6`, including the bounded CritiqueBrainz review reader, as `Brainz-0.1.0-1-f81d1b6-unsigned.ipa`. It was 7,108,377 bytes with SHA-256 `208866dbb1f5b9cdcea049b3e91fdbf8495c108dd308cf6c44fb869ea8a33b7b`. Independent extraction found exactly 12 unique entries under `Payload/Brainz.app`, one expected unsigned thin arm64 iOS executable, bundle `dev.nabekhan.listenbrainznative`, version `0.1.0 (1)`, minimum iOS 18, only Apple system dependencies, and a privacy manifest byte-identical to source. It found no traversal, duplicate or colliding ZIP entry, header mismatch, symlink, profile, entitlement blob, code-signature command or directory, nested code container, unexpected executable, encryption, or extra top-level path. The binary contains the new review-pagination types and **Load more reviews** copy, which binds it to the current product checkpoint rather than the older artifact. Separate structural and security reviews report SHIP for this unsigned/re-signable boundary. The reproducible IPA was removed after recording evidence; external signing and signed physical-device checks remain required.

## Cleanup

Derived Data, archive, and staging data live under one unique temporary directory and are removed automatically. Generated IPAs live under ignored `dist/` by default. Remove only the exact generated IPA when its evidence is recorded; never delete certificates, profiles, unrelated archives, or unrelated Trash contents as part of this workflow.
