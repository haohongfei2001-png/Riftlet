# Stage 2: distinguishing missing start evidence from missed start delivery

The first sections below record the initial source analysis and read-only diagnostic, before the new upload. The appended actual Stage 2 results are separate. The previous roughly 40 KB screenshot reportedly produced original input and attached evidence without an admitted start. File size alone does not establish the cause.

## Two independent observation windows

The v13 page calls `sampleStart` from mutation batches, original input-hash completion, image events and native query sampling. It needs the same unique original progress node, two actually sampled finite values with `0 <= previous < current < 100`, the original input sequence/time, and a verified file hash at the advancing sample. Initial missing `aria-valuenow` is permitted only while waiting for the first finite baseline. A baseline is not a start. Mutation `oldValue` records detect hidden invalid transitions, but are deliberately not promoted into two observed start samples.

The native adapter polls with a nominal 250 ms sleep between replies; transport and scheduling add time. It does not subscribe to page mutations. A page callback may construct `op.uploadStart` between native queries. If the progress reaches 100, disappears, errors, or final proof completes before the next native observation, that observation cannot export the historical start as a current `uploadStarted` state. Attached evidence is independent and supersedes it. Thus “no native start receipt” has two distinct explanations: the page never constructed start, or it constructed start but the native query missed its eligible window.

MutationObserver also samples only the final DOM state of each delivered batch. Multiple progress updates in one task can collapse into one finite sample. If the first sampled number is 100, or there is only one sub-100 sample followed by 100/removal, no start is proved. If an increasing pair occurs before file-hash verification, hash completion at an unchanged value does not manufacture a new increase; a further increasing sub-100 sample is required. These are testable code paths, not conclusions about the previous real screenshot.

## Read the original operation first

Load `page-evidence-helper.js` through the existing authorized exact-tab MAIN nonce bridge and invoke:

```js
riftletSystemScreenshotStage2Evidence({
  assetID: "<original asset UUID>",
  operationID: "<original operation UUID>",
  attempt: 1 // use the actual original attempt
})
```

The helper is standalone evidence code, never bundled into the App. It searches only v13/v12/v11/v10/v9, bounded to 32 generations and 32 operations per generation, and rejects an ambiguous exact selector. It never captures a target, samples an operation, drains mutation records, validates a lease, installs listeners, changes DOM, or requests input/network activity. No cleanup is needed because nothing is installed. The bridge's own receipt mechanics remain the runtime owner's responsibility.

Only fixed diagnostics, numbers and equality booleans are returned; no original IDs, chat text, raw labels, URLs, image bytes or exception messages are exported. Keep the original selector and any full private receipt in private evidence only. A non-OK status or bounded-out result is incomplete evidence. Returned fields are stored bookkeeping snapshots, not freshly authorized start/completion claims.

| Result | What it can establish | What it cannot establish |
| --- | --- | --- |
| `hasStoredStart=true`, original input/start times and sequences ordered | The original page constructed start evidence | That a native query observed or admitted it while eligible |
| `hasStoredStart=false`, clean retained final proof | Current bookkeeping contains no stored start; final proof can exist independently | Why a pair was absent, or that upload speed caused it |
| `startDisqualified=true` after completion | Start is no longer eligible | Early failure cause: normal removal of the original progress node also sets this flag |
| Bound progress detached, current value 100, stored sample below 100 | Original node and last sampled value differ at inspection | Whether an earlier callback missed 100; check hundred/ended/loaded sequences and proof too |
| `hashSequence` later than early sampled activity | Hash verification came later in the page sequence | Exact lost increasing values, since they are not stored |

Read `inputCount`, `inputSequence`, `inputObservedAtMS`, `hashVerified/hashSequence`, `started/hundred/ended/loadedSequence`, `sampledProgressValue`, original progress membership/value, `hasStoredStart/startObservedAtMS`, `startDisqualified`, `invalid/error`, and proof identity/node booleans plus completion time together. `startedSequence` records progress presence, not admitted upload start. All page times use that document's performance clock; do not subtract them from native uptime without a separately measured clock relationship.

## Evidence that cannot be recovered retrospectively

The production operation does not retain mutation batches, every progress sample, historical disqualification reason or intermediate labels. The helper explicitly reports `historicalMutationRecordsAvailable=false` and `disqualificationReason=NOT_RECORDED`; it does not reconstruct them. No stored start may also follow identity invalidation, so a damaged/invalid operation is not a complete historic timeline.

If the original snapshot cannot distinguish the hypotheses, a future independently authorized operation needs an already-installed bounded diagnostic recording only its exact generated filename/card/progress node, mutation batch and old/current numeric-or-missing state, hash timing and image load/error. Existing round-five diagnostic probes provide the pattern, but must be explicitly routed to v13 and to a new exact operation/asset. Do not re-input the old operation, change production sampling, or infer permission from diagnostic observations. A prospective event trace plus native reply times can distinguish missing page evidence from a native polling window; the retrospective snapshot alone cannot.

## Offline verification

`node --test engineering/evidence/2026-10-28-system-screenshot-stage2/page-evidence-helper.test.cjs`: 11/11 pass. Tests cover frozen objects and forbidden observer methods, exact selector routing, ambiguity/bounds, privacy sentinels, retained final state with detached progress, missing versus invalid numeric values and historical start/proof distinctions. This does not validate the real page or reproduce the prior screenshot's cause.


## 实际第二阶段结果

1.56 MiB 的新系统截图在单次输入后 1494.4 ms 取得原节点 10.2964→18.5335 的正向开始，原 page closure 与候选 journal 均记录。原40 KB样本没有历史中间值日志，仍不能把“太快”写成已确定根因。此次已证明原观察器能在该真实场景取得开始，不证明所有小图都有足够窗口。

完成阶段的阻断独立于开始：原图带ICC/cICP，页面预览重编码；显式sRGB+willReadFrequently路径相差108932个RGBA通道（总6148032，每个只差1）。同一原件与同一原预览的单变量只读对照，去掉willReadFrequently、保留显式sRGB，Offscreen及HTML均严格像素hash相等。最终源码移除该提示，未增加容差。实际输入运行仍为旧提示代码，原op已invalid/UNKNOWN；新代码没有重新输入或回填旧proof。完整SC-COMPLETE仍FAIL，待独立新截图复测。
