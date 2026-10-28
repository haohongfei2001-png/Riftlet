# Riftlet · 完整体验 AppKit 补充实施规格

版本：1.0 · 2026-10-29（北京时间）

**本文件为独立设计提案，尚未进入正式 App。** 它补全已批准「薄界」的使用与异常体验，不更换视觉方向、不改上传协议、不新增截图管理器。Q01–Q10 是本专项统一编号；本文详细定义 Q01、Q02、Q05–Q09，Q03、Q04 由本包的捕获/附加状态规格定义，Q10 是共同验收边界。

## 0. 集成条件与不可变边界

全部新增原生实现必须等当前正式集成结束，再从工程负责人确认的新正式 SHA 读取差异。以下源码定位固定到用户指定原生交接 `443d21da1a55c0061eafced823b5406879b96024`，产品候选为 `00dedc7f8164643c3435e3f87aa462e28af0b1c8`；它不是未来正式合流树的批准。本专项不修改 PR #1，不创建原生实现 PR，不覆盖 Main、Feedback 或他人的分支。

必须保留：固定模式槽、只移动取消盖片、真实上传开始后快速吞噬、开始与最终完成独立、无成功 Toast、原图/媒体/历史/UNKNOWN、点击时目标身份、安全失败与重试准入。系统截图习惯、无/磁力吸引两个入缝选项、减少动态 override 均保留。任何新的视图状态不得获得上传、再次输入、删除或清理权限。

Feedback 使用它已有的独立幂等投递与删除恢复机制；它的合规后台重试不能被截图 UNKNOWN 的“不重传”规则误删。反过来，Feedback 的幂等重试也不能借给截图附加使用。反馈后端应保留正式 `0e7ea8be` 已修复的定时器、丢凭证与删除竞态，禁止以候选旧后端覆盖它。

### 0.1 固定证据索引

下表是工程定位；行号仅用于固定 SHA，不要求后续文件保持原行号。

| 编号 | 证据与准确范围 |
| --- | --- |
| S01 | [首用与设置 controller，443d](https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletUI/RiftSetupController.swift)：86–120 状态更新；124–153 窗口展示；227–255 三步首用；262–289 五组设置。 |
| S02 | [能力/权限/来源文案，443d](https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletUI/SetupPresentation.swift)：107–179 来源与能力；200–225 动作守卫。 |
| S03 | [App 组合，443d](https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletApp/RiftletMain.swift)：169–170 首次展示；188–217 激活/退出；603–633 状态投影；691–727 来源/Automation 操作；1382–1445 菜单。 |
| S04 | [权限 gate，443d](https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletApp/AutomationPermission.swift)：34–81 原进程身份与只读检测；96–107 inspect/request 分离。[首次使用/来源书签](https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletApp/FirstUsePreferences.swift)：13–17 展示记录；20–68 实际目录校验。 |
| S05 | [主动截图 controller，443d](https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletCapture/InteractiveScreenshotController.swift)：75–100 主动启动/权限/屏幕变化；257–279 倒计时末权限复核。[系统捕获检查](https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletCapture/InteractiveScreenshotSystemCapture.swift)：14–16 Screen Capture preflight/request。 |
| S06 | [历史 controller，443d](https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletUI/RiftHistoryController.swift)：113–125 窗口/关闭；215–246 当前页过滤与动作；249–284 状态、详情及空格预览。[历史资格](https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletUI/HistoryPresentation.swift)：21–55 原操作对应、失败与恢复资格。 |
| S07 | [缩略缓存，443d](https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletUI/ThumbnailCache.swift)：21–26 缓存预算及 768px 上限；25–58 异步解码/epoch。 |
| S08 | [Feedback 窗口，443d](https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletFeedbackUI/FeedbackWindowController.swift)：80 已有条件主按钮；95–97 记录动作；123–125 字数；130–174 加载/保存；180–198 关闭；220–245 提交；278–295 删除。 |
| S09 | [Feedback 模型，443d](https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletFeedback/FeedbackModels.swift)：66–77 Unicode 标量/字节限制；81–115 本机状态、回执验证。[FeedbackHost](https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletApp/FeedbackHost.swift)：18–30 nil endpoint；46–49 退出保存。 |
| S10 | [正式 Feedback engine，0e7](https://github.com/haohongfei2001-png/Riftlet/blob/0e7ea8be148e1124b387e799fd886a7830e96559/Sources/RiftletFeedback/FeedbackEngine.swift)：120–125 scheduledWake 修复；149–162 删除/本机正文清理。[正式 store](https://github.com/haohongfei2001-png/Riftlet/blob/0e7ea8be148e1124b387e799fd886a7830e96559/Sources/RiftletFeedback/FeedbackStore.swift)：219–227 取消资格与已解决正文移除。 |
| S11 | [原生视觉组件，443d](https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletUI/RiftVisualStyle.swift)：7–31 字体/颜色/间距；43–65 外框/恢复；82–103 文字/按钮。 |
| S12 | [原生取证说明，443d](https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/engineering/evidence/2026-10-29-thin-edge-native/README.md)及 [results.json](https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/engineering/evidence/2026-10-29-thin-edge-native/results.json)：2x 合成原生绘制、软件 CGEvent、真机未测范围、设置未内嵌和大预览缓存限制。 |
| S13 | [正式视觉 token，7e03](https://github.com/haohongfei2001-png/Riftlet/blob/7e03bd2c26c6aa43dbac07b073e00d08d1951b71/design/final-system-20261028/TOKENS.json)及 [AppKit 规范](https://github.com/haohongfei2001-png/Riftlet/blob/7e03bd2c26c6aa43dbac07b073e00d08d1951b71/design/final-system-20261028/APPKIT_SPEC.md)。本规格复用它们，不发起新视觉方向。 |

### 0.2 证据与优先级语义

- **事实**：来自固定源码、原生图或明确测试结果。
- **提案**：本规格新增的呈现/行为要求，不能声称已实现。
- **待验证**：必须在未来组合 App 上得到实际证据，不能以浏览器原型代替。
- **P0**：真实能力和关键状态不能误导；本包中 Q01 是最小文案修复。
- **P1**：影响首次完成、异常理解、预览与恢复的质量补齐。
- **P2**：设置归位、窗口记忆和原生习惯完善。

## 1. 共用呈现约定

复用 `RiftVisualStyle` 的原生字体、token、card、按钮和外框。首用 560×520pt、设置 680×520pt、历史 760×560pt、Feedback 600×540pt 均沿用候选目标外框；不重画标题栏、交通灯或系统权限弹窗。正文13pt、辅助11pt、标题20pt及4/8/12/16/24/32pt间距沿用现有系统；内容变多时滚动，不缩小字。

原型的权限、延迟、上传、云回执都明确标注“设计模拟”。原生实现不得复用原型计时器推导业务成功。状态文本直接接投影；没有事实时显示“尚未检查/暂不能确认”，不得由按钮颜色或动画结束推导“已授权/已上传/已送达”。

普通状态不弹 app-modal；能在原窗口解释的状态用 inline 行。需要确认既有反馈删除动作时使用父窗口 sheet。关闭、返回和刷新保持键盘焦点；后台事件不重新打开窗口，不改变前台应用。

## 2. Q01 · 能力决定首用文案（P0，最小修复）

### 事实与影响

S01:238–250 的首屏及结束页未按 `SetupAttachmentState` 区分，普通 capture 首用同样显示“点一下，进入当前聊天草稿”；S02:147–148 却明确 productionDisabled 只收录。两者形成预期冲突。**本项只修呈现，不将生产能力提前开放。**

### 提案：保留当前三页结构，先修四组文案

| 模式/能力 | 首屏标题与关键说明 | 结束页 | 底部主动作 |
| --- | --- | --- | --- |
| `.productionDisabled` | “让截图停在手边” / “当前版本可在本机收录和查看截图。附加功能尚未启用。” | “继续使用系统截图。新截图会保存在本机，并出现在桌面边缘。”同时显示真实来源/暂停状态。 | “完成”；仅关闭引导，不暗中切换暂停或收录状态。 |
| `.systemScreenshotCandidate` | “截图停在手边，点一下附加” / “内部候选 · 仅支持已验证范围内的 Chrome 中文普通已有对话。” | 保留按实际能力生成的范围说明。缺权限时准确指出，不显示全部完成勾。 | “开始使用”；仅结束引导，不自动试传。 |
| `.syntheticWeb` / `.offlineSimulation` | “体验 Riftlet 的交互” / “合成演示，不是普通截图上传。”根据 mode 精确区别是否连测试网页。 | 标注合成数据和真实权限/上传范围。 | “完成”；仅结束当前模式的引导，不创建或打开新的演示入口，不读取真实媒体。 |
| `.available`（未来正式准入后） | “截图一次，点击一次” / 使用实际已准入支持矩阵。 | “回到当前受支持的聊天草稿，使用下一张截图。” | “开始使用”；不发送消息。 |

当前截图格式限制、候选状态、数据根、权限 gate 均不因文案变化而变。`available` 不能由点击“继续”、获授权或出现 composer 来设置。

### 接线与守卫

- 主类：`SetupPresentation` 增加纯文案投影；`RiftSetupController.rebuildPage()` 读取同一投影；`ApplicationMode` 的既有映射作为事实输入。
- `nextStep`、`recordPresentation` 的副作用不扩张；不写 permission、队列、adapter profile、dispatch intent。
- background update 仅换文本；已有 first responder 不因文本变更跳到默认按钮。
- 主标题、能力行、结束页和 accessibility label 必须同源，禁止只改可见文本留下相反 AX 描述。

### 验收 Q01-A

四类模式生成首屏/结束页快照；capture 首屏无可附加承诺，普通模式无 Chrome 必需授权动作。所有“继续/完成”只改变引导展示；原型、软件 AppKit 与真实首装三种结果分别记录。此项可以作为后续最小独立提交，不等待 Q02 的布局改动。

## 3. Q02 · 可选快速开始（P1）

### 事实与影响

候选已有三页原生首用、稍后设置、主动重开和一次展示记录（S01/S03/S04）；不是首用功能缺失。首尾静态说明可压缩，已可读目录无需再次授权。当前 accessButton:101–103 只检查存在路径，未因 source accessible 收敛。

### 提案：同一窗框，一页完成必要准备

这是 Q01 之后的可选改进，不要求在合流时替换已测三页。主区域从上到下为：一句操作说明；能力行；“系统截图位置”；“附加到当前草稿”（只在该模式适用）；可展开的详细范围。底部保留“稍后设置”和准确的完成动作。完整操作示意仍可从既有“使用引导”打开，不强制演练、不新增试传。

| 条件 | 主区域/动作 | 完成动作 |
| --- | --- | --- |
| 来源可读 + 当前模式只收录 | “已可读取 · 实际目录名称”；次要“在 Finder 中查看” | “完成”；不要求 Chrome 或屏幕录制授权。 |
| 来源可读 + 候选需要 Chrome | 展示所缺连接条件，已完成者仅状态行 | “完成”可用；缺项时保留“附加尚未就绪”文字，不能显示完成勾。 |
| 来源暂不可读 | 原因 + “检查目录访问…”；可选系统设置路径说明 | “稍后设置”始终可用；关闭不是授权。 |
| 正在检查 | 当前行“正在检查…”；禁用该项重复动作 | 保留关闭，不自动跳下一页。 |
| paused | “收录已暂停”；次要“继续收录”沿用独立动作 | 完成不得自动取消暂停。 |

建议删除以“认识→连接→开始”强制记忆的步骤条；不是删除帮助内容。说明留在与当前缺口相关的行中。窗口大小/颜色/控件沿用薄界，避免为减少步骤另建新卡片语言。

### 接线、无障碍与验收 Q02-A

`SetupSnapshot`/`SetupPresentation` 为单一事实来源；仍使用现有 source callback、permission gate 和 `FirstUsePreferences` 的 mode 隔离。若记录版本变更，不得清除旧“已展示”偏好使所有用户重新弹窗。可读目录路径的额外授权次数为0；正常已具备条件路径只需一次完成动作；关闭与后台导入不重开。Tab 顺序是未完成项的动作→可选详细信息→稍后→完成；动态状态只播报变化行，不重复整窗。

## 4. Q03 / Q04 · 与捕获及附加状态设计的接点

Q03 的倒计时、采集中和模式切换来自 `InteractiveScreenshotController` 的真实状态；Q04 的等待附加、未开始、严格 uploadStarted、UNKNOWN、已准入真实失败来自现有持久操作/投影。本文件不另建这两个状态机。

设置、首用与历史只消费它们，不在切到某个设置页面时新建 target、不重放点击。捕获错误定位到 Q05 的相应能力行；附加 UNKNOWN 定位到 Q06 的原记录；不能用“重新检查”按钮重传。固定槽、移动取消盖片和快速吞噬按本包对应状态规格实施。

## 5. Q05 · 权限与环境恢复（P1，关键守卫为 P0 保留）

### 5.1 三项系统授权与一个浏览器设置必须分开

这里的“三项授权”指截图目录、主动捕获所需屏幕录制、Chrome Automation。Chrome JavaScript 开关不是 macOS 系统权限；当前草稿是否有效又是独立业务事实。

| 能力/授权 | 何时需要 | 不应阻止什么 | 当前接线 |
| --- | --- | --- | --- |
| 系统截图目录访问 | 收录系统保存为文件的截图 | 已有历史查看；不要求用户因此开屏幕录制权限 | `ScreenshotFolderAccess`、capture source binding，S03/S04。 |
| 屏幕录制/屏幕捕获授权 | 用户主动点 Riftlet 自有截图入口 | 已有系统截图文件收录；已有历史查看 | `InteractiveScreenshotController.start()`、preflight/request，S05。 |
| Chrome Automation | 已启用 Web adapter 的明确候选/支持模式 | 普通本地收录及离线演示 | `AutomationPermissionGate`，S04。 |
| Chrome Apple Events JavaScript | 浏览器连接所需独立设置 | 不把 OS Automation 成功称作该开关已打开 | 现有帮助文案 + 原 Web 观察结果；不代改 Chrome 设置。 |
| 原当前草稿可验证 | 每次真实点击与输入边界 | 不作为永久“连接成功”配置位 | 原 target lease/复核机制；不在新设置中重实现。 |

### 5.2 UI 状态和动作守卫

| 状态 | 精确说明/动作 | 守卫 |
| --- | --- | --- |
| 未检查 | “尚未检查” / “检查状态” | 被动 inspect，不请求授权，不发测试附件。 |
| 检查中 | “正在检查…” | 同能力 single-flight；不能连续点击启动多个授权/面板。 |
| 文件夹可读 | “截图位置可读取” + 简短目录名 | 隐藏主授权动作；仍可通过次级“更改访问…”重选**当前实际目录**，不能改系统保存位置。 |
| 文件夹不可读 | “暂时无法读取当前截图位置” / “检查目录访问…” | NSOpenPanel只目录；提交时重读实际系统来源再比对；取消不改变旧书签/监听/数据。 |
| 文件夹改变 | “系统截图位置已变化” | 旧目录读取成功不能把新目录标绿；同样不自动把任意目录当来源。 |
| 系统截图只到剪贴板/无文件夹 | “截图需要保存为文件才能自动收录” | 展开系统截图工具栏“选项”说明，不写系统偏好；保留既有截图习惯。 |
| OS 未请求 | “需要此权限才能使用当前功能” / “继续…”或“检查权限…” | 仅明确动作调用系统 request；不在启动、hover、模式切页或轮询中请求。 |
| OS 已拒绝/后来撤销 | “此权限当前不可用” / “打开系统设置…” | 不反复 request，不重置 TCC；实际系统路径按所运行 OS 核验，无法直达时回退设置并给手工路径。 |
| Chrome 未运行/实例变化 | “请先打开受支持的 Chrome 窗口” | 不擅自启动/激活；新 PID+launchDate 需新检查；旧点击不等待后自动执行。 |
| Automation 已允许、JS未证 | “系统已允许自动化；浏览器连接仍待检查” | 不用绿色“已连接”覆盖未验证条件；只展示手工开关说明和只读复查。 |
| 回到 App | 原行显示复查结果 | 复用既有激活/唤醒恢复，不开新向导、不新授权、不恢复已取消点击。 |

设置中“已允许”只说明该权限；“可以附加”只可来自能力和实时有效目标各自的真实事实，不持久保存可绕过后续检查的 ready flag。屏幕录制权限在倒计时末撤销时，停止当前捕获并给对应解释，不把没有文件误称收录失败；原有队列和历史不受影响。

### 5.3 原生接线与验收 Q05-A

主类：`RiftSetupController`、`SetupPresentation`、Main 的 inspect/request/捕获错误映射；`AutomationPermissionGate`、来源书签和捕获 permission checker 保持原权威。新增屏幕捕获状态行只消费真实 checker，不能用自动请求来“检测”。文件夹 authorization 面板按窗口绑定，在选择中保持被选路径与 source revision，完成后复核。

AX label 应包含对象与事实，例如“系统截图位置，可读取”“Chrome 自动化，尚未请求”。不可只读绿色点；禁用按钮的原因有相邻可读文字。变更权限不要移动当前焦点；系统弹窗关闭后回到发起动作，不聚焦隐藏的成功按钮。

有限验收矩阵：三项授权分别初拒/允许/撤销/恢复；Automation与JS四组合；文件夹变更/选择错目录/取消；Chrome退出重开；屏幕录制在倒计时末撤销。检查每条路径的截图外部输入次数为0或原操作允许的一次，不出现复查自动输入。真实 TCC/系统设置跳转、跨应用焦点必须单列真机结果。

## 6. Q06 · 历史识别与清晰预览（P1）

### 6.1 已有与缺口

候选已有中文三栏历史、原比例详情、空格/双击预览、UNKNOWN 说明和 Core 控制的“放回裂缝”资格，全部保留。真实限制是 S06:271–284 请求 `320×backing` 的详情图后直接复用于640×480pt大窗口，且 S07统一cap768px。大图细字被放大；这不是原图/上传文件损坏。

### 6.2 识别与动作

详情标题使用“截图 · 当地日期和时刻”，状态独立在下方，避免标题与正文全都只说“待核实”；若同秒同尺寸多图，次级显示现有 sequence 或短 asset ID，只用于区分，不作为上传新身份。完整 ID 在显式详情中可复制；列表不暴露原完整路径。原200条/页和当前页搜索保持，搜索栏继续明确“搜索本页”，本轮不扩张全库搜索。

| 状态 | 详情说明 | 允许动作 |
| --- | --- | --- |
| 未附加/待用 | “保存在本机” | 原资格允许时放回裂缝；不立即上传。 |
| 已确认附加 | “已取得本次附加的完成证明” | 预览/Finder；不因查看自动恢复队列。 |
| UNKNOWN/未决 | “尚不能确认这次附加的结果。原记录保留，不会再次附加。” | 预览/Finder/已有只读核对；无“再试一次”。 |
| 已准入明确失败 | 依据原 receipt 和 Core 资格表达 | 保留现有正常重生/恢复资格；设计不新授予 retry。 |
| 缺本地副本 | “本地副本暂不可用” | 不放空白假图；说明可查看系统原截图所在位置（仅路径仍有效时）。 |

### 6.3 清晰预览像素预算（新增提案值，不是已有验收）

本轮仅增强现有 Fit 预览，**不新增100%缩放、编辑或导出功能**。窗口尺寸、Escape关闭与原比例保持。

1. 使用实际可绘制 viewport 的点尺寸 `(Vw,Vh)`，扣除窗口 chrome、标题和状态行。读取**预览所在窗口**当前 `backingScaleFactor=b`；不借历史窗口或主屏倍率。
2. 按经过方向解释的显示尺寸 `(Iw,Ih)` 计算 `f=min(Vw/Iw,Vh/Ih,1)`；显示图大小 `(Dw,Dh)=(Iw*f,Ih*f)`。请求像素 `Pw=min(Iw,ceil(Dw*b))`、`Ph=min(Ih,ceil(Dh*b))`。不得为了填满预览裁切原图；小图不虚增信息。
3. **每份最终显示解码图 ≤16,000,000 pixels，实际 `bytesPerRow×height ≤64 MiB`。** 按比例降低 Pw/Ph 同时满足两限；不能把“像素×4”的估算当作实际字节检查。高位深/特殊颜色图若输出占用更大，进一步降低分辨率，明确为显示降采样。
4. 独立 `HistoryPreviewLoader`（建议命名）采用**单 flight**：全 App 同时至多一个清晰预览解码；只保留当前预览一份清晰位图，原列表 ThumbnailCache 的16MiB/32项预算不扩大。不累积高清图缓存。ImageIO按目标thumbnail解码，避免主线程全源像素展开。
5. request key = assetID + 本地文件身份/版本事实 + window epoch + viewport像素桶 + backing。新选择、关窗、历史关闭、screen/backing变化递增epoch；完成时再次比对，不匹配就释放，不能复开旧窗口或覆盖新图。
6. Resize debounce建议120ms；旧预览继续显示，只有当前合并请求解码。关窗/换图立即作废，不等debounce。解码未完成前空格也应打开预览壳，显示“正在加载预览…”，而不是因 `detailImage == nil` 无响应。
7. 初始可用详情小图可暂时显示，并标“正在加载清晰预览…”。成功后去除该标签；若预算导致降采样且源图更大，使用“已按窗口显示”这种准确说明，不标“原始像素”。失败时“无法加载预览，图片记录仍保留”，提供已有Finder动作。
8. 输出64MiB是**显示位图上限，不是整个进程峰值保证**。验收记录解码期间总峰值；实现不得为了达到像素目标同步展开16-bit/HDR巨图。超预算失败保留低清预览，不OOM式重试，不改源字节/颜色元数据/上传hash。

### 6.4 接线、AX与验收 Q06-A

主类：`RiftHistoryController.previewSelected()` 调用独立 loader；列表仍走 `ThumbnailCache`；原 restore/remove 回调和 Core 守卫不变。预览面板 first responder 接 Escape/Space；加载状态只播报一次，图像AX描述包含时间、尺寸和状态，不读取图像内容。窗口关闭不会更新 operation 或可见性。

用全合成细字截图验证3840×2160横图、窄长图、小图，分别在1x/2x与跨屏backing变化下检查请求像素、实际rowBytes、比例、取消结果。快速连续选择A/B/A、加载中关闭再开、resize、缺文件各一次；迟到结果不可污染新选择。源/上传字节摘要相同；检查新预览加载完全不调用 dispatch。真实清晰度/内存结果单列，不以浏览器图稿代签。

## 7. Q07 · Feedback 本地、云端与删除语义（P1）

### 7.1 已实现，保留

S08:80 已有 `configured ? 发送反馈 : 保存待发送`；草稿自动保存、默认不附诊断、冻结诊断预览、关闭前保存和独立本机记录都已存在。不能再提“新增反馈后端”或把本地编号当云端回执。正式后端修复S10优先于候选继承的旧Feedback实现。

### 7.2 当前状态与主动作

| 事实 | 固定说明 | 主动作/记录状态 |
| --- | --- | --- |
| endpoint未配置 | “接收服务尚未启用。反馈可保存在这台Mac，当前不会上传。” | “保存待发送”；禁用任何声称立刻送达的动作。 |
| endpoint已配置、草稿尚未提交 | “草稿保存在这台Mac；关闭不会发送。” | “发送反馈”；只由明确点击创建/复用既有幂等提交。 |
| 已入本机outbox | “已保存在本机，等待服务接收” | 展示**本机反馈编号**，不显示云端勾。 |
| 网络异常/丢回执 | “尚未确认服务接收；本机记录保留” | 保留已有engine对同一report ID的幂等恢复；不能创建一个新report重投同内容。 |
| durable received | “服务已接收” | 仅匹配id且durable回执产生；不等于开发者已读。 |
| delivered | “已进入私有反馈中心” | 保留现有事实，不称人工处理完成。 |

服务配置状态与草稿保存状态使用两条信息行：自动保存不能覆盖服务未配置说明。输入时也不不断播报“已保存”；必要状态留在底部。

### 7.3 记录动作按原engine资格投影

新增只读 `FeedbackActionAvailability` 投影是**提案**；资格必须来自当前正式engine/store，禁止UI复制旧的 `attempts==0` 判断。UI不能仅凭缓存状态承诺未发送；实际执行前在actor内按原ID重判定。

| engine确认的事实 | 动作 | sheet标题与说明 | 完成后的显示 |
| --- | --- | --- | --- |
| 明确从未实际尝试网络提交 | “取消待发送” | “取消这条待发送反馈？” / “它尚未发送；取消后保留本机记录。” | 仅真实cancelled显示“已取消本机投递”。 |
| 已尝试/可能已到服务/已接收 | “申请删除…” | “申请删除这条反馈？” / “收到确认前保留编号与必要记录。服务会处理删除，当前不会重发正文。” | deletionQueued/pending与deleted分开。 |
| 正在删除 | “删除处理中” | 无重复确认框；“刷新状态”沿用现有单flight | 不因对话框关闭显示删除成功。 |
| 删除受阻 | “查看原因” / engine允许时“重新申请删除” | 只恢复原ID的删除义务，不重发正文 | 原凭证/义务保留，不能借清理绕过。 |
| cancelled或deleted | “移除本机正文…” | “移除这条本机反馈正文及访问凭证？” / “只影响这条已取消或已删除反馈。” | 严格沿用既有forgetResolved；不连带截图/历史。 |

执行 sheet 前冻结 `reportID` 与动作类型。sheet期间选择其他记录不改变操作对象。确认后动作行进入busy；重复点击不新增请求。actor重判定失效时解释“这条记录的状态已变化，请重新查看”，不靠UI旧判断硬执行。

`NSAlert.beginSheetModal(for:feedbackWindow)` 取代两处app-modal `runModal()`；它是窗口局部确认，不扩大权限。Escape/取消对应保留；破坏性移除不设置默认Return。动态按钮AX名称包含所选记录短编号与动作，如“取消待发送，反馈RF-12345678”。

### 7.4 字符计数与后端限额一致（可证差异）

S08:124–125 使用 `String.count`；S09:67–68使用 `unicodeScalars.count≤4000` 且 `utf8.count≤16384`。组合emoji可能界面未达4000而实际被拒。

提案：UI复用与提交相同的纯校验函数，显示“文本长度 n / 4,000”，帮助说明“按Unicode标量计，另有16KiB限制”；普通中文不增加技术文字负担，只有接近/越界时显示具体原因。不得用JS `length`、grapheme数或UTF-16码元数冒充后端计数。组字中保留完整文本、不截断、不自动提交；提交按钮状态与校验一致，仍在engine重复验证。字节超限时显示“文字超过本次发送上限，请缩短后重试；原文已保留”。

### 验收 Q07-A

nil/configured、queued、lost response、received、delivered、blocked、deletion states、cancelled/deleted逐项投影；本地编号从不等价云端成功。用组合emoji/重音字符/ASCII/中文测试UI与后端同判，真实IME另测。删除sheet期间切换记录、连续点击、凭证丢失、claim竞态保持原后端合同。反馈对截图路径的对照只验证此次UI改动是否干扰，不能因此重复旧UNKNOWN上传。

## 8. Q08 · 关闭、退出与再次启动（P1）

### 事实与问题

现有 `saveBeforeClosing` 已安全拒绝未加载、busy、marked text；退出会await保存并锁住编辑（S08:180–198、S09 Host:46–49）。问题是拒绝原因未全部可见，不能为“退出流畅”删掉保护。

### 提案状态

| 条件 | 用户看到 | 行为 |
| --- | --- | --- |
| 草稿已保存、无组字 | 正常关闭或退出 | 不新增确认；不等截图完成才允许退出。 |
| IME marked text | “请先完成当前文字输入，再关闭。” | 留在编辑器，保留组字与选区；不强制unmark、不把Return改成发送。 |
| 本机保存正在进行 | “正在保存草稿…” | 合并一个待关闭意图；完成后执行一次关闭，不要求反复点击。 |
| 提交尚在本地提交事务 | “正在保存本次反馈…” | 等现有提交结果并保留原幂等ID；不取消成另一次enqueue，不再发一份。 |
| 保存失败 | “草稿还未保存，文字仍在这里。” + “重试保存”“复制正文” | 窗口保留；复制由用户显式触发，只复制反馈正文；不删除任何历史/反馈记录。 |
| 存储不可用 | 同上 + 清楚说明只能保留当前窗口文本 | 不伪称已保存；本规格不新增自动丢弃或强制退出路径。 |

建议 `CloseIntent` 为UI/Host的单个待处理意图（none/window/app），只描述用户这次关闭意图，不是新的反馈业务状态机。`windowShouldClose`、保存并关闭、Cmd-Q都汇入同一路径；重复Cmd-Q不并发启动多次termination transaction。app退出成功后才清除意图；失败恢复编辑，意图不在未来无关编辑时自动再次退出。

保存未完成前保持原编辑冻结边界；任何后续await都不能重新开放编辑导致退出漏保存。若用户在IME提示后继续编辑，新的关闭必须重新保存最新revision。保存超时不能自动丢弃，网络超时不冒充磁盘保存失败。

重新启动：沿用原firstUse展示位、暂停/隐藏、原候选数据根、Feedback草稿/队列及截图历史；未知截图仅由既有恢复只读核对，不自动再次输入。不要为了展示“恢复完成”去清UNKNOWN或重建队列。正常再次启动静默留在菜单栏；必要异常在状态入口说明，不自动打开全部辅助窗口。

AX：关闭受阻仅播报简短原因，焦点回原编辑器/具体重试动作；busy时可读状态保留，焦点环不落到被移除的控件。关闭流程与Feedback诊断勾选没有关联副作用。

### 验收 Q08-A

保留原连续关闭/重开、最后一次编辑、lockOnSuccess、marked-text软件用例；补观察可见原因和焦点。注入慢本地保存/失败，连续关闭与退出各一次；确保只写最新revision、无额外enqueue、失败不失文本。真实中文IME/Keychain/磁盘拒绝需有限真机证据。重启后比对可见队列、UNKNOWN操作身份和反馈草稿，不重复旧上传。

## 9. Q09 · 设置内嵌、窗口位置与标准入口（P2）

### 事实

正式设计已包含完整五组设置；候选仍把入缝偏好打开独立窗口、截图入口配置打开原生菜单、归档留在菜单，没有显示器选择控件（S01:263–278、S12已知差异）。这属于**已设计未完全实现**，不新发起设置设计。

Setup/History已保留合法位置；Feedback `show():143` 每次center，存在窗口一致性差异。“设置…”菜单S03:1389无Cmd-,。

### 提案与守卫

1. 按既有设置设计逐项内嵌现有控制；保留原持久设置类型和callback。入缝只无/磁力；系统减少动态作为覆盖状态，不变成第三选项。当前实际生效值与保存失败清楚表达。
2. 入口默认模式只影响下一次会话。当前打开会话保持固定模式槽；设置页不能移动取消盖片所关联的逻辑选中状态或自动开始捕获。
3. 归档只改变可见性，现有期限是可调工程起点；不在本规格新增“推荐24小时”批准，不新增自动删除/存储回收。存储量是逻辑大小，不是可释放大小。
4. Feedback首显居中；随后合法位置/大小保留。沿用共享restore策略，完全离屏或标题栏不可达时最小回收；跨负坐标屏幕不反复居中。设置/首用可共享窗口实现但必须保留各自尺寸槽，不能互相覆盖。
5. 如增加跨重启frame记忆，分别使用稳定autosave name（建议 `Riftlet.Settings`、`Riftlet.History`、`Riftlet.Feedback`），只保存几何不保存强制打开状态；屏幕拓扑变化复核visibleFrame。
6. 设置菜单添加`keyEquivalent=","`、Command修饰；窗口内Cmd-W使用正常关闭流程。此为macOS标准访问，不更改系统截图快捷键、不要求日常新快捷键。

AX与验收：侧栏选中状态、标题、当前控件有稳定标识；键盘切换设置不把焦点丢给已隐藏页面。跨屏合法摆放、完全离屏、再次打开、显示器断开、普通重启测试；所有变化无新上传、无数据库reset、无修改原图。

## 10. Q10 · 像素、辅助功能与环境验收（共同门槛）

以下不是“发现都坏了”，是候选交接明确未完全验证的边界。只有受本次改动影响的路径需要新增证据，不要求全面重跑已有上传/H证据。

| 类别 | 必须保存的有限证据 | 不允许的替代结论 |
| --- | --- | --- |
| 1x/2x/缩放 | 新状态行/细线/预览在实际backing下清楚；viewport与实际解码像素记录 | 不把CSS像素等于真实Retina通过。 |
| 小屏 | 最小窗框下正文不裁切、固定底部主动作可达、长中文自动换行 | 不缩小到难读字号以通过截图。 |
| 全屏/Spaces/多屏 | 主动打开窗口的Space归属、标题栏可达、断开屏幕恢复、预览取消 | 不以helper提高层级的视觉截图证明产品前台/层级。 |
| 外观/减少透明度/对比度 | 动态变化后所有新图层/文本/焦点可辨；颜色不是唯一状态标记 | 不只测启动时浅色/深色截图。 |
| Reduce Motion | 新状态转换无强制空间动画，不改变事件门槛；旧快吞噬受已有系统偏好规则 | 不以减动画为由伪造立即开始或完成。 |
| Keyboard/VoiceOver | 首用、权限恢复、历史、Feedback、sheet/关闭的完整焦点链；状态仅在变化时适量播报 | 不把设置accessibilityLabel等同真实VoiceOver验收。 |
| 实机权限/IME | 三授权独立恢复、Chrome设置实际路径、真实中文组字关闭 | 不用软件marked text或模拟权限代签。 |
| 数据/安全 | 原截图/UNKNOWN/历史/反馈身份保留；改动不产生额外外部输入 | 不通过删库、隐藏失败或重传旧记录“修复”。 |

## 11. 工程包切分与交付完成条件

| 顺序 | 内容 | 完成标准 |
| --- | --- | --- |
| 1 | Q01文案投影 | 最小改动；模式条件事实一致；不扩张业务副作用。 |
| 2 | Q03/Q04/Q05关键状态解释 | 各自权威状态同源；错误定位到正确恢复动作；不重放点击。 |
| 3 | Q06预览 + Q07/Q08反馈异常 | 像素/内存/epoch限额、幂等记录动作、保存关闭安全门槛全部可验证。 |
| 4 | Q02快速开始、Q09设置与窗口一致性 | 独立体验改进；不成为阻断最小P0修复的依赖。 |
| 每包 | Q10对应环境验收 | 只补本包改变的风险；精确SHA/环境/结果/NOT_RUN，不累计虚假全量PASS。 |

工程开始前先复核最新正式组合是否已解决某项：已解决则标“保留”，不重复实现。每个包提交前列出实际改动文件、原业务合同未变的证据、软件测试与真机未测边界。设计原型的六组场景（开始、捕获、附加、设置恢复、历史预览、反馈退出）是可审查的意图说明，不能替代正式App验证。

## 12. 官方依据

- [Apple HIG · Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)：快速、可选、延后非必要配置。Q02的具体布局和优先级为本专项判断。
- [Apple HIG · Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy/)：在实际功能需要时请求权限，说明具体用途；自绘说明不冒充系统授权结果。
- [NSAlert](https://developer.apple.com/documentation/appkit/nsalert)及 [beginSheetModal](https://developer.apple.com/documentation/AppKit/NSAlert/beginSheetModal(for:completionHandler:))：app-modal与父窗口sheet的作用范围。
- [NSWindow.setFrameAutosaveName](https://developer.apple.com/documentation/appkit/nswindow/setframeautosavename(_:))：独立frame名称与默认系统存储。窗口恢复策略仍需按实际多屏环境验收。

**本文件完成的是补充设计规格；没有新增原生源码、没有改变准入、没有发送反馈、没有执行删除、没有合并或修改任何现有PR。**
