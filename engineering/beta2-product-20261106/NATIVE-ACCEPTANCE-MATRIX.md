# Beta 2 原生验收矩阵

本矩阵针对同一 App 中的新设置中心、控制中心与引导。实施代码、XCTest、真实 App 内部 action、WindowServer 图片、物理操作和用户最终外观决定分别记录，不互相替代。源码已分配版本身份 **Beta 2 · 0.2.0（2）**。最终源码 G / H、App SHA、报告 SHA、CI run / checkout、操作系统与架构：**PENDING，集成负责人在收口时填写**。

作者已完成新 UI/Host/Environment 的实际 target 编译与语法检查；本机 CLT 缺少 XCTest，因此没有用 shim 冒充 XCTest。最新新增文件定义了设置中心 27 项、Host 10 项、环境 12 项测试；计数表示存在的测试方法，**不是本机已运行通过的数量**。控制中心/引导与既有 model/login/appearance 测试也须以最终 CI 的实际执行、跳过和失败记录为准。

`PENDING` 表示待绑定精确候选的执行结果；`NOT_RUN` 表示尚无该类真实验收证据。中间 App 的实际窗口查看只能用于修正当前候选，不能提前填成最终通过。任何失败保留原 report/PNG/日志；修复后用新的源/工件身份复验受影响路径，不覆盖原文件。

## 自动化与原生运行的对应关系

下表的测试文件均在仓库内；case 名与当前 [`SettingsReviewDriver`](../../Sources/RiftletApp/SettingsReviewDriver.swift) 对应。driver 直接调用真实 AppKit 控件与文字编辑 API，走实际 host/model/独立 SQLite，**没有物理鼠标、操作系统 IME 或真实 ChatGPT 证明**。

| 场景与必须观察的结果 | 自动化覆盖 | 同一二进制 driver / 现场证据 | 当前最终结果 |
| --- | --- | --- | --- |
| 六页同窗、只看不保存、后台更新不弹窗；通用四开关为原生 switch，方向/AX标签一致 | [SettingsCenterTests](../../Tests/RiftletUITests/RiftSettingsCenterTests.swift)：`SixPages…`、`NativeSwitches…`；[HostTests](../../Tests/RiftletAppTests/SettingsProductHostTests.swift)：`ThreeNativeSurfaces…` | `environment-and-default-window`、`six-pages-light-and-dark`；每页浅/深原始 PNG | PENDING |
| 初次内容尺寸 960×684 pt，外框含系统标题栏；小屏可滚动、再次显示不重置 resize | SettingsCenter：`FirstShow…`、`FirstPresentationFrame…`、`ResizeRetains…` | `environment-and-default-window`、`resizing-and-reopen`；outer frame/contentRect/visibleFrame/backingScale 一起记录 | PENDING |
| 暂停与隐藏四组合；关闭入口独立；停止先有效、恢复失败不假开 | SettingsCenter：`ThreeStopErrors…`、`FailedResume…`；[ControlCenterTests](../../Tests/RiftletUITests/RiftControlCenterControllerTests.swift) 四态；[StateModelTests](../../Tests/RiftletUITests/SettingsStateModelTests.swift) | `orthogonal-pause-hidden-sqlite`，读回独立 SQLite 偏好及控制中心图片 | PENDING |
| 独立保存失败叠加、其他成功不清错、同方向 retry、错误依次清除 | SettingsCenter：`ThreeStopErrors…`；Host：`AppearanceSuccess…`；StateModel 延迟/部分失败 | `independent-write-failures-and-retry`；仅阻断已列明的 review JSON，恢复原文件并核对 | PENDING |
| 原始文本、光标、控件 identity 不被后台刷新覆盖，非 dirty 字段跟随 owner | SettingsCenter：`NativeFieldsKeepIdentity…`；Host：`OwnerRefreshDuringDraft…` | `configuration-editor-refresh-defaults`；真实 NSTextView/owner 读回 | PENDING；不等于 OS IME |
| 首击归档保存读取最后编辑，预设也是草稿，小数/0 正确；显式放弃/默认不被旧 editor 写回 | SettingsCenter：`ArchiveFirstSave…`、`ArchivePreset…`、`ExplicitDefaultsAndDiscard…` | `archive-editor-first-save-discard`、`configuration-editor-refresh-defaults` | PENDING |
| IME marked text 保留；Return 组词不提交；明确放弃使用原生编辑取消 | SettingsCenter：`MarkedComposition…`、`ExplicitDiscardCancelsMarkedInput…` | driver 无真实 OS 输入法；不能给物理中文组词 PASS | 软件层待 CI；OS IME NOT_RUN |
| 红关闭/⌘W：继续保留、放弃只影响草稿、应用等待真实保存；部分成功不重复成功域 | SettingsCenter：`FirstClose…`、`ApplyAndClose…`、`FailedApply…`、`DiscardClose…`、`PartialCloseSave…` | `close-sheet-continue-discard` 仅覆盖其实际两个分支；键盘红关闭/失败应用需另有实录 | PENDING；未执行分支不借用 driver PASS |
| 保存开始即 busy，同域不重入、跨域仍可用，新编辑在延迟回执后保留 | SettingsCenter：`InFlightSave…`；Host：`BusyChangePublishes…`；StateModel 对应测试 | driver 以具体持久化回读判定，不用固定 sleep 当结果 | PENDING |
| 显示器具体身份、同名屏不合并、菜单 tracking 中刷新不换目标、临时回退不改偏好 | SettingsCenter：`DisplayFallback…`、`DisplayMenuTracking…`、`SameNamedDisplays…`；[OnboardingTests](../../Tests/RiftletUITests/RiftOnboardingControllerTests.swift) | `three-step-guidance-light-and-dark` 只记录当时可用屏幕；热拔/跨屏另测 | 软件层待 CI；热拔 NOT_RUN |
| 本页恢复只重置有效本页数值；七个个性化兼容参数、显示器/另一页草稿保留 | SettingsCenter：`RestoreCurrentPage…`；StateModel：`PageDefaults…` | `configuration-editor-refresh-defaults`；JSON 内容核对 | PENDING |
| 选择动效不自播、主动预览、切页停止；减少动态 `min(80ms, 原时长)` 不变慢 | SettingsCenter：`ExplicitPreviewOnly…`；StateModel 单位测试 | `motion-explicit-play-and-navigation-stop`；截图只是瞬时画面 | PENDING；真实系统减少动态切换另记 |
| 外观先保存再应用，system 清除显式覆盖；错误/重试不串其他域 | Host：`HostAppearanceCreatesRealScopedJSON…`、`HostAppearanceWriteFailure…`；[AppearanceTests](../../Tests/RiftletAppTests/ApplicationPresentationPreferencesTests.swift) | `six-pages-light-and-dark`、失败 case 的真实 review JSON | PENDING；未改系统主题 |
| 登录系统状态与调用错误并存；等待批准不是已生效，读取不注册，同目标幂等 | Host：`ActualLoginReadback…`、`LoginFailedTarget…`；[LoginTests](../../Tests/RiftletAppTests/LoginItemPreferencesTests.swift) | review 模式明确 unavailable；禁止 driver 注册/注销/打开系统登录设置 | fake 待 CI；真实登录启动 NOT_RUN |
| 原生 popover 打开/关闭、点外面/Escape、右键菜单同一显式命令；不可用截图不误发 | ControlCenterTests | `orthogonal-pause-hidden-sqlite` 只证明实际执行的动作/图片；鼠标路由、Escape/键盘需原生输入实录 | PENDING |
| 三步可前后切换、稍后完成；已有连接不重复授权、位置保存/失败重试，不制造 capture | OnboardingTests | `three-step-guidance-light-and-dark`；三步×浅深图 | PENDING；真实授权弹窗 NOT_RUN |
| 真实历史、未测量不是 0 B；清空只有一次 Main 确认且保留所有内容 | SettingsCenter：`NoStorageMeasurement…`；Host：`ExternalActionsPassThrough…` | `history-real-records`；清空确认与原图保留需实录对应操作，未执行就单列 | PENDING |
| review UUID、根/marker/symlink/锁、只fixture来源、默认域分离、无Web/真实登录项 | [EnvironmentTests](../../Tests/RiftletAppTests/SettingsReviewEnvironmentTests.swift) | `environment-and-default-window`、`real-collector-synthetic-fixture`、`original-media-and-no-upload-operations` | PENDING |

设置中心异步测试按**特定 host action 完成 ID**、实际保存 continuation 或 native sheet completion 作有界等待，结束后仍执行原结果断言。超时是失败，不通过增加 sleep、跳过断言或重跑到绿来替代状态确认。Host 的延迟 owner 使用明确 gate / expectation。

## 必须单独保留的真实平台边界

| 平台项目 | 需要的实际证据 | 本轮状态 |
| --- | --- | --- |
| 物理指针、触控板与状态栏外部点击 | 实际 native 窗口点击/切换轨迹、原控件动作/窗口归属；内部 `performClick` 不足 | NOT_RUN，除非附有本轮精确记录 |
| 中文/其他 OS IME | 真正输入法组合、候选选择、选区、刷新/保存/关闭；不以 `setMarkedText` 当系统输入法 | NOT_RUN |
| VoiceOver 与完整键盘路径 | 实际朗读次序、名称/值、开关/菜单/折叠/滚动/sheet、Tab/Shift-Tab/Space/Enter/Escape | NOT_RUN；AX标签源码/对象检查仅软件层 |
| 实际多屏热拔、缩放、Spaces、睡眠唤醒 | 原偏好保持、临时回退、原屏恢复动作及无遗失窗口；记录真实屏幕环境 | NOT_RUN；合成 display ID 与窗口 resize 不替代 |
| 系统提高对比度/减少透明/减少动态的运行时切换 | 已打开表面的真实重绘与动态行为；原设置前后恢复 | NOT_RUN；深浅截图不是这三项证明 |
| 真实 ServiceManagement 登录启动 | 普通已打包身份下注册、系统批准/拒绝/撤销、注销、实际下一次登录；另行明确执行 | NOT_RUN；review 模式不执行 |
| 首次 TCC 与 Chrome JavaScript | 正常新身份权限弹窗、拒绝后恢复；文件来源/自动化/录屏各自测试 | NOT_RUN；preflight 与文案不等于授权成功 |
| Beta 2 真实附件与既有输入链 | 同一候选正常截图、原 click-time 草稿、正文/选区、START/吞噬、无重复/错投/自动发送 | review driver 明确不覆盖；旧 Beta 1 证据保留其原 SHA |
| 正式升级/回退、Gatekeeper、最低系统与 Intel 实机 | 最终包/签名身份、完整备份、实际旧→新过程、逐平台结果 | PENDING / NOT_RUN；CI编译或备份工具测试不等于生产升级 |

这些格子限制相应结论，不应阻止无依赖的编译、修复、审查和隔离验证。最终是否接受某项未实测限制，由实际本轮交付范围和最终外观决定明确记录，不能在矩阵中自行改为 PASS。

## 报告收口

每次 native driver 运行保留独立目录；检查 `completed`、逐 case 状态、`restorationFailures`、逐 frame 的 `RECORDED_NATIVE_WINDOWSERVER / NOT_RUN / FAIL`。总状态不承诺每张图存在。PNG 是精确 NSApp-owned window 的原始像素，必须与 App executable SHA、窗口/contentRect、backingScale、capture 方法一起审查；不只看缩略图或报告中的成功字符串。

最终合并证据需核对 G/tree 与完整 diff、独立非作者审查、仅准入变更的直接 H、实际 PR ordered parents/tree、五项正式 CI，再按获准的标准合并核对 actual main 与 main-push 结果。候选 App/ZIP 及实际 native 报告绑定这条来源链；外观决定、生产替换与对外发行按 [候选说明](../../docs/BETA2_CANDIDATE.md) 单独落事实。

本矩阵新增时没有填造最终 G、包名、hash、已完成 CI 或未执行的原生通过项。最终索引由集成负责人收口，原失败与未运行项继续保留。
