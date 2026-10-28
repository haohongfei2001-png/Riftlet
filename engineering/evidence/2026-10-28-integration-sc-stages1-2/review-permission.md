# Independent review: permission wake, original click authority and admission

Reviewer: `/root/review_permission`, a separate AI reviewer who did not author the source or integration changes. This is an engineering review, not a human GitHub approval or real-Mac acceptance.

Reviewed checkpoint: `f2ae645451044649fbe73326952efbe084353869`.
Reviewed tree: `33494e55f3e067782fa2b5f97d61450776f88286`.
Comparison base: `4b7228a07a23381d3de467a44dd8490d73e26e7e`.
Stage-one permission fix: `a5db972b7c4da20d30266ec8d1411fff9f434c13`.

## Result

No blocking defect found in the reviewed permission-wake integration or its surrounding original-click authorization paths. The fix repairs delivery of an already-required target-observation wake; it does not authorize an old selection, reuse a revoked ACK, fabricate upload-start evidence, or enable candidate/production admission.

## Evidence and reasoning

1. **Revocation precedes the new wake.** `Sources/RiftletApp/RiftletMain.swift:717–731` cancels selections, clears `armedTarget`, `armedCaptureDiagnostics` and `frozenPress`, requests an epoch-invalidating arm, copies the scheduler epoch into `armSession`, and only then consumes the returned wake. `cancelSelections` at lines 708–714 synchronously revokes `SelectionAuthority` and queued submissions before posting the asynchronous Coordinator cancellation. A later fresh capture cannot make the revoked token valid again.

2. **One current-epoch capture owns the slot.** `Sources/RiftletCore/TargetArmScheduler.swift:40–63` permits `begin()` only with running/pending/no-in-flight state. Completion must match the exact in-flight attempt. An invalidated attempt may drain but `acceptsAcknowledgement` is false; a duplicate old completion cannot release a replacement attempt. The newly consumed idle wake cannot create parallel capture work.

3. **The new arm rechecks actual permission and process identity.** `RiftletMain.swift:845–900` begins a fresh arm attempt, obtains a passive permission result bound to the original foreground Chrome process, rechecks foreground process and epoch before capture, then requires matching completion/epoch and the current process before publication. `Sources/RiftletApp/AutomationPermission.swift:96–99` uses `askUserIfNeeded: false`; this path does not request OS authorization. `NativeAutomationPermissionChecker` also checks PID/launch identity before and after the OS call. The earlier armed target was cleared, so a recovered target gets a fresh MainActor publication time rather than an old effective ACK.

4. **Late ACK cannot fill in an old event.** `RiftletMain.swift:774–791` freezes the existing armed target at the original press. `Sources/RiftletCore/ArmedTarget.swift:14–20` retains strict `acknowledgedUptime < eventUptime <= nowUptime`, exact host epoch and foreground process. App selection construction at `RiftletMain.swift:258–296` uses that frozen value. If it was absent, the no-capture Coordinator entry can only observe an already-existing unresolved operation; it does not await a new ACK and retry the refused input. The stage-two diagnostic `foregroundSessionMatches` change at line 968 reports `false` when there is no armed target and is not consulted as authority.

5. **The original accepted selection remains immutable and revocable.** `SelectionAuthority.permits` checks object identity, validity, host epoch, exact process, hidden state and termination. `validateAcceptedSelection` at `RiftletMain.swift:734–757` checks those predicates both before and after a fresh passive permission await. `AcceptedSelection` retains strict original-event timing and a maximum 30-second lifetime. `TransferCoordinator` revalidates before preparation/intent; `QueueStore.markDispatchIntent` calls the token's locked `authorizeDispatch` inside the SQLite transaction and verifies original asset/target/revision. The added arm wake does not bypass any of these gates.

6. **Recovery remains observation only.** `TransferCoordinator.swift:247–274,370–399` recovers/observes original operation IDs through `reconcile`, while `append` remains on the prepared → dispatch-intent path with its original selection. Permission recovery contains no new call to append/select/retry and does not reconstruct a token. UNKNOWN and compensation are not reset or granted retry.

7. **Admission is still closed and existing foundation preserved.** `Sources/RiftletApp/SystemScreenshotCandidateConfiguration.swift:10–14` still has empty upload-start, completed-attachment and safe-failure maps. Ordinary capture still constructs `UnavailableAdapter` and an empty receipt policy at line 36. A Git diff against the official base confirms no changes to `Sources/RiftletCore`, `Sources/RiftletCapture`, `Sources/RiftletUI`, `Package.swift`, `SelectionAuthority`, `PassivePermissionResume`, `AutomationPermission`, or candidate configuration. SQLite v3, Core state/receipt rules, capture fidelity, UI lifecycle and their existing tests are inherited unchanged. No feedback-branch code is part of this source delta.

## Regression coverage and limits

The three new `TargetArmPermissionWakeTests` reproduce the lost idle wake, show that consuming it restores later demand, and reject an old in-flight ACK/duplicate completion after invalidation. They explicitly test the scheduler contract, not live AppKit wiring. I also inspected the existing eight scheduler tests, the strict ArmedTarget test, four SelectionAuthority tests, eight PassivePermissionResume tests, AcceptedSelectionQueue tests for cancellation/permission/process/UNKNOWN/restart, and candidate integration tests for closed admission and no replay.

This review session performed static source and Git-object inspection only. There is no Swift compiler or macOS GUI in this reviewer environment; I did not independently execute native tests or claim a new TCC/browser/physical-input acceptance. The integration lead must bind the final checkpoint to the complete macOS CI result. Actual first-stage Mac evidence remains scoped to its original source and environment.

SC-INPUT and SC-START may retain their recorded limited PASS only. SC-COMPLETE remains old-source FAIL with the exact-color fix not yet exercised by a new real system-screenshot input. Candidate start/completion/safe-failure and ordinary production admission remain closed.
