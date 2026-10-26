# Attachment adapter boundary v1

## Current admission

No production adapter is enabled. The user's latest report establishes a real Chrome Apple Events synthetic INPUT/target/image association and an ATTACHED candidate; its anomaly evidence has not yet been delivered here. This is more recent than the archived technical package's NOT_TESTED state, but does not prove strict READY, terminal failure, or all concurrency/navigation cases. Keep these categories separate.

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

`verifiedReady` names Riftlet’s admitted product completion result. It does not require a private field literally named READY. A product-level ATTACHED criterion may be mapped to it only after its exact-image/original-draft semantics and abnormal cases pass the agreed real validation; the current candidate has not passed that gate.

## Receipt fields and admission

Identity must equal operationId, assetId, attempt, content hash and every TargetLease field. Attachment ID must be a target-observed, uniquely correlated identity, not merely a locally generated UUID or the sole newly observed removal button. The adapter asserts this only after its profile has passed actual identity tests. Stale/wrong replies are rejected without changing another operation.

| Outcome | Durable meaning |
| --- | --- |
| inputTriggered | External input reported; no completion |
| attachedCandidate | Candidate association/attachment appearance; no consumption |
| verifiedReady | Still subject to versioned successful-completion profile, original-draft membership and positive per-image evidence |
| definitiveFailure | Retry only with separate versioned failure profile and proof no residual auto-retrying attachment can still complete |
| unknown | Keep original operation/asset, target lock and recovery query |

Success and failure registration are independent. A normal-flow READY proof does not automatically admit network-failure retry semantics. The shipping default registries are both empty. `ReceiptPolicy` is code-reviewed policy, not a user-editable JSON override. Development tests may explicitly admit synthetic fixture profiles; shipping App does not pass them.

## Web implementation path

Implement one `WebAttachmentAdapter` around a shared composer/evidence module after the parallel validation chooses transport:

1. **Apple Events JS first candidate:** freeze Chrome app/profile session, stable window/tab IDs, document nonce, surface and composer generation; stream bounded byte chunks into the specific isolated world; validate+File/DataTransfer input atomically; observe only the operation's attachment; return bounded progress/terminal observation. Respect the actual Automation and JavaScript-from-Apple-Events settings. No clipboard or AX required for this route.
2. **MV3 only if evidence favors it:** native Messaging host + scoped chatgpt.com content code, transport identity from MessageSender, bounded chunking/checksum, reconnect by querying the old operation. No localhost HTTP service, debugger permission, or generic all-sites permissions by default. Native rift clicks do not themselves grant activeTab.

Web Chat and Work get separate profiles. If a positive result cannot be associated to the original draft, the result remains UNKNOWN. Do not import Oracle's input-only ready fallbacks, first-visible-composer guessing, generic selector tree, or message-send code.

## Mac implementation path

Separate adapter targets for new Mac Chat, new Mac Work and Classic, keyed by bundle/version/surface. First gather composer-scoped AX baseline/adding/uploading/ready/real-error snapshots. Prefer unique real-codec fileURL; independently test PNG representation and selection preservation. AX menu Paste is the first candidate; events are a separately validated alternative. Bind PID plus AX window/composer/draft, not PID alone.

Clipboards are restored only after proved consumption and only if marker/changeCount still belongs to this operation; never overwrite a later user copy or restore an old entire draft. Fixed 300 ms restoration is not accepted. Permission/privacy behavior is part of the real test. No Accessibility request is made by the current disabled adapter.

## Incoming validation handoff

Required public-safe package: environment version/build/surface and transport; W/M cases with failures as well as success; event IDs; per-image positive-ready, failure and invalidation semantics; sanitized fixtures; verdict and remaining gaps. No cookies, credentials, private screenshots/chat, full network bodies or signed URLs.

Review → regression fixtures → minimal adapter → separate ready/retry-safe registry admission → real synthetic draft end-to-end → scoped enablement. No changes to capture identity, durable queue schema or animation contract should be necessary merely because the final READY signal changes.
