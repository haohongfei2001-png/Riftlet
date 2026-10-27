# 同草稿连续点击：现状、复现信号与最小接口提案

2026-10-27；只读核对基线 `3bb13999b0f444c7748804eef1976e179a52a85e`，未合入 Pro `2449d40`。本文及隔离 lab 不修改 Core/UI/App，不启用上传或改动准入。前半部分是源代码分析和待实施接口；末节现已补入一次真实同草稿 targetBusy 复现，未验证双图上传通过。

## root 的最小真实复现窗口

复用已授权批次和既有 helper；本文不要求额外生成/上传。只有 root 操作 GUI/浏览器。

1. 同一原草稿、两张不同的可见生成图 A/B。记录两次原选择的 target digest、operationID、assetID、attempt。不能仅按 URL 判断同草稿。
2. 一次选择 A。最有区分力的窗口是 A 已有持久 `upload_starts`、visibility=`swallowed`、reason=`uploadStarted`，但 operation 仍为 `inputTriggered` / `attachmentPresent` / `unknown`，未 `succeeded`。等实际吞噬/补位过渡完成再点 B，避免把动画输入门与后端锁混为一谈。不能凭 0.120 秒默认值或历史 0.24 秒配置推测过渡已经结束。
3. 对仍 visible/pending 的 B 只做一次既有 helper AXPress（软件输入、physical=false）；不重新输入 A、不删除旧 UNKNOWN、不改变目标来绕锁。
4. 当前代码的可判别链：B `selection_boundary` 且 `freezeResult=accepted` → durable prepared → failed，原因精确为 `Original draft has an unresolved upload; no input occurred`。B 应无 `dispatchIntent` / 页面 `begin` / input；A input 仍为 1。prepared 可能过快而被轮询漏过，最终 reason 加代码路径可作定位，但不得声称实际采到了缺失的中间快照。
5. 无 B selection_boundary：检查 UI transition/hold/duplicate gate，不能称 targetBusy。freeze refused：原 ACK/epoch/前台问题，不能称后端锁。出现 `Original target changed before input`：页面复核失败早于锁检查。出现上述 unresolved reason 才能归因现有 conflict 路径。若 A 在 B markDispatchIntent 前已 succeeded，窗口错过，不能把 B 成功当成 start 阶段解锁。

真实信号应来自闭集原生日志、原 operation 状态/原因、原页面 inputCount；仅 helper AXPress 返回成功不证明 UI 接受或真正输入。公开证据保留 digest，不公开完整 target、URL、聊天或机器路径。

## 三层因果位置

| 层 | 基线代码 | 实际行为 |
| --- | --- | --- |
| UI | `Sources/RiftletUI/RiftPanelController.swift:565` / `:610` | mouseDown 与 AX 分别检查可见性、状态、transition、该 asset 的 selectionVersions；AX 另检查没有持有鼠标。选择占用按 asset，不因 A 的 transferring 直接禁止 B。 |
| UI 完成选择 | 同文件 `:349` | durable prepare 后解除对应 asset 选择占用；hold/重排仍受既有 interaction fence 管理。press 动画的 trackAnimation 不等同于 transitioning。 |
| App | `Sources/RiftletApp/RiftletMain.swift:181` / `:306` | 原 press 同步 freeze；onSelect 同步取走 frozen lease，再进 Task。Web 无 frozen target 即拒绝，不在点击后 capture。 |
| Coordinator | `Sources/RiftletCore/TransferCoordinator.swift:59` / `:90` / `:129` | 每 asset selecting 防重；首次 await 前取 FIFO ticket；prepared 持久后进入 waiting；单 drain 串行调用 append，早 start 返回可以推进 drain。 |
| Core 锁 | `Sources/RiftletCore/QueueStore.swift:254` | 同事务检查所有非 prepared 的未决操作；conflictsForDispatch 为 true 就 targetBusy。不会按不同 asset 或已有 upload_starts 例外放行。 |
| 冲突身份 | `Sources/RiftletCore/Models.swift:145` | 同 session/tab 是粗粒度锁；只有同一受识别 profile 的不同 business ID 才缩小冲突。同草稿同 ID 仍冲突；nil/未知/畸形/跨 profile 均保守。 |
| 当前 busy 结果 | Coordinator `:156` | targetBusy 被内部捕获，cancelPrepared → failed，继续 drain；没有保留 B 排队、没有等待 READY 后重放。App 最后显示 operationReason，而非抛出 targetBusy。 |
| start 与恢复 | QueueStore `:330` / `:361` | start 写不可变审计和 swallowed，但 phase 未终结；restart 取消 prepared，其他未决改为 UNKNOWN，仅 reconcile。 |

因此“把 selecting 移除”“缩短 UI 动画”“append 早返回”均不能单独修复同草稿连续点击。当前 `UPLOAD_STARTED_CONTRACT_V1.md` 第 3 节明确相同/不明草稿锁不因 start 解除。产品要求其他图不无限阻塞，但这是待解决的契约缺口，不能改名为已经可用。

## 最小可落地的第一步：只等待既有锁解除

这一方案无需扩大 start 的安全含义，仍可能要等 A READY；它改善 B 一次原点击被 targetBusy 丢弃的问题，不宣称达到自然连续输入速度。

新增不可变、非 Codable 的进程内 `AcceptedSelection`：

```swift
struct AcceptedSelection: Sendable {
    let selectionID: UUID
    let assetID: UUID
    let visibilityRevision: Int64
    let source: SelectionSource // mouse / accessibility；不推断物理真人
    let eventUptime: TimeInterval
    let acknowledgedUptime: TimeInterval
    let hostEpoch: UUID
    let target: TargetLease    // freeze 返回的完整原 lease，只读
}
// App 同步 freeze 成功后构造；不存在 ACK、ACK >= event 或取消 hold 均不构造。
// onSelect 只提交当前被接受边界对应的 token，不沿用后来最新 armedTarget。
func select(_ selection: AcceptedSelection) async throws
func invalidateQueuedSelections(epoch: UUID) async
func pendingFactsDidChange() async // 仅唤醒已有队列，不生成新选择
```

必须由同步 App 边界产生 token，普通调用方不能自填历史时间“补证”。token 与鼠标释放成功/AX 原调用绑定；取消 hold、hide、close、stop、host epoch 失效立即作废尚未 intent 的项。序号仍在首次 await 之前取得。UI 的 pending/transferring 与压下姿态处理维持现有语义，不把等待变成吞噬。

Core 可只增加只读阻塞查询，原事务门保持不变：

```swift
func dispatchBlockers(for preparedOperationID: UUID) throws -> [UUID]
// 必须与 markDispatchIntent 使用同一 conflictsForDispatch 谓词。
// 仅用来决定 park；最终输入仍必须由原 markDispatchIntent 原子提交。
```

Coordinator 不能像现在先 remove waiting/advance ticket 后把 busy 当失败：peek 当前项，复核原 token、revision、epoch；如果存在 blocker，将当前 prepared item park 并退出 drain。不要在 actor 里等待 READY、sleep 或忙轮询。已有原操作 reconcile/apply 后的事实变化唤醒 drain；记录阻塞 operation IDs 只为诊断。其他 target 被 head 阻塞的问题可先接受并说明，不能悄悄改全局 FIFO；若未来按 serialization lane 调度，另做顺序测试。

被唤醒后只用该项原 lease `adapter.validate(original)`；若 epoch/revision/visible/target 已失效，cancelPrepared，保留图片且需要新的实际点击。只有 blocker 已解除、原 token 仍有效，才原子 markDispatchIntent，再 append **一次**。这叫完成尚未输入的原点击，不是对已输入操作重试。不可调用 captureTarget，不能用最近 ACK 替换 queued target，也不能把 timeout 改成放行。

A 终结不保证 B 可输入：页面新 generation、导航、模态、旧卡移除、失焦/可用性撤销都可能令 B 原 lease 失效。当前页面 validate 要求命中历史精确 lease 且仍为 registry.tail；commit hash await 后还会 drain+复核，再在无 await 的 setter/change 段输入。保留这些门，失效就取消，不重新 capture。现有业务无可观察 ABA 残余仍不因排队消失。

同一 asset 已有非 prepared 未决操作，仍只能 reconcile，不能新建 attempt。提交 intent 后，无论 transport 成败、取消或进程退出，都不能再执行 append。重启不恢复 token；沿用 recoverInterruptedOperations 取消 prepared、只观察 intent 后原操作。等待不永久保留：stop/hide/epoch/移除立即取消；可定义有界等待期限（待工程选定），到期取消而不是换目标或输入。

## start 后何时可放行不同 asset

| 状态 | 当前基线 | 第一阶段提案 |
| --- | --- | --- |
| A/B 已证明不冲突的不同目标 | 可以串行输入 | 保持既有事务检查 |
| 同草稿 A 只有 intent/input/placeholder | 拒绝 | park 或取消；绝不当开始 |
| 同草稿 A 获准 start，仍 inputTriggered/attachmentPresent | 拒绝 | 仍 park；start 不是草稿锁豁免 |
| 同草稿 A UNKNOWN/compensated；即使保留 start 审计 | 拒绝 | 仍 park/有界取消；不可重输 A |
| A succeeded 或已独立准入的安全终止 failed，且无其他 blocker | 可输入 B | 验证 B 原 token/lease 后仅输入 B 一次 |
| 旧未知身份、跨 profile、同 tab 不明草稿 | 拒绝 | 不回填/不迁移/不缩锁 |

若产品要在 A start 后立刻输入 B，需 Pro 审查第二阶段的**不同资产输入隔离能力**，它不是 retry grant，也不能复用 uploadStartProfiles。建议最小候选：代码持有、默认空、限定 adapter/surface/profile/build 的 `serialDistinctAssetAfterStart` 能力。QueueStore 原子意图事务只有同时满足下列条件才可例外：A/B 不同 asset/op；A 首份 start 审计身份完整且获准；A 尚处于明确定义的正常 started 阶段（UNKNOWN/compensated 不自动豁免）；同一受识别 business draft 和 profile；B 原点击 lease 有效；没有任何第三个未知/旧 wildcard blocker；输入 drain 确认 A 的 append 已返回，B 只输入一次。**基线没有这个能力，本文不提供绕过现有锁的补丁。**

能力准入还需要真实双图证据：每次 setter/change 对应自己的 op/hash/name/card，第二次设置 input.files 不撤销或替换 A，A/B 分别保留独立 start/READY/late-failure 观察，文本/旧附件/选区保留，错误与 UNKNOWN 不串号，页面业务 identity 连续，关闭/导航/重启不再输入。单图 start 成功、最终成功、模拟不同草稿或“JS 有 Map”均不够。若还要让 hidden UNKNOWN 不永久阻碍其他图，必须另证明旧操作与新输入的隔离及终止/非重复界限；不能仅凭历史 start 放开 UNKNOWN。

## 最小测试接口与当前交付

隔离 `lab/consecutive_click_model.py` 是纯调度提案模型，`python3 .../lab/consecutive_click_model.py` 可运行，不链接正式 Swift、不接数据库/浏览器、不上传。它接收既有 Core 的 blocker 结果，不发明 start 解锁规则。覆盖原 token 有效性、start 后继续阻塞、READY 后原 token 一次发出、冷事件/取消/epoch/revision/lease失效拒绝、重复点击防重、intent 后不重放、restart 不恢复。

Pro 实施时仍须在正式 Core tests 加真实 QueueStore/Coordinator 测试：同草稿 start 后 busy 保留 prepared、reconcile success 唤醒且原 target 未变、等待中 user remove、validate 与 markIntent 间新增 blocker、无 capture、同 asset重复选择仅原操作观察、跨 profile/旧 UNKNOWN 仍锁、restart prepared 不 dispatch、晚失败阻塞新 intent、输入中的取消不再 append。若只实现等待版本，不得把它标成 start 后同草稿连续上传准入。

本次实际执行：上述纯 Python 调度模型 **10/10 通过**，`git diff --check` 通过。模型不含正式 Swift actor/SQLite 事务、真实页面或 AX，且不模拟新点击驱动的安全重试；不是 Core 实现验收，也不是同草稿上传通过。未运行新 GUI、Chrome、上传或原生构建。


## 本轮真实复现：B 被接受，但同草稿未决锁阻止输入

配套脱敏记录：[consecutive-click-evidence.json](consecutive-click-evidence.json)。实际源码 `7878de3138d1c140369c3cfbe69a28dd2770294c` 加 round5 两个已知临时 overlay（AX metadata、App start/呈现诊断）；executable SHA256 `6119a6fb872f7e5cd380d1d234955d2e14e6e8f48d80bbaaeda35afcd5ea91ee`。运行来源由协调方提供；此分析仅只读已有文件与 SQLite `mode=ro`，没有点击、页面操作或 DB 写入。

A 为 `D1871E45-5FB8-4F8E-9BAD-920C4EE8E8A2`，原 op `134D2BC3-19D5-4E87-BAFC-EE8D23195C13`；B 为 `F73A7D51-A241-4657-831E-8636A2EF60F3`，原 op `1232C18C-91CF-4947-806C-066AE8D58FBC`。两次均为一次 helperAX 软件调用、physical=false，前后台进程未变，App freeze accepted。A/B asset、图片 hash 不同；完整 lease 的 documentID/draftGeneration 不同，但私下核对 logical identity 完全相等、adapter/application/session/tab 序列化字段相等。两次 App host epoch 也不同，不能写成同一 lease。公开 JSON 仅留完整 target 各自 digest、logical identity digest 和比较布尔，不公开原值。

| 事件 | host uptime（秒） | 解释 |
| --- | --- | --- |
| A helper AXAction | 462710.782554458 | 原软件输入边界 |
| A 首个 swallowed 提交观察 | 462714.200412333 | 精确 COMMIT 的观察上界 |
| A AppKit actualStart | 462714.200664125 | 代码边界 |
| A AppKit close | 462714.451277917 | 代码边界，非像素采样 |
| B 前 A DB phase 读取 | 462714.760558916 | inputTriggered；不是与 B 点击同一原子读取 |
| B helper AXAction | 462714.812424375 | 比 A 点击晚 4.029870 秒、比 A close 晚 361.146 ms |
| B 首个 transferring/visible 观察 | 462714.814285625 | 点击后 1.861 ms |
| B 首个 failed/visible 观察 | 462714.878007333 | 点击后 65.583 ms |

A actualStart→close 为约 **250.614 ms**，请求仍是保留配置 0.24 秒，不能当作正式默认 0.120 秒实测。B 出现 selection_boundary 且 freeze accepted，因此本次失败不是 UI 按下门拒绝或无发布 ACK。B 首次 transferring 快照没有直接记录 operation phase；prepared 是由既有 prepare 路径、后续 cancelPrepared 专用原因与代码共同定位，不能宣称快照直接抓到了 phase=prepared。

只读 DB 中 B 最终仍 visible/failed、attempt=1、无 receipt、start 审计 0 行，原因精确为 **`Original draft has an unresolved upload; no input occurred`**。这说明草稿锁取消了尚未输入的 B，不是 B 图片上传失败。A 在 B 前读取为 inputTriggered；该锁事务本身也表明当时仍有冲突未决操作。随后只读快照看到 A used/succeeded、首份 start 审计 1 行、visibilityReason 仍 uploadStarted；不能把后来成功倒写到 B 点击前。

从 A AXAction 到批次 finished 的闭区间，native bridge 记录 **begin=1、chunk=13、commit=1、validate=2、captureTarget=6、observe=22**。输入命令均 transportSucceeded=true。begin 排队至 commit 返回约 **1039.036 ms**；首 chunk 排队至最后 chunk 返回约 **893.453 ms**。这些是实际该窗口调用数；bridge 自身不带 op ID，结合该批唯一页面操作 A 和 B 在输入前取消才能归属，不能单凭时间把所有 observe 归到 A。A 文件 3,147,775 bytes，符合 v12 的 12 个完整 256 KiB 分块加 2,047 bytes 尾块；日志本身没有逐块长度，长度分布是源码与文件大小推导，非额外观测。

后取页面快照只有本次 A 原操作，inputCount=1；一次 change 记录 files=1、isTrusted=false、selectionPreserved/textPreserved/cardsPreserved=true，最终 oldCardsPreserved=true。此为 probe 的保留断言，不公开正文或旧附件，不扩展到任意富文本/选区情况。B 没有页面输入操作，不能因 AX 返回成功写成第二图已上传。

**本结论是 B 时 Core 未决锁生效，不以“B 前页面尚未 READY”为前提。** 后取快照中适配器 proofCompletedAtMS 可经 bridge 区间换算，落在 B 后约 4.827–5.092 秒；这是原适配器最终 proof 完成时间的回溯区间，不是 B 点击当下页面视觉或服务器 READY 的直接采样。因此不把它说成已证明 B 前页面未 READY，也不据此量化数据库延迟。

同一 native 日志还包含一次更早、其他 asset 的 noPublishedTarget 冷拒绝，本次双图计数窗口排除了它。最终 A 成功已由只读 DB 确认；日志未见 A ready 事件不作为失败依据。该日志包含其他历史操作、后台反复观察及可能的记录上限，不能拿全日志条数当成本轮输入数。

本轮真实结果确认了前述 Core/Coordinator 阻断位置；没有实施 park 接口、没有再次点击 B、没有解锁 UNKNOWN、没有证明 start 后同草稿连续输入安全。纯调度模型仍仅是提案验证。
