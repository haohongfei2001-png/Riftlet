# Release preparation, 2026-11-07

This lane preserves the installed personal Beta 3 and the existing release state machine. It adds explicit staging labels and repeatable private ZIP/DMG preparation. It does not install, upload, publish, modify production data or declare the product ready for public distribution.

## Changes

- New `build` calls require version/build/display label. Both source values and final values are bound in the receipt. Historical source metadata without a display label is accurately recorded as `null`; old receipts remain verifiable.
- `package-review` accepts only a pinned `PREPARED` package and produces visibly marked local-review ZIP/DMG artifacts. It binds the ZIP's embedded manifest to the intended candidate pin, verifies the real mounted DMG contents, then detaches normally before recording success. The formal packager now checks the same ZIP-to-candidate binding.
- The formal `package` path still requires `STAPLED` and a verified Developer ID identity. Review packaging does not modify that state, permit a manual update, or clear a signing/notary failure.
- The prior safe App-only update/rollback algorithm was audited, including its irreversible lock-release boundary. No second installer or automatic updater was introduced.

Implementation and instructions: [release tool](../../../scripts/release-tool.py), [personal Beta packaging](../../../docs/release/PERSONAL_BETA_PACKAGING.md), [manual update and recovery](../../../docs/release/MANUAL_UPDATE_AND_RECOVERY.md).

## Actual evidence

| Check | Observed result |
| --- | --- |
| ReleaseReadiness | 54 passed, zero skipped/failed; 41 inherited and 13 targeted additions |
| Existing packaging suites | 17 + 17 passed, zero skipped/failed |
| New PREPARED build | Actual ARM64 release product build at `b9caabcb7fe02d9aae5521c3ada37fda9bd9143c`, 65.32 seconds; explicit `0.3.0 / 3 / Beta 3`; no normal App launch |
| New review ZIP/DMG | ZIP complete identity check; actual HFS+ UDZO create/verify, read-only `-nobrowse -noautoopen` mount, complete inner payload check, normal detach |
| Existing Beta 3 DMG | Container of the unchanged prior `fe5b09…` package; exact manifest and App file/mode checks plus strict ad-hoc signature verification; no new binary/build/installation claim |
| Credentials | Actual local `security find-identity -v -p codesigning`: zero valid identities; notarytool/stapler available; no secret export or account mutation |
| Formal signing/notary/Gatekeeper | Not performed; `PUBLIC_BETA_BLOCKED_OWNER_CREDENTIALS` |

[Validation](validation.json) binds all source/tool/log hashes and separates the actual build from the subsequent historical-label compatibility and ZIP identity checks. The existing real build is not relabeled as rebuilt by the later tool. The final tool produced and verified fresh ZIP/DMG containers from an exact copy of that unchanged PREPARED payload, then independently verified its manifest and archive pins. Complete local build logs are private because they contain local paths; their hashes are retained. The non-sensitive test logs are included here.

Independent review reproduced a real output-identity gap: the first implementation accepted a different internally valid ZIP while naming the original source in its result. [The original synthetic counterexample](zip-candidate-binding-before-fix.json) remains unmodified. Both packaging routes now reject this mismatch before writing a successful receipt. The new tests preserve the internal archive checks and add explicit wrong-candidate cases rather than replacing them with weaker expectations.

[Final review artifacts](prepared-review-artifacts-final.json), [earlier container run](prepared-review-artifacts.json), [historical Beta 3 DMG](historical-beta3-dmg.json), [credential inspection](credential-readiness.json), and [manual-update audit](manual-update-audit.json) retain their separate scopes. Both containers contain software that is **not Developer ID signed or notarized**. Reproducible means pinned inputs and verified contents, not a promise of byte-identical Swift binaries or UDIF containers.

Apple's current process distinguishes valid Developer ID signing from ad-hoc signing and requires appropriate hardened-runtime/timestamp protections for notarization. Read the official [Developer ID overview](https://developer.apple.com/developer-id/) and [notarization instructions](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution). Having local `notarytool` does not supply the missing identity or prove a valid account profile.

Independent review, integrated G/H source admission, and complete formal CI are owned by the integration lead. This author validation neither replaces those gates nor claims new Intel device, clean-install, production rollback, or real attachment acceptance.
