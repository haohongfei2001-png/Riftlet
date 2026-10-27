# Attachment adapter boundary v1

> **Latest user product supersession (2026-10-27):** [fast-swallow interaction contract](INTERACTION_CONTRACT_2026-10-27.md). The UI must swallow a screenshot **as soon as its actual upload start is positively evidenced**; it must **not wait for this contract's stricter `verifiedReady` evidence**. The full adapter receipt/retry guarantees below still apply to backend truth and safe retry. No current `inputTriggered`/`attachedCandidate` or placeholder may automatically masquerade as confirmed upload start. Add an independently reviewed per-surface start signal; maintain a separate durable visible/archived state; strong failure may trigger late rebirth while ambiguous outcomes remain hidden internally. This change is **not implemented or production-enabled** by documentation alone.

> **Further user ruling:** classified upload failure must produce **an ordinary clickable reborn image**, not a disabled retry UI. Backend safety should be achieved by improving the evidence boundary for calling something a *failed upload*; cases where the old upload might still complete remain UNKNOWN, not falsely classified as failed. A click on a reborn failure is a user-requested new attempt, never a background automatic replay. A current window with no usable composer/attachment entry never starts upload or swallows; success is visible in the draft itself with **no extra success Toast**. Speed/near-consecutive clicks are optimized only within stability guarantees. This is a product target; the existing production registries remain disabled until real evidence and engineering admission.



## Current implementation increment — interaction lifecycle

Core separates SQLite v3 visibility, upload-start audit and terminal facts. UI consumes only committed visibility/reason; admitted start causes the short swallow, later success is silent, and unsafe failure/UNKNOWN retains existing visibility: an already-swallowed asset stays internal, while an asset without admitted start is not falsely hidden. Removal, persistent hide, interaction-protected archive and bounded local history are implemented. The formal composition now includes Web v12/schema2 upload-start observation and early return, plus v6–v11 read-only recovery. First-use guidance, passive Automation checks and PassivePermissionResume remain intact. Native CI and exact scope are recorded in [VERIFICATION](VERIFICATION.md); the unchanged receipt interface is [uploadStarted v1](UPLOAD_STARTED_CONTRACT_V1.md).

## Current admission

No production adapter is enabled. Only explicit isolated generated-image Web acceptance admits the existing reviewed start and completion profiles. The new explicit [system-screenshot candidate](SYSTEM_SCREENSHOT_WEB_CANDIDATE.md) can input eligible original PNGs in its separate real-origin store, but its three independent admission maps remain empty: input/observation is not visual exit, success or retry permission. Unadmitted start/attached observations remain durable UNKNOWN and visible. Ordinary capture still uses `UnavailableAdapter`.

[Current integration](INTEGRATION_HANDOFF.md) preserves the round-seven merge and reviewed permission fixes. The f6417c6 real sample proves original B waits while A is unresolved, then enters once after A succeeds; each generated image has its own start and final proof. The same sample preserves nonempty text, selection and three old attachments with an unfocused editor. It does not admit concurrent input after start. Missing-ACK cold click still safely refuses and remains a product FAIL. CLEAR rejects erroneous selection but underlying click-through remains FAIL; GAP is software-only. Original evidence and historical round-six performance limits remain unchanged.

Scoped ordinary-thread attachments, background DOM-error compensation and a real POST100 XHR abort are inherited second-round v6 evidence. Third-round v7 has no new real upload/MID abort or full cold-first-click/ABA acceptance. Root-monitor ordinary-commit operation/restoration and native scheduling were observed within explicitly recorded exploratory-source limits. Actual App self-inclusion is now FAIL for the isolated CLI region capture; capture-only ten-minute resources are measurement-only. Production screenshot input/consumption and safe retry remain closed; this integrator did not operate the local Mac.

## API

```swift
protocol AttachmentAdapter: Sendable {
    var id: String { get }
    func preflight(asset: ImportedAsset, fileURL: URL) async throws
    func captureTarget() async throws -> TargetLease
    func validate(_ target: TargetLease) async throws -> Bool
    func append(_ request: TransferRequest) async throws -> TransferReceipt
    func reconcile(_ request: TransferRequest) async throws -> TransferReceipt
}
```

`preflight(asset:fileURL:)` is local-only eligibility validation, with a default no-op for existing adapters. It must not contact an external app, capture a target or input. The coordinator handles an existing original operation first; only new input preflights before reserve/prepare. Unsupported format/size therefore creates no operation, intent, UNKNOWN or target lock. A candidate JPEG from an old UNKNOWN is still eligible for original read-only reconciliation. The normal selection/revision/permission/target/intent checks remain after this await.

The coordinator commits `dispatchIntent` before external append and passes that durable operation to append. Input and completion are separate facts. An append timeout/throw after intent becomes UNKNOWN, including a later file-integrity rejection before observable input. Reconcile must only observe the original operation, never call append, paste, replace input files, or select a fallback transport.

Target selection must freeze the intended foreground surface at the original selection boundary. Web prearms through `captureTarget` using the existing single-flight scheduler, activation/wake/new-image signals and a bounded fallback; stale host epochs cannot publish. Selection freezes only an ACK that predates the native event in the same host/browser session; missing ACK refuses input. It never replaces the frozen target with an asynchronous post-click capture. This preserves safety but leaves the documented cold-first-click availability defect. `validate` is a preflight; the adapter MUST check the same lease and perform input in one target-side execution before yielding. Concurrent user navigation can invalidate it. A URL alone is not a draft identity. Use an explicit composer/draft generation that changes on new draft/thread/rebuilt composer but not normal typing.

Optional `WebAttachmentAdapter.captureTargetWithDiagnostics(context:)` preserves the ordinary API and single capture. Host-only request/attempt/epoch metadata is excluded from page JSON; native stage logs and adapter/App completion are joined only by that exact request, not repeated target digest. App records actual publication and the original effective ACK/request on reuse. These timestamps cannot authorize input or backdate ACK. See [the shared contract](UPLOAD_STARTED_CONTRACT_V1.md#7-第四轮合流后的直接接入要求).

The request's immutable file URL is beneath the app's private media root. The adapter should recheck its bytes/hash before transmission, use an operation-specific upload name with the real encoding extension, and enforce target size/type limits without silent lossy conversion. It never reads/sends chat history, replaces composer text, deletes pre-existing attachments or sends a message.

`verifiedReady` names Riftlet’s admitted product completion result. It does not require a private field literally named READY. The inherited scoped ATTACHED evidence has now been inspected. Scoped integrated tests are recorded separately from inherited experiments. Scoped ordinary-thread success does not close the outstanding MID, first-click/business-transition, physical GUI or independent production-admission matrix.

## Receipt fields and admission

Identity must equal operationId, assetId, attempt, content hash and every TargetLease field. Attachment ID must be a target-observed, uniquely correlated identity, not merely a locally generated UUID or the sole newly observed removal button. The adapter asserts this only after its profile has passed actual identity tests. Stale/wrong replies are rejected without changing another operation.

| Outcome | Durable meaning |
| --- | --- |
| inputTriggered | External input reported; no start/visual-exit or completion permission |
| uploadStarted | Independently admitted, original-operation positive start; persist first-start evidence and hide, without success or retry permission |
| attachedCandidate | Candidate association/attachment appearance; no consumption |
| verifiedReady | Still subject to versioned successful-completion profile, original-draft membership and positive per-image evidence |
| definitiveFailure | Retry only with separate versioned failure profile and proof no residual auto-retrying attachment can still complete |
| unknown | Keep original operation/asset, target lock and recovery query |

Start, success and safe-failure registration are independent. A normal-flow READY proof does not automatically admit early visual exit or network-failure retry semantics. All shipping production registries remain empty. `ReceiptPolicy` is code-reviewed policy, not a user-editable JSON override. The explicit Web acceptance composition passes a separate `syntheticAcceptanceProfiles` map: it requires synthetic origin, exact surface and the usual positive evidence, and cannot grant retry by itself. The separate `syntheticUploadStartProfiles` and `syntheticRetrySafeProfiles` also require synthetic origin and matching surface. `WebAcceptanceConfiguration` registers only the reviewed `chatgpt-web-zh-progress-start-development-20261027-v1` start profile; its synthetic retry map remains empty. Offline simulation remains a separate mode. The ordinary capture composition passes no development profiles. Default normalization still rejects `integratedDevelopment` for real assets. Only the native-controlled `systemScreenshotCandidate` scope plus its exact independent profile accepts that provenance unchanged for candidate observations; `.syntheticFixture` is never accepted for real screenshots. Neither label is a claim of a new live test.

The candidate requires the bundled v12 source ID and a `SystemScreenshotObservationJournal`. The journal validates the persisted asset and full operation identity and retains at most six first observations per attempt (64 KiB each) in existing SQLite v3 checkpoints via atomic `saveCheckpointIfAbsent`; it cannot write `upload_starts`, change visibility or grant admission. Failed evidence persistence after intent remains UNKNOWN. Source ID is a composition identifier, not a cryptographic authentication of arbitrary injected programs. See the [exact candidate contract and format matrix](SYSTEM_SCREENSHOT_WEB_CANDIDATE.md).

## Web implementation path

The existing `WebAttachmentAdapter` and W0/W1 boundaries are implemented. W2 incrementally integrates actual page observations and abnormal-case evidence into that single candidate path; unavailable structures or identity continuity must remain refused. Do not rebuild Core/Capture/UI, invent selectors, or add a second production transport merely because the full admission matrix is incomplete.

1. **Apple Events JS first candidate:** freeze Chrome app/profile session, stable window/tab IDs, document nonce, surface and composer generation; address the exact tab/document and bound byte transfer; validate+File/DataTransfer input atomically; observe only the operation's attachment; return bounded progress/terminal observation. Do not claim Apple Events provides a browser-extension isolated world; establish the actual execution context in real tests. Respect the actual Automation and JavaScript-from-Apple-Events settings. Attachment input requires no clipboard/AX route. Third-round scheduling optionally uses existing AX trust for Chrome activity hints; unavailable trust does not enable a prompt or authorize input.
2. **MV3 only if evidence favors it:** native Messaging host + scoped chatgpt.com content code, transport identity from MessageSender, bounded chunking/checksum, reconnect by querying the old operation. No localhost HTTP service, debugger permission, or generic all-sites permissions by default. Native rift clicks do not themselves grant activeTab.

Web Chat and Work get separate profiles. If a positive result cannot be associated to the original draft, the result remains UNKNOWN. Do not import Oracle's input-only ready fallbacks, first-visible-composer guessing, generic selector tree, or message-send code.

Implement only one production candidate path at a time. Consider MV3 when specific observed failures justify the change; lack of a final report alone is not a reason to build both. Independent technical review and the lead's evidence-based admission replace routine user approvals; production registries remain empty until the gate actually passes.

### Implemented boundary in this branch

`RiftletAdapters` now contains `ObservationDecoder`/`ObservationNormalizer` and `WebAttachmentAdapter`/`ChromeAppleEventsExecutor`. Both observation schemas are bounded to 64 KiB and reject unknown fields, including nested identity/lease fields. Current v12 uses schema2; historical read-only responses use schema1. Incoming data cannot supply an admission profile or positive-ready/safe-retry policy. Code-owned mapping is followed by the existing Core policy.

The native executor uses a shared serial utility queue and PID-addressed Apple Events, checking process launch identity before dispatch. MainActor handles AppKit snapshots. It transfers bounded chunks from a verified private descriptor (generic/legacy programs default to 64 KiB; the reviewed synthetic v12 program uses at most 256 KiB, with an 8 MiB image limit), checks operation/attempt/chunk acknowledgements, and rechecks the complete file hash before a single commit. Input-side events verify original foreground Chrome window/active tab. The App freezes its prearmed target synchronously on original mouse-down or AX invocation; the page revokes input epochs on relevant focus/visibility changes and drains pending mutations before final input. Full delayed-event/window/draft race acceptance remains open. Observation is addressed to the original target and never activates it.

Chrome's Apple Events JavaScript was observed in an isolated world; the relevant React properties are in MAIN. `MainWorldCommandEnvelope` submits one percent-encoded `javascript:void(...)` expression through the exact tab URL property, then reads/removes a random nonce DOM receipt. The MAIN command is never resubmitted when its reply is missing. Decoding is bounded and rejects wrong nonce, non-Boolean `ok`, unknown fields and malformed results; exceptions expose only a code-owned failure. The read-loop budget is one second between calls, not a hard deadline for the five-second-per-event transport. The local control observed zero Navigation events from this command; no generalized browser-version guarantee is inferred.

`ChatGPTWebPageProgram.load()` loads the bundled v12 `chatgpt-web-20261027.js` with an observe-only v6–v11 router. The development scope is observed Chinese Home/thread Chat, PNG≤8MiB and≤16M decoded pixels. Home retains its unambiguous Chinese Chat/Work header. An ordinary `/c/…` route additionally requires the unique marked form, exact textbox/file input, explicit non-Home/non-Work/non-temporary/non-readonly properties and matching business draft key. The committed React chain must actually contain the form, including the valid alternate branch, terminate at `HostRoot.current`, and stay within512 levels; neither pending properties nor the URL establishes identity. Other structures refuse input. Source ID is `chatgpt-web-zh-20261027-integrated-v12`; the development completion profile is `chatgpt-web-zh-attached-development-20261027-v2`.

The current ordinary-thread candidate retains the v8 composer binding and v7 monitor and wraps only the proven root's configurable/writable `current` data property. Ordinary assignments preserve the latest tree value and check each live form once; mismatches, checker failure, reentry or descriptor loss revoke prior authority. Home has no root monitor. Explicit stop restores only its still-owned descriptor/latest value, with a non-rearmable tombstone. This changes property reflection semantics and cannot cover in-place props ABA, defineProperty bypass-and-restore or pre-install history. At most4 roots are monitored; real business-transition continuity and peak overhead remain admission gates. Live ordinary commit counts are not a real A→B→A result.

Chrome activity observation now reuses an observer only for the same PID and launchDate, refusing a missing launch identity. It reads only the focused-window handle under existing authorization, requesting a 50 ms messaging timeout on each object; registration now checks the timeout setter result and refuses failed setup; an actual hard total deadline is still not established. Window/title/focus notifications and row mouseEntered are wake hints for the existing single-flight scheduler. They grant no draft identity. Total startup time must be measured separately. Optional App/transport logs each cap at2048 lines; `transportSucceeded` describes the bridge stage, while `arm_completion` records host ACK publication. Capture rechecks active window/tab before returning the receipt and still checks foreground launch identity afterward.

The native active-selection fast path parses one absolute fixed tab-ID → window-ID → null descriptor, with exact descriptor kinds/fields and utxt descriptors containing canonical ASCII-decimal positive Int64 IDs. Unsupported shapes use the previous ID-based reads; transport failure propagates. PID/launchDate, foreground selection before input, capture-return selection and complete page/receipt identity checks remain. Its bounded `active_identity` trace is diagnostic only, never an ACK; App publication and original-event ACK ordering are unchanged. The original fallback remains unexercised live in round six.

The page registers a one-shot operation before async hashing, then revalidates original target/nodes/focus synchronously with the files setter and change event. Completion still needs entered File hash, unique input, original card/image continuity, its own progress→100→progress removal→final image load and exact bytes or sRGB RGBA+dimensions. Async proof stays bound to the original operation/nodes/source/load sequence; transient removal/reinsertion or final-source replacement vetoes it. The bundled resource has no send, composer edit, attachment deletion, network hook or retry command. The archived network-fault tool is a separately scoped lab fixture, not an app resource.

Post-commit work is bounded observation (default 10 seconds, capped configuration 30 seconds); time only stops work, never proves success. Each native call separately has a five-second Apple Events timeout, so the polling budget is checked between calls rather than being a hard total deadline. Restart/click on UNKNOWN only observes the original operation. Missing document/observer remains UNKNOWN. Page operation tombstones and observation work are bounded; the current development session refuses new work after its limits rather than silently rearming.

Explicit `--web-acceptance` wires the real Chrome bridge in a separate synthetic-only data root, checking origin before and after importer recovery. Explicit `--system-screenshot-candidate` uses a different system-origin-only root and an empty admission policy. Ordinary capture uses `UnavailableAdapter`; `--simulate` remains offline. Fresh acceptance/candidate launch makes no input; restart only observes original unresolved/completed operations. SQLite v3 retains original success and correlated late failure atomically as `compensated`, keeps the asset hidden until separately admitted safe termination, and forbids stale success from consuming it again. Safe failure restores the original sequence as an ordinary clickable image unless user remove/archive intent takes precedence. Migration preserves the old v2 operation and compensation evidence. Completed Web watches are bounded.

Focus/visibility/pageshow changes revoke input authority while a still-bound original operation may continue background observation. Route, business identity, Navigation events, original nodes or attachment loss invalidate observation. Trusted interaction outside the form now rechecks the exact original binding and composer availability; text-editor focus is not required. Document focus/visibility and native foreground/target checks remain required. These guards do not establish a business transition epoch for an entirely unobservable same-DOM A→B→A; UX-01 and UX-02 remain production gates. Do not retain a refused click and re-authorize it against a later target without evidence spanning the original selection boundary.

Cross-program recovery routes only observe to retained original v6–v11 closures, matching the complete target and operation/asset/attempt/hash. Input actions always use v12. Missing/stopped historical registries, lost proofs, ambiguous matches or old tabs remain UNKNOWN; no historical input program is installed and no monitor is stopped to bypass ownership. Frozen VM snapshots cover all six historical versions, including original v11 observer completion after early start return. They do not prove live restart across every version; round4 live evidence covers direct v6 read-only invalidation with unchanged input count. Never clear UNKNOWN or reconstruct identity/proof to bypass this boundary.

Receipt identity remains the complete original lease. Dispatch conflict checking is separate: for Chrome webChat in the same browser-session/tab, only two recognized identities in the same profile with distinct valid UUIDs narrow the lock: `chatgpt-composer-react-20261027-v1` requires `local-chatgpt:UUID`, and `chatgpt-composer-react-persisted-20261027-v1` requires the exact bare36-character UUID. Different profiles always conflict; no local-to-persisted mapping is inferred. The same ID remains locked across rearm/window movement; a legacy nil, invalid or unknown-profile identity is a whole-tab wildcard in either direction. No old target JSON is rewritten or backfilled. Real same-tab/URL/window transition independence is still unaccepted; unit persistence tests do not prove React continuity.

Success or POST100 abort does not make retry safe. The normalizer's absence-only failure has no attachment ID, while compensated release requires the original nonempty ID; admission must first close that retirement-identity contract and prove no residual auto-completion. Never treat nil, timeout, a new token, an apparently vanished card or a cleared journal as permission to replay.

## Mac implementation path

Separate adapter targets for new Mac Chat, new Mac Work and Classic, keyed by bundle/version/surface. M0 can now implement the target/receipt boundary, system pasteboard data representations and clipboard-ownership state machine using test doubles; it does not depend on a ready AX snapshot. M1 gathers real composer-scoped AX baseline/adding/uploading/ready/real-error snapshots and validates actual input before enabling that surface. Prefer unique real-codec fileURL; independently test PNG representation and selection preservation. AX menu Paste is the first candidate; events are a separately validated alternative. Bind PID plus AX window/composer/draft, not PID alone. Do not invent an AX selector from an unobserved app version.

Clipboards are restored only after proved consumption and only if marker/changeCount still belongs to this operation; never overwrite a later user copy or restore an old entire draft. Fixed 300 ms restoration is not accepted. Permission/privacy behavior is part of the real test. No Accessibility request is made by the current disabled adapter.

M0 now implements `MacTargetSession`, `ClipboardSnapshot`/`ClipboardOwnershipLease` and `MacAttachmentAdapter` against injected `MacAttachmentExecutor`/`ClipboardTransactionDriver`. Nineteen synthetic tests exercise PID/launch, window/composer/draft/surface binding, the actual write→paste→observe→conditional-restore orchestration, concurrent user copies and separately admitted failure. A terminal failure may release the input lease for a later explicit retry; it does not trigger paste or claim clipboard consumption. The independent M1 increment now adds native AX/NSPasteboard implementations, synchronous final file/target/owner checks, a shared flock and metadata-only durable journal, and original-operation recovery. See [M1 native backend](M1_NATIVE_BACKEND.md) for the existing-interface composition and evidence scope. The native executor and adapter must share the exact coordinator; unresolved clipboard/input intent cannot be bypassed by a new instance. A resolved tombstone can re-observe the original operation after a Core-commit interruption. Coordination failure returns UNKNOWN; restart never reconstructs a clipboard snapshot. Built-in client profiles remain empty, the binding provider is unavailable by default, and the App does not construct this backend. No real ChatGPT Mac AX tree, selection behavior, per-image completion or production profile is claimed validated.


For Core `.succeeded` and `.compensated`, M1 now verifies the exact consumed journal tombstone with `verifyConsumedObservation`, releases its transient read lock before AX work, then returns the original observation directly. These phases never use clipboard recovery/settlement, restore a snapshot, rewrite the tombstone or obtain new input rights. An existing clipboard owner is left untouched. Unresolved recovery after journal-resolution/Core-commit interruption keeps its original separate path. These are synthetic/native regression guarantees; the App still does not enable a Mac completed-operation watch or real client provider.

## Incoming validation handoff

Required public-safe package: environment version/build/surface and transport; W/M cases with failures as well as success; event IDs; per-image positive-ready, failure and invalidation semantics; sanitized fixtures; verdict and remaining gaps. No cookies, credentials, private screenshots/chat, full network bodies or signed URLs.

Build the disabled adapter/fixture path before complete evidence is available. On handoff: review new evidence → extend regression fixtures → adjust the narrow adapter/normalizer → exercise proposed profiles in tests → real synthetic draft end-to-end → admit successful-completion and retry-safe profiles separately → scoped production enablement. Admission is the lead engineer's evidence-based decision with independent technical review, not a request for the user to approve every profile. No changes to capture identity, durable queue schema or animation contract should be necessary merely because the final READY signal changes.


## 第七轮已集成的原选择等待

实现来源 `f6417c6` / `9de6a85`，正式合流 `2aaaadb`，权限接收进程修复 `595142d`。下方第六轮提案保留为历史；实际接口如下，不再重开发顺序调度。

| 已编译边界 | 当前行为 |
| --- | --- |
| `AcceptedSelection` | runtime-only、非 Codable；保留原 asset/full target、host epoch、effective ACK、event/accepted uptime、visibilityRevision、capture/arm ID 和期限。严格 ACK < event，最长30秒，不由重启恢复。 |
| `SelectionSubmissionQueue.enqueue` | App 同步接受选择时、任何 Task/permission await 前分配单调 ordinal；唯一 consumer 按原顺序调用同一 Coordinator。只负责提交，不写 intent 或调用 append。App最多16个提交、Core最多12个 accepted token，是工程界限而非产品等待承诺。 |
| `TransferCoordinator.select(AcceptedSelection)` | 复用原 Core ticket、prepared operation/attempt 和唯一 drain；targetBusy 保留原 prepared 槽，未开始不吞噬。有实际 expiry task、精确 token 取消和 `drainRequested` 合并唤醒。 |
| `validateAcceptedSelection` | App 检查原对象/epoch/前台进程/隐藏/终止/期限，按原 session 新鲜被动检查权限，再复核 authority。无 capture、无请求授权、无缓存 granted。 |
| 已有 UNKNOWN/compensated 的 accepted 再点击 | 先要求 adapter/application/session 与原 operation 相同，再执行上述 validator，之后才可只读原 operation；不借另一个仍活跃进程的权限，不增加新 attempt。权限拒绝保持旧事实；后台原操作观察仍是独立路径。 |
| `QueueStore.markDispatchIntent(_:selection:)` | 同一原事务重新检查 prepared、原 asset/target/revision、activeOperation、visible/hidden 与既有 conflictsForDispatch；取得数据库事务后才进入 token 短锁写 intent。start、UNKNOWN、compensated、旧nil及跨profile锁不豁免。 |
| settle / finish / cancel | UI release 使用 exact token + owner/revision；异步取消只传原 selection ID。旧回调不能取消/释放同图新点击。hide/remove/clear/stop/失权/host失效/到期取消未intent选择；intent之后只观察原操作。 |
| `recoverOriginalObservations(operationIDs:)` | 本地 v3 恢复和原 ID 快照先完成；首轮预绑定**尝试结束**后开始旧 ID 只读观察，不再次 reset 新 prepared 操作。首轮尝试不保证发布成功 ACK；第七轮实测样本中确实 ACK 先于观察。 |

新选择的权限校验也覆盖 existing-operation 只读分支，这是合流审查发现并修复的实际旁路；跨进程的旧操作不借当前点击授权。既有后台 generic 权限预检没有在本轮改为逐原操作接收进程预检，不宣称这一真实多进程权限矩阵已经通过。其行为仍由原完整目标检查、OS权限和 UNKNOWN 保留约束；后续如需调整，使用最小共享接口独立审查，不借本轮双图证据扩大准入。

真实双图证据绑定 f6417c6，最终 GUI/来源CI绑定9de6a85；正式组合修复以本轮 [CI和非作者审查](../engineering/evidence/2026-10-28-integration-round7/README.md) 为准。组合CI不替代修复后二进制的真实TCC/多进程/冷首击/物理GUI验收。uploadStarted schema、v12页面和v6–v11只读路由未变。

<details>
<summary>第六轮制定的共享边界与审查要求（历史保留，现已按上表映射实现）</summary>

## 第七轮顺序调度共享边界 v1（实现待正式交接）

本节固定第七轮实现与非作者审查所需的最小信息和行为，不新增第二套 Coordinator，不声称已经实现或验收。同草稿 B 的真实 `targetBusy` 是**尚未输入就取消**，不是图片上传失败；原证据见[第六轮提案及复现](../engineering/evidence/2026-10-27-real-mac-round6/consecutive-click-proposal.md)。本地 Codex 独占实现和真机验证，root 收到正式交接后统一整合 Core/App 共享改动；不得以旧 App 覆盖本轮首次使用、权限恢复和策略。

### 现有 API 与拟扩展点

现有 `select(assetID, frozenTarget:, visibilityRevision:)`、`AttachmentAdapter.validate/append/reconcile`、`QueueStore.markDispatchIntent` 保持当前行为。以下名称沿用第六轮提案作为接口映射说明，**尚不是已编译 API**；第七轮如已采用不同命名，只需清楚映射，不重复实现。

| 边界 | 必须保留的信息／行为 |
| --- | --- |
| App → `AcceptedSelection` | 按下/原 AX 边界冻结 full TargetLease、原 effective ACK、原 event uptime、host epoch、asset/revision；同步接受选择时再固定 selectionID、进程代际与单调 sequence。token 不可持久化或重启恢复。 |
| `select(selection)` / settle | 唯一 Coordinator 维护原始接受顺序；拒绝、取消、超时和重复选择都必须结束其序号，不能留下空洞。 |
| 注入的被动权限 preflight | 只返回当前可否执行，不返回新 lease，不调用 capture，不请求授权；`askUserIfNeeded=false`。等待后每次尝试输入都重新执行。 |
| `dispatchBlockers(for:)` | 可增加只读查询，但必须复用原 `conflictsForDispatch` 谓词；查询不是 dispatch 授权，最终原事务仍重新检查。 |
| `pendingFactsDidChange()` | 原操作事实改变时唤醒既有 drain，合并 pending wake／事实代际，不能因 `isDraining` 丢掉解除锁事件。 |
| `invalidateQueuedSelections` | hide、stop、host epoch 失效、移除／revision变化、到期，使尚未 intent 的对应选择失效；不删除资产、远端附件或审计。 |

**与首次使用权限组合的必要修正：** 当前 App 同步取 frozen/revision 后，先 await 权限，再进入 Core；仅在 Core 首次 await 前取 ticket 不能保证原点击 FIFO。顺序必须在 App 同步接受边界、任何权限 await 前固定。可把被动 preflight 注入既有 drain，或保留 App 检查但提交每个预分配序号的 authorized/cancelled 结果；不得建立 App 与 Core 两套竞争队列，也不得把先返回的 B 当先点击的 A。若在 mouseDown 预分配，取消按住也必须 settle/skip。不能在较晚回调从最新 armedTarget 补出原 token 的 ACK/epoch。

### 一次原选择的合法等待

1. 只有无 `dispatchIntent` 的 prepared 原选择可以等待；未输入不吞噬。原点击必须已有完整 ACK，严格早于原事件。无 ACK 的拒绝不排队等待未来授权。
2. 等待唤醒后检查原 token 的代际、有效期、前台会话、可见性/revision；新鲜被动权限检查后只 `validate(originalLease)`，再复核 prepared/取消状态，最后由原 `markDispatchIntent` 原子重查锁并仅 append 一次。每个 await 都可能发生取消、目标变化或新 blocker。
3. 权限拒绝／不可用、原 lease 失效、hide、stop、移除或超时，取消尚未 intent 的项并保留截图。后来授权、ACK 或显示恢复不能复活旧选择。取消后，新的真实点击可以产生新选择，不能永久按 asset 禁止。
4. intent 之后的取消、超时、进程中断不回退成 prepared，不再 append；只按原 operation/attempt/target/hash 核对 UNKNOWN/补偿。重启取消 prepared，不能恢复点击 token。
5. 原同草稿 start、UNKNOWN、compensated、旧未知身份和跨 profile 锁均不放宽。A 获得 start 不是输入 B 的授权；A 终结也不证明 B 原 lease 仍有效。任何第三个 blocker 都必须继续生效。
6. 等待必须有实际到期调度和有界存量；时长是可调整工程参数，不是证据有效期或新产品保证。不能只在下一次状态变化时才发现 expired，也不能使 UNKNOWN 永久堵住所有后来目标。本阶段可接受明确记录的有界队首等待，不悄悄引入另一套并发／跨 lane 调度。
7. 锁在 drain 的查询后、park 前被解除，或最后一个未决操作终结后没有下一轮观察时，也必须继续已有队列；用合并唤醒／事实代际处理，不能靠忙轮询或用户第二次点击补救。

### 必须覆盖的回归与真实验收

| 情况 | 必须观察到的结果 |
| --- | --- |
| A 权限挂起、B 先返回 | 保留原 A→B 次序；A 拒绝／取消／超时后 B 能继续，无序号空洞 |
| park 期间、恢复前已观察到撤权／取消／epoch或revision改变 | 旧选择不触发页面 validate/begin/input，不请求授权，不在恢复后复活；若只读 validate 已在途才发生变化，不声称撤销已发调用，必须阻止后续 begin/commit/new capture |
| 同草稿 A start 后 B 等待；A 合法终结 | 原锁未豁免，B 只验证原 lease；仍有效才一次输入，失效则取消且 captureCount=0 |
| blocker 在 validate 与 intent 之间出现；解除锁与 park 交错 | 原事务阻止误输入，等待与唤醒不丢失 |
| 同 asset 重复点击；无 intent 取消后的新点击 | 原选择不重复输入，新实际点击仍可正常受理 |
| intent 后取消／崩溃／重启／迟到回执 | 原操作只读核对，旧 UNKNOWN、第一份 start、补偿和跨 profile 锁保持 |
| 未输入／开始／最终成功 | 只在原资产获准 start 后吞噬；成功不重复动画或 Toast |

原 `lab/consecutive_click_model.py` 的 10 项通过只证明隔离提案模型。它不覆盖正式 App 权限乱序、Swift actor/SQLite 竞态、deadline、完整 lease 或取消后新点击；其 originals 集合取消后不释放，不能照搬为正式资产生命周期。

上述是“等待既有锁合法解除”的第一阶段，不能标为“start 后同草稿连续输入”已准入。若第七轮提出 start 后允许另一资产的能力，需另有默认关闭的精确版本/目标隔离准入、真实双图身份/一次输入/旧卡文字选区/独立最终事实与迟到错误证据；不能借 start、最终成功、读取优化或 timeout 放开 UNKNOWN 或安全重试。

</details>
