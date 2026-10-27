# 第五轮 App 快速吞噬接入与诊断建议（交 Pro）

2026-10-27；最新只读核对 HEAD `1f9dec2dec9cf6ef61f36776a6e4f7c3439f4f8a`，已合并 Pro 正式提交 `e89d49f763036781c90618422da256e03cbca2ac`，并保留第五轮 adapter 工作。`git diff e89d49f -- Sources/RiftletCore Sources/RiftletUI Sources/RiftletApp` 为空，确认这三处正式源码与 Pro 一致。下列行号按此 HEAD 的未应用 overlay 源码定位。本文件前期提案现已有更新：正式 Core/UI/App 源码仍未修改；两个独立临时构建已应用补丁，最终 53ebcc4 的真实 synthetic start→AppKit close→独立最终成功通过，详见 [最终报告](README.md)。本文件下文保留提案时的接口分析，不构成生产准入。依据：`docs/UPLOAD_STARTED_CONTRACT_V1.md`。

## 原提案接线与阻断（以下为前期设计记录）

1. `RiftletMain.swift:180–238` 已将原选择冻结、selection boundary、交互锁、Coordinator.onChange→refresh 接入实际 App。`refresh():493` 将仍有 row 的 retired asset 纳入 snapshot，因此已吞噬记录可以送到 UI。
2. `QueueStore.apply:330–337` 对获准 `.uploadStarted` 在同事务中存第一份 `upload_starts`、设 `.swallowed/.uploadStarted`，阶段保持未决（通常 `.inputTriggered`）。`RiftPanelController.render:382–419` 见到 visible→该状态才启动短动画；默认配置 0.120 秒，实际遵循减少动态效果。最终 READY 不重复吞噬；只有 READY 的旧适配器走 `legacyCompletion` 静默退出。
3. **实际 Web App 尚缺 start 策略接线。** `RiftletMain.swift:234` 只有 `syntheticAcceptanceProfiles`；start registry 默认空。即便 adapter 返回合法 start，当前 Core 也会按未准入设 UNKNOWN，不能据此验收快吞噬。普通 capture 模式仍为 `UnavailableAdapter`，不是生产系统截图上传模式。
4. **同草稿 different asset 仍阻断。** `QueueStore.markDispatchIntent:254–264` 检查全部非 prepared 未决操作；`Models.swift:145–152` 相同 logical ID 冲突，没有 asset 例外。第一图 start 后仍未决，第二图无法持久 dispatch intent。`TransferCoordinator.drain:156–160` 捕获 `targetBusy` 后 `cancelIfPrepared`，不等待旧上传、不自动继续该次点击。这不是重复选同图的防抖。
5. `completionWatch:246–253` Web 每 5 秒最多观察 4 个 pending；早返回后，后端成功较晚被 Core 看见是可能的。必须区分页面真实 READY、adapter 观察到 READY、Core 持久 READY，不把轮询间隔算作上传耗时。

新版 Pro 的 capture publication 接线已正式存在（App:357–424）：每次 arm 生成 `CaptureInvocationContext`，调用 `captureTargetWithDiagnostics`，串起 requestID / armAttemptID / hostEpoch / targetDigest / adapterValidatedUptime；在 scheduler 完成且 epoch、前台 session 可接受后记录 `mainPublishedUptime` 与 publicationResult。相同 target 复用时保留原 effective ACK 与对应 capture identity，新 publication 时间不改写原 ACK。App:306–322 的 freeze 仍仅使用已发布 ArmedTarget 和原 NSEvent 时间，native 诊断早到不授予点击权限；App:438–463 已记录原事件、handler、冻结结果/拒绝理由、effective/in-flight request ID。这些是**现有正式源码接线事实**，不是本报告新加功能或本轮运行 PASS。它们不解除第 4 点的同草稿未决锁。

第 4 点与现有上传开始契约 §3.3 一致：“相同/不明草稿锁不因开始而解除”。若产品要求第一图尚未 READY 就连续点击第二图进入同草稿，这是当前明确未达成项，需要 Pro 单独裁决。不能只排除所有 `.inputTriggered` 或按 swallowed 跳过锁；这会影响 UNKNOWN、未获准开始、旧操作迟到副作用与附件关联安全。本报告不提出未经审查的锁放宽补丁。`InteractionLifecycleTests.testRunnableSimulationSeparatesEarlyExitFinalSuccessFailureAndUnknown` 和 `SimulationAdapter.captureTarget` 使用独立 synthetic draft，不能替代同草稿连续输入测试。

## 最小 synthetic start 接线补丁

当前 adapter 工作区已提供**代码持有**的 `ChatGPTWebPageProgram.acceptanceUploadStartProfileID = "chatgpt-web-zh-progress-start-development-20261027-v1"`，并接入候选 ObservationProfile。它只是候选映射，不等于 ReceiptPolicy 准入；必须与归一化器填入 `UploadStartEvidence.profileID` 完全一致，不能读取页面 JSON 自授信任。先由无 start 准入的实际 App 采集真实开始证据，再独立审查其观察、解码、归一化与早返回；通过后才可在临时构建副本应用以下 overlay。

满足此前提后，Pro 可在 `.webAcceptance` 分支作以下唯一策略变化：

```diff
-            policy = ReceiptPolicy(syntheticAcceptanceProfiles: [ChatGPTWebPageProgram.acceptanceProfile.profileID: .webChat])
+            policy = ReceiptPolicy(
+                syntheticAcceptanceProfiles: [ChatGPTWebPageProgram.acceptanceProfile.profileID: .webChat],
+                syntheticUploadStartProfiles: [ChatGPTWebPageProgram.acceptanceUploadStartProfileID: .webChat])
```

不添加 `uploadStartProfiles` 或 `syntheticRetrySafeProfiles`；不动 capture/simulation 分支；完成 profile 不自动变成开始 profile。沿用隔离 Web store 与 synthetic-only 检查。至少添加“生成图通过新 start、系统截图拒绝、错 profile 拒绝、safe retry 仍拒绝”的组合断言；已有 Core policy 测试不证明这个 App composition 已接对。

## 实际 App 最小事件链与 overlay 范围

已生成 [app-acceptance-overlay.patch](app-acceptance-overlay.patch)，在新 HEAD `1f9dec2dec9cf6ef61f36776a6e4f7c3439f4f8a` 上再次执行 `git apply --check` 通过，独立范围审查通过；截至本次文档修订，补丁**未应用、未构建、未完成运行验收，候选 start 未准入**。它不是 Pro 正式 App 源码改动或生产启用。补丁保留原 hunk 行号，由 git 按上下文适配新位置；本次未重制 patch。补丁只包含 App 的 synthetic start registry、UI 默认空诊断回调与 App 日志接线，不修改 Core 事务。下表中的 Core 精确 commit hook 与 Coordinator prepared hook 仍是后续协调建议，均不在该 overlay 内。

复用 `--acceptance-trace` 与 `recordAcceptance` 的有界单行 JSON sink，不新建 GUI 工具、不轮询屏幕、不靠动画配置值猜完成时间。建议共享字段：runID、assetID、operationID、attempt、visibilityRevision、process systemUptime；target 和 attachment 仅记录本轮盐化摘要。原图、草稿文字、URL、文件路径、认证资料和完整 React props 不进入 trace。日志 cap 命中需要一个闭集 `trace_truncated` 标记，此后该批不可宣称完整时序。

| 事件 | 精确采样点 / 语义 |
| --- | --- |
| `selection_boundary` | 复用 App:438 的原 `eventUptime` 与 callbackUptime、source；mouse 表示 AppKit 路由，不证明真人。追加现有 boundary.windowNumber/clickCount 即可，不读 `NSApp.currentEvent`。按住取消的 boundary 不算已派发选择。 |
| `selection_prepared` | Coordinator.prepare 返回后，记录 asset→operation/attempt 的连接及原选择序号；只读诊断，不另 capture。重点击可能同 asset 不同 attempt，不能仅按 asset 拼接。 |
| `adapter_start_observed` | adapter 归一化首次可信 start 后采样；包含闭集 signal、code-owned profile 与 evidence/attachment 摘要、inputCount。页面 progress 时间只能用页面时钟局部差值，不能直接减 native uptime。 |
| `receipt_commit_returned` | `QueueStore.apply` 的 transaction 成功返回后、尚未离开 actor 同步函数时采样；记录 outcome、result.visibility/reason/revision、firstStartInserted、result.status。必须失败不发成功事件、拒绝 start 不记 `start_persisted`。这是 COMMIT 返回后的采样，不声称存储硬件落盘精确瞬间。 |
| `presentation_boundary / swallowActualStart` | UI:400–410 对实际存在的 row、写入 committed record 后、首次 `animateImage` 前；记录 asset、revision、generation、实际时长与 uptime。render 入口只算请求，hold/selection/transition 可能推迟，不能当动画开始。 |
| `presentation_boundary / swallowClose` | UI:411–418 的 generation 校验成功后，实际移除/close row 时采样；含相同 revision/generation。此时只证明 AppKit 代码路径已移除窗口，不能当屏幕像素呈现完成的测量。 |
| `presentation_boundary / swallowScheduled` | 现有 hold/selection/transition deferral gate 已通过、swallowed rows 已确定后，在逐行启动动画前记录。这不是 render 首次收到状态的时间；可能紧邻 actual start。 |
| `ready_commit_returned` | 同一 Core post-transaction hook，只在实际结果 `.used`/operation `.succeeded` 且对应完整身份回执获准时记录。重复 reconcile 的 READY 可标 repeated；不把未获准 `.verifiedReady` 当成功。 |

实际 overlay **没有 cancelled 回调或额外取消状态机**。hide/reflow/close/reset 使原 completion guard 不通过时，不产生 `swallowClose`；缺少 close 只能判为未观察到正常关闭，不能仅凭缺失日志确定取消原因或宣称完成。三种 phase 都含 assetID、可选 operationID、visibilityRevision、generation、uptime、actualDuration；actualDuration 是本次传入动画的时长，不是像素完成实测。

精确最小接口建议：

```swift
// UI：public enum/struct，默认空，Pro 在上述三个实际分支调用。
public enum RiftPresentationPhase: String, Sendable {
    case swallowScheduled, swallowActualStart, swallowClose
}
// 字段：phase, assetID, operationID?, visibilityRevision, generation, uptime, actualDuration。
// controller init 新增 onPresentationBoundary: (RiftPresentationBoundary) -> Void = { _ in }

// Core：QueueStore init 新增默认空同步诊断 sink：
// onReceiptApplied: @Sendable (ReceiptAppliedDiagnostic) -> Void = { _ in }
// 字段：operationID, assetID, attempt, requestedOutcome, resultStatus,
// resultVisibility, resultReason, visibilityRevision, firstStartInserted, uptime。
```

以下 Core hook 仅保留为将来需要准确 commit-return 采样时的建议，**当前 overlay 不实现**。Core 实现保持 `apply` 返回类型 `AssetRecord` 与现有事务内容；将 `try database.transaction { ... }` 结果绑定为局部值，事务返回后立即采 uptime/调用有界非阻塞 sink，再 return 原结果。`firstStartInserted` 在事务内依据首次审计是否已存在记录局部布尔，但不在事务内输出外部日志。sink 不 await、不重入数据库、不读 GUI、不让日志失败传播到业务；App 若经 MainActor 转发只保留源时间，不用转发时间冒充 commit 时间。同步 sink 需明确线程安全，默认关闭。避免同步写磁盘拖慢动画；复用有界缓冲后统一写 JSON。

若本轮不愿改 Core，则 Coordinator 在 `store.apply` await 前后采两个 uptime，并核对已存 start，**只能输出 commit 所在区间及上界**。App refresh 看到吞噬的时间也是可见状态观察上界；`upload_starts.started_at` 在事务内部写入、且为墙钟，不是准确 COMMIT 时刻。不能把这些替代值标成精确持久化时间。准确 UI 回调同理不可由外部 helper 的轮询时间替代。

当前 overlay 选择最小观察方案：在 `refresh` 已有 store awaits 全部返回后采 `snapshotObservedUptime`，以 `committed_visibility_observed.commitUpperBoundUptime` 记录已提交可见状态上界，以 `ready_persistence_observed` 记录成功操作查询结果。多次读取不是原子多行 snapshot，重复观察也不是重复发生；日志不声称直接读取了首份 start 审计。没有增加 await、额外 DB 查询或 render 前重计算。

测量开销：overlay 复用现有有界单行 JSON / stderr 同步日志；编码、采时钟及写入会延长当前 MainActor 回调，阻塞的日志接收端也可能增加延迟。结果属于**启用诊断的构建**，不能标成零开销性能基线。尤其 `swallowActualStart` 的采样发生在该条日志写出、随后 `animateImage` 之前，包含日志至动画调用的微小间隔；`swallowClose` 则在实际 close 返回后采样。保持小批量与可正常消费的本地 sink；不为估计开销额外发输入、改动画时长或新增等待。日志达到 2048 上限后，缺失事件不能算成功；本 overlay 沿用现有 cap，不新增 cap 通知。

从事件链输出：原 click→start observed、start commit-returned→UI start、UI start→row closed、start commit-returned→ready commit-returned；保存原始值和缺失/取消理由。READY 可能比 UI 动画结束更早，不要求人为制造 `closed < READY`；需要证明 UI 触发依赖 start 而非 READY。

## 现有 helper 的角色与最小验收

`RiftletGUIAcceptance/AcceptanceMain.swift:330–384` 已复用产品 `RiftPanelController`，有真实选择边界和下层 probe；但 outcome dropdown 目前仅以 `SyntheticScene.displaying` 切换状态，日志明确 `receiptEvidence:false`。它没有真实 QueueStore、adapter、upload-start 审计链，不能测实际 App 持久化或 Web 上传速度。

无需增加第二个 App 或传输工具。本轮可只让实际 App 接上上述诊断。若 Pro 提供 UI callback，helper 可独占追加对应事件记录，保留 `syntheticOnly:true/receiptEvidence:false` 用于动画回归；不要在 helper 伪造真实 Web start、用固定 350ms 定时器充当上传证据。本报告尚未编辑 helper。

建议一次合并验证：synthetic 真实上传的首份 start→吞噬→READY；start 后 UNKNOWN 保持内部；隐藏/hold 中 start 的 deferred/cancelled 路径；同草稿第二图在第一图未决时明确记录当前拒绝且 appendCount 不增；旧 READY-only 路径标 legacy；重复 start 不重复动画；重开后 start 审计仍在、无重新 append。`RiftLifecycleTests` 已覆盖状态触发吞噬与 READY 不重播，但没有实际 App 完整事件链，不能提升为本轮真机 PASS。
