# Release readiness — separate admission levels

This is an engineering preparation checkpoint, not permission to publish a download or invite participants. The exact installed personal build remains0.3.0(3), source2e779f6, ARM64 binaryfe5b09c…; the distinct 0.3.1(4) candidate adds the measured recovery fix and must pass the documented review, isolation and backup gates before replacement.

| Level | Current result | Remaining evidence |
|---|---|---|
| PERSONAL_BETA_3_ACCEPTED — this sprint's expanded criterion | NOT_ESTABLISHED_FOR_EXPANDED_SCOPE | Previous PR45 integration/upgrade acceptance remains valid; current-version real ChatGPT screenshots/attachments still require an available authorized browser surface. Ordinary current status-bar mouse paths remain partial. |
| CLOSED_BETA_READY | NOT_READY | Fresh-device installation/permission/core workflow; trustworthy distribution; unresolved exact scope of current status-icon GUI access. Local isolation, consumer guides and a plan are preparation rather than external user acceptance. |
| PUBLIC_BETA_READY | PUBLIC_BETA_BLOCKED_OWNER_CREDENTIALS | Developer ID, notarization/stapling, clean-device Gatekeeper/permissions, current live core evidence and reviewed external Beta boundary. No participants recruited. |

## Observed distribution facts

- Local code-signing search returned0 usable identities and0 Developer ID Application identities. `notarytool`/`stapler` tooling exists; no private key or credential value was read/exported.
- Same-repository remote inspection found0 repository Actions secrets,0 secrets in its only environment github-pages, and no configured Developer ID/notary route in the actual main workflows. No workflow or paid plan was changed. This does not claim that the owner lacks certificates on every other machine/account. See [cloud route](release/cloud-route-summary.json).
- Current installed App read-only `spctl --assess --type execute -vv` returned3/rejected; `stapler validate` returned65/no ticket. These expected personal ad-hoc results are **not** distribution passes; no security override was applied. See [actual trust check](release/current-personal-app-trust.json).
- Current Beta3 can be retained for the owner's existing personal use with full rollback. Its exact unchanged App was placed in a locally verified DMG, including read-only mount, file/mode identity and signature validation; this does not make it notarized.
- New release tooling builds explicit version/build/label PREPARED candidates and produces separately marked REVIEW-NOT-NOTARIZED ZIP/DMG. ZIP and DMG verify the externally pinned candidate manifest. The formal package path still requires the previously established Developer ID/STAPLED stages.

[Current packaging commands](../../docs/release/PERSONAL_BETA_PACKAGING.md) and [manual update/rollback](../../docs/release/MANUAL_UPDATE_AND_RECOVERY.md) are the authoritative new entry points. Older command examples remain historical. Automatic updates/dependencies were not added; manual update verification and a full App/data rollback remain the chosen next-release baseline.

## Work that does not need owner testing

Local package preparation, exact source review, formal CI, real native collector/storage tests, isolated ServiceManagement registration, consumer documentation and a low-burden10–20-person closed Beta protocol are independently executable. Each result remains scoped in [evidence](EVIDENCE.md). User product decisions are not replaced with repeated manual test assignments.

The remaining account-side prerequisite is an owner-authorized signing/notary environment. The browser prerequisite is an available authorized tool surface, after which Codex performs the remaining tests itself. The [bounded local tool inventory](release/clean-host-inventory.json) did not identify a configured clean macOS VM or a supplied clean device. A clean Mac/OS trust environment and physical compatibility are separate from both; no TCC reset, browser-policy bypass, public release or invitation was performed.
