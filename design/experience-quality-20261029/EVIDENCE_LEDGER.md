# Riftlet 完整体验专项 · 证据与体验缺口清单

日期：2026-10-29（北京时间）。范围：第一次启动、日常截图和附加、异常恢复、辅助窗口、退出与再次启动。本表先确认已经完成的行为，再确定补充设计；未实现、未集成、未验证是不同事实。没有重复全球竞品或Logo研究。

## 1. 固定版本与证据等级

| 对象 | 本次核对结果 | 用法与限制 |
| --- | --- | --- |
| GitHub PR #1 | **Open / Draft**；正式头 `0e7ea8be148e1124b387e799fd886a7830e96559` | [PR #1][PR1]。本专项不修改PR、分支或正式代码。PR元数据随其他工程工作可能变化；以下源码引用全部固定SHA。 |
| main | `eba1a4fc77648a665e1d5c1f2609df1314c3b079` | 本次远端核对的main；不把测试merge提交或他人的本地组合树当作main。 |
| 正式设计 | `7e03bd2c26c6aa43dbac07b073e00d08d1951b71` | [薄界规格][D-Spec]与[token][D-Tokens]。本轮用户已指定为正式方向；历史“待视觉批准”措辞不构成重新竞选方向的理由。 |
| 原生候选 | `00dedc7f8164643c3435e3f87aa462e28af0b1c8` | 产品/测试源码候选；不能将其未进入PR #1的部分判作“未实现”。 |
| 原生交接/薄界分支 | `443d21da1a55c0061eafced823b5406879b96024` | [交接说明][C-Evidence]；交接元数据后继，产品树沿用候选。所有候选链接固定此SHA。 |
| 候选Native CI | [40742061755][CI]，GitHub workflow/jobs核对为success | 交接报告620项原生测试及包装通过；旧arrival分支专属条件步骤仍按原条件跳过。没有在本设计专项重新运行这次CI，也不将其称为物理GUI/真实权限/真实上传PASS。 |
| 正式Feedback最新修复 | `0e7ea8be` | [engine][F-Engine]、[store][F-Store]。后续合流须保留正式修复，不能用薄界候选继承的旧后端覆盖。 |

证据强度按用途区分：**固定源码**证明实现与明确逻辑；**测试源码/日志**证明相应用例和执行范围；**真实AppKit/WindowServer合成画面**证明该环境中的呈现；**CGEvent软件输入**不等于物理鼠标；**设计HTML/本专项原型**仅表达设计意图。静态审查不声称已完成新的原生或真实上传测试。

## 2. 分类口径

| 分类 | 含义 |
| --- | --- |
| 正式已有 | 已在远端正式PR #1的固定头内存在；不意味着全部真实环境已验收。 |
| 候选已实现 | 在用户指定薄界原生候选/交接中存在；等待正式集成不构成设计缺陷。 |
| 已设计未实现 | 正式薄界已明确要求，候选仍有呈现或组织差额；不重复发明。 |
| 真实缺陷 | 固定源码/原生画面能证实的文案冲突、信息错误、呈现缺口或质量限制；逐项标明是否有真实运行复现，不能泛称崩溃/数据风险。 |
| 尚未验证 | 当前证据不能支持结果；包含明确NOT_RUN及历史失败尚未被新版重测的边界，不能直接写为“新版已坏”。 |

“本轮补充提案”记录在最后一列，不是把提案倒写成已有事实。Q01–Q10详见[AppKit补充规格](APPKIT_SUPPLEMENT.md)和[状态转换规格](STATE_TRANSITIONS.md)。优先级与可执行动作以本包最终工程清单为准；P0保留门槛不等于发现了新的错传或数据丢失事故。

## 3. 全旅程证据台账

### A. 首次使用与权限

| ID | 环节 / 分类 | 证据支持的判断 | 具体证据与范围 | 本轮处理 |
| --- | --- | --- | --- | --- |
| E01 | 首次展示 · **候选已实现** | 三页原生首用、稍后设置、记录一次展示、菜单主动重开均存在。不能称“没有引导”。 | [Main][C-Main] 169–170；[FirstUsePreferences][C-FirstUse] 13–17；[Setup][C-Setup] 132–138、237–255；[原生首用图][C-SetupImage]仅证明合成内容的窗口绘制。 | **保留**；Q02仅提出可选精简，不要求重做首用系统。 |
| E02 | 首屏能力承诺 · **真实缺陷** | 首屏/结束页无条件承诺点击进入当前草稿，但普通模式实际为productionDisabled只收录。代码可证文案冲突；尚无真实首装用户观察。 | [Setup][C-Setup] 238–250与[能力文案][C-SetupPresentation] 145–160对照；普通模式也调用该首用。 | **Q01 / P0最小文案修复**；不提前开放生产能力，不把授权当准入。 |
| E03 | 首用步骤精简 · **候选已实现** | 当前三页可用且可跳过；已可读目录仍存在访问按钮，不是权限功能缺失。 | [Setup][C-Setup] 101–103、237–255；[首用展示测试][C-WindowTests]。 | **Q02 / P1提案**：同窗一页必要准备，已可用项仅状态行；正常完成只关闭引导，不暗改暂停/收录。 |
| E04 | 系统截图目录授权 · **候选已实现** | 目录访问与真实来源独立核验；选择目录不是更改系统截图保存位置，取消不能更换旧授权。 | [Main][C-Main] 691–709；[FirstUsePreferences][C-FirstUse] 20–68；[FirstUseTests][C-FirstUseTests]。 | **保留**；Q05补来源改变、暂不可读、无文件输出的准确解释。 |
| E05 | 主动截图的屏幕权限 · **候选已实现** | Riftlet主动入口使用Screen Capture preflight/request；收录已保存的系统截图文件不应因此要求屏幕录制权限。 | [InteractiveScreenshotController][C-Capture] 75–100；[系统捕获][C-SystemCapture] 14–17。真实TCC另见E46。 | **保留**；Q05按所做功能解释，仅显式入口动作请求。 |
| E06 | Chrome Automation · **候选已实现** | 被动inspect与用户显式request分离；Chrome实例身份受约束，普通仅收录模式不借授权开启上传。 | [AutomationPermission][C-Automation] 34–81、96–107；[SetupPresentation][C-SetupPresentation] 164–225；[AutomationPermissionTests][C-AutomationTests]。 | **保留**；Q05区分未请求、已拒绝/撤销、未运行与当前能力关闭。 |
| E07 | Chrome JavaScript设置 · **候选已实现** | Chrome的Apple Events JavaScript条件与macOS Automation、当前草稿可验证是独立条件，不能合并成永久“连接成功”。 | [AutomationPermission][C-Automation]及[SetupPresentation][C-SetupPresentation] 166–180；[现有支持说明][C-InternalBeta]保留手工连接边界。 | **保留**；Q05用四条真实条件解释，不代改Chrome设置。当前版本/系统实际路径仍须验证。 |
| E08 | 权限恢复与返回 · **正式已有** | 既有激活/唤醒恢复用于被动检查，不赋予旧点击新的上传授权。隐藏/暂停和既有媒体保留。 | 正式[PassivePermissionResume][F-Resume]与[Main][F-Main]；候选继续继承。 | **保留**；Q05补可见原因与正确设置入口，不循环请求权限、不自动补拍/补传。 |

### B. 截图入口、模式、取消与收录

| ID | 环节 / 分类 | 证据支持的判断 | 具体证据与范围 | 本轮处理 |
| --- | --- | --- | --- | --- |
| E09 | 固定模式槽与移动取消 · **候选已实现** | 槽位由会话开始时固定，模式变化立即改变语义；只移动取消盖片。截图后连续会话保留。 | [ScreenshotEntryModel][C-EntryModel] 85–124；[ScreenshotEntryController][C-EntryController] 445–452、550–565；[原生入口图][C-QueueImage]为限定软件原生绘制。 | **保留**；Q03不重排槽位、不增加确认步骤。 |
| E10 | 倒计时与本次/下一张 · **真实缺陷** | 已完整选择后冻结请求并倒计时，Host未接onStateChange到可见剩余时间。切模式只影响下一张，当前缺少本次/下一张说明。是呈现缺口，不是旧请求错误继续执行。 | [Capture][C-Capture] 224–267；[Types][C-CaptureTypes] 113–149；[Host][C-EntryHost] 65–90；[CaptureTests][C-CaptureTests] 58–71明确冻结语义。 | **Q03 / P1**：纯展示倒计时和下一模式行，原requestID/target/options不变。 |
| E11 | X/Escape取消范围 · **候选已实现** | X结束整个截图会话和未完成pending，不是只取消当前显示的下一模式；已交付原图保持既有保留规则。 | [Host][C-EntryHost] 198–208；[Capture][C-Capture] 123–139；[Markup][C-Markup] 65–83。 | **保留**；Q03统一“结束截图”，不因取消就断言没有任何落盘文件。 |
| E12 | 捕获期间权限/目标失效 · **真实缺陷** | 既有控制器会再次核权限与目标，安全拒绝存在；错误主要进入菜单状态，操作现场解释不足。没有证据证明它会改投目标。 | [Capture][C-Capture] 271–298；[Host][C-EntryHost] 83–85；[Main][C-Main] 1447附近错误映射。 | **Q03/Q05 / P1**：就地说明；先结束选择再打开系统设置，返回需新手势。 |
| E13 | 拍好后本地导入失败 · **真实缺陷** | 原捕获文件被保留，但catch把多类错误统一指向空间问题；未提供稳定的单文件恢复契约。不是原图丢失或上传失败证据。 | [Host][C-EntryHost] 173–195；[状态规格Q05](STATE_TRANSITIONS.md)。 | **Q05 / P1**：区分“已保存、未收录”；仅用已有真实本地入口，不新增“重试导入”承诺。 |
| E14 | 主动捕获来源准入 · **候选已实现** | applicationScreenshot来源与既有系统截图准入分离；新捕获/编辑副本不能借用已批准的系统原图start/completion/retry profile。 | [候选交接][C-Evidence]“接线”与安全范围；[Types][C-CaptureTypes]；[受限准入说明][C-Admission]。 | **保留P0门槛**；Q03/Q05原型只模拟本地捕获，不扩大真实附加能力。 |
| E15 | 入口光标与自包含 · **尚未验证** | 代码有光标无效化与捕获隐藏接线，但连续真实截图、系统浮层协同及所有系统截图方法自排除未获本候选完整验收。 | [EntryController][C-EntryController]；[交接已知边界][C-Evidence]。 | **Q10**：只补受影响入口的真实Mac证据，不承诺所有系统截图均排除Riftlet。 |

### C. 队列、预览、点击与上传状态

| ID | 环节 / 分类 | 证据支持的判断 | 具体证据与范围 | 本轮处理 |
| --- | --- | --- | --- | --- |
| E16 | 薄界几何与长队列 · **候选已实现** | 固定边缘/首槽、等比微图、分页、极端比例可见编号垫片均有实现。 | [RiftLayout][C-Layout]；[Panel][C-Panel]；[原生队列/分页/竖屏证据][C-Evidence]；[正式token][D-Tokens]。 | **保留**14/202/60、72×56fit与25%遮挡。Q10不以另一套容器/大卡片取代。 |
| E17 | 透明区域与资产点击身份 · **候选已实现** | 图片/编号输入岛与留白穿透、按住补位、双击替换保护已有软件原生证据。 | [Panel][C-Panel]；[software-routing.json][C-Routing]；[交接范围][C-Evidence]。clickState=2由软件显式注入。 | **保留P0门槛**；Q10不能把软件证据改称物理鼠标/OS自动双击识别。 |
| E18 | 完整比例hover peek · **候选已实现** | 450ms停留、320×240包络、100ms离开延迟/80ms淡出、鼠标穿透和迟到解码epoch保护存在。 | [RiftEdgeAccessories][C-Accessories] 70–131；[原生极端比例预览图][C-PeekImage]；[正式规格][D-Spec] §4.3。 | **保留**；Q04只协调状态说明优先级，不取消正常peek。 |
| E19 | 等待/未知反馈 · **候选已实现** | transferring单下划线、unknown双下划线、真实feedback tooltip与AX label/help均存在。不能称没有反馈。 | [Panel][C-Panel] 195–210、227–235、683–688。普通hover tooltip删除仅为避让peek。 | **保留**；Q04不把新增等待徽章作为功能。 |
| E20 | 附近非激活原因说明 · **已设计未实现** | 正式§7已规定最大240pt、13/18文字、鼠标穿透附近说明；候选尚未形成该独立可见呈现。 | [正式规格][D-Spec] §7；对照[Panel][C-Panel]反馈路径。 | **Q04 / P1**：落实既有设计，短暂且owner/revision匹配；不增加全局Toast。 |
| E21 | prepared与迟到反馈 · **正式已有** | 已修为中性“附加处理中”，并用owner/revision隔离迟到取消；不能持续声称仍未输入。 | 正式[ProductStatus][F-ProductStatus] 89–101、[Main][F-Main]与[Beta体验证据][F-BetaUX]；候选继承。 | **保留**；Q04的250/450/2400ms提案只控制显示，不推导业务事实。 |
| E22 | 上传开始与最终完成 · **正式已有** | 真实start与独立completion分离；严格uploadStarted才快吞噬；最终成功后台记录，无成功Toast或自动发消息。 | 正式[上传开始合同][F-Started]、[TransferCoordinator][F-Coordinator]；候选[原生运动证据][C-MotionTiming]为合成事实投影。 | **保留P0门槛**；Q04不等待READY才吞，也不以动画结束伪造成功。 |
| E23 | UNKNOWN、重启与后续截图 · **正式已有** | 已开始UNKNOWN保持隐藏/原操作只读，不自动重生/重输；不同新截图必须用自己的新点击与资格。 | 正式[TransferCoordinator][F-Coordinator]、[InteractionLifecycleTests][F-LifecycleTests]；候选[HistoryPresentation][C-HistoryPresentation] 21–55。 | **保留P0门槛**；Q04/Q08不清库、解锁、重建旧asset或借反馈幂等策略重传截图。 |
| E24 | 安全失败重生 · **正式已有** | 状态机具备获准明确失败恢复普通可点图的规则，但真实安全失败/retry准入仍关闭。不能把一般断网等同安全失败。 | 正式[InteractionLifecycleTests][F-LifecycleTests]与[受限准入][F-Admission]；[候选交接安全边界][C-Evidence]。 | **保留**；Q04仅条件隔离模拟。未获准不启用，获准后也不做永久不可点红色死卡。 |
| E25 | 输入前取消与已输入未知 · **正式已有** | input intent之前的确定取消可保留图并等待新点击；intent后不明须保持未知，不存在新“撤回上传”能力。 | 正式[开始合同][F-Started]、[SelectionSubmissionQueue][F-SelectionQueue]；[正式视觉状态表][D-Spec] §7。 | **保留**；Q04明确关闭说明≠业务取消，截图X≠撤回附件。 |
| E26 | 冷首击与真实响应速度 · **尚未验证** | 历史无ACK首击仍有失败限制；旧H/UX证据是预绑定软件输入，不是候选物理冷首击。设计不能证明真实附加变快。 | [历史BetaUX][F-BetaUX]；[候选交接未重测范围][C-Evidence]。候选约126–130ms仅AppKit start→close。 | **Q04解释/Q10验收**；不以更快原型定时宣称修复真实延迟。 |

### D. 历史、设置与长期可读性

| ID | 环节 / 分类 | 证据支持的判断 | 具体证据与范围 | 本轮处理 |
| --- | --- | --- | --- | --- |
| E27 | 历史与恢复资格 · **候选已实现** | 中文三栏、待核实/已附加区别、200条/页、搜索本页、原比例详情、Space/双击预览与Escape关闭均存在。 | [HistoryController][C-History] 132–160、215–284、336–347；[HistoryPresentation][C-HistoryPresentation]。 | **保留**；Q06不扩成截图管理器，不增加UNKNOWN重试。 |
| E28 | 历史行识别与空状态 · **真实缺陷** | 日期+尺寸串入172pt描述列，原生图可见普遍尾部截断；无选择/空筛选/搜索无结果共用泛化说明。 | [HistoryController][C-History] 149–154、259–262、310–312；[原生历史图][C-HistoryImage]。 | **Q06 / P1**：时间与状态分层、详情保留完整元数据；区分本页空与全库空。 |
| E29 | 大预览清晰度与加载 · **真实缺陷** | 大窗口直接重用320×backing详情图，统一cache上限768px；加载未完时previewSelected直接返回。是显示质量/响应限制，不是原图被缩图。 | [HistoryController][C-History] 271–284；[ThumbnailCache][C-Cache] 21–58；[交接已知差异][C-Evidence]。 | **Q06 / P1**：独立有预算的Fit预览、加载说明、asset/window epoch；不新增编辑/导出或100%缩放。实际清晰度/峰值内存仍待证。 |
| E30 | 五组设置与内嵌偏好 · **已设计未实现** | 五组设置壳已实现，部分偏好仍跳独立窗/菜单，归档还在菜单，没有显示器选择控件；交接已明确。 | [Setup][C-Setup] 262–289；[正式规格][D-Spec] §8；[交接已知差异][C-Evidence]。 | **Q09 / P2**：承接已设计内嵌，不新增第三种动效/新归档期限/自动清理。 |
| E31 | 暂停、隐藏、归档与移除 · **正式已有** | 显示与收录意图独立；归档/移除只改可见性，不删原图/私有媒体或远端附件。 | 正式[LifecycleSettings][F-LifecycleSettings]、[交互合同][F-Interaction]；候选[SetupPresentation][C-SetupPresentation] 122–137。 | **保留P0门槛**；Q05/Q08/Q09仅准确显示与继承。 |
| E32 | 窗口位置一致性 · **真实缺陷** | Setup/History保留合法位置，Feedback show每次center；重复打开的原生窗口行为不一致。实际多屏影响尚未物理复测。 | [Setup][C-Setup] 141–153；[History][C-History] 113–118；[FeedbackWindow][C-FeedbackWindow] show附近143。 | **Q09 / P2**：复用共享恢复；首显居中，合法位置保留，完全离屏时最小回收。 |
| E33 | 标准设置访问 · **真实缺陷** | 现有设置菜单未配置Cmd-,，属于明确的原生习惯细节缺口，不是截图核心故障。 | [Main][C-Main] 1389附近。 | **Q09 / P2**：增加系统常规设置入口；不改变截图快捷键、不新增日常必需操作。 |
| E34 | 1x编号垫片边框 · **真实缺陷** | 垫片固定0.5pt描边与正式“1物理像素”规格在1x下不一致；严重程度尚未实机验收。 | [Panel][C-Panel] 219–222；[VisualStyle][C-VisualStyle] 133–135对照；[正式规格][D-Spec] §4.2。 | **Q10 / P2**：同一backing像素规则；不改变点击岛、边缘平面或队列布局。 |

### E. Feedback、关闭、退出与再次启动

| ID | 环节 / 分类 | 证据支持的判断 | 具体证据与范围 | 本轮处理 |
| --- | --- | --- | --- | --- |
| E35 | Feedback本地/服务能力 · **候选已实现** | nil endpoint已显示“保存待发送”；服务未配置不等于开发者已收到。诊断默认关闭、预览快照与本机记录已有。 | [FeedbackWindow][C-FeedbackWindow] 80、138、225–232；[FeedbackHost][C-FeedbackHost] 18–30；[原生反馈图][C-FeedbackImage]。 | **保留**；Q07只完善状态组合和记录动作，不重复造后端。 |
| E36 | Feedback最新可靠性修复 · **正式已有** | 正式头已修定时器重新调度、丢凭证取消/删除义务和claim删除竞态；不能用候选旧后端覆盖。 | 正式[FeedbackEngine][F-Engine]、[FeedbackStore][F-Store]、[Feedback交接][F-FeedbackHandoff]。 | **保留P0合流门槛**；Q07复用正式engine资格，不在UI复制旧attempts判断。 |
| E37 | Feedback取消/删除说明与模态 · **真实缺陷** | 混合“取消待发送／申请删除”动作和统一确认文案，且使用app-modal runModal；是否实际干扰截图点击尚无物理证据。 | [FeedbackWindow][C-FeedbackWindow] 95–97、278–295。 | **Q07 / P1**：按原ID/真实资格分动作，父窗sheet，busy防重复；不改变删除权限。 |
| E38 | Feedback文本限额 · **真实缺陷** | UI按String.count计数，后端按Unicode scalar≤4000和UTF-8≤16384字节；组合字符会出现UI与提交判定不一致。 | [FeedbackWindow][C-FeedbackWindow] 123–125；[FeedbackModels][C-FeedbackModels] 66–77。 | **Q07 / P1**：复用相同纯校验，不截断marked text；保留真实IME待验证。 |
| E39 | 关闭/退出安全门禁 · **候选已实现** | 草稿自动保存、未加载/busy/marked text拒绝、退出await并锁编辑、失败保留文本已有。 | [FeedbackWindow][C-FeedbackWindow] 156–198；[FeedbackHost][C-FeedbackHost] 46–49；[FeedbackCloseTests][C-FeedbackCloseTests]。 | **保留**；Q08不能为顺畅关闭删安全gate。 |
| E40 | 关闭被阻止的解释 · **真实缺陷** | marked-text等拒绝分支未完整给出可见原因，用户可能只看到关闭无响应。软件测试不证明真实IME体验。 | [FeedbackWindow][C-FeedbackWindow] 180–198；[FeedbackCloseTests][C-FeedbackCloseTests]限定软件语义。 | **Q08 / P1**：组字/保存中/保存失败准确解释；慢保存合并关闭意图，不新增丢弃正文捷径。 |
| E41 | 再次启动与持久状态 · **正式已有** | 既有first-use展示、暂停/隐藏、截图/反馈数据根、持久记录及原UNKNOWN恢复机制应继承。重启不等于再输入。 | 正式[FirstUsePreferences][F-FirstUse]、[LifecycleSettings][F-LifecycleSettings]、[生命周期测试][F-LifecycleTests]；候选窗口变更不改变这些权威。 | **保留**；Q08补可理解的状态，不强制每次引导、不自动重开全部窗口。 |

### F. 环境、证据边界与未验证事项

| ID | 环节 / 分类 | 证据支持的判断 | 具体证据与范围 | 本轮处理 |
| --- | --- | --- | --- | --- |
| E42 | 浅深色与原生辅助窗口 · **候选已实现** | 原生controller/WindowServer截图证明限定环境的颜色、字号、窗框和排列；不是浏览器画板。 | [VisualStyle][C-VisualStyle]；[asset manifest][C-Assets]；[windows.json][C-Windows]。素材为合成，helper使用隔离背板/部分提升层级。 | **保留**；不把真实桌面材质、正常跨应用层级或系统权限效果算作这些截图已证。 |
| E43 | 无/磁力/减少动态中断 · **候选已实现** | 五段真实AppKit录屏覆盖合成投影驱动的none、magnet、Reduce Motion、途中取消和缺来源静态。无第三动效。 | [候选录屏说明][C-Evidence]、[timing][C-MotionTiming]、[asset manifest][C-Assets]。影片来源888a4b0。 | **保留**；Q10系统实时通知/真实来源准入另证，软件动画不是上传开始证据。 |
| E44 | 多屏、1x/缩放、Spaces/全屏 · **尚未验证** | 源码有preferred→main→first、负坐标几何、通知撤旧装饰；只有2x横屏/旋转屏限定证据，真实插拔/Spaces/全屏/1x未完成。 | [DisplaySelection][C-Display]、[ReconfigurationTests][C-ReconfigurationTests]；[交接NOT_RUN][C-Evidence]。 | **Q10**：最终组合App按受影响矩阵补证；不能将NOT_RUN写成已知错位/抢焦点。 |
| E45 | VoiceOver/物理输入/外观实时变化 · **尚未验证** | AX接线、软件点击、静态浅深/部分减少动态结果已存在；完整VoiceOver、物理双击、系统实时Contrast/Transparency与跨应用焦点未证。 | [Panel][C-Panel]、[Routing][C-Routing]、[交接NOT_RUN][C-Evidence]。 | **Q10**：保留软件证据标签，有限真实Mac验收；不要求创始人担任Beta测试员。 |
| E46 | 真首装、TCC、Gatekeeper、IME/Keychain · **尚未验证** | 原生画面、软件marked-text和CI不能证明真实首装授权/签名阻挡/输入法/钥匙串组合。 | [候选交接][C-Evidence]与[正式内部Beta说明][F-InternalBeta]。 | **Q01/Q05/Q07/Q08/Q10**：现有授权设备可用后独立记录；设备缺失只阻塞相应验收。 |
| E47 | Feedback真实云端端到端 · **尚未验证** | 当前endpoint nil；本机队列/Mock HTTP/SQLite测试不代表原生→实际服务→私有反馈中心已通过。 | [正式Feedback交接][F-FeedbackHandoff]及[PR #1][PR1]的真实服务/设备阻塞说明。 | **保留事实**；Q07不得显示伪造回执或开发者已读；本专项不部署服务/发送反馈。 |
| E48 | 正式组合App最终体验 · **尚未验证** | 他人正在进行的本地合流/审查不能当成远端正式完成，更不能替代最终App包的局部回归。 | 本次[远端PR #1][PR1]与固定候选[results.json][C-Results]；不引用移动本地树作为完成证据。 | **全部原生Q项等待正式集成结束**，从负责人确认的新SHA去重后实施；设计交付现在完成。 |

## 4. 原生媒体来源与本专项边界

以下来源以[asset-manifest.json][C-Assets]为准。它们随交接SHA收纳，不意味着重新在`00dedc7`或`443d21d`拍摄。

| 原始取证源码SHA | 对应媒体 | 能证明 / 不能证明 |
| --- | --- | --- |
| `46a909a35df16b76b6153fcb772a48740fb07ac6` | setup/settings/history/feedback/motion的浅深窗口图；portrait-retina.png | 真实WindowServer原像素、2x环境、合成内容绘制。不能证明最终候选所有源码更改后的物理交互。 |
| `ad4854c849448bb37c387528bddf673732d8e362` | queue-light16.png、queue-dark16-entry.png、extreme-hover-safe.png、pager-last-page.png | 收口后队列/入口/peek/分页限定原生画面。不是真实截图上传或所有屏幕拓扑验收。 |
| `888a4b0075bc8faf944a3e7a75ebd9a7a7ff3acf` | magnet/none/reduce-motion/interrupt/missing-source.mov | 真实AppKit/WindowServer运动；业务事件为syntheticOnly、receiptEvidence=false。不是OS来源坐标准入或真实上传表现。 |

候选取证环境为Apple Silicon、macOS27.0(26A428)、本地Swift6.4，1920×1080逻辑点@2x及800×1280@2x旋转负坐标屏。候选CI环境另为macOS14.8.9(23J631)、Swift5.10、arm64；两者不合并称一次“全环境PASS”。具体原始像素、SHA-256、字节数、时间测量见上述manifest、windows、timing和results。

本专项浏览器原型的审查发现、修复和截图记录只归入设计验证，不进入本表的原生缺陷数量。原型中的权限、上传开始/完成、失败、清晰预览和Feedback回执均为模拟事实。不得拿原型的每条分支通过来抬升E44–E48的证据等级。

## 5. 本表导出的行动判断

- 先保留已经良好的几何、输入所有权、预览、连续截图、状态安全、Feedback保护和原生视觉。
- Q01是能力文案的最小修复；Q03/Q04/Q05补足用户当下看不到或容易误解的真实状态。
- Q06/Q07/Q08改善阅读、恢复、反馈和退出；不增加截图管理、云同步或上传重试权限。
- Q02与Q09可独立后置，不应成为最小修复的依赖；Q10只补与实际改动有关的环境风险。
- 工程开始时先核对新正式SHA。如果本轮列项已由当前集成解决，改为“保留”，不再次实施。

## 固定来源链接

[PR1]: https://github.com/haohongfei2001-png/Riftlet/pull/1
[CI]: https://github.com/haohongfei2001-png/Riftlet/actions/runs/40742061755
[D-Spec]: https://github.com/haohongfei2001-png/Riftlet/blob/7e03bd2c26c6aa43dbac07b073e00d08d1951b71/design/final-system-20261028/APPKIT_SPEC.md
[D-Tokens]: https://github.com/haohongfei2001-png/Riftlet/blob/7e03bd2c26c6aa43dbac07b073e00d08d1951b71/design/final-system-20261028/TOKENS.json
[C-Setup]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletUI/RiftSetupController.swift
[C-SetupPresentation]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletUI/SetupPresentation.swift
[C-Main]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletApp/RiftletMain.swift
[C-FirstUse]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletApp/FirstUsePreferences.swift
[C-FirstUseTests]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Tests/RiftletAppTests/FirstUseTests.swift
[C-WindowTests]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Tests/RiftletUITests/QuietEdgeWindowTests.swift
[C-Automation]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletApp/AutomationPermission.swift
[C-AutomationTests]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Tests/RiftletAppTests/AutomationPermissionTests.swift
[C-InternalBeta]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/docs/INTERNAL_BETA.md
[C-Capture]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletCapture/InteractiveScreenshotController.swift
[C-CaptureTypes]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletCapture/InteractiveScreenshotTypes.swift
[C-CaptureTests]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Tests/RiftletCaptureTests/InteractiveScreenshotTests.swift
[C-SystemCapture]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletCapture/InteractiveScreenshotSystemCapture.swift
[C-EntryModel]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletUI/ScreenshotEntryModel.swift
[C-EntryController]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletUI/ScreenshotEntryController.swift
[C-EntryHost]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletApp/ScreenshotEntryHost.swift
[C-Markup]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletApp/ScreenshotMarkupController.swift
[C-Admission]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/docs/SYSTEM_SCREENSHOT_RESTRICTED_ADMISSION.md
[C-Layout]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletUI/RiftLayout.swift
[C-Panel]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletUI/RiftPanelController.swift
[C-Accessories]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletUI/RiftEdgeAccessories.swift
[C-History]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletUI/RiftHistoryController.swift
[C-HistoryPresentation]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletUI/HistoryPresentation.swift
[C-Cache]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletUI/ThumbnailCache.swift
[C-VisualStyle]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletUI/RiftVisualStyle.swift
[C-Display]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletUI/RiftDisplaySelection.swift
[C-ReconfigurationTests]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Tests/RiftletUITests/RiftReconfigurationTests.swift
[C-FeedbackWindow]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletFeedbackUI/FeedbackWindowController.swift
[C-FeedbackModels]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletFeedback/FeedbackModels.swift
[C-FeedbackHost]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Sources/RiftletApp/FeedbackHost.swift
[C-FeedbackCloseTests]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/Tests/RiftletFeedbackUITests/FeedbackCloseTests.swift
[C-Evidence]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/engineering/evidence/2026-10-29-thin-edge-native/README.md
[C-Results]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/engineering/evidence/2026-10-29-thin-edge-native/results.json
[C-Assets]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/engineering/evidence/2026-10-29-thin-edge-native/asset-manifest.json
[C-Windows]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/engineering/evidence/2026-10-29-thin-edge-native/windows.json
[C-Routing]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/engineering/evidence/2026-10-29-thin-edge-native/software-routing.json
[C-MotionTiming]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/engineering/evidence/2026-10-29-thin-edge-native/motion-timing.json
[C-SetupImage]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/engineering/evidence/2026-10-29-thin-edge-native/screens/setup-light.png
[C-HistoryImage]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/engineering/evidence/2026-10-29-thin-edge-native/screens/history-light.png
[C-FeedbackImage]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/engineering/evidence/2026-10-29-thin-edge-native/screens/feedback-light.png
[C-QueueImage]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/engineering/evidence/2026-10-29-thin-edge-native/screens/queue-dark16-entry.png
[C-PeekImage]: https://github.com/haohongfei2001-png/Riftlet/blob/443d21da1a55c0061eafced823b5406879b96024/engineering/evidence/2026-10-29-thin-edge-native/screens/extreme-hover-safe.png
[F-Main]: https://github.com/haohongfei2001-png/Riftlet/blob/0e7ea8be148e1124b387e799fd886a7830e96559/Sources/RiftletApp/RiftletMain.swift
[F-Resume]: https://github.com/haohongfei2001-png/Riftlet/blob/0e7ea8be148e1124b387e799fd886a7830e96559/Sources/RiftletApp/PassivePermissionResume.swift
[F-FirstUse]: https://github.com/haohongfei2001-png/Riftlet/blob/0e7ea8be148e1124b387e799fd886a7830e96559/Sources/RiftletApp/FirstUsePreferences.swift
[F-ProductStatus]: https://github.com/haohongfei2001-png/Riftlet/blob/0e7ea8be148e1124b387e799fd886a7830e96559/Sources/RiftletApp/ProductStatus.swift
[F-SelectionQueue]: https://github.com/haohongfei2001-png/Riftlet/blob/0e7ea8be148e1124b387e799fd886a7830e96559/Sources/RiftletApp/SelectionSubmissionQueue.swift
[F-LifecycleSettings]: https://github.com/haohongfei2001-png/Riftlet/blob/0e7ea8be148e1124b387e799fd886a7830e96559/Sources/RiftletApp/LifecycleSettings.swift
[F-Coordinator]: https://github.com/haohongfei2001-png/Riftlet/blob/0e7ea8be148e1124b387e799fd886a7830e96559/Sources/RiftletCore/TransferCoordinator.swift
[F-LifecycleTests]: https://github.com/haohongfei2001-png/Riftlet/blob/0e7ea8be148e1124b387e799fd886a7830e96559/Tests/RiftletCoreTests/InteractionLifecycleTests.swift
[F-Engine]: https://github.com/haohongfei2001-png/Riftlet/blob/0e7ea8be148e1124b387e799fd886a7830e96559/Sources/RiftletFeedback/FeedbackEngine.swift
[F-Store]: https://github.com/haohongfei2001-png/Riftlet/blob/0e7ea8be148e1124b387e799fd886a7830e96559/Sources/RiftletFeedback/FeedbackStore.swift
[F-Started]: https://github.com/haohongfei2001-png/Riftlet/blob/0e7ea8be148e1124b387e799fd886a7830e96559/docs/UPLOAD_STARTED_CONTRACT_V1.md
[F-Interaction]: https://github.com/haohongfei2001-png/Riftlet/blob/0e7ea8be148e1124b387e799fd886a7830e96559/docs/INTERACTION_CONTRACT_2026-10-27.md
[F-Admission]: https://github.com/haohongfei2001-png/Riftlet/blob/0e7ea8be148e1124b387e799fd886a7830e96559/docs/SYSTEM_SCREENSHOT_RESTRICTED_ADMISSION.md
[F-InternalBeta]: https://github.com/haohongfei2001-png/Riftlet/blob/0e7ea8be148e1124b387e799fd886a7830e96559/docs/INTERNAL_BETA.md
[F-FeedbackHandoff]: https://github.com/haohongfei2001-png/Riftlet/blob/0e7ea8be148e1124b387e799fd886a7830e96559/docs/FEEDBACK_V01_HANDOFF.md
[F-BetaUX]: https://github.com/haohongfei2001-png/Riftlet/tree/0e7ea8be148e1124b387e799fd886a7830e96559/engineering/evidence/2026-10-28-beta-ux
