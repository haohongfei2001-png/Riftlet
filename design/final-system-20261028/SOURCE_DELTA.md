# 当前工程 →「薄界 / Quiet edge」差异与 Codex 实施交接

状态：设计交接，**本轮未修改原生源码**。固定正式基线`1920e0562db893a3292af89a89270a26ddb46a5f`，独立预测入口来源`5d6a683652d255af8c1d3e0d9533587fcc27a24d`。本文件不要求重复合入Feedback、fa74体验修复或真实上传代码。

## 1. 实施前唯一入口

后续正式工程负责人先重新读取远端HEAD、活跃工程分支与设计批准记录，再建立独立实现worktree。按真实Git祖先关系继承预测入口；不要把它的旧Main覆盖到最新正式Main。保持PR #1 Draft，不合main、不发行、不配置Feedback云端。

本设计分支只新增`design/final-system-20261028/`。完整源码现状与精确数值见[原生界面审查](research/native-surface-audit.md)；目标参数见[APPKIT_SPEC.md](APPKIT_SPEC.md)。浏览器原型只模拟产品状态，不连接真实Chrome、Core、SQLite或Feedback网络。

## 2. 原生文件差异清单

| 当前文件/模块 | 当前事实 | 目标差异 | 不可改变 |
| --- | --- | --- | --- |
| `RiftConfiguration.swift` | 72×56、25%遮挡、60pitch、0.7线、外8、首槽180；多个工程动效参数 | 保留fit/遮挡/pitch；外14、稳定首槽202；集中token；明确arrival与swallow独立 | legacy设置可读；参数验证；不把数据删除作为迁移 |
| `RiftLayout.swift` | 大队列为容纳底部抬高首图；min44只是行包络 | 稳定首槽；明确overflow容量与28pt分页保留；极端比例编号垫片；字形实测宽 | 等比原图、可见图片/编号精确几何、空队列line=zero、资产排序 |
| `RiftPanelController.swift` | 三NSPanel/行；输入岛；220ms淡入、120ms吞噬、180ms补位；tooltip/AX；ReduceMotion仍移动 | 统一绘制token；左角1.5；60/80按压；160补位；450ms peek；非空间ReduceMotion；准确中文AX | 原窗口/事件/owner/revision/generation；strictStart触发；无successToast；decorative穿透；UNKNOWN只读 |
| `ThumbnailCache.swift` | utility串行缩略图、16MiB/32项cache、实际scale、768px上限 | 复用；peek只请求必要更大尺寸、离屏不持续解码 | 原文件、色彩/ICC、hash、尺寸、上传字节 |
| `RiftDisplaySelection.swift` | preferredID→main→availablefirst | 复用；同一F驱动入口和队列几何 | 不从到达时鼠标猜截图来源、不改原目标 |
| `RiftSetupController.swift` | 610×660 content长状态表，12pt正文 | 外框560×520首用、680×520设置；必要步骤与日常状态分层；13/18字体 | 主动授权；刷新不激活；first-use显示记录；关闭不表示许可 |
| `SetupPresentation.swift` | 完整闭集状态和支持说明 | 新层级只重组已有事实；保留所有阻断原因、候选范围和local/remote区别 | 不把普通上传关闭解释成权限；不把granted解释为targetverified |
| `RiftHistoryController.swift` | 英文720×500content表；92预览列、68行；200本页搜索 | 中文760×560外框三栏；152/260/余量；64行、56×44preview；详情与按需标识 | 分页事实；Finder定位不上传；动作来自Core资格；刷新不前置 |
| `HistoryPresentation.swift` | 已区分confirmedfailure与pre-inputfailed、needsVerification、restoreeligibility | 保留判断，映射新视觉标签；UNKNOWN明确“待核实” | 旧operation/attempt/target/hash验证；不能通过改名授予retry |
| `RiftletMain.swift` | owner/revision-safe反馈；prepared/cancelled投影；Feedback全部hooks | 只做新UI初始化、设置和状态传递的最小接线 | selectionRejected、assets/operations、uiProjectionDeferred；原ACK/目标/点击；FIFO；退出保存 |
| `ProductStatus.swift` | exact reason→闭集中文；supportDescription明确candidate | 复用或按同一闭集优化短/长文案层级 | unknown reason中性回退；不持续误称未输入；不扩大支持 |
| `LifecycleSettings.swift` | 可调24h工程默认、nil关闭 | 设置窗口调用已有保存；显示用户现值，不新增强制清理政策 | original/private bytes、history、audit；hover/selection保护归档 |
| `ApplicationMode.swift` | capture与candidate独立；REALTEST标记 | 内部标识更成熟但仍清楚；普通模式不能静默切candidate | 四模式/data root/准入语义 |
| `FeedbackWindowController.swift` | 560×560content单列全部任务；120msautosave；nilendpoint仍“发送反馈” | 600×540外框、同窗本机记录折叠区、13/18正文；未配置“保存待发送” | 草稿revision、IME、关闭重开保存、显式submit、单次诊断、取消/删除生命周期 |
| `FeedbackHost.swift` | endpointnil，独立Feedback-v01/Keychain，白名单诊断 | 仅提供真实configured状态给UI（若现有engine状态不够） | 无部署、不新采集截图/聊天/路径；不写Core；所有退出hooks |
| `ScreenshotEntryModel/Controller.swift`（独立分支） | 已有36/132、32pitch、17glyph、双alpha、预测/取消/固定会话槽 | 继承实际源码；anchor与新裂缝共面且上下66；统一token/系统无障碍；其余最小差异 | 固定槽；默认影响下会话；取消盖片；截图后保持展开；输入不等动画 |
| `ScreenshotEntryHost/Preferences.swift`（独立分支） | 入口/系统捕获及默认模式接线 | 只接入新设置与共同几何 | 捕获操作身份、设置持久化、屏幕源信息、无自动上传 |
| 新UI token资源 | 当前没有统一产品token | 建立单一语义色、字体、间距、尺寸与motion资源；AppKit展示只读 | 不用token或任意配置控制准入/策略 |

## 3. 不在本次视觉实施中改动的区域

- `Sources/RiftletCore/`：SQLite v3、操作身份、可见性、失败/恢复资格、原点击顺序不重写。
- `Sources/RiftletAdapters/` 与页面脚本：v9/v10/v12/v13兼容、严格sRGB内容证明、uploadStarted、完成证据不更改。
- 既有`Sources/RiftletCapture/`收录、原文件、hash、ICC和私有副本不因视觉缩略图而重编码。
- Feedback Core、云端服务源码、Keychain、独立SQLite和隐私白名单不重做；服务未部署。
- 历史真实证据与审计不改写；旧UNKNOWN的operation/attempt/锁不清理。

如果新设计只能通过改变这些区域才能实现，先把受影响点作为明确工程依赖单独提出，不用“视觉优化”覆盖授权范围。

## 4. 对应 HANDOFF 的五个实施阶段

本节是[HANDOFF.md 第3节](HANDOFF.md#3-五阶段最小实施顺序)的源码接线摘要，顺序与阶段编号完全一致；详细实施要求与验收边界以该交接为准，不再维护另一套四阶段计划。

### 阶段一：统一 tokens 与原生辅助界面

实现token、中文文案一致性、首次使用/设置/历史/Feedback的统一层级。先保留裂缝上传路径原样，使用已有回调和闭集状态。Feedback未配置文案优先修正；记录浏览和删除不挤占编辑主任务。

交付：原生各窗口100%尺寸截图，明暗主题、最小窗口、长文案、键盘顺序；确认关窗/重开和IME安全逻辑仍走原实现。不要因改了字体再跑一轮真实截图上传。

### 阶段二：裂缝几何、可见命中与可选完整预览

实现外14、首槽202、稳定60pitch、overflow、可见编号垫片、细线与小左圆角。保持独立图片/编号输入窗口；先把drawing和input从同一个布局结果生成。随后添加完全穿透的peek和准确AX自定动作。

交付：1366×768、1440×900、1728×1117；0/1/3/12图；1:8与8:1；真实Clear/Gap/Image/Number命中与原位doubleclick；按住跨reflow；peek出现/关闭不抢焦点、不延迟原事件。只验证改变的命中与视觉风险，不重新宣称旧上传范围扩大。

### 阶段三：预测入口按真实祖先组合

按祖先关系集成实际预测入口，不重写。统一位置/材质；保留固定会话槽、100ms盖片和180msquintic展开、预测双alpha。入口截图完成仍保持展开。

交付：三个默认模式/会话内切换、取消后光学连续、截图后继续展开、入口和队列点击不冲突；多屏、缩放与权限按实际范围记录。不自行宣称系统浮动缩略图排除或所有捕获路径已完成。

### 阶段四：复用原生入缝层，对齐独立动态

最终远端复核新增读到 `codex/arrival-none-magnet-native-20261028` 的 `d552a7388af3890bf693bb3fb24f4b8fc5bc12e7`。它已实现Presenter、源元数据、偏好和设置；与预测入口5d6a683同从1920e056分出，互非祖先。必须复用其基础并处理真实合流，不能照本表早期“待接入”的描述重新开发。现有440ms与本设计560ms、none关闭全部位移与本设计独立吞噬、0ms补位与本设计160ms的差异，逐项见[补充审计](research/arrival-native-branch-check.md)。本设计不改变真实源坐标准入。

接入arrival设置，仅“无 / 磁力吸引”；assetReady/存储不等动效。source rect可信才560ms磁力；来源未知、跨屏未验证、ReduceMotion走0ms；幽灵全穿透、不阻塞现有队列点击。strictStart先到时取消arrival，不允许晚到视觉回调重生。不新增业务资产、数据库、上传协调器或成功状态机。

交付：可中断动效录屏；可信源、缺失源、连续收录、飞行中点击、隐藏和换代的实际结果；原输入可用时间独立于装饰时长。560ms是设计时长，不是截图收录速度承诺。

### 阶段五：原生100%体验与发行质量复核

对实际改变的窗口/命中/焦点/动画进行一次有限真机体验；新截图用新样本，H/F/旧UNKNOWN不重传。正式组合保留原生命周期，运行必要Native与Feedback CI并安排非作者源审查。发布更新的内部candidate后进入创始人真实使用，而非继续常规工程循环。

首轮人体验应看：桌面尺度是否适当；微图是否容易辨认/点中；系统截图入口和预测入口是否自然；等待是否准确；120ms开始后吞噬是否干净；连续点击与补位是否误选；首次设置是否无需工程知识；反馈能否本地保存并再打开。

## 5. 固定来源审计的处理

当前schema2审计精确固定了已批准UX源码、Main以及Feedback和证据树。未来原生视觉修改必然改变这些对象；**不能把审计停掉、改成宽泛目录白名单、忽略失败或把新源码伪称旧blob**。

每个获准实现批次记录：基线SHA→批准设计版本→实际变更路径→新的源对象/树→审查人→完整CI。更新审计应继续逐文件或严格目录不变量固定未改动部分；新Main仍需核对Feedback钩子和原目标/选择保护。历史证据目录仍固定原树。浏览器原型通过不等于Native审计或真机通过。

## 6. 推荐、待确认与真实未完成项

本轮推荐待视觉确认：外14/首槽202、极端比例可见编号垫片、450ms完整peek、窗口组织与尺寸、统一色值、160ms补位、磁力微颤1.2pt、局部静态/无障碍呈现。现有split-R素材只保留，不把本轮当新logo批准。

已有批准不再重开：无/磁力两项；笔直稳定裂缝；固定入口会话槽；取消盖片；截图后保持展开；真实开始吞噬；无successToast；无图无裂缝；UNKNOWN只读；失败需安全准入。

仍待真实工程解决或验证：无ACK冷首击、物理鼠标全场景、系统截图自包含、系统浮动缩略图协同、跨屏/旋转/Spaces、真实安全失败与重试、普通生产、Developer ID/公证/发行、Feedback云端。设计规格不给这些项补PASS，也不把它们变成创始人必须提前排查的安装步骤。

## 7. 交接给 Codex 的执行摘要

> 从最新正式HEAD建立独立实现worktree，以已确认的`design/final-system-20261028/APPKIT_SPEC.md`和`motion/MOTION_SPEC.md`为新视觉与动态依据。严格对应HANDOFF五阶段：统一token与辅助界面→裂缝几何/输入岛/预览→按祖先继承预测入口→独立两模式arrival装饰→原生100%体验与正式组合。保留Core/SQLite/适配器/上传准入与所有旧UNKNOWN。Main最小组合，Feedback全部初始化/诊断/保存/退出接线保留。无效点击不吞噬；严格start才120ms吞噬；成功静默；真实安全失败/重试仍关闭。固定来源审计按精确获准路径更新，不禁用。所有模拟标注模拟；完成必要局部原生验证和组合CI后交付内部candidate，优先创始人真实体验。
