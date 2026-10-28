# Internal Beta — Feedback v0.1 non-author review

Reviewer: `/root/beta_feedback_review` (did not author or change the reviewed product code).

Date: 2026-10-28 (Asia/Shanghai).

## Result

**PASS for integrating the delivered Feedback v0.1 into the restricted internal candidate, subject to the final combined macOS CI and App packaging verification. No blocking source finding remains from this review.** This is not live Cloudflare/private Issues, physical GUI, Keychain permission, or latency acceptance.

The reviewed worktree was `/workspace/scratch/16d4559e9aa8/Riftlet-internal-beta`, based on evidence-only `c177174e400064d8ec8bb79685c33d01c4e93b89` (parent `e421e6687651c2fac1441410c1af2bd5b8151e55`) with `f195bebbc22ed1a162b5866ca1fe6c7ccb9835b9` merged without committing. The reviewer made no worktree, Git, index, branch, App, service, or endpoint changes.

At the review checkpoint, an exact `git diff --exit-code` confirmed the Feedback Core/UI/Demo, FeedbackHost, native/UI tests, service sources, and Package.swift matched the actual delivered feedback head. A separate exact comparison confirmed Core, Capture, RiftletUI, Adapters, Resources and their test trees matched official e421e668. The integration lead owns any subsequent launch/packaging changes and their final audit.

## Source review

### Storage and credentials

- `FeedbackHost` initializes a separate `Feedback-v01/feedback.sqlite` under the active mode directory, using a detached utility task. `FeedbackStore` is its own actor and SQLite connection, with a separate lock file, 200 ms busy timeout, FULL synchronous transactions, and schema version 1. It neither opens the screenshot queue nor receives its writer.
- The store creates private directories/files (0700/0600), rejects existing non-regular sidecars, and bounds pending/report storage without evicting human text. Enqueue atomically stores a frozen report, records the submitted revision, removes the credential intent, and creates the next empty draft.
- The shipping host always selects `KeychainFeedbackSecrets(namespace: modeDirectory)`. Random per-report capabilities are absent from SQLite and URLs. Read-only retry cannot replace missing credentials, and background reads/removals prohibit authentication prompts.
- Credential intents are bounded and precede Keychain creation. Cleanup checks the durable ledger before deleting any capability, preserves ambiguous/error cases, and skips credentials currently being created. Only cancelled or confirmed-deleted records can be locally forgotten; exact capability removal precedes body removal and failures preserve recoverable state.

### Privacy and explicit submission

- `FeedbackDiagnostics.record` accepts only closed `FeedbackFact` enums and bounded counts. Its ring contains at most 64 events and does not create tasks, perform I/O, or accept arbitrary error strings, image/operation/target identifiers, hashes, paths, chat content, browser state, or clipboard data.
- UI consent defaults off per new draft. Selecting diagnostics freezes the snapshot; preview and enqueue retain that same snapshot even when later events occur. Plain text feedback does not borrow available diagnostics.
- Saving, closing, reopening, and initialization do not authorize sending. Only explicit user submission produces a durable outbox record. Retries retain the exact frozen report ID, bytes, and capability.
- Local visibility, queue status, operation phase and visibility reason are separately projected. Swallowed does not become succeeded and UNKNOWN is not classified as failure.

### No endpoint and honest status

- `FeedbackHost.endpoint` is exactly `nil`; the host chooses `DisabledFeedbackTransport`.
- `FeedbackEngine.pump` may clean abandoned local credentials but returns before request enumeration/network dispatch when the transport is not configured. Newly submitted reports stay `queued` with zero attempts.
- The initial UI states that the receiver is not configured and no upload occurs. Subsequent status uses `已保存在本机，等待服务接收`; cloud receipt states require a validated durable, matching-ID receipt. A storage/Keychain failure retains the draft and never claims success.
- With the current disabled endpoint, cancellation of a never-attempted report remains local, then explicit forgetting can remove its own body and capability. Previously attempted records retain deletion intent instead of being falsely presented as unsent or deleted.

### Window and draft lifecycle

- Every normal close passes through `windowShouldClose`, locks editing, cancels pending autosave, advances the draft revision, and awaits persistence before programmatic close. There is no reusable bypass flag that could skip a later reopened-window save.
- Save failure leaves the window/text available. Composition (`hasMarkedText`) blocks close/submit. Return is not assigned to Send.
- Quit calls `saveBeforeClosing(lockOnSuccess: true)`, keeps editing disabled through the later host awaits, stops the engine, records the clean exit, then replies to AppKit. A failed save rejects quit and reopens the window.
- Older asynchronous saves cannot overwrite a newer revision. Enqueue/submit failures keep human text; successful enqueue atomically clears only the submitted draft and resets diagnostic consent.

### Screenshot integration isolation

- Relative to e421e668 the original Feedback Main patch adds imports, a lazy host, menu/open/quit wiring and typed observation calls. It does not replace the existing screenshot startup, permissions, authority, upload, Core, queue, or animation implementation.
- Event-boundary calls perform only bounded in-memory recording; no `await`, SQLite transaction, network request, target lookup, ACK generation, or new screenshot action is added to the click path.
- Existing refresh results are projected after `rift.render(snapshot)`; feedback does not fetch additional screenshot records or consume their ownership. Aggregate counting is synchronous and proportional to the existing snapshot/operation arrays. No actual latency improvement or zero-overhead claim is made.
- Opening the feedback window is an explicit user activation; it does not retain, restore, guess, or renew a Chrome target. Existing activity/ACK logic remains authoritative on returning to Chrome.

### Service source retained, not deployed

- Receiver/delivery configs retain disabled acceptance/delivery switches, no public workers.dev route, no live D1 identifier or production endpoint, and disabled logging. This review did not create resources, deploy Workers, set secrets, contact a receiver or submit Issues.
- Receiver validates strict body/diagnostic allowlists, size/age limits, capabilities, and SQL quotas; durable receipt follows the awaited transaction. A delete-before-submit capability-bound tombstone prevents a late POST from reviving content.
- Delivery validates private destination before sending, persists a one-attempt claim, and handles ambiguous POST outcomes by read-only marker reconciliation. It does not blindly repeat Issue creation.
- Deletion/retention preserve unresolved private-Issue deletion obligations and do not equate closing an Issue with deletion. This source review does not substitute for the deliberately unperformed live service acceptance.

## Checks actually run in this review

- Linux Node `v24.22.1`, `node --experimental-sqlite services/feedback/feedback.test.mjs`: **12/12 passed**, zero failures/skips. Actual SQLite with D1-shaped adapter and mocked HTTP, not cloud.
- `node --experimental-sqlite services/feedback/retention.test.mjs`: **6/6 passed**, zero failures/skips. These cover retention, local SQL, delete races and remote-obligation semantics.
- `python3 -B -m unittest discover -s Tests/FeedbackIsolation -v`: **4/4 passed**. Real temporary Git repositories exercise actual-parent handling, protected-blob mutations, feature-blob mutations and wrong refs; no product files changed.
- The first Node `--test` invocation emitted only two file-level pass summaries in this environment. Direct module runs above supplied the individual 12+6 case results; no 2+18 double counting.
- Read all 25 Feedback core test cases and all 7 software AppKit cases. Their meaningful regressions cover frozen/idempotent submission, SQLite rollback, capacity, credentials/cleanup, late receipts/deletion, close/reopen, termination locking, consent and unavailable store. No Swift toolchain is installed in this review environment; current native/UI execution belongs to the final macOS CI, not this local check.

## Remaining scope and handoff

The final integration should retain this exact Feedback implementation and e421 screenshot mechanism, run the full final macOS CI plus the dedicated Feedback workflow, and verify the actual downloadable combined App. Physical AppKit/IME/VoiceOver, real Keychain permission/restart, first-install Gatekeeper/notarization, screenshot click-latency comparison with feedback idle/open/failing, and deployed receiver/private Issues E2E remain unperformed here. They do not justify enabling ordinary production upload, screenshot safe retry, or a server endpoint.

Old screenshot UNKNOWN records, media, locks and audits are outside all Feedback mutation APIs and remain protected by the original candidate policy. No screenshot was uploaded or replayed by this review.
