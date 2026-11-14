# QA-ATT-003 / QA-ATT-004 独立复核

复核角色：settings_audit（未编写 attachment.md，未修改产品实现）。基线：`44f745a15ecb3682a9da0bda17f17a5d9fc1f07e`。日期：2026-11-14（Asia/Shanghai）。范围：源码与调用链复核；Linux，无原生 AppKit/Chrome 卡顿或真实附件重测。

## 复核结论

两项缺陷的核心因果链成立。**QA-ATT-003 的 P2 展示整改通过，QA-ATT-004 的 P1 UI 活性风险通过。** 建议按以下约束完善工程指令；当前尚未实现，不能写为已修复。

## QA-ATT-003：START 后被永久算作待核实

独立读取发现：

1. `QueueStore.swift:604–612` 在准入 uploadStarted 后保存不可变 `upload_starts` 并收起微图，但不把 status 改 used，也不把 phase 变 succeeded。
2. `TransferCoordinator.swift:543–544,583–592` 在 independent file input 的 START 后撤销后续观察；`642–644` 也拒绝此类 completed watch。这正是已采纳的“交给 ChatGPT 后结束 Riftlet 附件管理”，不是当前应修的错误。
3. `HistoryPresentation.swift:42–44` 将 transferring 或 unresolved 全部视为 needsVerification；`RiftHistoryController.swift:447–449,474–476` 因而展示「结果待核实 · 不会再次附加」，并附上一段不能确认结果的解释。
4. `RiftletMain.swift:1285` 只从 unresolved 排除 prepared，未排除正常已START，所以每次成功交接会进入 pendingCount。
5. 历史「已附加」筛选按 swallowed 选择（`RiftHistoryController.swift:287,403–405`），与该行“待核实”形成语义冲突。

### 允许的最小修复

在现有 historySnapshot 的事务中加入**只读交接事实**，来源为当前 active operation 关联的不可变 START；UI 显示「已交给 ChatGPT」，需要时一行「上传结果见原对话」。将这一正常交接排除于需要用户处理的 pendingCount。列表、图像网格、筛选、搜索语义和设置提醒必须使用同一个只读投影。

现有 `QueueHistoryRecord`/`RiftHistoryEntry` 只传 lastReceipt，没有传不可变 START（`QueueStore.swift:64–70`、`HistoryPresentation.swift:6–18`），不能仅靠 visibility=swallowed 或最后一条 receipt 猜测交接事实。不要为一条展示文案新建永久数据库状态，也不要重启全程上传监控。

### 必须保留的例外

- **有 START 不代表一切正常**：历史 `compensated`、当前关联的后发错误（`QueueStore.swift:568–592`）仍需提示；媒体缺失也不能被绿色交接状态掩盖。
- 只读 START 与 activeOperationID、operation.assetID、attempt、target、assetSHA256 需要一致。不能拿其他尝试/其他截图的 START 盖住当前 UNKNOWN。
- 单纯“未知完成结果但已证实交接”的记录可显示交接事实；明确关联失败/补偿必须优先显示异常。
- 无 START 的 uncertain input 继续保留待核实，不得自动重传。
- `canRestoreToQueue`（`QueueStore.swift:134–146`）、`canRestoreToRift`（`HistoryPresentation.swift:47–54`）、ReceiptPolicy 的重试准入不能被展示分类修改。START不是READY，也不是retry permission。

### 验收最小矩阵

| 数据事实 | 期望展示 | 是否计入待核实 | 是否因本整改获得重试 |
|---|---|---|---|
| 当前操作有准入START，无后发异常 | 已交给ChatGPT | 否 | 否 |
| 当前操作无START，输入结果未知 | 结果待确认 | 是 | 否 |
| 当前操作有START，后发关联错误但未证明终止/compensated | 需要检查原对话 | 是 | 否 |
| 当前操作已准入verifiedReady | 已附加 | 否 | 否 |
| 准入安全失败 | 附加失败/图片保留 | 按失败呈现 | 只由原有Core决定 |
| 其他旧attempt有START，当前操作未知 | 当前结果待确认 | 是 | 否 |
| 本地媒体缺失且有历史START | 本地副本不可用，可保留交接事实 | 不掩盖缺失 | 否 |

直接复用真实 QueueStore.apply 的记录组合验证，不用 UI 构造器随意指定一个“成功”布尔值。增加原生实际行文与计数截图。由于本轮未执行 Swift/macOS，此处是缺陷独立确认和修复准入要求，不是已完成原生验收。

## QA-ATT-004：鼠标按下同步等待 Apple Events

独立确认链路：

- `RiftletMain` 类型是 `@MainActor`（87），`freezePress` 同步执行 `web.targetForClick()`（1149–1163）。
- `WebClickTargetPinning` 协议和 adapter 方法均是 `@MainActor`（`WebAttachmentAdapter.swift:66–67,203–206`）。
- `ChromeAppleEventsExecutor` 是 `@MainActor`（7），`targetForClick` 在返回 Task 前调用 activeIdentity（44）及 URL（45–46）。返回 Task 之后的 DOM工作虽异步，这之前的ID/URL查询仍阻塞主线程调用栈。
- `ChromePIDEvents.send` 用同步 `sendEvent(options:[.waitForReply],timeout:timeout)`，未传 receiptBudget 时 timeout=5（348–361）；ID和URL的 `get` 没有传该预算（381–396）。
- 常见快路：active tab对象一次get + 指定tab URL一次get，**两次事件**。兼容路径首个get不能解析后另有3次get，最后再URL，共**五次事件**。因此“最长5秒”只适合描述某一次事件的配置超时，不能作为整个点击的总上限。第一项不应答会先等待该事件5秒；多个慢响应可能累计更久。

本轮没有macOS实测，不宜声称所有设备每次都卡5秒、实际UI一定连续冻结精确时长或OS事件泵具体表现；准确结论是主线程同步等待路径明确，符合需要修复的P1响应风险。

### 点击目标不能因性能修复漂移

**拒绝把 `activeIdentity()` 原封不动放到后台排队就算完成。** 该查询使用 `front window` 和 `active tab` 动态对象（400–418），如果真正执行被推迟，读取的是后来的用户选择。后续比较这个“后来取得的目标”与自己不能证明原点击目的地。

可行的最小方向应由原生实验决定：

1. 先为点击边界的ID快照设一个短的整组UI预算，只做取得绝对window/tab身份所需操作；固定ID的URL查询与DOM初始化异步。超预算保持截图、结束该点击，不用后来活动标签替代，也不把旧后台ACK变成首击必需条件。
2. 若采用原生异步reply，必须证明请求在点击边界发起、回复所带绝对ID属于该次选择，并能排除等待期间选择变化；取消、超时、迟到回复都不得再注入。不能把“已创建Task/已入队”当冻结成功。

不预先规定一个无法测量的万能50/100ms阈值；Codex须记录实际正常/慢Chrome的主线程延迟，再选可支持冷首击的预算。该工作有安全回归风险，应独立提交和复核。

### 需要的证据

- 主线程心跳/事件响应采样：目标Chrome迟回或5秒无应答，Riftlet菜单、退出和反馈仍可响应。
- cold first click，无已有relay/ACK；按下后立即换tab/窗口；不同Chrome进程生命周期；连续双图；取消后迟到回复；都仍绑定原目标或安全保留，不自动选后来窗口。
- 同一attempt的input setter/change最多一次；不能因快照超时或原生迟回自动重试。
- 源码和原生计时、目标ID日志相互印证，不以`async`字样或单元测试成功代替原生观察。
