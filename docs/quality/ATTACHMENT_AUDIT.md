# Riftlet 附件链路独立审计

审计人角色：attachment_audit，非产品实现作者。日期：2026-11-14（北京时间）。

## 基线与证据边界

- main：`44f745a15ecb3682a9da0bda17f17a5d9fc1f07e`。
- 最新正式版本：`v1.0.1`，发布源 `5da42a221fb3e6496585c127e6cf11b8e836840f`。
- `git diff --name-only v1.0.1..44f745a -- Sources Package.swift Resources` 为空，本次附件 findings 对应正式版同一套产品源码。
- 当前 JS：`Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js`，SHA-256 `0daf3f2763e340503b8c957c4ef35a619417c5e486ac48fccbcae3f657ff9a09`。
- 已执行：Node v24.22.1，现有 `attachment-entry-handoff.test.cjs` + `ordinary-composer.test.cjs` 共 56 测试通过；另以生产 JS 和仓库的合成 DOM fixture 两次复现 QA-ATT-001。
- 未执行：本机无 Swift/macOS，未运行原生 AppKit、Apple Events、TCC、真实 ChatGPT。尝试独立 Linux Chromium/loopback 实证，Chromium 启动即被环境拒绝 `socket() ... Operation not permitted`，没有进入测试；不算原生通过。
- 原生受控脚本已准备，可在可用 Mac/Chromium 中复跑；此脚本也不能代替真实 ChatGPT。

## Findings

### QA-ATT-001 · P0 · 无归属的异步 picker 能收到截图

**结论：已在受控 DOM 中复现，属于正确附件目的地边界失效；尚无真实用户受影响记录。** P0 指修改后的公开发行准入优先级，并不表示已观测到线上泄露。

**位置与因果链**

- `Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js:499–508`：只要本次入口已有 invoked，匿名 picker 在其他异步活动中调用 `.click()` 且没有可识别的相反 owner，就会进入 captured，哪怕 `owned=false`、`tied=false`。
- 同文件 `617–632`：当 captured 只有一个无归属 picker 时，等到 discovery deadline 后 `if (tied.length || ended) return execute(input, true)` 将“唯一且时间到了”升为可提交依据。
- 同文件 `857–878`：`invoked=true` 还略过 discovery deadline 条件，真正把当前文件设置到该对象并派发 input/change。
- 现有 `Tests/WebPageProgram/attachment-entry-handoff.test.cjs:239–286` 仅覆盖外部活动与后来真实 picker 同时出现等组合；遗漏“真实入口不产生 picker，而无关活动仅产生一个 picker”。

**最小复现**

1. 复用仓库合成 fixture，移除 composer 原 input。
2. 在 composer 放一个可见、可点击的 Add files 按钮；其 handler 只计数，不引用、创建或调用任何 picker。
3. 页面另一个无标记 section 中放一个 file input，使用在 commit 之前安排的独立 timer 调用其 `.click()`。
4. Riftlet 发起当前截图 commit。
5. 约 3 秒后，无关 input 收到本图 FileList 和 change。

复现脚本：`attachment-foreign-picker-repro.cjs`。命令：

```sh
node attachment-foreign-picker-repro.cjs /absolute/path/to/Riftlet
```

实际结果：`entryClicks=1`、`foreignSetters=1`、`foreignChanges=1`、`foreignReceivedCurrentFile=true`、`state=inputTriggered`；无 ChatGPT、网络或私人图片。脚本当前是缺陷见证，退出 0 表示仍复现；修复的回归测试必须反向断言 0 setter/change。

**理想行为**

只有能够归属于原 composer 的 picker 才能接收文件；超时和“未看到第二个候选”都不构成归属证据。不确定时本图保留，可给短句解释无法附加，不寻找其他 input、不自动重传。

**最小修改方向**

移除 sole-untied-on-timeout 晋升；保留已证实 direct input、显式 DOM 控制关系、当前入口同步调用、已绑定 popup 的路径。若支持实际 ChatGPT 无 DOM 关系的异步 picker 是必要条件，应针对真实页面建立可验证的窄归属路径；不要通过改写 Promise/Timer、凭空推定 causal owner 或退回任意全局 input 获得“成功率”。

**验收**

- 本复现中无关 input 的 setter/change 必须均为 0；原图和草稿、旧附件未变。
- 增加未调用真实 picker、真实 picker 延迟到超时后、多个匿名 picker、相反 owner、同页独立任务等回归。
- 现有 direct/portal/detached/重建 picker 能力按其真实归属继续通过；因修复收窄的无依据 fixture 应明确标出设计原因，不能静默删失败用例。
- 原生 Chrome FileList 上同样验证 0 误投；当前正式签名候选真实 ChatGPT 的冷首图及第二图另行通过。

影响：触发频率未知，正常单一 direct picker 不触发；一旦触发可能向错误页面子功能提交私人截图。成本中等，回归风险集中在异步入口。建议第一修复包最高优先级。

### QA-ATT-002 · P1 · 崩溃前已持久化的 prepared 操作重启后滞留

**结论：完整源码调用链确认；未在此 Linux 环境运行 Swift/AppKit 崩溃实验。**

**位置**

- `Sources/RiftletCore/QueueStore.swift:221–239`：prepare 原子持久化 `phase=prepared`，asset 改为 `transferring`。
- `Sources/RiftletApp/RiftletMain.swift:556–568`：正式 Web adapter 属于 IndependentFileInputAdapter，启动完全跳过 `recoverInterruptedOperations()`，仍记录 local_recovery_complete。
- `Sources/RiftletCore/TransferCoordinator.swift:323–335`：其 recover 同样直接返回，不收尾 prepared。
- `Sources/RiftletCore/TransferCoordinator.swift:238–269`：用户再次点击该资产时将 prepared 视为原 unresolved；仅 unknown/compensated 会尝试 reconcile，prepared 只刷新并返回，没有重新排入等待队列。
- `Sources/RiftletApp/RiftletMain.swift:1294–1311`：仍为残留 prepared 显示“附加处理中，结果尚待确认；请保留当前聊天草稿。”
- 现有 `QueueStore.swift:732–733` 已有 prepared→failed 的安全本地恢复，但是正式 Web 启动不调用。

**复现条件**

在 prepare 提交后、markIndependentFileInputIntent 之前杀死 App/系统崩溃，特别是在另一张输入占用期间已有后续 prepared 操作时；原 operation 从未进入外部输入。重启后该图保持 transferring/prepared，点击没有新输入，自动归档也跳过 unresolved。

原图和私有媒体没有丢失。当前通过“移出队列→历史恢复”能绕行，因为 `QueueStore.removeVisible` 会把 prepared 改为 failed；这不是普通用户应猜出的恢复步骤，故定为 P1 而非不可恢复数据损失 P0。

**推荐方案**

增加启动时仅收尾“没有 dispatch intent、没有输入调用凭证”的 prepared 恢复，回到可显式点击状态。复用现有事务语义，不能顺手调用整个历史恢复而改写 old UNKNOWN/START/receipt，不能启动任何隐式 append。

**验收**

- 独立 SQLite fixture 精确停在 prepared 边界，重启后本图可再次单击附加，首次输入计数仍 0，用户新点后总计 1。
- 同时带着旧 UNKNOWN、START、dispatchIntent、compensated fixture，原操作、receipt、时间戳和媒体逐项保持；未自动输入。
- 真实 App 在连续两图及强退/重开下复验，不再永久显示 preparing。

影响：存在 prepared 操作时异常退出的用户；成本小至中等；主要风险是误把已入外部副作用的操作当可重试。第一轮修复。

### QA-ATT-003 · P2 · 正常接收后的历史和设置永久显示“待核实”

**结论：源码与状态映射确认；是用户呈现/语义问题，不能据此宣称服务端上传完成。**

**位置**

- `Sources/RiftletCore/QueueStore.swift:604–612`：已准入 START 持久化 upload_starts，收起微图，但保持 `phase=inputTriggered`、`status=transferring`。
- `Sources/RiftletCore/TransferCoordinator.swift:543–544,583–592,642–645`：正常独立文件交接在 START 后停止观察，此后无完成状态更新。
- `Sources/RiftletUI/HistoryPresentation.swift:42–45`：所有 transferring/unresolved 都需要核实。
- `Sources/RiftletUI/RiftHistoryController.swift:447–449`：正式历史行显示“结果待核实 · 不会再次附加”。`HistoryPresentation.stateText` 的英文 Checking attachment 主要用于检索，不能误写为正式界面实际英文标题。
- `Sources/RiftletApp/RiftletMain.swift:1285` → `Sources/RiftletUI/RiftSettingsCenterRendering.swift:111`：所有非 prepared unresolved 被计入设置待核实数，包括每张正常 START。

**用户路径**

在 ChatGPT 实际开始接收后微图消失，随后一直在历史/设置待核实；同一记录又出现在“已附加”筛选中（该筛选实际按 visibility=swallowed）。成功交接和真正的未确定输入被混为一类。

**裁决**

保留 11 月 4 日已确认的“文件交接在 START 后结束，上传/发送交给 ChatGPT”；不要重建旧的全程上传事务来修一条标签。将现有不可变 START 作为展示事实，新增独立只读展示语义“已交给 ChatGPT”；仅真正未知的输入标“待确认”。这不把 START 升为 READY、不开放自动重传、不重写旧数据。必要时只给一行“上传结果见原对话”，无需状态卡片或技术说明。

**验收**

- 正常 START 不再进入待核实提醒计数，历史状态/筛选一致。
- 无 START 的未知输入仍明确保留，不可自动重试。
- 旧记录重新打开时从原 receipt/start 事实推导，不批量篡改历史、不授予恢复权限。
- 代码测试用真实 QueueStore.apply 的状态组合验证，原生截图验证实际文案。

影响：每次正常附加都出现；成本小至中等；第二轮信息架构和第三轮历史精修可合并实施。

### QA-ATT-004 · P1 · 点击回调在主线程同步等待 Chrome Apple Event

**结论：线程与超时代码确认；没有本轮原生卡顿计时，不能声称所有用户每次卡 5 秒。**

**位置**

- `Sources/RiftletApp/RiftletMain.swift:1150–1165`：mouse-down 的 freezePress 同步调用 targetForClick。
- `Sources/RiftletAdapters/ChromeAppleEventsExecutor.swift:7,40–46`：类型是 `@MainActor`；activeIdentity 与 url 在返回异步 Task **之前**同步完成。
- 同文件 `348–361`：每个 identity getter 使用 `sendEvent(.waitForReply)`，缺少 receiptBudget 时 timeout=5 秒。
- 同文件 `400–418`：常见快路1次 identity事件，再读URL1次；兼容路径额外3次事件。若Chrome响应缓慢，UI累计阻塞可达数秒；若第一项超时，至少等待该5秒上限才回到App事件循环。

**复现/验证条件**

在隔离 Mac 让目标 Chrome 在 native identity read 中延迟/不响应，鼠标点微图，记录主线程心跳、点击反馈和菜单可操作性。保持真实进程/窗口身份，不使用私人对话。当前此场景尚待 native 执行。

**推荐方案**

为点击时目的地冻结设计短、有界、可取消的非阻塞通道；目标不能漂移。优先将确切 Apple Event 的发送与回复处理移出主线程，保留原事件所请求对象的身份；异步期间若无法证明原窗口/标签/页面一致则保留图片，不改读后来活动标签。若实现中必须短暂同步冻结，为整组冻结设统一且很短的UI预算，不能逐项沿用5秒。不要以后台旧ACK作为必须条件，也不要把UI活性修复变成点击目标猜测。

**验收**

- 5秒无应答 fixture 中，菜单/退出/显示层不被同步阻塞；迟到回复不触发错目标附件。
- 冷首击、无早期relay、点击后切tab、窗口切换、连续双图保留精确目的地与一次性输入。
- 记录原生主线程延迟与实际target，不仅验证函数使用了async关键字。

影响：Chrome忙、恢复/退出、自动化事件慢时；成本中等；回归风险高于状态文案，必须保持 click-time binding。建议第一轮或与 QA-ATT-001 同轮但独立提交。

## 仍有效的机制

- 原生目标含进程生命周期、window/tab、document/composer/generation；后续 validate/commit 使用原 target。没有发现自动转到后续活动聊天的显式fallback。
- JS commit 在可能进入 setter 前先记 committed；进入 setter后不换输入路径，重复commit拒绝。
- Swift lost commit reply 仅 observe 原 operation；precommit失败才返回可证明的 pre-input rejection。未发现自动blind retry。
- 当前 file-input execution 与后续 START观察拆开，旧 UNKNOWN 不再占有下一张独立截图的输入位；这应保留。
- 未发现自动发送消息能力。注入入口过滤submit/send，真正发消息仍由用户。
- 主数据 UNKNOWN/media不能为修复清空；QA-ATT-002只需处理能证明尚未dispatch的prepared。

## 需负责人裁决的失败范围

当前 JS 没有网络终态/明确迟发失败观察，`sample` 在START后立即返回，页面observe仍返回不可变START；这是后期文件交接设计的实际行为。现行支持说明已经说上传进度、最终附件交给ChatGPT，因此不能仅因旧AGENTS的“失败重生”就宣布当前实现违反最新设计。新一轮用户要求附件失败与恢复需要覆盖，建议先明确：未提交的失败立即可再点；未知输入保留；已确认交给ChatGPT的终态以原对话为准。若要恢复“START后明确失败自动重生”，必须是独立产品裁决及原操作精准终止证明，不能重启旧的大型上传状态机或允许重复投递。

## 历史真实附件证据

- PR #61 body明示build18提供真实双图结果。原文首次进入 `cba5f8d6e83eaea153fc1dcd797ef5ed7f27ad7b` 的 `docs/consumer/SUPPORT-MATRIX.md`：正式安装build18、打开Chrome Apple事件JavaScript开关、两图同一草稿、正文原附件保留、逐图START收起、未发送；build19继承同源附加代码。较早6ff5875、2444b99仍NOT_RUN，是后补验收，不可拿旧文本覆盖新记录。
- 在已审阅仓库范围尚未找到该build18本轮对应的独立原始run/屏幕证据索引，因此标为“仓库记载/历史已执行，原始见证待归档”，不是本审计亲验。
- 当前 `docs/consumer/SUPPORT-MATRIX.md:18`明确1.0.0独立Mac连接ChatGPT超时，无新双图复测；`docs/release/SPARKLE_ACCEPTANCE.md:28`明确更新后ChatGPT为NOT_RUN。
- 应要求修复候选新实测，但不能把“当前版本尚缺实测”写成“Riftlet从未真实附加成功”。
