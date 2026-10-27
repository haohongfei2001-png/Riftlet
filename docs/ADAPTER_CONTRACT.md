# Attachment adapter boundary v1

## Current admission

No production adapter is enabled. On 2026-10-27 the actual [Web handoff](../research/web-attachment-handoff-2026-10-27/README.md) was obtained at `6f4156988f32fa06d4df9f06a43f564b560e0a1d` and independently reviewed. It substantiates the user's scoped product-level ATTACHED report. The input program and per-image observations are now integrated, but the new integrated program has not run on a live Mac/ChatGPT in this session. Both actual aborts remain UNKNOWN; there is no safe-retry admission. The archive explicitly leaves active browser-tab switching, same-URL draft replacement and post-preview failure untested.

## API

```swift
protocol AttachmentAdapter: Sendable {
    var id: String { get }
    func captureTarget() async throws -> TargetLease
    func validate(_ target: TargetLease) async throws -> Bool
    func append(_ request: TransferRequest) async throws -> TransferReceipt
    func reconcile(_ request: TransferRequest) async throws -> TransferReceipt
}
```

The coordinator commits `dispatchIntent` first and passes that durable operation to append. Input and completion are separate facts. An append timeout/throw after intent becomes UNKNOWN. Reconcile must only observe the original operation, never call append, paste, replace input files, or select a fallback transport.

`captureTarget` must capture the actual foreground surface at the click, not the last remembered ChatGPT tab. `validate` is a preflight; the adapter MUST check the same lease and perform input in one target-side execution before yielding. Concurrent user navigation can invalidate it. A URL alone is not a draft identity. Use an explicit composer/draft generation that changes on new draft/thread/rebuilt composer but not normal typing.

The request's immutable file URL is beneath the app's private media root. The adapter should recheck its bytes/hash before transmission, use an operation-specific upload name with the real encoding extension, and enforce target size/type limits without silent lossy conversion. It never reads/sends chat history, replaces composer text, deletes pre-existing attachments or sends a message.

`verifiedReady` names Riftlet’s admitted product completion result. It does not require a private field literally named READY. The inherited scoped ATTACHED evidence has now been inspected. Real integrated target/completion/recovery tests and independent production admission are still required; the new implementation does not inherit a live PASS merely by reusing the input source.

## Receipt fields and admission

Identity must equal operationId, assetId, attempt, content hash and every TargetLease field. Attachment ID must be a target-observed, uniquely correlated identity, not merely a locally generated UUID or the sole newly observed removal button. The adapter asserts this only after its profile has passed actual identity tests. Stale/wrong replies are rejected without changing another operation.

| Outcome | Durable meaning |
| --- | --- |
| inputTriggered | External input reported; no completion |
| attachedCandidate | Candidate association/attachment appearance; no consumption |
| verifiedReady | Still subject to versioned successful-completion profile, original-draft membership and positive per-image evidence |
| definitiveFailure | Retry only with separate versioned failure profile and proof no residual auto-retrying attachment can still complete |
| unknown | Keep original operation/asset, target lock and recovery query |

Success and failure registration are independent. A normal-flow READY proof does not automatically admit network-failure retry semantics. The shipping default registries are both empty. `ReceiptPolicy` is code-reviewed policy, not a user-editable JSON override. The explicit Web acceptance composition passes a separate `syntheticAcceptanceProfiles` map: it requires synthetic origin, exact surface and the usual positive evidence, and cannot grant retry. The ordinary capture composition passes no development profiles. `integratedDevelopment` provenance is also rejected for system screenshots by the normalizer; it is a code-source label, not a claim of a new live test.

## Web implementation path

Implement one `WebAttachmentAdapter` around the existing target/receipt contract. Do not wait for the complete anomaly handoff before writing isolated adapter code and synthetic contract tests. The reported real INPUT evidence makes Apple Events the first **development candidate**; it does not admit production input or completion. W0 builds versioned observations/fixtures while W1 builds the single disabled candidate transport; they can proceed in parallel against the existing contract. Keep unavailable page-specific observations pending instead of inventing selectors or identities. W2 alone waits for real abnormal-case evidence and controls surface enablement.

1. **Apple Events JS first candidate:** freeze Chrome app/profile session, stable window/tab IDs, document nonce, surface and composer generation; address the exact tab/document and bound byte transfer; validate+File/DataTransfer input atomically; observe only the operation's attachment; return bounded progress/terminal observation. Do not claim Apple Events provides a browser-extension isolated world; establish the actual execution context in real tests. Respect the actual Automation and JavaScript-from-Apple-Events settings. No clipboard or AX required for this route.
2. **MV3 only if evidence favors it:** native Messaging host + scoped chatgpt.com content code, transport identity from MessageSender, bounded chunking/checksum, reconnect by querying the old operation. No localhost HTTP service, debugger permission, or generic all-sites permissions by default. Native rift clicks do not themselves grant activeTab.

Web Chat and Work get separate profiles. If a positive result cannot be associated to the original draft, the result remains UNKNOWN. Do not import Oracle's input-only ready fallbacks, first-visible-composer guessing, generic selector tree, or message-send code.

Implement only one production candidate path at a time. Consider MV3 when specific observed failures justify the change; lack of a final report alone is not a reason to build both. Independent technical review and the lead's evidence-based admission replace routine user approvals; production registries remain empty until the gate actually passes.

### Implemented boundary in this branch

`RiftletAdapters` now contains `ObservationDecoder`/`ObservationNormalizer` and `WebAttachmentAdapter`/`ChromeAppleEventsExecutor`. The version-1 observation is bounded to 64 KiB and rejects unknown fields, including nested identity/lease fields. Incoming data cannot supply an admission profile or positive-ready/safe-retry policy. Code-owned mapping is followed by the existing Core policy.

The native executor uses one shared serial utility queue for AppleScript, leaving AppKit snapshots on MainActor. It transfers 64 KiB chunks from a verified private descriptor, checks operation/attempt/chunk acknowledgements, and rechecks the complete file hash before a single commit. Input-side commands now also require the original foreground Chrome window/active tab. This still does **not** prove click-time tab identity if a switch occurs before queued target capture. Observation remains addressed to the original target and never activates it.

`ChatGPTWebPageProgram.load()` loads the bundled `chatgpt-web-20261027.js`. The narrow inherited scope is exact `https://chatgpt.com/`, Chat, the observed Chinese attachment/progress labels, PNG ≤8 MiB and ≤16M decoded pixels. Nonmatching routes/input structures are rejected. The acceptance operator must select Chat: the program does not independently identify Chat versus Work, so its fixed webChat label is a development precondition, not proven surface recognition. The page registers a one-shot operation before async hashing, then revalidates the original nodes/lease/visibility/focus synchronously with the files setter and change event. Completion requires the entered File hash, unique input, original card/image continuity, its own progress→100→progress removal→final data-image load, and exact file bytes or exact sRGB decoded RGBA+dimensions. Async proof is rebound to the same operation/nodes/source/load sequence before observation can report ATTACHED. Transient removal/reinsertion and final-source replacement veto that proof. The resource has no message-send, composer-edit, attachment-removal or network-hook operation.

Post-commit work is bounded observation (default 10 seconds, capped configuration 30 seconds); time only stops work, never proves success. Each native call separately has a five-second Apple Events timeout, so the polling budget is checked between calls rather than being a hard total deadline. Restart/click on UNKNOWN only observes the original operation. Missing document/observer remains UNKNOWN. Page operation tombstones and observation work are bounded; the current development session refuses new work after its limits rather than silently rearming.

Only explicit `--web-acceptance` wires the native bridge, in `Riftlet-Web-Acceptance`, with generated images and origin checks before and after importer recovery. Ordinary capture still uses `UnavailableAdapter`; `--simulate` remains offline. Fresh acceptance launch makes no input; a restart may observe old unresolved operations. The integrated real Chrome path, first-click behavior and terminal animation have **not** been exercised live here. Used bytes are retained, but post-consumption late-failure revival is not implemented or admitted.

## Mac implementation path

Separate adapter targets for new Mac Chat, new Mac Work and Classic, keyed by bundle/version/surface. M0 can now implement the target/receipt boundary, system pasteboard data representations and clipboard-ownership state machine using test doubles; it does not depend on a ready AX snapshot. M1 gathers real composer-scoped AX baseline/adding/uploading/ready/real-error snapshots and validates actual input before enabling that surface. Prefer unique real-codec fileURL; independently test PNG representation and selection preservation. AX menu Paste is the first candidate; events are a separately validated alternative. Bind PID plus AX window/composer/draft, not PID alone. Do not invent an AX selector from an unobserved app version.

Clipboards are restored only after proved consumption and only if marker/changeCount still belongs to this operation; never overwrite a later user copy or restore an old entire draft. Fixed 300 ms restoration is not accepted. Permission/privacy behavior is part of the real test. No Accessibility request is made by the current disabled adapter.

M0 now implements `MacTargetSession`, `ClipboardSnapshot`/`ClipboardOwnershipLease` and `MacAttachmentAdapter` against injected `MacAttachmentExecutor`/`ClipboardTransactionDriver`. Nineteen synthetic tests exercise PID/launch, window/composer/draft/surface binding, the actual write→paste→observe→conditional-restore orchestration, concurrent user copies and separately admitted failure. A terminal failure may release the input lease for a later explicit retry; it does not trigger paste or claim clipboard consumption. The independent M1 increment now adds native AX/NSPasteboard implementations, synchronous final file/target/owner checks, a shared flock and metadata-only durable journal, and original-operation recovery. See [M1 native backend](M1_NATIVE_BACKEND.md) for the existing-interface composition and evidence scope. The native executor and adapter must share the exact coordinator; unresolved clipboard/input intent cannot be bypassed by a new instance. A resolved tombstone can re-observe the original operation after a Core-commit interruption. Coordination failure returns UNKNOWN; restart never reconstructs a clipboard snapshot. Built-in client profiles remain empty, the binding provider is unavailable by default, and the App does not construct this backend. No real ChatGPT Mac AX tree, selection behavior, per-image completion or production profile is claimed validated.

## Incoming validation handoff

Required public-safe package: environment version/build/surface and transport; W/M cases with failures as well as success; event IDs; per-image positive-ready, failure and invalidation semantics; sanitized fixtures; verdict and remaining gaps. No cookies, credentials, private screenshots/chat, full network bodies or signed URLs.

Build the disabled adapter/fixture path before complete evidence is available. On handoff: review new evidence → extend regression fixtures → adjust the narrow adapter/normalizer → exercise proposed profiles in tests → real synthetic draft end-to-end → admit successful-completion and retry-safe profiles separately → scoped production enablement. Admission is the lead engineer's evidence-based decision with independent technical review, not a request for the user to approve every profile. No changes to capture identity, durable queue schema or animation contract should be necessary merely because the final READY signal changes.
