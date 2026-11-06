# Beta 2 原生验收矩阵

本矩阵针对同一 App 中的新设置中心、控制中心与引导。实施代码、XCTest、真实 App 内部 action、WindowServer 图片、物理操作和用户最终外观决定分别记录，不互相替代。源码已分配版本身份 **Beta 2 · 0.2.0（2）**。最终源码 G / H、App SHA、报告 SHA、CI run / checkout、操作系统与架构：**PENDING，集成负责人在收口时填写**。

作者已完成新 UI/Host/Environment 的实际 target 编译与语法检查；本机 CLT 缺少 XCTest，因此没有用 shim 冒充 XCTest。截至 run06 的 `d72f966`，测试文件定义了设置中心 38 项、Host 12 项、环境 12 项、控制中心 10 项、动态样式 2 项测试；计数表示存在的测试方法，**不是本机已运行通过的数量**。引导与既有 model/login/appearance 测试均须以最终 CI 的实际执行、跳过和失败记录为准。

`PENDING` 表示待绑定精确候选的执行结果；`NOT_RUN` 表示尚无该类真实验收证据。中间 App 的实际窗口查看只能用于修正当前候选，不能提前填成最终通过。任何失败保留原 report/PNG/日志；修复后用新的源/工件身份复验受影响路径，不覆盖原文件。

## run01 已观察事实

[原始绑定](evidence/native-run-01.json)对应源码 `45418bba9fb05e5c2649473c8c1f26a460fb54c5`，13 组实际 native action / owner / SQLite 检查均为 PASS；3 张 fixture、0 个附件 operation、0 个 upload start。实际首窗内容 960×684 pt。原报告 `completed=true`、恢复失败为空，但这只表示 driver 完成检查，**不表示进程已正常退出**。

| run01 项目 | 实际结果 | 当时要求的复验 |
| --- | --- | --- |
| 原始 WindowServer 图片 | 30/33；`control-light`、`control-normal`、`control-paused-hidden` 为 `NOT_RUN / ownedWindowUnavailable` | run02 取得各自真实窗口图，不补造旧图 |
| 正常退出 | runner 180 秒超时，状态 INCOMPLETE_TIMEOUT；只终止其隔离子进程 | 完整候选正常退出与同包新进程重启 |
| 控制中心说明列 | 可用空间未被文字使用，出现过窄换行 | 宽度约束窄修已实现；待新浅/深及状态图 |
| 布局说明 | “左中 · 3 张”覆盖示意卡 | 已移至画布外 native caption；待新图 |
| 六位置当前值 | 已保存位置的按钮外观不清晰 | 已选项 checkmark + accent/bezel；待新图与实际选择 |
| 引导初窗 | 实际宽度 562 pt，未达到约定初始尺寸；第三步仍可滚动 | 约束建立后恢复初始尺寸；待新图和 frame |

旧退出路径的独立 AppKit 探针也超时；修改后的探针退出码为 0。它支持生命周期修复方向，不能替代完整候选退出。设置草稿 Quit 确认、保存失败保留同一 sheet、跨 Feedback 清理期间临时锁定新设置动作已有针对性测试。四项视觉差异保留为原始发现，不能因源码已改就改记视觉 PASS。

## run02 与额外 CUA 观察

[run02 原始绑定](evidence/native-run-02.json)及 [CUA 单独记录](evidence/cua-native-bc903f7.json)都绑定 `bc903f7141b1218dcd93964cc301fcb911a90bd3` 的相同运行可执行文件。CUA 使用固定隔离 launcher 包装，其包身份/签名有测试差异；不称完整 App 包逐字相同。

| 项目 | 实际结果 | 不能据此推断 |
| --- | --- | --- |
| 自动 native driver | 12 PASS、1 FAIL：`onboardingOuterSizeMismatch` | 不是 13/13 通过；没有新的引导图 |
| 进程结束 | exit 0，20.16 秒，无超时 | 不证明全部 Quit/系统注销路径 |
| 窗口图 | 27 个文件已核对原始 hash；7 个控制中心捕获被独立审查否决为不完整裁切/黑或透明空区 | `RECORDED` 不等于视觉 PASS，不能确认说明列修复 |
| 预览说明与六位置选中 | 独立审查确认该二进制浅/深/紧凑图不再重叠，勾选清晰 | 不延伸为最终候选或其他系统外观通过 |
| 同包重启 | NOT_RUN；首轮功能失败后没有继续重启阶段 | 正常 exit 0 不等于持久化重启验收 |
| CUA 原生输入 | Return 三步、选右下、⌘,、键入 6.25、⌘Q 继续保留、再次应用退出；退出后 22500 秒 | 不等于 OS IME、VoiceOver、用户物理输入或浏览器附件 |
| CUA 剩余失败 | ⌘W 无标准 Close 菜单、引导初窗尺寸不足 | 后续源码修正仍待新候选验证 |

run02 完整运行是 FAIL，原图和原始结果不改写。

## run03 继续保留的失败

[run03 绑定](evidence/native-run-03.json)对应 `ea312a6393cb49c0819269ef1bc19aac82ca0de4`，正常 exit 0 / 14.99 秒，12/13 功能 PASS。引导 case 已通过，六张引导原图均为 1304×1216 像素、652×608 pt 外框；这记录尺寸与实际执行，不自行代替完整目视批准。

唯一失败是 `orthogonal-pause-hidden-sqlite` 的 `controlUnavailable:settings.center.paused`；集成侧定位为 driver 在控件暂时禁用时提前发起下一动作。29 个原图文件已核对哈希，三个已取得的控制中心帧仍有 WindowServer 与 AppKit 尺寸差异，例如 210×311 对 362×539 pt，不能作为完整稳定视图验收。该失败 case 的另四张状态图未产生，同包重启没有执行。

后续 driver 修正实际可用/完整稳定窗口等待，不能把旧失败重标 PASS。完整功能、原生捕获、正常退出与同包同根新进程重启须共同满足；run04/run05 的实际结果另列如下，正式 CI、最终 App/ZIP 仍待完成。

[ea312a6 的 CUA 键盘复验](evidence/cua-native-ea312a6.json)有四项有明确前置观察的 PASS：Escape 退出引导后 ⌘, 打开设置；先确认已有草稿后 ⌘W 显示关闭 sheet；继续编辑保留草稿；⌘Q 不保存后进程退出并保留 86400 秒已确认归档值。快速连批预设选择/关闭未先观测草稿，结果仍是 `INCONCLUSIVE`；失效 AX 索引是 `TOOL_ERROR_RECOVERED`，切换后重读是 `REOBSERVED`，退出后文件缺失假设改查真实保存值是 `AUDIT_ASSUMPTION_CORRECTED`。这些不确定性不新增为产品 FAIL，也不补成 PASS。

## run04 / run05 原始失败

两轮各自新增原始绑定：[run04](evidence/native-run-04.json) 为 `4174a04`，[run05](evidence/native-run-05.json) 为 `64ac68b`。源码 tree、候选可执行文件、runner、实际 report、独立审查原记录及已产生 PNG 的哈希分别核对，未改写前轮证据。

| 项目 | 实际结果 | 结论边界 |
| --- | --- | --- |
| run04 功能与退出 | 11 PASS / 2 FAIL；六页浅深、暂停/隐藏 case 为 `conditionTimedOut`；29.65 秒正常 exit 0 | 整轮 FAIL，同包重启 NOT_RUN |
| run04 窗口记录 | 25 条中 23 PNG、2 NOT_RUN；normal / paused / save-failure 三张 control 原图获非作者局部视觉 PASS | 说明列与完整捕获只对这三张关闭发现；缺失状态与深色不借用通过 |
| run05 磁盘报告 | `completed=true`，9 PASS / 4 FAIL；新增失败包含独立写失败恢复和 resize/reopen；22 条中 19 PNG、3 NOT_RUN | 报告完成不等于进程或 suite 成功 |
| run05 runner | `INCOMPLETE`，180 秒超时，exit -15；日志为空且未取得 stdout 报告路径 | 从同一 review 根实际文件核对 UUID、进程与 binary 后单独绑定，不伪造 runner 报告回执 |
| run05 退出等待 | 集成侧观察到失败 case 遗留草稿，正常 Quit sheet 等待决定 | 保留超时，不据此推断无草稿退出倒退；独立源码审查未直接查看该待决进程 |
| 控制中心关闭时序 | 展示动作返回后，原生激活交回与无条件 `didResignActive` 关闭重叠；独立审查批准删除这一重复路径及窄回归 | 通知顺序不能单独证明唯一因果；不增加产品焦点门槛，等待 run06 实际复验 |

原 run04/run05 失败和 run05 报告/runner 的差异继续保留。后续结果按以下精确工件与范围记录，不覆盖前轮。

## run06、精确原包 CUA 与独立重启

三份证据都绑定 `d72f9665845c30910786558acb090dd72328ccd9` / binary `54749ad5695a5edd6e2eb6077e4456be4498d02b43f7451fb911bb99bfedf545`；CUA 使用原候选包，未使用前轮包装 App。

| 证据 | 已执行结果 | 保留限制 |
| --- | --- | --- |
| [run06](evidence/native-run-06.json) | 9 PASS / 4 FAIL；26 PNG / 3 NOT_RUN；首次浅色 popover 保持可见并达到完整尺寸 | 后续程序化打开仍关闭过早；runner 180 秒 timeout / exit -15；整轮 FAIL、完整 runner 重启阶段 NOT_RUN |
| [精确原包 CUA](evidence/cua-native-exact-d72f966.json) | 精确候选隔离启动；Escape 关闭引导；⌘Q 工具超时后核对进程已不在 | 状态栏工具面不可用，打开/再点关闭/外部点击 NOT_RUN；没有正常退出码，不将工具限制判为产品失败 |
| [独立 restart-only](evidence/independent-restart-d72f966.json) | 同包同根新进程，正常 exit 0 / 0.466 秒；五 JSON / owner / SQLite 暂停隐藏读回；1 媒体及 asset 映射相等；既有引导不再展示 | `PASS_SCOPED_NATIVE_RESTART`，不覆盖原 FAIL 或 full-runner 前置；不等于生产升级 |
| 重启外部只读 SQL | 两次均在子进程退出后事务读取，完整 operation 表 0、START 0；前后媒体摘要一致 | 原 native report 自身的完整操作表计数仍标 NOT_RUN，外部 SQL 作为单独补充，不改原报告 |

移除 `didResignActive` 的窄修已在 run06 的源和运行包中；独立审查确认原有关闭路径保留。首次与后续打开的 key-window 状态差异支持继续诊断，但还不是唯一原因证明。只补有界诊断调用栈；实际状态栏输入仍缺证据，不能从 `.transient`、合成通知或程序化 `performClick` 推断物理操作通过。

[Draft PR #43](https://github.com/haohongfei2001-png/Riftlet/pull/43) 已开，初始 head `974e0bc` / base `c72fca7`。截至 2026-11-06 10:56 UTC，[Native](https://github.com/haohongfei2001-png/Riftlet/actions/runs/42205691399) 与 [Feedback](https://github.com/haohongfei2001-png/Riftlet/actions/runs/42205691613) 两项 source gate 均 FAIL（仍是 PR42 准入记录），ARM64 / Intel 正在执行 unit/integration 步骤，Feedback native and service 已 SUCCESS；其旧 composition 条件步骤 skipped 如实保留。最终独立源码审查、G / H、完整 CI、最终包和外观决定仍待完成；不声明 review-ready。

## 自动化与原生运行的对应关系

下表的测试文件均在仓库内；case 名与当前 [`SettingsReviewDriver`](../../Sources/RiftletApp/SettingsReviewDriver.swift) 对应。driver 直接调用真实 AppKit 控件与文字编辑 API，走实际 host/model/独立 SQLite，**没有物理鼠标、操作系统 IME 或真实 ChatGPT 证明**。

| 场景与必须观察的结果 | 自动化覆盖 | 同一二进制 driver / 现场证据 | 当前最终结果 |
| --- | --- | --- | --- |
| 六页同窗、只看不保存、后台更新不弹窗；通用四开关为原生 switch，方向/AX标签一致 | [SettingsCenterTests](../../Tests/RiftletUITests/RiftSettingsCenterTests.swift)：`SixPages…`、`NativeSwitches…`；[HostTests](../../Tests/RiftletAppTests/SettingsProductHostTests.swift)：`ThreeNativeSurfaces…` | `environment-and-default-window`、`six-pages-light-and-dark`；每页浅/深原始 PNG | PENDING |
| 初次内容尺寸 960×684 pt，外框含系统标题栏；小屏可滚动、再次显示不重置 resize | SettingsCenter：`FirstShow…`、`FirstPresentationFrame…`、`ResizeRetains…` | `environment-and-default-window`、`resizing-and-reopen`；outer frame/contentRect/visibleFrame/backingScale 一起记录 | PENDING |
| 布局 caption 与卡片分离；六位置清晰唯一选中，失败保持实际 owner 位置 | SettingsCenter：`LayoutCaptionStaysOutsideDrawing…`、`PlacementHasOneVisibleCheckmark…` | `settings-light-display`、`settings-dark-display`、`settings-minimum-size` 原图及真实位置保存 | run02 该二进制已独立目视确认；最终候选 PENDING |
| 暂停与隐藏四组合；关闭入口独立；停止先有效、恢复失败不假开 | SettingsCenter：`ThreeStopErrors…`、`FailedResume…`；[ControlCenterTests](../../Tests/RiftletUITests/RiftControlCenterControllerTests.swift) 四态；[StateModelTests](../../Tests/RiftletUITests/SettingsStateModelTests.swift) | `orthogonal-pause-hidden-sqlite`，读回独立 SQLite 偏好及控制中心图片 | PENDING |
| 独立保存失败叠加、其他成功不清错、同方向 retry、错误依次清除 | SettingsCenter：`ThreeStopErrors…`；Host：`AppearanceSuccess…`；StateModel 延迟/部分失败 | `independent-write-failures-and-retry`；仅阻断已列明的 review JSON，恢复原文件并核对 | PENDING |
| 原始文本、光标、控件 identity 不被后台刷新覆盖，非 dirty 字段跟随 owner | SettingsCenter：`NativeFieldsKeepIdentity…`；Host：`OwnerRefreshDuringDraft…` | `configuration-editor-refresh-defaults`；真实 NSTextView/owner 读回 | PENDING；不等于 OS IME |
| 首击归档保存读取最后编辑，预设也是草稿，小数/0 正确；显式放弃/默认不被旧 editor 写回 | SettingsCenter：`ArchiveFirstSave…`、`ArchivePreset…`、`ExplicitDefaultsAndDiscard…` | `archive-editor-first-save-discard`、`configuration-editor-refresh-defaults` | PENDING |
| IME marked text 保留；Return 组词不提交；明确放弃使用原生编辑取消 | SettingsCenter：`MarkedComposition…`、`ExplicitDiscardCancelsMarkedInput…` | driver 无真实 OS 输入法；不能给物理中文组词 PASS | 软件层待 CI；OS IME NOT_RUN |
| 红关闭/⌘W：继续保留、放弃只影响草稿、应用等待真实保存；部分成功不重复成功域 | SettingsCenter：`FirstClose…`、`ApplyAndClose…`、`FailedApply…`、`DiscardClose…`、`PartialCloseSave…` | `close-sheet-continue-discard` 仅覆盖其实际两个分支；ea312a6 CUA 已在先确认草稿后执行 ⌘W/继续编辑 | 该 ⌘W 分支已观察；其他未执行分支与最终候选仍 PENDING |
| App Quit 复用关闭决策；保存失败保留同 sheet；Continue/teardown/晚回执不误批准；Feedback 清理期间不能打开新设置或发起命令 | SettingsCenter：9 个 `Termination…`；Host：2 个 `TerminationPreparation…`；ControlCenter：`SuspendedInteraction…` | 完整候选正常退出；草稿、失败应用、取消与新动作竞态按实际执行分开记 | run02 正常退出、CUA 继续/应用分支已观察；完整分支及最终候选 PENDING |
| 保存开始即 busy，同域不重入、跨域仍可用，新编辑在延迟回执后保留 | SettingsCenter：`InFlightSave…`；Host：`BusyChangePublishes…`；StateModel 对应测试 | driver 以具体持久化回读判定，不用固定 sleep 当结果 | PENDING |
| 显示器具体身份、同名屏不合并、菜单 tracking 中刷新不换目标、临时回退不改偏好 | SettingsCenter：`DisplayFallback…`、`DisplayMenuTracking…`、`SameNamedDisplays…`；[OnboardingTests](../../Tests/RiftletUITests/RiftOnboardingControllerTests.swift) | `three-step-guidance-light-and-dark` 只记录当时可用屏幕；热拔/跨屏另测 | 软件层待 CI；热拔 NOT_RUN |
| 本页恢复只重置有效本页数值；七个个性化兼容参数、显示器/另一页草稿保留 | SettingsCenter：`RestoreCurrentPage…`；StateModel：`PageDefaults…` | `configuration-editor-refresh-defaults`；JSON 内容核对 | PENDING |
| 选择动效不自播、主动预览、切页停止；减少动态 `min(80ms, 原时长)` 不变慢 | SettingsCenter：`ExplicitPreviewOnly…`；StateModel 单位测试 | `motion-explicit-play-and-navigation-stop`；截图只是瞬时画面 | PENDING；真实系统减少动态切换另记 |
| 外观先保存再应用，system 清除显式覆盖；错误/重试不串其他域 | Host：`HostAppearanceCreatesRealScopedJSON…`、`HostAppearanceWriteFailure…`；[AppearanceTests](../../Tests/RiftletAppTests/ApplicationPresentationPreferencesTests.swift) | `six-pages-light-and-dark`、失败 case 的真实 review JSON | PENDING；未改系统主题 |
| 登录系统状态与调用错误并存；等待批准不是已生效，读取不注册，同目标幂等 | Host：`ActualLoginReadback…`、`LoginFailedTarget…`；[LoginTests](../../Tests/RiftletAppTests/LoginItemPreferencesTests.swift) | review 模式明确 unavailable；禁止 driver 注册/注销/打开系统登录设置 | fake 待 CI；真实登录启动 NOT_RUN |
| 原生 popover 打开/关闭、点外面/Escape、右键菜单同一显式命令；不可用截图不误发 | ControlCenterTests | `orthogonal-pause-hidden-sqlite` 只证明实际执行的动作/图片；精确 d72 CUA 未取得状态栏操作面 | 程序化完整 case FAIL；真实状态栏操作 NOT_RUN；原因待定 |
| 三步可前后切换、稍后完成；已有连接不重复授权、位置保存/失败重试，不制造 capture | OnboardingTests | `three-step-guidance-light-and-dark`；三步×浅深图 | PENDING；真实授权弹窗 NOT_RUN |
| 真实历史、未测量不是 0 B；清空只有一次 Main 确认且保留所有内容 | SettingsCenter：`NoStorageMeasurement…`；Host：`ExternalActionsPassThrough…` | `history-real-records`；清空确认与原图保留需实录对应操作，未执行就单列 | PENDING |
| review UUID、根/marker/symlink/锁、只fixture来源、默认域分离、无Web/真实登录项 | [EnvironmentTests](../../Tests/RiftletAppTests/SettingsReviewEnvironmentTests.swift) | `environment-and-default-window`、`real-collector-synthetic-fixture`、`original-media-and-no-upload-operations` | PENDING |
| 同包同 UUID 新进程重启；配置/SQLite/media 读回相同，不重跑 UI suite 或制造附件 | [原生 runner](../../scripts/run-settings-review.sh)、`SettingsReviewDriver.verifyRestart()` | d72 独立 restart-only、前后逻辑快照、新旧进程及同一 executable hash；原 run06 超时记录保持 | d72 独立重启 PASS_SCOPED；完整 runner 成功首轮后联动重启 NOT_RUN；最终候选 PENDING |

设置中心异步测试按**特定 host action 完成 ID**、实际保存 continuation 或 native sheet completion 作有界等待，结束后仍执行原结果断言。超时是失败，不通过增加 sleep、跳过断言或重跑到绿来替代状态确认。Host 的延迟 owner 使用明确 gate / expectation。

## 必须单独保留的真实平台边界

| 平台项目 | 需要的实际证据 | 本轮状态 |
| --- | --- | --- |
| 物理指针、触控板与状态栏外部点击 | 实际 native 窗口点击/切换轨迹、原控件动作/窗口归属；内部 `performClick` 不足 | NOT_RUN，除非附有本轮精确记录 |
| 中文/其他 OS IME | 真正输入法组合、候选选择、选区、刷新/保存/关闭；不以 `setMarkedText` 当系统输入法 | NOT_RUN |
| VoiceOver 与完整键盘路径 | 实际朗读次序、名称/值、开关/菜单/折叠/滚动/sheet、Tab/Shift-Tab/Space/Enter/Escape | NOT_RUN；AX标签源码/对象检查仅软件层 |
| 实际多屏热拔、缩放、Spaces、睡眠唤醒 | 原偏好保持、临时回退、原屏恢复动作及无遗失窗口；记录真实屏幕环境 | NOT_RUN；合成 display ID 与窗口 resize 不替代 |
| 系统提高对比度/减少透明/减少动态的运行时切换 | 已打开表面的真实重绘与动态行为；原设置前后恢复 | NOT_RUN；动态样式测试真实解析同一 cached color 的 Aqua/DarkAqua，HC 仅明确标注的匹配 fixture。SDK 不允许直接构造 HC 命名外观；没有修改系统偏好 |
| 真实 ServiceManagement 登录启动 | 普通已打包身份下注册、系统批准/拒绝/撤销、注销、实际下一次登录；另行明确执行 | NOT_RUN；review 模式不执行 |
| 首次 TCC 与 Chrome JavaScript | 正常新身份权限弹窗、拒绝后恢复；文件来源/自动化/录屏各自测试 | NOT_RUN；preflight 与文案不等于授权成功 |
| Beta 2 真实附件与既有输入链 | 同一候选正常截图、原 click-time 草稿、正文/选区、START/吞噬、无重复/错投/自动发送 | review driver 明确不覆盖；旧 Beta 1 证据保留其原 SHA |
| 正式升级/回退、Gatekeeper、最低系统与 Intel 实机 | 最终包/签名身份、完整备份、实际旧→新过程、逐平台结果 | PENDING / NOT_RUN；CI编译或备份工具测试不等于生产升级 |

这些格子限制相应结论，不应阻止无依赖的编译、修复、审查和隔离验证。最终是否接受某项未实测限制，由实际本轮交付范围和最终外观决定明确记录，不能在矩阵中自行改为 PASS。

## 报告收口

每次 native driver 运行保留独立目录；检查 `completed`、逐 case 状态、`restorationFailures`、逐 frame 的 `RECORDED_NATIVE_WINDOWSERVER / NOT_RUN / FAIL`。总状态不承诺每张图存在。PNG 是精确 NSApp-owned window 的原始像素，必须与 App executable SHA、窗口/contentRect、backingScale、capture 方法一起审查；不只看缩略图或报告中的成功字符串。

最终合并证据需核对 G/tree 与完整 diff、独立非作者审查、仅准入变更的直接 H、实际 PR ordered parents/tree、五项正式 CI，再按获准的标准合并核对 actual main 与 main-push 结果。G/H、包和报告的完整身份由仓库外私有 `final-manifest` 与正式 PR 交付记录绑定，不在尚未形成的提交内猜测自身 SHA。外观决定、生产替换与对外发行按 [候选说明](../../docs/BETA2_CANDIDATE.md) 单独落事实。

本矩阵新增时没有填造最终 G、包名、hash、已完成 CI 或未执行的原生通过项。最终索引由集成负责人收口，原失败与未运行项继续保留。
