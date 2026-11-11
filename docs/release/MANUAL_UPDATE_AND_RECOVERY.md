# Manual update and recovery audit

Riftlet currently uses an explicitly reviewed App-only replacement, not an automatic updater. This document records the working safety boundary from the personal Beta 3 upgrade and complements [RELEASE_ENGINEERING.md](../RELEASE_ENGINEERING.md). The queue format transition and recovery steps are described below.

## Before replacing an App

Confirm the exact reviewed source/merge and completed required CI; verify the actual candidate's full inventory, binary architecture, bundle ID, version/build/label and hash. For an external release, also verify the Developer ID team and notarized/stapled artifact. A release manifest inside an unknown download cannot authenticate that same download without an independently trusted pin.

**Check whether macOS can recognize the previous code identity before planning an unattended personal update.** From a Mac with Swift, run the read-only [update identity check](../../scripts/check-update-identity.swift) against the exact currently installed App and the candidate:

```sh
swift scripts/check-update-identity.swift --installed "/path/to/current/Riftlet.app" --candidate "/path/to/candidate/Riftlet.app"
```

The tool verifies both bundles and tests the candidate against the installed App’s designated code requirement. Exit 0 means that requirement matched; it does **not** mean macOS grants the candidate any permission. Exit 2 identifies two different update identities or bundle identifiers. Exit 1 means the inputs or their signatures could not be verified. The check never opens the Apps or reads or edits privacy grants.

If the current App relies on a protected screenshot folder such as Downloads and the check reports a mismatch, keep the working installation in place for an unattended update. Test the intended distribution identity and its normal permission flow in an authorized independent environment. A personal build may require explicit user consent again. Do not assume that two ad-hoc bundles sharing a bundle ID share the same grants; do not work around a missing grant by changing macOS security settings or launching from a privileged host. Even with a match, check source access on the normally launched installed App and preserve a verified rollback. [Apple DTS: file system permissions and code identity](https://developer.apple.com/forums/thread/678819).

Normally quit every Riftlet instance and verify both process absence and ownership of the **existing** queue and Feedback locks. Do not delete or replace lock files. Backup verification is performed on private copies, and the live snapshot must be rechecked after acquiring both locks. An old backup is not sufficient if current data changed in between.

Retain these domains together:

| Domain | Preservation and comparison |
| --- | --- |
| Current App and rollback ZIP | All regular files, directory/file modes, binary hash, actual architecture and signature; keep the exact retained old App after atomic exchange |
| Queue SQLite and sidecars | Main DB and any WAL/SHM files from the same quiescent snapshot; schema, complete typed rows, media references, operations, actual `upload_starts`, historical UNKNOWN and locks |
| Media and journal | Every referenced media file and journal entry; hashes and relative mappings, including originals and orphan evidence retained by current policy |
| Feedback | DB, WAL/SHM, pending outbox, drafts, tombstones and associated files; no replay, delete or delivery during update verification |
| Configuration and diagnostics | Every existing configuration domain, presence/absence, accepted/pending state and diagnostics files; a newly defaulted setting must not erase unrelated old keys |
| UserDefaults and filesystem metadata | Export the specific application preference domain, retain typed values and compare before/after; capture ACL, modes, flags and extended attributes separately rather than assuming file hashes cover them |
| Keychain and system permissions | Preserve identity; do not export secret values, reset TCC, clear quarantine or change login/account settings to make a package appear usable |

The recorded Beta 3 comparison preserved all database typed rows/schema, old UNKNOWN rows, media, journals and old preferences. It also retained the original nonzero comparison result: Feedback SQLite header counters and the queue WAL-index sidecar changed physically, while database payload/rows and media remained equal. A logical-equality result must not be described as “every byte unchanged.” A sidecar difference requires diagnosis; it is not automatically corruption or permission to overwrite the current data.

## Replace only the App, while ownership is held

The prior private installer copies the verified candidate into same-filesystem staging, verifies the copy, and uses `renamex_np(..., RENAME_SWAP)` while holding both locks. It verifies installed and retained App inventories, signature, unchanged data, and the original lock inode identities. It never starts the App itself.

The successful receipt is published only after validation, pending-receipt persistence and lock release. The previously found release-boundary error remains documented: after any lock release has begun, a receipt/publication failure **must not automatically swap App paths again**, because another process may already have acquired ownership.

| Failure boundary | Required behavior |
| --- | --- |
| Before exchange | Preserve current App/data and failed attempt; do not launch candidate |
| After exchange, both locks still held | App-only automatic restoration may exchange the retained original back; preserve the triggering error and any restoration error |
| Any unlock/close has started | Leave the verified candidate and retained previous App in place; record `STOPPED` and `FRESH_LOCKS_AND_APP_IDENTITY_RECHECK`. No unlocked second exchange |
| A previous rollback itself failed | Keep both paths and all evidence. Reinspect identities and obtain fresh ownership before any recovery; do not claim restored |

Seven isolated fault fixtures already cover success, post-exchange validation, partial pending-receipt write, real-unlock failure, real-close failure, final receipt publication failure and rollback failure. They are tests of the installer algorithm, not evidence of public Developer ID updates or current live production state. The current audit reused those original records and did not repeat an installation.

## Restart and rollback

After a verified successful receipt, start only one exact installed executable. Confirm version/architecture, normal startup, history/settings persistence and source access without replaying external uploads. Keep the previous App and a fresh verified data snapshot until the new version has adequate normal-use evidence.

Before a later rollback: normally quit, preserve a **new current-data backup**, verify the old App's exact retained identity and confirm it can read the current schema and state semantics. Replace only the App under fresh ownership. Do not restore the pre-upgrade database over newer history merely to make old software run. A schema number alone is not proof of compatibility. If compatibility is not established, retain both versions and use a forward fix.

The volume-aware App upgrades its ordinary screenshot queue to v4 on first open, before collection starts. Beta 3 supports queue versions through v3. Its queue initializer rejects v4 before opening the collector or recovering imports. Keep Beta 3 closed on current data. Its independent Feedback service and first-use preferences can start before its queue check.

If the update fails before the new App first opens the queue, the retained old App can still use its proven v3 data. After migration, quit the old process, retain both Apps and a consistent copy of the **latest** data, then open the same data with the verified v4-capable App or a compatible repair. Keep the pre-upgrade backup as separate historical data. Replacing only the database file or lowering its version discards this protection and can separate the queue from media, WAL and import journals. Earlier private previews that stored volume identities in v3 must first be opened by the fixed App; Beta 3 can duplicate captures if opened on those unprotected previews.

Uninstalling the executable is separate from erasing personal history. Move the stopped App to Trash only when requested; keep its data, original screenshots and rollback backup. No uninstall or recovery step here authorizes deletion of media, UNKNOWN, Feedback state, Keychain items or system permissions.

The archived Beta 3 packages used ad-hoc signing. The later 0.3.5 (16) → (18) upgrade used Developer ID Application with Team ID `ZB9D4T66QB`. Both the build 18 app and its universal DMG were notarized and stapled. The installed-Mac receipt covers that machine’s app-only exchange, fresh-data-preserving rollback, return to build 18, and screenshot collection. A move from ad-hoc to Developer ID on another account still requires its own check of folder access and Automation. The [installation guide](../consumer/INSTALL-AND-PERMISSIONS.md) identifies the current DMG.
