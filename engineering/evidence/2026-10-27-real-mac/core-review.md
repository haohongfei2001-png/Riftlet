# Core compensation and frozen-target review

Date: 2026-10-27, Asia/Shanghai. Reviewed source: `f58b22762d1dc42368a6e13fe2ef3a8e2d156106`.

This record distinguishes source review, standalone native execution, XCTest execution, and the lead's live acceptance observations. It does not admit production screenshot upload or successful consumption.

## Ownership and scope

The `late_failure` contributor inspected Core, proposed the compensation patch, authored the regression tests, and executed standalone native Core/SQLite smoke programs. The integration lead reviewed and applied the Core patch, implemented the completed-operation observer and frozen-target entry point, and owns App/adapter integration. The contributor subsequently reviewed those Core entry points independently of their author. The compensation proposal itself was contributor-authored; this document is not a claim of independent non-author review of every line in that proposal.

No contributor browser input, live screenshot collection, or ChatGPT upload was performed as part of this Core subtask. The live results below were executed and reported by the integration lead.

## Defect and resulting durable behavior

Previously, `QueueStore.apply` returned immediately for all terminal operations. A correctly identified error after successful consumption could therefore never restore the thumbnail. A prior regression test explicitly enforced that incorrect behavior; its assertion now applies only to uncorrelated late observations.

The existing state machine now includes unresolved `compensated`. A late error must match the active operation, asset, attempt, original hash, complete target lease, and the stored successful receipt's nonempty attachment identity and profile. It must belong to the original draft, carry an error, and not assert positive readiness. Neither navigation nor a generic UNKNOWN observation is enough.

The compensation transaction restores queue visibility as `unknown` while preserving the original asset, operation, attempt, capture order and sequence. A `compensations` row permanently retains the original success and the first correlated failure. Repeated errors are idempotent; old successful/candidate/UNKNOWN observations cannot swallow the restored image again. Restoration grants no new input or retry permission. Only separately admitted safe-retry evidence can release the operation.

A previously successful image can fail after a second image has begun uploading to the same draft. `compensated` therefore does not enter the single-in-flight target index, which would prevent restoration in that case. The dispatch guard explicitly includes compensated operations, preventing further dispatch on that draft. The original per-asset unresolved-operation constraint remains. Restart and observation errors preserve the compensation phase; missing local bytes remain `missing` until verified restoration.

Relevant sources:

- `Sources/RiftletCore/Models.swift`: compensation phase and immutable audit evidence.
- `Sources/RiftletCore/QueueStore.swift`: identity validation, atomic compensation, observation set and dispatch lock.
- `Sources/RiftletCore/SQLiteDatabase.swift`: schema migration.
- `Sources/RiftletCore/TransferCoordinator.swift`: observation-only recovery and completed-operation observation.

## Schema version 2

The migration reconstructs the operations table with the additional phase, copies existing rows, recreates the existing unique indexes, creates the compensation audit table, and advances `user_version` within one transaction. It preserves asset rows, receipt bytes, operation identities, attempts, timestamps and ordering. Unsupported future schema versions remain rejected.

Native standalone execution exercised the actual version-1 schema and stored success data, not merely a changed version number. A deliberately conflicting object forced a failure at the final migration CREATE after the operations-table replacement; SQLite restored the old schema, original rows, existing object and version 1. After removing the fixture conflict, migration succeeded. A separate forced asset-write failure during compensation rolled back the audit insertion, operation transition and queue update together; the original successful receipt survived, and the subsequent fault-free compensation succeeded.

## Completed-operation observation and click-time target

`successfulOperations(limit:)` returns only still-active successful operations, newest first, with a maximum of 64. `observeCompleted(operationID:)` calls only the original adapter's `reconcile`, then applies the result. Transport exceptions do not relabel success as UNKNOWN. Its return value stops the runtime success watch when the original draft is lost or the operation is no longer successful. App scheduling and Web observation admission are lead-owned integration work, not proven solely by this Core review.

The new `select(_:frozenTarget:)` overload preserves the supplied target without calling `captureTarget`. A missing target rejects a pending image before operation creation or input. Rejected selection tickets do not stall later valid clicks. UNKNOWN and compensated selections continue observing their original operation even when the caller supplies nil or a different target. The original `select(_:)` behavior remains available for other adapters. This Core property does not by itself prove that the App captured the correct physical browser tab at mouse-down.

## Regression coverage and executed checks

`Tests/RiftletCoreTests/LateFailureCompensationTests.swift` adds 14 XCTest cases covering:

- Original queue position, both durable receipts, duplicate failure and stale-success veto.
- Wrong attachment/profile/draft rejection and absence of error evidence.
- Coexistence with a newer in-flight image, draft locking, missing bytes and restart.
- Compensation transaction rollback, actual v1 migration and migration rollback.
- Completed-operation observation with zero new input, unrelated-image preservation, lost-draft and transport-error handling.
- Bounded restart watch selection, inactive-success exclusion and the 64-operation cap.
- Selection/recovery of compensated operations through observation only.

`Tests/RiftletCoreTests/TransferCoordinatorTests.swift` adds four frozen-target cases: exact frozen-lease dispatch without recapture; nil refusal without prepare/capture/validation plus subsequent ticket progress; UNKNOWN with nil/changed lease; compensated with nil. Existing tests for the legacy selection API are retained.

| Check performed by this contributor | Result | Scope |
| --- | --- | --- |
| Core native compilation | PASS | Current Core source compiled with the local Swift toolchain |
| Standalone compensation smoke | PASS | Real temporary SQLite, original ordering, both receipts, identity rejection, in-flight coexistence, locks, idempotence, restart and no new attempt |
| Standalone migration/fault smoke | PASS | Actual v1 schema/data, atomic v2 upgrade, migration rollback, compensation rollback and subsequent recovery |
| Standalone completed-observation smoke | PASS | Coordinator → fixture observer → SQLite; no capture/append, matching compensation and duplicate-watch termination |
| Standalone frozen-target smoke | PASS | Nil causes no operation; next valid frozen selection works; UNKNOWN nil selection observes the original operation with input count still one |
| Authored-test whitespace check | PASS | `git diff --check` |
| Local XCTest execution | NOT_RUN | Both Swift Build and native SwiftPM attempts stopped at missing `XCTest` in the installed Command Line Tools; no XCTest pass count is claimed |

The standalone smoke programs used temporary synthetic fixtures, actual Core code and actual SQLite. They are not substitutes for XCTest, browser acceptance or the complete product flow. Their execution occurred during this work session against the corresponding incremental Core changes; the reviewed final source includes those changes. No broader CI result was independently verified by this contributor for this record.

## Live integrated late-failure check — executed by integration lead

The following is the lead's reported real-Mac result at `f58b22762d1dc42368a6e13fe2ef3a8e2d156106`, received on 2026-10-27. It was not independently operated or observed in the contributor's Core subtask. Detailed environment, exact event times and broader live scope belong in the lead's acceptance record.

Generated-image operation `1C95A118-5B48-40E2-94E7-31FD4CE25A90` produced one input, received `verifiedReady`, and became `used`. The lead then inserted a test `role="alert"` element with `Upload failed` into that same attachment card. This was a controlled DOM failure injection, **not an observed network-upload failure**.

The running completed-operation watch restored the original queue position with asset status `unknown`, operation phase `compensated`, and exactly one compensation record. Clicking the restored image performed observation only; the page's input count remained one. After application restart, the operation remained compensated with attempt 1 and one compensation record. The injected test element was subsequently removed.

This supports the integrated reaction to an identity-associated late DOM error, including durable revival and no automatic re-upload. It does not establish behavior for real network failure after 100%, every ChatGPT error structure, lost page observers, arbitrary threads, or the production system-screenshot path. Production upload/consumption remains disabled.

## Follow-up finding: rearming must not bypass an unresolved Web tab lock

The lead identified a further integration defect after the source revision above: rearming the Web page creates a new draft-generation token. The former exact-lease dispatch lock could therefore admit a second input in the same browser tab while an older operation remained UNKNOWN or compensated. Receipt identity must remain exact, but dispatch serialization needs a more conservative scope.

The lead's follow-up Core change introduces a separate `TargetLease.serializationKey`. For `webChat` in `com.google.Chrome` with a nonempty tab identity, it uses adapter, application, browser session and tab identities, ignoring window, document, composer and generation. Other surfaces and unidentified tabs retain the original exact `stableKey`. `markDispatchIntent` compares all active unresolved operations except prepared operations inside its database transaction; successful/failed history does not lock the tab. Receipt matching itself still compares the complete original target.

**Conservative limitation:** navigating to a different thread in the same Chrome tab, refreshing, rearming, or moving that tab to another window does not release an unresolved upload lock. New input stays blocked until the original UNKNOWN/compensated operation is resolved. A different tab is independent. This prevents duplicate-side-effect ambiguity at the cost of refusing some otherwise safe new-thread inputs; it is not a claim to identify every ChatGPT draft reliably.

`Tests/RiftletCoreTests/WebTargetLockTests.swift` adds five targeted XCTest cases: UNKNOWN across rearm/window/document changes and restart; independent tabs/browser sessions; compensated rearm across restart; exact-lock fallback for other surfaces, non-Chrome browsers and missing/empty tab IDs; and exclusion of merely prepared operations from the lock. These tests use synthetic assets and local SQLite only. Test authoring and review do not constitute a live tab-switch acceptance pass; execution results belong to the subsequent verification record.

The contributor subsequently compiled the updated Core sources directly and executed a standalone native SQLite smoke for this lock change: **PASS** for same-tab rearm plus new document/composer and window move being blocked, a distinct tab being allowed, and the lock surviving database reopening. This is executed Core evidence, not an XCTest or real browser switch result.
