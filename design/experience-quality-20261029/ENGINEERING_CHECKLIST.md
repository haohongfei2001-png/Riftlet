# Riftlet · 工程可执行改进清单

版本：2026-10-29（北京时间） · 独立「完整体验」设计交接 · **没有新增原生实现或运行验收结论**

本清单按 Q01–Q10 将补充设计收敛为最小工单。正式视觉继续采用「薄界」；本轮不增加 SDK、截图编辑能力、全库搜索、100% 缩放、导入重试、云服务或新的上传准入。工单中的“验收”是未来完成条件，不表示本轮已经 PASS。

## 1. 执行入口与共同等待条件

### 现在可做

审阅本目录的高保真图与状态原型，核对文案、状态事实、权限含义、可访问性文本和工单范围；只读核对现有证据，记录已实现内容与未验证环境。**现在不能接入原生回调、修改源代码、改正式分支或 PR #1。**

### W · 全部原生工单共同等待条件

1. 当前正式集成由其负责人完成并给出新的正式 source SHA；读取该 SHA 的实际源码、最新约束和反馈后端，不把审计起始 SHA 当作未来实施基线。
2. 对每个 Q 项重新比对：新 SHA 已解决的标记“保留／无需修改”，只实施剩余差额。Q01 的最小文案修复不依赖 Q02 的布局提案。
3. 在独立实现分支/工作树提交本次选定工单。只按本目录中的设计规格取意图，**不能把整个设计分支合并进正式工程**，不能覆盖另一工程 Pro 的 App/Main、Feedback、分支、PR 或集成现场。
4. 本清单不授权修改 PR #1、合并 main、发布、启用 profile、清理历史或重复真实上传。后续提交如何进入正式工程由既有集成所有权处理。

没有创始人 Beta 依赖。可用的工程 Mac、受控合成素材、既有自动化与原生证据优先；缺少设备或授权只阻塞对应真机验收，准确标为 `NOT_RUN / BLOCKED`，不向创始人转移例行体验任务。

### 规格和固定依据

| 依据 | 使用方式 |
| --- | --- |
| [APPKIT_SUPPLEMENT.md](APPKIT_SUPPLEMENT.md) | Q01、Q02、Q05–Q09 的文案、布局、动作守卫、像素预算；S01–S13 有固定 SHA 源码定位。 |
| [STATE_TRANSITIONS.md](STATE_TRANSITIONS.md) | Q03、Q04、Q05 的事实转换、owner/session 约束和 Q10 环境矩阵。 |
| [Riftlet-Experience-Prototype.html](Riftlet-Experience-Prototype.html) | 六组可审查的合成情境；仅表达设计意图，不把模拟时钟或按钮结果接入业务。 |
| [正式薄界 7e03bd2](https://github.com/haohongfei2001-png/Riftlet/tree/7e03bd2c26c6aa43dbac07b073e00d08d1951b71/design/final-system-20261028) | 继续使用正式 token、窗框、固定几何、无／磁力吸引两项与快速吞噬。 |
| [原生交接 443d21d](https://github.com/haohongfei2001-png/Riftlet/tree/443d21da1a55c0061eafced823b5406879b96024) | 以下定位对应的固定审计对象，包含候选 00dedc7 源码；不是未来正式组合的批准。 |
| [正式 Feedback 0e7ea8be](https://github.com/haohongfei2001-png/Riftlet/tree/0e7ea8be148e1124b387e799fd886a7830e96559/Sources/RiftletFeedback) | 已知定时器、丢凭证和删除竞态修复必须保留；实施时再以新正式 SHA 的后端为权威。 |

## 2. 优先级与证据分类

| 编号 | 优先级 | 最小结果 | 性质 |
| --- | --- | --- | --- |
| Q01 | P0 | 首用文案准确反映当前模式能力 | 代码可证的文案冲突；不是错传证据。 |
| Q02 | P1 | 可选一页快速开始；已可读来源不再要求授权 | 首用已实现；本项是精简提案。 |
| Q03 | P1 | 倒计时说明本次已选目标及下一张模式 | 安全模型已有；可见呈现存在接线差额。 |
| Q04 | P1 | 落实正式设计的附近轻说明 | 已设计未完成；下划线、tooltip、AX 已有。 |
| Q05 | P1 | 各权限、浏览器设置及目标条件独立解释与恢复 | 原守卫已有；补齐呈现，真权限路径待验证。 |
| Q06 | P1 | 历史身份易辨，现有 Fit 预览按视口清晰解码 | 低分辨率复用限制可证；新预算是提案。 |
| Q07 | P1 | 反馈本地／云端／删除含义准确，校验口径一致 | 部分已有；字符口径差异可证，状态呈现需补齐。 |
| Q08 | P1 | 关闭／退出受阻有准确原因与安全恢复 | 关闭保护已有；不主张已经丢失草稿。 |
| Q09 | P2 | 已有设置归位、窗口位置一致、Cmd-, | 已设计未完全实现及原生习惯差额。 |
| Q10-V | P1，验证 | 受改动影响的 Spaces、物理输入、像素与辅助功能证据 | 尚未验证，不计为已知缺陷。 |
| Q10-P | P2，实施 | 极端比例编号垫片边框采用 1/backing | 固定 0.5pt 的代码差异可证；1x 实际观感未测。 |

Q10-V 与 Q10-P 属于同一个 Q10，分别列出验证任务和局部实现差额，避免把环境覆盖缺失包装成新缺陷。

## 3. P0 · 最小能力文案修复与既有安全门槛

### Q01 · 修正首用能力承诺

| 要素 | 最小工单 |
| --- | --- |
| 问题与影响 | 候选首屏/结束页一概说点击进入当前聊天，而 `productionDisabled` 只允许本地收录；用户可能误以为授权后即可附加。[固定源码：RiftSetupController 238–250](https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletUI/RiftSetupController.swift#L238-L250)。 |
| 方案 | 保留当前三页与窗框，先把标题、说明、结束页、主按钮及 AX 文本投影到真实 mode/attachmentState。普通模式：“当前版本可在本机收录和查看截图。附加功能尚未启用。”候选明确已验证支持范围；合成模式明确演示。完成只结束当前引导、保持既有 mode；不新增演示启动入口。 |
| 类／文件 | `Sources/RiftletUI/SetupPresentation.swift`：纯文案投影；`RiftSetupController.swift`：读取同源文案；`Sources/RiftletApp/RiftletMain.swift`：只复核现有状态映射，非必要不改。 |
| 不变量 | 不写准入、权限、目标、队列或上传 intent；获授权不等于可附加；不改变暂停/隐藏；完成不试传、不发送消息；可见文本和 AX 描述一致。 |
| 验收 | 对现存普通、候选、syntheticWeb、offlineSimulation 的首屏与结束页逐项核对；普通模式没有可附加承诺或必须授权 Chrome 的动作。执行完成前后比对业务状态无变化。纯投影按需验证，不为几处静态文案扩写镜像测试；软件快照与真实首装证据分别标记。 |
| 等待 | **W。** 现在可以审阅精确文案；新正式 SHA 如已修复则保留。无需等待 Q02、Q09。 |

### G0 · P0 既有安全保留门槛，不是新增缺陷单

本轮没有证据证明新的错目标、重复输入或数据丢失缺陷；不得用这些风险虚增 P0 数量。下面约束只作为相关改动的接受门槛：

- 保留点击时原目标、完整手势、session/request/operation/owner/revision；陈旧回调不能作用于新图、新会话或新草稿。
- 只有原同身份操作获准的真实 `uploadStarted` 才开始快吞噬；吞噬不等于最终成功。无成功 Toast、无自动发送消息。
- 固定模式槽、移动取消盖片、原图及媒体、历史、UNKNOWN、隐藏/暂停、候选数据根和历史锁全部保留。
- 结果不明不能变成安全失败。已开始的 UNKNOWN 保持隐藏/只读；不重生、不重输、不删库清理。现有 safe-failure/retry 准入保持原状，隔离演示不泄漏到真实模式。
- Feedback 使用自己已有的同 ID 幂等投递与删除恢复，不重写其最新后端，不把它的可恢复投递规则用于截图 UNKNOWN。

若未来改动实际触发这些门槛失败，阻止该改动交付并保留证据；其他独立工单继续。验收只覆盖改动可能触及的路径，不新增真实上传来重复证明旧结论。

## 4. P1 · 完整使用与恢复体验

### Q02 · 单页可选快速开始

| 要素 | 最小工单 |
| --- | --- |
| 问题与影响 | 已有三页原生引导及“稍后设置”，不是首用缺失；静态首尾页可压缩，目录已可读时再给主授权动作会制造不必要步骤。 |
| 方案 | 沿用 560×520pt 外框，一页呈现一句用法、能力行、实际截图位置及本模式需要的连接条件；详细范围折叠。已可读项只显示事实；不可读项才给检查入口。完成与稍后始终清楚；完整帮助仍可主动打开。 |
| 类／文件 | `RiftSetupController`、`SetupPresentation` / `SetupSnapshot`、`Sources/RiftletApp/FirstUsePreferences.swift`；复用已有 callback。 |
| 不变量 | 不强制教程/试传；不清 first-use 展示记录逼老用户重新走流程；不以完成自动授权、恢复暂停或启动捕获；不把 optional Screen Recording 作为普通收录前提。 |
| 验收 | 来源可读的普通模式只需一次完成动作，额外授权次数为 0；不可读可稍后退出；关闭后后台导入不重开。Tab 到未完成项、详细信息、稍后、完成；状态更新不重置焦点。 |
| 等待 | **W。** 单页结构属于可独立采纳的提案，不能阻塞 Q01 最小修复；新正式引导若已达到相同目标，不重复改。 |

### Q03 · 倒计时与“本次／下一张”

| 要素 | 最小工单 |
| --- | --- |
| 问题与影响 | 当前模型冻结已选请求，切模式只影响下一张，但 Host 未绑定专用倒计时呈现；用户难判断还会拍什么。[ScreenshotEntryHost 65–90](https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletApp/ScreenshotEntryHost.swift#L65-L90)。 |
| 方案 | 将原 capture 状态只读投影为“已选区域 · 3 秒后拍摄”“正在拍摄已选区域”；倒计时中切模式另加“下一张：窗口”。说明复用 240pt 最大宽、13/18pt 正文，靠近现有固定列，不移动槽或 X。首轮只接文字；新增选区装饰无可靠自排除证据前不实施。 |
| 类／文件 | `Sources/RiftletApp/ScreenshotEntryHost.swift`；`Sources/RiftletCapture/InteractiveScreenshotController.swift`、`InteractiveScreenshotTypes.swift` 的只读状态适配；`Sources/RiftletUI/ScreenshotEntryController.swift` 的说明呈现。复用原 `onStateChange / onCapture / onError`，不另建捕获状态机。 |
| 不变量 | 倒计时在完整选择后开始；本次 mode/target/options/deadline 不随下一张设置改变；同时一个 pending；X/Esc 结束会话；旧 session 不交付到新会话。已交付原图不因结束截图被删除，取消文案不武断宣称没有落盘文件。 |
| 验收 | 一次 5 秒请求中区域→窗口→全屏，原 request 不变且只捕获一次；下一张才用全屏。延时 0 不闪“0 秒”；改选项不改本次倒计时；立即 X 后旧 timer/completion 不复现；已交付/未交付分别核对取消文案。AX 首次播报一次，不逐秒抢读；新说明纳入现有自排除范围。 |
| 等待 | **W。** 状态适配只针对合流后实际接口；没有新 target/capture API 的授权。真撤权/自包含证据无法取得时如实保留对应未测项。 |

### Q04 · 落实附近状态说明

| 要素 | 最小工单 |
| --- | --- |
| 问题与影响 | 正式设计已有附近轻反馈；候选已有 transferring 单线、UNKNOWN 双线、真实原因 tooltip 和 AX，但短暂拒绝/等待原因仍不够直接可见。[RiftPanelController 195–235](https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletUI/RiftPanelController.swift#L195-L235)。 |
| 方案 | 复用反馈投影建立 nonactivating 说明：确定拒绝即时显示；等待持续≥250ms 且仍在同一输入岛才显示；最长 2400ms，主动 hover 450ms 可重读。最大 240pt、13/18pt；原因说明与图片 peek 不叠层。prepared 使用“附加处理中，结果尚待确认”，不持续承诺尚未输入。 |
| 类／文件 | `Sources/RiftletUI/RiftPanelController.swift`、`Sources/RiftletApp/ProductStatus.swift`；Main 既有 owner/revision 安全投影只适配，不改上传协议或 Core。详见 `STATE_TRANSITIONS.md` Q04。 |
| 不变量 | 原下划线、tooltip/AX、450ms peek 保留；说明 `ignoresMouseEvents=true`，不 key/main、不激活 App、不新增输入岛。所有 timer 绑定 asset/operation/owner/revision/generation；换 owner、Space、隐藏、曝光立即作废。关闭说明不是取消操作。uploadStarted 才吞噬，UNKNOWN 不变成 retry。 |
| 验收 | 249/250ms 边界、离岛与同图新 attempt、2400ms 超时、450ms 重读各一次；旧文字不覆盖新状态。呈现/隐藏不会改变 begin/chunk/commit/input 次数。无安全空位时回退原 AX/tooltip；透过说明的实际点击与全屏焦点归 Q10-V 真机验证。 |
| 等待 | **W。** 不能倒退已修正的 prepared 文案与迟到取消保护；safe failure 只能用隔离 fixture 验证设计，不开放真实准入。 |

### Q05 · 权限、浏览器设置与目标各自恢复

| 要素 | 最小工单 |
| --- | --- |
| 问题与影响 | 已有权限 gate 与安全拒绝；完整体验还需解释究竟是哪项不可用，避免把所有失败都归为“权限”或让用户授予无关能力。 |
| 方案 | 分别呈现：①实际系统截图目录可读性；②仅自有入口需要的屏幕录制；③Chrome Automation；④Chrome Apple Events JavaScript 设置；⑤本次目标/ACK。各项独立显示尚未检查、检查中、可用、拒绝/撤销与准确动作。回到 App 只复查；已可读目录不再主推授权。 |
| 类／文件 | `RiftSetupController`、`SetupPresentation`；`Sources/RiftletApp/AutomationPermission.swift`、`FirstUsePreferences.swift` 的现有权威；Main 的来源/权限映射；`ScreenshotEntryHost`、`InteractiveScreenshotController`、`InteractiveScreenshotSystemCapture` 的错误呈现适配。 |
| 不变量 | inspect 不 request；只由明确用户动作请求相应权限。目录选择只接受实际来源、取消不改原绑定；不代改 Chrome 设置、不擅自启动/激活 Chrome。Automation 通过不代表 JS、目标或生产准入通过。撤权先结束未完成捕获，恢复后不重拍、不重放旧点击；intent 后未知按原 UNKNOWN/visibility。 |
| 验收 | 用现有 fake driver 分别缺少五项条件，确认文案/按钮只指向该项；三项系统访问各初拒/允许/撤销/恢复、Automation/JS 四组合、目录变更/误选/取消、Chrome 重启按本次差额选最小必要用例。普通系统文件收录不触发 Screen Recording；自有入口才请求。真 TCC、系统设置导航、IME/跨 App 焦点另记实际结果。 |
| 等待 | **W。** 系统设置路径以部署 OS 实测；无法直达提供手工路径，不假称成功。截图已保存但未收录只沿用既有本地入口和真实路径范围，本轮不新增“重试导入”。 |

### Q06 · 历史身份与清晰 Fit 预览

| 要素 | 最小工单 |
| --- | --- |
| 问题与影响 | 已有中文三栏、搜索本页、Finder、完整预览与恢复资格。详情复用 `320×backing` 小图到 640×480pt 预览，且缩略缓存 cap768px，细字易被放大；这是显示限制，不是原图损坏。[RiftHistoryController 249–284](https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletUI/RiftHistoryController.swift#L249-L284)、[ThumbnailCache 21–58](https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletUI/ThumbnailCache.swift#L21-L58)。 |
| 方案 | 标题“截图 · 日期时刻”，状态独立；必要时用现有短 ID 区分同秒图片。列表/详情/预览绑定同一 asset。现有 Fit 预览独立按可绘制 viewport×实际预览窗口 backing 请求像素、保持方向/比例，不升采样伪造信息。加载壳立即可开，显示加载/失败事实。 |
| 类／文件 | `Sources/RiftletUI/RiftHistoryController.swift`、`HistoryPresentation.swift`；复用列表 `ThumbnailCache`，建议独立 `HistoryPreviewLoader` 负责 ImageIO 显示解码；不更换 SDK。 |
| 不变量 | 每份显示位图≤16,000,000px，实际 `bytesPerRow×height≤64MiB`；全 App 至多一个高清解码 flight、只留当前一份；不扩大原列表缓存。选择/关窗/backing/文件身份变化使 epoch 失效，迟到结果丢弃；resize 合并建议120ms。64MiB不冒充进程峰值保证。原字节/ICC/上传 hash 不变；200条分页与当前页搜索不变；无100%缩放新功能。UNKNOWN 无放回/重输，其他恢复仍由原 Core 判定。 |
| 验收 | 合成细字横图、窄长图、小图在1x/2x验证请求像素、实际 rowBytes、比例与峰值；A→B→A、关窗再开、resize/换屏和缺文件只取当前结果。列表、时间、详情、预览同身份；预览不调 dispatch；原图/上传摘要不变。原生清晰度记录与 HTML 图稿分开。 |
| 等待 | **W。** 先比对新正式缓存和预览实现，已有清晰方案则保留。高清解码失败保留可用小图及解释，不靠重复全图解码追求成功。 |

### Q07 · 反馈提交、精确取消与删除

| 要素 | 最小工单 |
| --- | --- |
| 问题与影响 | nil endpoint 的“保存待发送”已经实现；服务能力与草稿状态仍需持续区分。候选 UI 用 `String.count`，后端用 `unicodeScalars`，组合字符可能界面未达限却被拒。记录动作需准确区分取消尚未提交、申请云删除与移除已解决正文。[FeedbackWindowController 80、123–125、278–295](https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletFeedbackUI/FeedbackWindowController.swift)、[FeedbackModels 66–77](https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletFeedback/FeedbackModels.swift#L66-L77)。 |
| 方案 | 服务能力行与草稿保存行分开，输入不能覆盖“当前不会上传”。UI复用提交校验：去空白非空、≤4000 Unicode scalars、≤16384 UTF-8 bytes，组字不截断。记录动作来自当前 engine 的只读资格：从未尝试才“取消待发送”；可能已提交则“申请删除”；删除处理中保留编号；cancelled/deleted 才使用既有正文移除。改为绑定反馈窗口的 `NSAlert.beginSheetModal`。 |
| 类／文件 | `Sources/RiftletFeedbackUI/FeedbackWindowController.swift`、`Sources/RiftletApp/FeedbackHost.swift`；模型校验复用 `Sources/RiftletFeedback/FeedbackModels.swift`。资格读取当前正式 `FeedbackEngine / FeedbackStore`，不要复制候选旧 attempts 判断；需要只读接口时最小适配并保留后端合同。 |
| 不变量 | 本地编号不是云回执，received不等于开发者已读；没有本地持久化成功不能称已保存待发送。sheet冻结 reportID/动作，actor执行前重判资格，重复确认不产生新请求；Escape/默认焦点保留，破坏性动作不是默认 Return。折叠不改记录数量/状态。保留原同ID幂等恢复、凭证与删除义务；不影响任何截图/UNKNOWN。 |
| 验收 | nil/configured、outbox、丢回执、received/delivered、删除待确认/受阻/完成各投影真实事实；纯空白/组合emoji/重音/中文与后端同判；sheet期间切选择、连续确认和资格变化不作用于错记录；取消后保留 cancelled。复用现有后端竞态测试，仅增加改变的 UI/投影边界，不重新实现服务。 |
| 等待 | **W，特别保留最新正式反馈后端。** 此项不是重新部署服务、创建目标仓库或索要凭据的任务；不得以候选旧engine覆盖正式修复。 |

### Q08 · 关闭、退出、IME 和保存失败解释

| 要素 | 最小工单 |
| --- | --- |
| 问题与影响 | 现有关闭已保护未加载、busy、marked text，退出会 await 保存；用户可见原因不完整，容易误以为关闭无响应。没有证据据此宣称草稿已丢失。[FeedbackWindowController 180–198](https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletFeedbackUI/FeedbackWindowController.swift#L180-L198)、[FeedbackHost 46–49](https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletApp/FeedbackHost.swift#L46-L49)。 |
| 方案 | 单一关闭意图覆盖窗口关闭、保存并关闭、Cmd-Q。marked text说明“请先完成当前文字输入”；busy说明正在保存并合并一次待关闭；失败说明正文仍在、提供显式重试保存与复制正文。正常已保存直接关闭，不增加确认。再次启动沿用 firstUse、隐藏/暂停、草稿及历史。 |
| 类／文件 | `FeedbackWindowController.saveBeforeClosing`、`FeedbackHost`、Main既有 termination 接线；建议 UI/Host `CloseIntent`，不是新反馈状态机。 |
| 不变量 | 不强制 unmark、不把 Return 改成发送；保存前编辑冻结边界保留；仅最新 revision 成功后关闭。失败恢复编辑，清掉会在未来无关编辑自动退出的陈旧意图；不新增enqueue/删除/强制丢弃。网络超时不冒充本地保存失败。重启不清 UNKNOWN、不重放上传、不自动打开所有辅助窗口。 |
| 验收 | 真实/模拟marked text分别标注；注入慢保存与失败，连续关闭/Cmd-Q仅一个事务，最后编辑仍在；失败后复制只复制用户正文；显式重试成功才关闭。重启比较可见性、暂停/隐藏、反馈草稿及UNKNOWN原身份。焦点回到正文/重试，AX只说明阻止原因。 |
| 等待 | **W。** 可先审阅状态文案；原生接线与真实中文IME/磁盘失败验收在合流后执行，无法取得的实机证据保持NOT_RUN。 |

### Q10-V · 受改动影响的环境与辅助功能验收

| 要素 | 最小工单 |
| --- | --- |
| 问题与影响 | 候选已有软件 AppKit、合成绘制与部分事件证据，真实1x、多屏/Spaces/全屏、物理鼠标、完整VoiceOver和组合App焦点仍未完整证明。这是证据边界，不能列为“这些环境已坏”。[固定原生取证说明](https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/engineering/evidence/2026-10-29-thin-edge-native/README.md)。 |
| 方案 | 从 `STATE_TRANSITIONS.md` ENV-01–12 中只选本次改变的具体风险：新说明/窗口的Space和层级、down/up及快速取消、1x/2x像素与换屏、运行时外观、键盘/VoiceOver、权限/IME/恢复。先利用已有软件与受控原生工具，再补无法替代的物理观察。 |
| 类／文件 | 验收对象为本次实际修改的 `RiftPanelController`、`ScreenshotEntryController/Host`、Setup/History/Feedback窗口及 `RiftDisplaySelection`；测试资产写入新的 evidence 目录，不改旧证据。此验证工单本身不要求新增产品代码。 |
| 不变量 | 合成CGEvent不是物理鼠标，HTML不是AppKit，helper置前不是最终产品跨App焦点通过；旧H上传/旧CI不改名为新SHA验收。只在既有授权的Mac与surface执行真实操作，不为填矩阵新开准入、复投UNKNOWN或删除数据。 |
| 验收 | 至少保存所改路径的 source SHA、App hash、macOS build、显示器/缩放、mode/权限、输入类别、实际事实、结果及证据路径。若改附近说明/窗口，观察普通Space↔全屏、切App不抢焦点、换屏无旧条；若改输入附近几何，用物理点击验证透明区穿透/取消；若改预览/垫片，补实际1x/2x像素。Keyboard/VoiceOver必须真实完整遍历才可PASS。 |
| 等待 | **W＋可用工程Mac及必要系统权限。** 设备不可用只标对应NOT_RUN/BLOCKED；不要求创始人Beta。已有只读证据整理现在可以做，不用等待。 |

## 5. P2 · 原生一致性补齐

### Q09 · 设置内嵌、窗口位置与 Cmd-,

| 要素 | 最小工单 |
| --- | --- |
| 问题与影响 | 五组设置已有；候选仍外跳动效窗口/入口菜单，归档留在菜单，显示器选择未内嵌。Feedback每次center，Setup/History已保留合法位置；设置菜单无Cmd-,。这属于已有设计差额，不重新设计设置。[RiftSetupController 262–289](https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletUI/RiftSetupController.swift#L262-L289)。 |
| 方案 | 将已存在的入口、入缝/显示、归档控制按正式五组设置归位，复用原存储与callback。Feedback首次居中，之后保留合法frame；完全离屏/标题栏不可达最小回收。按窗口分别记几何，设置与首用不互相覆盖尺寸。菜单增加Command+`,`，Cmd-W沿用正常关闭。 |
| 类／文件 | `RiftSetupController`、`ArrivalMotionSettingsController`、`RiftDisplaySelection`、`RiftVisualStyle.restoreWindowSize`；`FeedbackWindowController.show`；`ScreenshotEntryPreferences / ArrivalMotionPreferences`与Main既有菜单回调。不重写设置存储。 |
| 不变量 | 入缝仅无/磁力；Reduce Motion是系统覆盖，非第三选项。默认模式只影响下一次，不能动本次冻结请求或固定槽。归档/隐藏只改可见性，不删原图/历史；逻辑存储量不称可释放空间。frame记忆不意味着重启自动打开窗口；不更改系统截图快捷键。 |
| 验收 | 当前值、保存失败与系统覆盖准确；控制内嵌前后同一偏好结果。合法负坐标屏幕不被反复居中；再开/重启、断屏、完全离屏分别处理；Tab切页焦点稳定；Cmd-,打开设置、Cmd-W经过原关闭门槛。无新上传/数据库reset。 |
| 等待 | **W。** 逐项核对新正式设置已内嵌哪些；已有正确布局保留，不为了形式统一搬动足够优秀的部分。 |

### Q10-P · 编号垫片的一物理像素边框

| 要素 | 最小工单 |
| --- | --- |
| 问题与影响 | 候选 `RiftRowView.draw` 的编号垫片使用固定 `pad.lineWidth=0.5`，与正式 1/backing token 在1x下不一致；2x下数值恰好一致。1x实际视觉影响尚未测，不把它扩大为所有细线都错误。[源码219–222](https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletUI/RiftPanelController.swift#L219-L222)、[正式规格§2.2及垫片](https://github.com/haohongfei2001-png/Riftlet/blob/7e03bd2c26c6aa43dbac07b073e00d08d1951b71/design/final-system-20261028/APPKIT_SPEC.md#L39-L45)。 |
| 方案 | 此处沿用实际所属窗口的 `1 / backingScaleFactor` hairline及既有提高对比度规则；在实际backing坐标对齐描边，不手工重复乘scale。换屏/backing变化重新绘制。只补这处可证差额，其他线条按各自正式token核对。 |
| 类／文件 | `Sources/RiftletUI/RiftPanelController.swift` 中 `RiftRowView.draw`；必要时复用 `RiftVisualStyle` 的既有绘制工具，不建立新视觉系统。 |
| 不变量 | 逻辑垫片大小、圆角、编号、双输入岛与空隙穿透不变；不为变清晰扩展透明命中范围。原图比例/内容/上传字节、固定平面及模式槽均不变。 |
| 验收 | 同一1:8/8:1合成图在实际1x/2x的原生100%像素截图；普通边框分别1pt/0.5pt、无双边；换屏后不残留旧scale。检查图/编号点击矩形未变、外侧透明区仍穿透。原生渲染证据与几何检查分开；不为此小改动扩跑无关上传测试。 |
| 等待 | **W。** 当前可核对token与源码；新正式SHA若已改为同源hairline即保留。真实1x设备/环境不可用时保留对应未验收项。 |

## 6. 工程 Pro / Codex 可直接复制的短指令

```text
执行 Riftlet design/experience-quality-20261029/ENGINEERING_CHECKLIST.md 的选定 Q 工单。

先等当前正式集成结束，由集成负责人给出新正式 source SHA；只读读取该 SHA、最新 AGENTS/docs 与设计包，逐项核差异。已完成者标保留，不能照旧报告重复改。现在仅可设计review、文案核对和证据整理，不能接线。

从新 SHA 建独立实现分支/工作树；只采用 design/experience-quality-20261029/ 内的设计意图，不 merge 整个设计分支，不改 PR #1、main、另一Pro的分支/工作树/正在集成代码。一次完成最小相关工单，复用已有AppKit类、token与回调，不新增SDK或范围外功能。

Q01先修真实能力文案；其余按P1/P2选择最小增量。保持固定槽、移动X、真实uploadStarted才快吞噬、无成功Toast、点击时目标和陈旧回调守卫。保留原图/媒体/历史/UNKNOWN/历史锁及暂停隐藏；不重传未知、不启用safe retry，不清理数据。保留新正式Feedback后端修复及其同ID幂等恢复，不能用候选旧后端覆盖。

只补本次改变的具体风险验证，并履行已有必需gate；软件、合成CGEvent、浏览器、真实AppKit、物理输入与真实服务证据分开。记录精确SHA/hash、环境、观察及PASS/FAIL/NOT_RUN/BLOCKED，不借用旧结果宣称新组合通过。无Founder Beta依赖；缺设备/权限只挂起对应验收，其余授权工作继续。

交付改动文件、实际结果、未测边界、独立review及最小后续动作；不擅自合并、发布、扩准入或重复真实上传。
```

## 7. 完成判据

一个工单只有在“新正式 SHA 差额复核 → 对应最小改动 → 实际受影响验收 → 明确未测边界 → 独立审查”均有记录后，才可称该范围完成。`NOT_RUN` 不改写成 PASS，也不自动变成已知产品缺陷。本文件交付的是精确工程清单；没有声称已经运行其中任何新的原生测试。
