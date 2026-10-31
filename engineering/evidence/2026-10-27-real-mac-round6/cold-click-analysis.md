# 冷首击边界：无 ACK 与尚未进入 App 的 ACK

只读分析，2026-10-27。分析基线 `3bb13999b0f444c7748804eef1976e179a52a85e`；不合入 Pro `2449d40`。独立审阅者未改 Core/UI/App/adapter、未操作浏览器或执行点击。下文早期测试方案是提案；末节另记录协调方后来实际执行的边界样本，不能混作该提案已经执行。

**真正没有点击前目标证明的事件不能安全补救。** 后台预捕获只能减少空档；点击后 capture、将较晚 ACK 倒签、暂存事件等待目标、二次点击都不满足当前约束。host-only mailbox 只可能改善“完整验证且已在原事件前发布，但 App 尚未处理”的较窄情况；那不是完全无预绑定的冷首击成功。

## 当前路径与可观测空档

| 边界 | 当前实现 | 可观测空档 / 含义 |
|---|---|---|
| 触发 arm | `RiftletMain.startArming/requestArm`；启动、激活、wake、Chrome AX、pointerApproach、定时 fallback | AX/hover 是唤醒信号，不是目标证明。fallback 在无可见图时 3 秒、有图时 1 秒；触发到发起之间可能没有目标。 |
| 调度 | `TargetArmScheduler`：一个 inFlight、一个合并 pending、epoch 失效 | 不取消在途 capture，不允许并行。失效后旧调用必须排空，后续请求才能开始。停止/重启旧 completion 不可发布。 |
| Native 排队 | `ChromeAppleEventsExecutor.scriptQueue`，共享串行 utility queue | capture 与既有 observe/input transport 共用队列；`queuedUptime→startedUptime` 单独计时。慢或失联旧观察可能延后预绑定；不能把队列等待称 MainActor 延迟。 |
| 原页 capture | 前台进程/launch 校验、当前 window/tab、MAIN nonce 命令与原回执 | 一次 submit，随后只读 nonce 回执；无回复不会重发。轮询 1 秒在 Apple Events 调用间检查，不是整个调用的硬上限。 |
| native_validated | `NativeCaptureProof` 解码全 TargetLease，校验原 session/window/tab/必需字段，再复查 active window/tab | 这是 native 证据诊断，尚未成为点击权限；此阶段没有完成后续 MainActor 前台复核和 adapter 验证。不能只凭 digest 或 accepted=true 当 ACK。 |
| main_actor_return | executor continuation 回 MainActor，再校验前台 PID/launch | 与原 native 验证之间存在调度空档；原事件可能已进入系统事件队列。该事件仍不是 App publication。 |
| adapterValidated | `WebAttachmentAdapter.captureTargetWithDiagnostics` 解码/check 后记录时间 | adapter actor 到 App continuation 仍有空档。CaptureInvocationContext 不编码进页面请求，不能授予输入。 |
| App publication | scheduler.complete 接受 epoch；当前 foreground session 一致才设 ArmedTarget | `acknowledgedUptime` 是此处实际 host uptime。相等目标保留其原 effective ACK；不能以本次调用 ID 与旧 ACK 混接。 |
| 原选择 | UI mouseDown 使用原 `NSEvent.timestamp`；AX 使用 handler 进入时 systemUptime | `freezePress` 同步调用 `ArmedTarget.freeze`：同 epoch、同 foreground session、ACK 严格早于原事件且原事件不在未来。鼠标回调晚处理也不能用 callback 时间替换 event 时间。 |
| 冻结后执行 | mouseUp/onSelect 取先前 frozenPress；Coordinator `select(...frozenTarget:)` 禁止 capture | pending 图 nil target 只暂时 reserve/release，拒绝且不 prepare/append；旧 unknown/compensated 可以仅 observe 原操作。选择错误不能转成新输入。 |

源码锚点：`Sources/RiftletCore/ArmedTarget.swift`、`TargetArmScheduler.swift`、`TransferCoordinator.swift`；`Sources/RiftletApp/RiftletMain.swift` 的 `freezePress/performPendingArm/recordSelection`；`Sources/RiftletAdapters/ChromeAppleEventsExecutor.swift`、`NativeCaptureProof.swift`、`CaptureDiagnostics.swift`；`Sources/RiftletUI/RiftPanelController.swift` 的 `onDown/onUp/onAccessiblePress`。

关键区别：`native_validated < event < App publication` 只能定位潜在空档，不能让现有代码接受该次点击。`event < native_validated` 更不可能通过调度优化追回权限。进程激活通知/Chrome AX 通知自身也经 MainActor；延迟送达的失效通知不能被 mailbox 的旧 epoch 掩盖。最终原页 validate/commit 必须继续拒绝换目标，不能用 host epoch 代替业务连续性证明。

## 无上传的最小边界测试

### 现有代码即可执行的确定性安全负例

1. 在隔离 synthetic Web acceptance store 选一个从未 prepare 的 pending 图；保留原队列、日志及页面 observer，不点旧 unknown。启动时让非 Chrome 应用保持前台，确认新进程没有 `publishedNewTarget`，并记录 `noPublishedTarget` 前置状态。
2. 对该图执行一次当前已有的精确 AXPress；保持前台不变，不制造 mouseEnter 预热，不追加第二次点击。需要现有 synthetic identifier/enabled 临时 metadata 时，只使用已审查的最小补丁。
3. 预期 selection source=accessibility、freeze refused/noPublishedTarget，原图仍 visible，未新增操作、attempt、upload_starts；trace 无 begin/chunk/commit；页面 input 无增量。稍后 arm 成功也不得补发此选择。

这是“没有目标时不输入”的安全负例，**不是有效 Chrome 当前草稿的冷首击体验测试**。AXPress handler 成功与 freeze 拒绝并不冲突；前者只是原选择入口被调用。

### 有效 Chrome 草稿、确定性空档、仍保证无上传

原代码没有可从外部可靠停在 `native_validated→App publication` 的 latch。仅在启动/切回 Chrome 后“尽快点击”是竞态，若 ACK 抢先完成就可能上传；预先读一条日志也不是点击时同步保证。不能将其写成无上传的确定步骤。

最小可复核提案是在**独立测试构建的 transport seam**增加一次性诊断 gate，正式实现不变：

1. 所有 begin/chunk/commit 在实际 native dispatch 前无条件拒绝并计数；仅允许 capture/validate/observe。此禁输入门独立于 timing gate，避免测试误时上传；不得用禁输入结果充当正常附加成功。
2. 新 App 进程、单一 pending synthetic 图、真实可用 Chrome 草稿。不让 gate 阻塞 MainActor；在初始 capture 的 native 验证后挂住 continuation delivery，保留原 request/attempt/epoch，记录 gateReached/nativeValidated 时间。App 仍可处理唯一选择。
3. 执行一次精确 AXPress。核验原 event 时未有 App publication，freeze 为 noPublishedTarget，且无 prepare/input。释放 delivery 后只允许正常 arm 完成；等一次有限 drain 检查，没有自动重放原点击。
4. 独立覆盖更早 gate（native 验证前）及原事件早于后来 mailbox publication 的负例。若要验证鼠标队列延迟，需使用原 NSEvent.timestamp 的独立测试；AX 没有更早的硬件事件时间，不能替代此项。

Gate 是可控故障注入，不代表自然场景空档发生率。停止条件按单次测试结束，不循环开页、上传或重试。这是起草时的受控方案建议；该 gate 未实施。后续自然时序样本单列于末节，只按实际原始时序归类。

## 最小诊断字段与判定

沿用 requestID/captureRequestID、armAttemptID、hostEpoch、targetDigest；每次 invocation 全链关联，equal digest 不可替代 invocation 身份。公开只存摘要，不记录完整 target/URL/会话标识。

- capture：triggerReason、queued/started、nativeReceived/nativeValidated、mainActorReturn、adapterValidated、App mainPublished、publicationResult、epochAccepted、是否 reused，以及独立 effective ACK/request/attempt。
- selection：source、原 eventUptime、callback/handler uptime、eventNumber（仅真实 NSEvent 路径）、freezeResult/refusalReason、effectiveAckUptime、当前 epoch 匹配、foreground session 匹配、inFlight request/attempt。
- 若有 gate/mailbox：gate phase、到达/释放时刻；mailbox 实际 publishUptime、读取 uptime、context 匹配、epoch 失效序号和拒绝原因。所有时钟用同一 host uptime，renderer performance 不直接比较。
- 零输入证据：按本图核对 selection 次数、prepare/dispatch/attempt、begin/chunk/commit、page inputCount、upload_starts、visibility/revision 前后值；允许的旧操作 observe 必须与本图分开。

必须区分：无 native proof；有 native proof 无 mailbox；mailbox 已发布但晚于原 event；mailbox 早于 event 而 App 尚未读取；已有 App ACK。只有最后两种可能支撑原事件前证明，其中倒数第二种需要新增且独立审查的权限契约。

## host-only mailbox 可行性与不可越过的边界

可提议一个有锁、容量 1（或严格有界）的 immutable candidate mailbox，绑定 request/attempt/epoch、完整 TargetLease 与 digest。发布必须来自已完成全部必要解码/原进程/原选择校验的可信 host 路径。**在锁内真正写入时采样 publishUptime**，绝不能复制更早 nativeValidated 作为发布时间；选择必须 `publishUptime < originalEventUptime`。相等、未来、非有限时间全部拒绝。读取不能 await、启动 capture 或等待 mailbox。

当前 `native_validated` 阶段并未完成后续全部检查，因此直接复制这个日志到 mailbox 不够。若在 scriptQueue 发布，需要将必需的安全检查明确移入可并发的 host 验证路径，并保留选择时前台/epoch检查和原页最终验证；不能绕过当前 MainActor return guard。若只在现有 adapterValidated 后发布，仍可能缩短 adapter→App continuation 空档，但不能消除前面的 MainActor 排队。

Mailbox 失效需与 scheduler epoch/stop/进程变化有明确同步规则；旧 completion 不得覆盖更新 epoch。未知 identity/不同 invocation 不可拼接；异常不发布，读取失败就保留图。旧页面 observer 和原 operation 不清理、不迁移。Mailbox 不保存选中 asset 或点击，不持有待发输入，不提供 retry。

**单改 adapter 不会改善现 App**：App `freezePress` 只读 ArmedTarget，现接口没有 mailbox 读取。需由 Core/App 负责人审查增加冻结边界的显式输入，保留全部旧规则及 no-capture API；该变更不在本报告授权写入范围。

绝不可能修复：原事件前尚无完整目标证明；浏览器/页面尚不可用；native reply 丢失/歧义；原事件前尚未真正发布候选；点击前发生未被证明连续的业务 A→B→A；进程/epoch/当前目标已变；用户点击发生于启动或重新授权之前。不能为了宣称“一次冷首击”抹平这些事实。队列优先级、预热频率或 mailbox 只减少延迟，不创建过去的证据。没有独立业务身份连续性事实时，后续 capture 看到相同 URL/DOM/ID 也不能补证。

## 最小回归建议

1. 实际 publish `< / == / >` 原事件，晚处理旧鼠标事件、NaN/未来时钟，分别拒绝/接受正确。
2. epoch 失效、stop/restart、PID 重用、不同 invocation 同 digest、旧 completion 到达，均不得借用候选。
3. gate 释放只更新 arm；被拒绝原选择不进入 prepare/append。nil frozen pending captureCount=0，旧 unknown 只 reconcile。
4. single-flight/pending coalescing 仍成立；不取消在途 capture，不增加并行 AE，不让 mailbox 锁跨 IPC/await。
5. main/native 校验失败、receipt 错 target/nonce/字段、foreground 改变不发布；后续 page validate 拒绝仍不输入。

现有 ArmedTargetTests、TargetArmSchedulerTests、TransferCoordinator 冻结目标测试可复用，但不能将原有通过记录记为 mailbox 新测试通过。此处不预断后续样本；末节真实无 ACK 样本的产品结果为 FAIL，物理事件仍 NOT_RUN。

## 后续真实边界证据：冷首击要求尚未通过

公开脱敏关联见 [cold-click-evidence.json](cold-click-evidence.json)。实际 GUI/Chrome 操作为协调方执行，独立审阅者读取固定或读取时快照日志，并以只读 SQLite 查询核对四个资产。文件名不代表验收类别；`valid-cold` 这一命名的最初样本实际上也没有获得支持页面的捕获。

| 样本 | 实际结果 | 可以证明 / 不能证明 |
|---|---|---|
| `75A829E6…` | noPublishedTarget，邻近 capture 返回 unsupportedSurface；pending/visible，无 operation | 安全拒绝；不支持普通对话冷首击结论。较晚活动标签读取不等于原点击时页面快照。 |
| `D27D5EA6…` | noPublishedTarget，邻近 capture 仍 unsupportedSurface；pending/visible，无 operation | 同上。该日志另有其他资产的后续输入，不能把整个文件的一次 commit 归给此图。 |
| `BFB6FAB2…` | App publication 比原选择早 **3.354333 ms**，effective ACK 早 **3.355250 ms**；accepted，begin/commit 各 1，used/succeeded | 真实已有预绑定成功，实际额外输入了一张生成图，不能记录为零输入或 cold PASS。差距只有 3 ms 也仍是预绑定。 |
| `E503EC07…` | 原选择 noPublishedTarget；随后同次 capture 完整验证成功并发布；pending/visible，无 operation；整份 trace 无 begin/chunk/commit | 有效普通目标的真实无 ACK 拒绝：安全边界通过，产品“一次冷首击附加”要求未通过。 |

后两批来源是 `7878de3138d1c140369c3cfbe69a28dd2770294c` 加原两份受限临时 overlay。全部为软件 accessibility 选择，不是物理鼠标。协调方以激活 Chrome 与一次 helper 行为的时间重叠寻找边界；最后脚本的 80 ms 调度间隔只是测试协调，不是产品等待策略、事件重播或上传重试。本文不将批次之间不同资产的输入混成同图重传。

### E503 的原事件与同一次 capture

完整 capture invocation 的 request/attempt/epoch 在私有原日志中一致，公开仅留 targetDigest。下表以原 AX handler 事件时间为零；无用 callback 时间代替原事件的回填：

| 边界 | 相对原事件 |
|---|---:|
| nativeReceived | −20.422958 ms |
| 原 selection / freeze refused | 0 ms |
| nativeValidated | +6.364750 ms |
| executor MainActor return | +6.710333 ms |
| App publication | +7.247250 ms |

回执收到时尚未完成解码/摘要与原 active window/tab 复核。**收到 JSON 不等于有效 ACK**，不能利用提前 20 ms 收到回执来回填该选择。后验同页唯一普通 composer 的检查和该 capture 随后成功支持本次普通目标归类，但不是对原事件瞬间页面状态的额外原子快照。原拒绝被保留；较晚 ACK 没有重新触发旧选择。

只读数据库确认 E503 为 pending/visible/revision 0、activeOperationID=null、操作数 0。测试 App 已停止；独立日志核验没有 begin/chunk/commit。没有把原生零输入推断冒充另一次页面 inputCount 采样。此处不公开页面 URL、完整 target 或 session/tab 标识。

### 本批优化应针对哪里

receipt→nativeValidated 是 **26.787708 ms**；nativeValidated→MainActor return 只有 **0.345583 ms**，到 App publication 合计 **0.882500 ms**。该样本不支持“大量 MainActor 积压导致错过”的判断。前一区间包含 decode/digest 和三次 AE 的 `activeIdentity()` 原选择复核；源码显示三次调用，当前日志未分别计时，故不能把全部 26.787708 ms 精确归为 AE。

本批即使消除全部 MainActor 发布延迟，完整 nativeValidated 仍晚于原事件。因此无需为这份证据先开发 mailbox 或 capture gate；优先评估保留原选择复核、减少往返的 adapter 优化。Gate 方案仍可用于日后确定性回归，不是现有真实失败的补救或重新演示理由。没有新独立证据，不应重复 E503 输入。

## v12 与 descriptor 优化独立代码审查

v12 代码保持总 8 MiB、逐 chunk ACK、严格 nextChunk、第二遍文件摘要复核及唯一 commit；只将代码持有的 chunk 能力从默认 64 KiB 扩展到最多 256 KiB。Legacy wrapper 透传当前能力，但 v6–v11 路由仍仅 observe/schema1，不取得 start 或输入权限。独立执行 current page 72 + legacy 54，共 **126/126 PASS**；这不是新的真实冷首击通过记录。

提交 `c000cc1b930b278ae22b29e6b01941a9faf0a87d` 的 `ChromeActiveTabDescriptor` 优化审查未发现阻断：一次 `get acTa of front window` 只接受精确 `obj CrTb / form ID / canonical positive Int64 utxt` → `obj cwin / form ID / canonical positive Int64 utxt` → 空 `null` 的完整链。每层恰好 want/form/seld/from 四字段，want/type 与 form/enum 类型及四字节长度校验；不解析 description，不接受相对索引或宽松字符串。返回 window/tab 仍用于原来的 post-receipt `active == selected` 检查，未取消原选择复核、前台/进程校验或原页 final validation。

不支持的 descriptor 形状走既有三次读取兼容路径（加上失败的快速探测总计四次读取）；AE 传输错误直接失败，不自动重发命令。兼容路径可能变慢，应保留这一性能限制。严格格式不匹配可能拒绝快速路径，但不会放宽权限。五组纯 parser 测试覆盖 fixed-ID 正例和相对选择器、数值 descriptor、错误类型、缺项/额外项、错误容器与非法数字；本次独立 Swift parser 检查通过，native XCTest 执行不由该语法检查替代。

这项优化只是减少不可跳过的验证开销，尚不能推断节省的毫秒数、真实通过率或保证任何无证明点击成功。后验 descriptor 探测证明当前浏览器形状可用，不证明所有 Chrome 版本相同；保留 fallback 与原拒绝边界是必要条件。

## 单次固定 ID 读取：实际只读 App 验证

最终源码 `c000cc1b930b278ae22b29e6b01941a9faf0a87d` 加相同两份受限 overlay，App SHA256 `17d89ddcf72d9efa84a826436175843a0401bbfa16136b0afd48c88e527cd89c`。一次有界真实 Chrome 批次获得三次完整捕获，初始与返回选择复核的六次读取全部记录 `descriptor_fast`，均成功。详见 [selection-read-evidence.json](selection-read-evidence.json)。没有 selection、begin、chunk、commit，运行后停止该 App；未重试 E503 或旧 UNKNOWN。

回复到 nativeValidated 分别 **4.383208 / 4.784208 / 11.911583 ms**；其中返回选择读取分别 4.131375 / 4.287542 / 11.606167 ms。到 App 发布另为 1.216750 / 0.714625 / 0.484250 ms。初次完整捕获执行 76.475208 ms，随后 41.401625 / 42.521708 ms；不把旧样本的总耗时与新样本强行等价，也不推断分位数。已确认真实快路径可用，完整校验区间小于本轮旧路径 26.787708 ms 失败样本。

这是实际延迟改进与只读兼容验证，不是修改后新的无 ACK 点击通过。任何早于新完整 ACK 的选择仍会拒绝；未引入邮箱、MV3、Native Messaging、延时点击或目标回填。fallback 本批未触发，保留其四次读取的可能性能退化。
