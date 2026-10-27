# uploadStarted v1 · Core / 本地 Codex 共享接口

2026-10-27。用户批准的 [交互契约](INTERACTION_CONTRACT_2026-10-27.md) 已进入 Core/UI/App 实现。本页是当前 Swift 接口与接入条件，不是真实 Web 开始证据或生产准入。root 已在 [PR #1 的协调记录](https://github.com/haohongfei2001-png/Riftlet/pull/1#issuecomment-6437363795) 发出最小契约；未假定本地 Codex 已确认或完成实现。

## 1. 最小接口，不重建 transport

保留 `AttachmentAdapter.captureTarget / validate / append / reconcile`，只增加一个回执 outcome 与可选证据。现有无该字段的回执仍可解码。

```swift
TransferReceipt(
    operationID: operation.id,
    assetID: asset.id,
    attempt: operation.attempt,
    assetSHA256: asset.sha256,
    target: operation.target,             // 完整原 TargetLease，不能重新捕获
    outcome: .uploadStarted,
    profileID: completionProfileID,       // 原适配器/完成 profile
    attachmentID: observedAttachmentID,
    positiveReady: false,
    belongsToOriginalDraft: true,
    hasError: false,
    isUploading: true,
    safeToRetry: false,
    reason: boundedReason,
    uploadStartEvidence: UploadStartEvidence(
        version: 1,
        profileID: reviewedStartProfileID, // 开始准入，独立于完成/失败
        signal: .correlatedProgress,       // 或 .correlatedByteRequest
        evidenceID: originalObservationID,
        inputCount: 1
    )
)
```

所有身份字段必须与持久原操作相等：operation、asset、attempt、hash、完整 target（含 session、document、composer、draft identity）。`attachmentID` 必须非空且 ≤1024 UTF-8 bytes，`evidenceID` 非空且 ≤256 bytes，start profile 非空且 ≤128 bytes。观察 ID 不包含聊天文本、完整页面 URL、认证资料或用户截图内容。第一份获准开始证据持久后，其他非空 attachment ID 的回执被拒绝。

这些字段是**适配器的证据声明**；`ReceiptPolicy` 仍要使用代码持有、经独立审查的 surface/profile 注册表。页面不得通过 JSON 自行指定一个受信任 profile 或 safe-retry 权限。Web 观察 JSON 的版本/严格字段解码由本地 Codex 在自己的分支增量实现，并提供旧回执兼容测试；本轮未改 Web decoder、页面源码或 Chrome transport。

## 2. 开始、完成、失败分别准入

| 权限 | 生产 registry（默认空） | 显式生成图片验收 registry（默认空，synthetic-only） |
| --- | --- | --- |
| 视觉退出 | `uploadStartProfiles` | `syntheticUploadStartProfiles` |
| 最终成功 | `admittedProfiles` | `syntheticAcceptanceProfiles` |
| 安全失败/可再次点击 | `retrySafeProfiles` | `syntheticRetrySafeProfiles` |

普通收录模式仍使用 `UnavailableAdapter`。现有 `--web-acceptance` 只保留已审查的生成图片**完成** profile，没有自动增加开始或安全失败 profile。离线 `--simulate` 另要求 simulation store、synthetic asset、simulation target/adapter、`simulation-v1` 以及 `simulation-upload-start-v1`；这些标签不能用于真实 Web 或系统截图。

有效开始必须是**原操作唯一一次图片输入已经进入原目标上传流程**的正向事实。单独 click、dispatch intent、`input.files`、`change`、占位图、删除按钮、普通 DOM 变化或 `isUploading` 布尔均不够。所选 progress 或 byte-request 判据需要真实源码、图片/目标身份链、相邻反例和精确范围。Core 不通过等待时长推导开始、成功或安全终止。

安全失败还需要原附件的强失败证据与**旧操作不再可能生成重复附件**的终止事实。超时、失焦、刷新、观察器丢失、用户主动删卡、网络 abort 的孤立日志均不自动证明可重试。失败回执必须 `hasError && safeToRetry && belongsToOriginalDraft && !isUploading && !positiveReady`，并通过独立失败 profile；完整身份和 attachment ID 仍须一致。

## 3. 时序与持久化

1. Coordinator 保持先持久 `dispatchIntent`、后唯一一次 `append`。
2. `append` 得到获准正向开始后即可返回 `.uploadStarted`，无需等待最终 READY。Core 将第一份回执写入 `upload_starts`，与 `visibility = swallowed`、reason `uploadStarted` 和必要操作阶段更新放在同一事务；不写 `succeeded/used`，不删文件、不授予再输入。
3. App 刷新已提交状态，UI 执行短吞噬与补位。输入队列可以继续处理**已经证明不冲突**的其他目标；相同/不明草稿锁不因开始而解除。
4. `reconcile` 只观察该原操作。App 有界轮询未决操作，后续 READY、UNKNOWN、强失败分别更新后端事实。UNKNOWN 不覆盖第一份开始审计，不自动 append，不让已吞噬图重新出现。
5. 最终 READY 记录成功，已隐藏图片不再播放动画。兼容旧适配器的 READY 若未曾有 start，只以 `legacyCompletion` 静默退出；这不冒充新体验验收。
6. 获准安全失败让 visible/swallowed 图片以原顺序恢复为普通可点击图片；下一次输入必须来自新的用户点击。用户先行 remove/archive 的意图优先，不被迟到失败覆盖。
7. 成功后的关联错误保留原成功及补偿审计；没有安全终止准入时仍内部隐藏、待核实。旧 attempt/错目标/错附件回执不能复活新尝试或别图。

SQLite schema v3 保留 v1/v2 资产、原操作、回执、补偿、顺序和私有媒体，新增可见性、原因、修订号、闲置锚点和第一份开始审计。迁移整体事务化；没有从旧 `used` 捏造 start。旧成功及不安全补偿迁到内部，未开始的 UNKNOWN 保持原可见性。已升级数据库不要交给仅支持旧 schema 的二进制；旧数据和备份保留，不清库绕过恢复问题。

## 4. 本地 Codex 下一次交接的最小证据

- 在自己的 Web/Chrome 分支实现观察、归一化和早返回；不争写 Core/UI/App。记录实际已测 SHA、页面/归一化版本、受支持 ChatGPT/Chrome 范围。
- 给出 input=1、原 asset/operation/attempt/target/attachment 身份链、真实 start 早于最终成功，以及点击/文件设置/占位但未开始的反例。
- UNKNOWN、导航、真实中断、迟到失败、旧观察器丢失按实际命中范围分别记录；未实际命中继续 `NOT_EXERCISED`。安全失败必须单独证明旧操作已终止，不能借成功证据准入。
- 保留既有冷首击/ACK、真实 A→B→A/同 URL 草稿、MID、物理 N1、截图自包含/延迟及资源测量任务；本轮合成 UI/状态机结果不关闭它们。
- root 独立审查并集成后，只改适配器/策略组合的获准 profile；无需再改截图收录、SQLite 可见性或裂缝动画。生产准入仍由对应真实证据决定。

## 5. 可直接运行的隔离演示

在 macOS 构建：`bash scripts/build-macos.sh`，然后 `open build/Riftlet.app --args --simulate`。也可使用本轮 CI artifact 中的 development App；它是 ad-hoc 工程构建，未公证/发行。

菜单明确显示 **SIMULATION — no real uploads**，数据使用独立 `Riftlet-Simulation` 目录。第一次、第二次、第三次输入依次演示：开始后延迟成功、开始后延迟安全失败重生、开始后 UNKNOWN 保持内部隐藏。每次模拟输入使用明确独立的 synthetic 草稿；这不是同一真实草稿并发已获准。模拟延迟是开发参数，未作为真实上传速度证据。重生图可直接再次点击；第四次输入演示下一轮成功。菜单可追加 3 张生成图，不清除旧 UNKNOWN。

`Hide rift` / `Show rift` 持久保存隐藏意图；新增图、唤醒和重排不能解除。`Local screenshot history…` 查看分页历史、待核实/已吞噬/归档/真正失败/移除，恢复动作由 Core 复核资格；UNKNOWN 不能借恢复入口重新输入。右键移除、清空可见队列均不删除图片或 ChatGPT 附件。归档时长可在菜单或 `lifecycle-settings.json` 调整/关闭；24 小时仅为明确可调的工程起点，不是新批准的固定产品参数。

软件面板测试可证明状态接线；物理点击穿透、焦点、真实全屏/多屏、系统 Screenshot.app 自包含与实际延迟仍要由本地 Mac 验收。

## 6. 当前已验证工程输入

`d834a3a4a76cacedd0cb763044085c9c2093680c` / [完整 macOS CI](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40479556833)：287项原生，生命周期详细13 passed /0 skipped，Release/签名/三个自检通过。可运行制品见[artifact](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40479556833/artifacts/12721893223)；完整来源与失败修复见[本轮记录](../engineering/evidence/2026-10-27-interaction-lifecycle/README.md)。本页所在的后续文档检查点保持该构建输入不变，最新正式HEAD由PR #1指向。真实start/安全终止仍待本地Codex，未因CI准入。

## 7. 第四轮合流后的直接接入要求

第四轮 `c9c68a6` / `03a67cc` 已与 `b848920` 的生命周期合流；最新完整工程验证及正式检查点见 [INTEGRATION_HANDOFF](INTEGRATION_HANDOFF.md)。第6节保留此前测试来源，不代表第四轮源码已由该旧运行验证。当前捆绑页面是 v8，保留 v6/v7 **只读原操作**观察；新 Core 识别独立 persisted UUID profile，但 local/persisted 跨 profile、旧 nil/未知身份仍锁同 tab。所有旧 UNKNOWN、媒体、回执及补偿保留。没有新增生产或 synthetic 开始准入。

本地 Codex 从 PR #1 最新正式 HEAD 建独立分支，直接修改自己的 Web 页面程序、版本化 observation/严格 decoder/normalizer 和 `WebAttachmentAdapter` 的观察循环，不重新实现 Core/UI/App：

1. 用原输入的 asset/operation/attempt/hash/完整 target 与唯一 attachment 身份，证明实际 progress 或实际字节请求属于该输入。提供真实源码、开始之前的反例、唯一 input=1、开始→最终 ATTACHED 时序；`inputTriggered`、files/change/占位图不能改名成开始。
2. 新观察结构采用显式版本，严格拒绝缺字段、未知字段/枚举、错身份、伪造或不完整开始，保留现有 v1 及旧 v6/v7 原操作只读恢复。start profile 由已审查 native 代码持有，页面不能自行授予信任。现有 v1 `started` 计数不是本契约的回执。
3. 一旦归一化得到可供策略评估的 `.uploadStarted`，`append` 立即返回该回执，不能继续等原来的最终完成轮询。后续仅 `reconcile` 原操作；不重发 begin/commit、不新捕获目标。正常/UNKNOWN/迟到失败均保留第一份开始事实。先提交拟用的 synthetic-only start profile 与实际依据，由 root 审查组合；不要争写 App 准入注册表。
4. 在合流后的 v3 App 上实际记录一次输入、获准开始、持久隐藏、可见消失、较晚 ATTACHED/UNKNOWN，证明早返回没有造成重复输入。真实开始与安全终止分别提供证据；成功不授予重试。旧 absence-only 或单独 POST100 abort 不足以重生。

用于同时测量首击的最小诊断接口已经落地：`WebAttachmentAdapter.captureTargetWithDiagnostics(context:)` 返回原 target、完整 target 的 sorted-key JSON SHA-256、`adapterValidatedUptime`；`CaptureInvocationContext` 的 requestID / armAttemptID / hostEpoch 只在宿主传递，**不编码进页面命令**。native 日志按同一 requestID 给出 received / validated / MainActor-return，App 记录实际 publication、effective 原 ACK、是否复用和原始选择事件；native 时刻不直接随返回对象传递，也不能靠重复 digest 拼接不同请求。

保持 `--web-acceptance --acceptance-trace` 显式生成图验收。只有 scheduler 接受当前 epoch/session 后才发布；同 lease 保留有效旧 ACK 的 requestID。`effectiveAckUptime` 与 `mainPublishedUptime` 是赋值前后分别采样的观测边界，其极小间隔本身不是 publication race 证据。未实现 mailbox，不等待/回放冷点击，不改变严格 ACK 先于原事件规则。

第四轮真实成功只是**已预绑定、空正文/零附件、编辑器未聚焦的一个普通已有会话**。冷首击、业务 ABA（含已保留的无可观察反例）、非空正文/旧附件/选区保留、MID、物理 GUI、系统截图自包含与完整延迟继续开放。普通捕获仍不使用 Web 上传；新版快吞噬的真实验收尚待这一接入。

第四轮合流验证补记：`c85020b` 的 [完整macOS CI40484855920](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40484855920) 已通过306原生、48页面/14legacy、13生命周期逐项passed及Release/签名/三个自检；完整来源见[当前集成记录](../engineering/evidence/2026-10-27-integration-round4/README.md)。这是工程接线验证，真实Web start与快吞噬仍未运行。
