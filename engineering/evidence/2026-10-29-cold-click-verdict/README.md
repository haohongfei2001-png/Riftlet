# 冷首击技术裁决与可运行比较 — 2026-10-29

本轮结论：**现有原生微图在真正无点击前目标证明时，仍不能保证首次附加。停止以轮询或发布毫秒优化承诺消除此边界。** 已做出并运行一个更接近目标的替代入口：页面先持有完整 witness，浏览器把原点击直接送到同一页面，点击同步冻结原目标，随后只复核它。该入口在没有 host ACK 的离线 Chromium 实验中完成一次唯一输入；它改变了点击所属界面，尚不能替代已批准的原生产品。

这是 `codex/riftlet-cold-click-reliability-20261029` 上的隔离实验增量。继承交接 `b4590f4fee8ab43e0ad30d23c980abebe324d20c`、已审生产源码 `c308d46c1412a56e90d665972c0bc8f6ad1511a3`。本轮没有修改任何已有生产源码、测试、准入、旧 gate、权限或数据库。正式 PR #15 在开始核实时仍为 Draft、HEAD `c15fd4b4a27659946ef49280131e875f4d5ab9d1`；本分支没有写入它、PR #1 或 main。

本轮可运行源码：`b031f239100f28c133bec690ab84237fb9d13a58`。新 [macOS CI 40896682733](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40896682733) 在该精确提交首次 **SUCCESS**（attempt 1）；后继仅补公开审查与交接记录，不重跑同一源码。原始 artifact `12907586256` 已下载核对，各文件 hash 保存在审查记录。

## 一、四类原因分别裁决

完整原始 trace 哈希、关联字段、同域时间线与源码入口见 [causal-audit.md](causal-audit.md)。不能将这四类统一称作一个竞态。

| 问题 | 本轮事实 | 裁决 |
| --- | --- | --- |
| 截图之后未及时启动预绑定 | 三轮样本没有真实 T0/T1→arm 的同链路边界。当前源码已有 durable capture 提前唤醒；该回调的诊断时间不是实际 MainActor 入场时间。 | **NOT_MEASURED**，不能给出 watcher 故障归因或新速度提升。 |
| 页面结果到达，完整原生验证未完成 | R6 receipt 比原点击早 20.423 ms；完整 native validation 比点击晚 6.365 ms。页面执行完成本身没有校准时间戳。 | **已确认的分段边界**。receipt 不能替代返回窗口/标签复核后的 ACK。 |
| 完整 native 验证已有，App 尚未发布 | R6/R7/R9 native→有效 ACK 分别 0.881／0.419／0.724 ms；三者 native 验证均已晚于原事件。 | **没有命中该类的真实样本**。不能据此新增 mailbox 或倒填 ACK。 |
| 原事件前缺完整目标证明 | R7/R9 receipt 分别晚 21.403／192.470 ms；完整 native 分别晚 26.323／208.687 ms。 | 原生首次点击产品结果 **FAIL**，原安全拒绝正确。 |

权限结果乱序、空 lease 不恢复和旧监视器兼容是已修复的独立缺陷，不能把它们改称上述全部原始失败的根因。本轮不重复开发这些修复，也不使用旧成功上传来证明无 ACK 成功。

## 二、可运行方案与不可行性边界

| 路径 | 能解决什么 | 不能保证什么／体验代价 | 决定 |
| --- | --- | --- | --- |
| 现有 Apple Events 提前预绑定 | 稳态下先取得原生/页面完整证明，沿用已审唯一输入路径。 | 新页面、窗口切换、忙队列或恢复后的事件可能早于完整证明。同步发送 AE 只查询 Chrome 执行命令时的状态。 | 保留已审修复；只继续修真实 bug，不再调计时器追求零空档。 |
| 晚到页面 witness＋时钟区间证明 | 在已验证时钟映射及连续性假设下，可以证明页面观察早于原事件。 | 仍不能证明该页面就是另一个原生窗口所收点击的当时前台业务草稿；休眠、进程和原点变化还会破坏映射。 | 不进入原生 `ArmedTarget` 授权，不实施补签。 |
| MV3 document-start push＋Native Messaging，保留原生点击入口 | 历史第八轮已跑通独立文档发布与 stdio 通道，可更早安装观察器。 | 已推送元数据也可能在失效通知到达前过时；document ID 不等于业务草稿。单换传输不补齐原生事件归属。 | 不重复搭传输；不能仅凭该实验切换默认路线。 |
| **页面内入口＋点击前完整 witness** | 浏览器把原始事件路由到具有原 witness 的页面；同 renderer 时间线同步冻结，异步资产响应后仍只复核原目标。 | 改变原生裂缝入口；真实扩展/Native host 安全、页面兼容、跨应用行为未完成。完全无页面 witness 时仍拒绝。 | **本轮可运行技术 PASS**；值得作为下一条有边界的架构方向，尚非生产方案。 |
| AX／WindowServer／事件 tap 当前快照 | 可提供原生窗口或较早的输入提示。 | 不提供原事件对应的 ChatGPT 业务草稿历史。 | 不授予上传权限，不转发模拟鼠标冒充原事件。 |
| ACK 前隐藏或禁用微图 | 可以避免让用户点击一个未就绪入口。 | 实际变成等待，改变截图可见与选择契约，并未满足立即一次点击。 | 本轮不实施，不用它宣称修复。 |

不可行性结论有明确前提：**原生入口只持有不完整/过时观察，且没有覆盖原事件的可信目标历史**。在此前提下，原生可见记录可以完全相同，而原点击所在业务草稿不同。任何相同决策至少在一个历史中错传；安全结果只能拒绝。这不是对所有未来浏览器实现的普遍不可能证明。

运行 [authority-counterexample.mjs](../../experiments/click-time-witness-20261029/authority-counterexample.mjs) 可复现四组观察模型：同 native 观察不同原目标、精确页面时间仍不证明原生事件归属、后查询不重建原目标、未监视业务 ABA 不等于端点连续性。它明确是模型，不是 macOS 实测；有真实且完整的连续性日志时，模型前提不成立。

## 三、本轮实际实现的入口实验

源码与命令见 [实验 README](../../experiments/click-time-witness-20261029/README.md)，本机结果见 [browser-result.sanitized.json](../../experiments/click-time-witness-20261029/browser-result.sanitized.json)。它复用当前生产 v13 页面程序与现有 Playwright 1.62.1 lock；不新建生产桥、不安装扩展、不连接用户浏览器、不访问 ChatGPT 服务。

实验的完整原始事件关系为：

`页面 capture+validate 完成并保存不可变 witness` → `浏览器产生并路由原 pointerdown` → `严格检查 completedAt < event.timeStamp ≤ handlerNow` → `同步冻结原 target/asset/operation/attempt/epoch` → `匹配的原 pointerup` → `有界取得同一图片字节并重算 hash` → `复核同一 witness` → `一次 begin/chunk/commit`。

点击 handler 不调用 capture、不重选草稿、不保存无证明点击等待未来 witness。没有 host target ACK 是实验构造条件，host 权限/连接 epoch 为明确的 fixture 值，并非真实扩展或原生权限证明。

本机 Chromium 151.0.7922.34 有界运行的关键结果：

- **PASS（技术限定）**：唯一实际合成 File/change；非空正文、非折叠选区、未聚焦编辑器、旧附件 DOM 身份保留。页面只达到 `inputTriggered`，没有制造 uploadStarted 或 attached。
- **PASS（拒绝反例）**：原事件之后才生成 witness、handler 延迟期间 A→B→A、等待资产期间身份/权限/连接变化、模态、旧节点替换、错误 attempt/hash/响应，均零输入。
- **PASS（唯一性）**：重复/双击以及修改 attempt/visibilityRevision 不能重新消费已输入 asset。消费后的边界失效保留 UNKNOWN，迟到结果不能改成成功。
- **NOT_RUN**：真实 ChatGPT、系统截图、原 NSPanel 冷首击、人工物理鼠标、跨进程权限撤销、扩展安装安全、持久 UNKNOWN 恢复。页面 `isTrusted` 只表示 Chromium 派发；本轮是 CDP 软件事件。

原生点击被转成一个后来生成的页面事件不具有上述属性；工具栏弹窗或 side panel 也是另一文档，不能套用 B 的结论。真正投入下一阶段时应保留单一原操作和持久 once-ledger，验证扩展发送者/原文档、资产响应、断连恢复与真实页面业务监视，再考虑产品入口调整。

这些平台边界与官方资料一致：content script 的隔离世界不直接共享 MAIN 变量，`document_start` 早于其余 DOM 构建；Native Messaging 需要扩展上下文、明确权限及 native host。见 [Chrome content scripts](https://developer.chrome.com/docs/extensions/develop/concepts/content-scripts)、[Native Messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging)。时间戳和 `isTrusted` 的含义见 [DOM Standard](https://dom.spec.whatwg.org/#interface-event)；这些 API 事实本身不构成产品验收。

## 四、真实 Chrome 控制恢复到哪一层

只读原生探针：[probe.swift](../../experiments/chrome-control-probe-20261029/probe.swift)。本机编译和 descriptor self-check **PASS**。实际逐接收者结果见 [control-results.json](control-results.json)。

- macOS 27.0、两个 Chrome 主进程。按 PID＋launch lifetime 直接发 AE；被动 Automation 检查均返回 0，不请求授权。前台接收者固定 tab＋只读 DOM 成功约 25.663 ms，直接 AX 窗口读取约 20.625 ms。这些是探针自身的权限与当前快照，不能借给 Riftlet 当目标 ACK。
- 另一个非前台 Chrome 的同类页面执行返回原生状态 12。没有猜测其含义，也没有修改该 profile 的设置或换接收者来上传。
- CUA 原生 Chrome 和 Preview AX 都返回 `-10005 timeoutReached`；已有 profile 引用不可用且缓存/provider 身份不一致。重新解析在线连接后，创建/列举/关闭标签成功，新的专用 ChatGPT 页 DOM 仍在 15 秒边界超时。公共静态页的导航＋只读 CDP 序列也未在 12 秒内返回，该序列没有隔离到单个失败子步骤。
- IAB 空白页可创建/观察/关闭。两个本轮 Chrome 临时标签已关闭，原用户标签未关闭或重载；没有文件输入、消息发送、扩展安装、Chrome 重启或权限变更。

结论是**部分控制面可用，完整验收通道未恢复**。证据排除了“所有 Chrome AE 或本机 AX 都不可用”这一笼统解释，但不能确定是控制服务内部哪一处错误，也不能仅据此断言 ChatGPT 页面正常。直接 AE 当前读成功，不等于已经获得一个独立新草稿的完整可用证明。本轮新的系统截图→一次输入→真实开始/完成因此 **NOT_RUN**；没有为复测启动 App 操作旧数据库。

## 五、交付与投入裁决

**不再投入无证据的 Apple Events 计时微调。** 已审原生修复可以独立交给 PR #15 负责人：仅取 `c15fd4b..c308d46` 的三处产品源码与相应回归，保留正式工程自己的组合门禁。不得把本专项 workflow、实验、来源 gate、交接元数据整包视为正式产品合入。

若严格保留“原生微图、无扩展、任意无证明时刻也必须一次成功”三项条件，本轮没有可安全交付的方案。现行 Beta 必须诚实保留无证明拒绝，不标为已解决。若下一阶段允许调整点击入口，优先投入**浏览器持有原始点击及点击前 witness**，再用最小 Native Messaging 传送原资产；价值是消除该入口对 host 预先 ACK 的依赖，代价是一次扩展/native host 安装、页面内界面以及新的安全/兼容验收。仅更换 AE 为元数据 push 不值得作为解决方案继续投入。

本轮 CI 在 macOS 15.8.2 arm64、Swift 6.1.2、Node 22.23.4、Chromium 151.0.7922.34 上运行新增探针编译、自检和离线架构比较，并验证 b459 的 **890 个既有文件对象**不变。一次 fixture 输入与正文/选区/旧附件保持均通过，没有向外部发出请求。完整 App/Swift/AppKit 仍引用已审源码对应的 [既有 CI 40881144683](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40881144683)，没有把它改称新实测。新源码 SHA、独立审查和新 CI 记录在 [review-and-validation.json](review-and-validation.json)。

数据核对见 [retained-data.json](retained-data.json)：三个原数据根全表（含 sqlite_sequence）摘要、32 个操作、7 个 start、3 个补偿和 50 个私有媒体的字节/hash 均与上一已保存快照一致。旧 UNKNOWN、原图和审计未清理、未重输；公开文件只含脱敏结果与原件 hash。
