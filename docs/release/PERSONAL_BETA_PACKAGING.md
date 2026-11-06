# Personal Beta packaging and release identity

This supplements the historical examples in [RELEASE_ENGINEERING.md](../RELEASE_ENGINEERING.md). It introduces local review containers, not a new source-admission gate or permission to publish. Existing signed/notary/staple states and the ordinary attachment implementation are unchanged.

## Assign a version once

Every new `build` invocation supplies **version, build, and display label**. The source values and final values are stored in the signed-content preparation receipt. This prevents a new `0.3.0 (3)` package from retaining an old “Beta 2” label. Source `Resources/Info.plist` is never edited by the tool.

- `CFBundleShortVersionString`: three numeric components, such as `0.3.0`.
- `CFBundleVersion`: positive integer, globally increasing when distributing a changed product build. A source/documentation/container-only rebuild does not independently allocate another product build number.
- `RiftletVersionLabel`: an explicit display label, such as `Beta 3`; it is never inferred from old source metadata.
- Identical version/build labels do **not** prove identical artifacts. Source commit/tree/input objects, preparation tool hashes, actual Mach-O architecture, complete package inventory, manifest SHA-256 and container SHA-256 remain the precise identity.

The historical personal Beta 3 uses runtime source `2e779f646ac4874344fac94f79103e8ddf9b02c8` and explicit `0.3.0 / 3 / Beta 3` staging metadata. Its original package and private delivery receipts remain immutable. A later receipt must not relabel that package as newly built or newly tested.

## Build in a fresh private directory

```sh
python3 -B scripts/release-tool.py build \
  --source '<reviewed-full-40-character-source-commit>' \
  --version '0.3.0' --build '3' --label 'Beta 3' \
  --arch arm64 --workspace '/absolute/new/private/release-workspace'
```

Add `--arch x86_64` only when intentionally building a universal candidate. The receipt reads actual Mach-O slices; it does not infer Intel execution from an Apple Silicon build. The build runs the ordinary early-exit build-information probe, not the normal App. It does not install, start screenshot collection, read production data or run XCTest.

The source commit is exported independently of dirty worktree bytes. New receipts include `sourceVersion` and `versionLabel`; an old source with no display-label key records `null` for its source label and still uses the explicit new label. Old schema-1 receipts remain readable without being rewritten. The preparation tool itself is separately pinned because it may differ from the product source commit. Historical commands without `--label` now fail during argument parsing instead of inheriting a misleading label.

## Produce a local ZIP and DMG

Read and retain the PREPARED manifest SHA-256, then pass that independently recorded pin:

```sh
shasum -a 256 '/absolute/new/private/release-workspace/Riftlet-Release/release-manifest.json'

python3 -B scripts/release-tool.py package-review \
  --workspace '/absolute/new/private/release-workspace' \
  --manifest-sha256 '<recorded-64-character-manifest-sha256>'
```

This accepts only the tool's own `PREPARED` format. It does not import arbitrary private delivery manifests or convert failed signing/notarization attempts into clean review packages. The outcome is permanently `REVIEW_ONLY`, `NOT_NOTARIZED`, and `gatekeeper=NOT_RUN`. The file names include `REVIEW-NOT-NOTARIZED`.

The new `review-distribution/` contains ZIP, DMG and `review-artifacts.json`. It is created once; a failed or successful attempt is never overwritten. Logs and partial files remain available on failure. The tool:

1. Checks the exact pin and complete candidate inventory.
2. Creates a resource-preserving ZIP and verifies its contained files, modes, receipt and architecture without executing them. It also matches the embedded raw manifest SHA-256 to the intended candidate pin; another internally valid candidate archive cannot be substituted. The formal `package` path applies the same binding.
3. Copies the same payload into a new image source and adds a clear review-only note.
4. Creates an HFS+ UDZO image, verifies its image checksum, and mounts it read-only at a new owned path with `-nobrowse -noautoopen`.
5. Rechecks the mounted manifest, every payload file/mode/stable extended attribute, and review note. It then normally detaches only that owned mount.
6. Rechecks the untouched original candidate before writing a successful artifact receipt.

No Finder window, application, installer, administrator process or network request is opened. An attach, content, or detach failure prevents a successful receipt; there is no force-eject or automatic retry. Neither ZIP nor DMG verification establishes Developer ID, notarization, Gatekeeper, clean-machine launch, data compatibility or public-release approval.

This is a reproducible **procedure with pinned inputs and verified contents**. Swift builds, ZIP transport metadata and HFS+/UDIF containers are not promised to be bit-for-bit reproducible. Each actual output gets its own hash. Repeating only a container operation does not become a new application acceptance result.

## The public-release route remains separate

The existing `sign → notary-submit → notary-status → staple → package` route is unchanged; `package` still requires a valid `STAPLED` candidate and matching Developer ID signature. `package-review` cannot grant that state, and its output is not accepted as an update by `update-plan`.

Apple's current external-distribution workflow requires the appropriate Developer ID identity, hardened runtime, a secure timestamp, valid entitlements, and notarization. An ad-hoc signature is not a substitute. See [Developer ID](https://developer.apple.com/developer-id/) and [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

The local credential inspection for this increment found **zero valid code-signing identities**, with `notarytool` and `stapler` installed. Therefore the current external-distribution status is `PUBLIC_BETA_BLOCKED_OWNER_CREDENTIALS`. No profile secrets were read, no credential storage or account settings were changed, and no upload was attempted. Notary-profile availability was not inferred from the absence of a signing identity.

See [manual update and recovery](MANUAL_UPDATE_AND_RECOVERY.md) before replacing any installed App. This package procedure alone authorizes no installation, downgrade or data restoration.
