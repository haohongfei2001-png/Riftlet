# Beta 2 原生验收矩阵

本矩阵针对同一 App 的六页设置、控制中心与三步引导。实施源码、XCTest、真实 AppKit action、原始窗口图、CUA 键盘和物理操作分别记录。源码版本为 **Beta 2 · 0.2.0（2）**；最终 G/tree、直接 H、五项 CI 与最终 App/ZIP 由独立交付 manifest 和正式 PR 绑定，不在此猜测未来 SHA。

当前精确候选 `f0e5b99c0945c59652559501585b87aacb3203dc` / binary `9c33fddcb93accb379e240385aac7fd7a27b66b0c68e75d2fa4b17c6aa7e0fd5` 已取得以下 scoped 结果，尚未声明 `BETA2_REVIEW_READY` 或 `PRODUCT_READY`。

| 证据 | 实际结果 | 保留边界 |
| --- | --- | --- |
| [run11 原生 + 自动重启](evidence/native-run-11-owned-page-trace.json) | 13/13 功能、33 PNG、正常 exit 0；同包同 UUID 新进程 6/6、正常 exit 0；五 JSON、3 资产/媒体映射及 hash、operations/START 0 前后相等 | UUID 隔离根，真实 owners/SQLite/collector/native actions；不是普通根升级、系统截图或真实附件 |
| run11 独立原图审查（同一绑定内） | 非作者逐张查看全部 33 原图，hash 相同，无阻断视觉发现，VIS01–05 在对应帧闭环 | 公开仅 scope/hash；无原始私有图/路径。整数显示 3.0 张是非阻断精修；不代替用户最终外观决定 |
| [精确候选 CUA 键盘](evidence/cua-final-keyboard-f0e5b99.json) | 引导 Escape、⌘,、2.25 草稿；⌘W→Escape/Return 均保留焦点与 dirty；⌘Q→Escape 取消退出；应用退出后目标进程不存在、JSON 为 8100 秒 | 最后 AX read 超时，exit code NOT_CAPTURED；不称成功 AX read 或物理键盘。选区范围由对象探针覆盖，CUA 未测 |
| [run10](evidence/native-run-10-pause-trace.json) | 12/13，28 PNG，正常 exit 0；暂停/隐藏与 collector 观察通过；六页 `pageNotPresented` | own-window 鼠标事件来源与因果 UNATTRIBUTED，原 FAIL 保留 |
| [run09](evidence/native-run-09-native-responder.json) | 12/13；四个已到达 popover 稳定；暂停/隐藏 timeout | 该失败未归因；后续通过不重构缺失 trace |
| [首 CI](evidence/ci-974e0bc-first-failures.json)与 [修正范围](evidence/ci-settings-repair.json) | 原 ARM64/Intel 相同 12 个 case 失败；局部修正、target/parser 和实际对象探针分开绑定 | 修正批次与最终五项 CI 待收口；本机 CLT 缺 XCTest，无 shim 冒充执行 |

run11 相对 run10 只有 driver 的页状态/hit trace，没有产品、等待阈值或断言变化。完整历史结果见 [状态索引](STATUS.md)：run01–10 原 FAIL/PARTIAL/timeout、run07 诊断终止、run08 回执缺失与文件恢复、d72 独立重启均保留各自来源。

`PENDING` 表示该最终结论未收口，`NOT_RUN` 表示尚无相应实际执行；通过单项不批准未执行分支。下表中的 run11 PASS 仅指该 case 实际执行的路径。原始图 SHA 核对与非作者目视已分别完成；最终视觉决定仍独立。

## 自动化与原生运行的对应关系

下表的测试文件均在仓库内；case 名与当前 [`SettingsReviewDriver`](../../Sources/RiftletApp/SettingsReviewDriver.swift) 对应。driver 使用真实 AppKit 控件、标准 target-action 与文字编辑 API，走实际 host/model/独立 SQLite；CUA 是另行记录的工具输入。二者**没有物理鼠标、操作系统 IME 或真实 ChatGPT 证明**。

| 场景与必须观察的结果 | 自动化覆盖 | 同一二进制 driver / 现场证据 | 已观察结果与剩余范围 |
| --- | --- | --- | --- |
| 六页同窗、只看不保存、后台更新不弹窗；通用四开关为原生 switch，方向/AX标签一致 | [SettingsCenterTests](../../Tests/RiftletUITests/RiftSettingsCenterTests.swift)：`SixPages…`、`NativeSwitches…`；[HostTests](../../Tests/RiftletAppTests/SettingsProductHostTests.swift)：`ThreeNativeSurfaces…` | `environment-and-default-window`、`six-pages-light-and-dark`；每页浅/深原始 PNG | run11 对应 case PASS；最终 CI/交付身份待收口 |
| 初次内容尺寸 960×684 pt，外框含系统标题栏；小屏可滚动、再次显示不重置 resize | SettingsCenter：`FirstShow…`、`FirstPresentationFrame…`、`ResizeRetains…` | `environment-and-default-window`、`resizing-and-reopen`；outer frame/contentRect/visibleFrame/backingScale 一起记录 | run11 对应 case PASS，内容 960×684 pt；最终 CI 待收口 |
| 布局 caption 与卡片分离；六位置清晰唯一选中，失败保持实际 owner 位置 | SettingsCenter：`LayoutCaptionStaysOutsideDrawing…`、`PlacementHasOneVisibleCheckmark…` | `settings-light-display`、`settings-dark-display`、`settings-minimum-size` 原图及真实位置保存 | run11 对应原图已非作者目视 PASS；最终外观决定独立 |
| 暂停与隐藏四组合；关闭入口独立；停止先有效、恢复失败不假开 | SettingsCenter：`ThreeStopErrors…`、`FailedResume…`；[ControlCenterTests](../../Tests/RiftletUITests/RiftControlCenterControllerTests.swift) 四态；[StateModelTests](../../Tests/RiftletUITests/SettingsStateModelTests.swift) | `orthogonal-pause-hidden-sqlite`，读回独立 SQLite 偏好及控制中心图片 | run11 四组合/SQLite PASS；暂停 2.044s/40 次采样无新增，恢复后新 fixture 收录；不推断追补策略 |
| 独立保存失败叠加、其他成功不清错、同方向 retry、错误依次清除 | SettingsCenter：`ThreeStopErrors…`；Host：`AppearanceSuccess…`；StateModel 延迟/部分失败 | `independent-write-failures-and-retry`；仅阻断已列明的 review JSON，恢复原文件并核对 | run11 对应 case PASS；软件测试最终 CI 待收口 |
| 原始文本、光标、控件 identity 不被后台刷新覆盖，非 dirty 字段跟随 owner | SettingsCenter：`NativeFieldsKeepIdentity…`；Host：`OwnerRefreshDuringDraft…` | `configuration-editor-refresh-defaults`；真实 NSTextView/owner 读回 | run11 对应 case PASS；不等于 OS IME |
| 首击归档保存读取最后编辑，预设也是草稿，小数/0 正确；显式放弃/默认不被旧 editor 写回 | SettingsCenter：`ArchiveFirstSave…`、`ArchivePreset…`、`ExplicitDefaultsAndDiscard…` | `archive-editor-first-save-discard`、`configuration-editor-refresh-defaults` | run11 对应 case PASS；最终 CI 待收口 |
| IME marked text 保留；Return 组词不提交；明确放弃使用原生编辑取消 | SettingsCenter：`MarkedComposition…`、`ExplicitDiscardCancelsMarkedInput…` | driver 无真实 OS 输入法；不能给物理中文组词 PASS | 软件层待 CI；OS IME NOT_RUN |
| 红关闭/⌘W：继续保留、放弃只影响草稿、应用等待真实保存；部分成功不重复成功域 | SettingsCenter：`FirstClose…`、`ApplyAndClose…`、`FailedApply…`、`DiscardClose…`、`PartialCloseSave…` | `close-sheet-continue-discard` 仅覆盖其实际两个分支；ea312a6 CUA 已在先确认草稿后执行 ⌘W/继续编辑 | run11 实际按钮分支 PASS；f0e5b99 CUA 的 ⌘W→Escape/Return 保留草稿；未执行分支另记 |
| App Quit 复用关闭决策；保存失败保留同 sheet；Continue/teardown/晚回执不误批准；Feedback 清理期间不能打开新设置或发起命令 | SettingsCenter：9 个 `Termination…`；Host：2 个 `TerminationPreparation…`；ControlCenter：`SuspendedInteraction…` | 完整候选正常退出；草稿、失败应用、取消与新动作竞态按实际执行分开记 | f0e5b99 CUA 取消/应用退出分支已观察；应用后进程不存在、8100 秒，exit code 未捕获；完整竞态测试待 CI |
| 保存开始即 busy，同域不重入、跨域仍可用，新编辑在延迟回执后保留 | SettingsCenter：`InFlightSave…`；Host：`BusyChangePublishes…`；StateModel 对应测试 | driver 以具体持久化回读判定，不用固定 sleep 当结果 | PENDING |
| 显示器具体身份、同名屏不合并、菜单 tracking 中刷新不换目标、临时回退不改偏好 | SettingsCenter：`DisplayFallback…`、`DisplayMenuTracking…`、`SameNamedDisplays…`；[OnboardingTests](../../Tests/RiftletUITests/RiftOnboardingControllerTests.swift) | `three-step-guidance-light-and-dark` 只记录当时可用屏幕；热拔/跨屏另测 | 软件层待 CI；热拔 NOT_RUN |
| 本页恢复只重置有效本页数值；七个个性化兼容参数、显示器/另一页草稿保留 | SettingsCenter：`RestoreCurrentPage…`；StateModel：`PageDefaults…` | `configuration-editor-refresh-defaults`；JSON 内容核对 | run11 对应 case PASS；全部兼容字段软件断言待最终 CI |
| 选择动效不自播、主动预览、切页停止；减少动态 `min(80ms, 原时长)` 不变慢 | SettingsCenter：`ExplicitPreviewOnly…`；StateModel 单位测试 | `motion-explicit-play-and-navigation-stop`；截图只是瞬时画面 | run11 对应 case PASS；真实系统减少动态切换 NOT_RUN |
| 外观先保存再应用，system 清除显式覆盖；错误/重试不串其他域 | Host：`HostAppearanceCreatesRealScopedJSON…`、`HostAppearanceWriteFailure…`；[AppearanceTests](../../Tests/RiftletAppTests/ApplicationPresentationPreferencesTests.swift) | `six-pages-light-and-dark`、失败 case 的真实 review JSON | run11 浅深/实际 JSON 和失败重试 PASS；未改系统主题 |
| 登录系统状态与调用错误并存；等待批准不是已生效，读取不注册，同目标幂等 | Host：`ActualLoginReadback…`、`LoginFailedTarget…`；[LoginTests](../../Tests/RiftletAppTests/LoginItemPreferencesTests.swift) | review 模式明确 unavailable；禁止 driver 注册/注销/打开系统登录设置 | fake 待 CI；真实登录启动 NOT_RUN |
| 原生 popover 打开/关闭、点外面/Escape、右键菜单同一显式命令；不可用截图不误发 | ControlCenterTests | `orthogonal-pause-hidden-sqlite` 只证明实际执行的动作/图片；精确 d72 CUA 未取得状态栏操作面 | run11 七次展示/14 次稳定检查 PASS；原图非作者目视通过；物理状态栏/外部点击 NOT_RUN |
| 三步可前后切换、稍后完成；已有连接不重复授权、位置保存/失败重试，不制造 capture | OnboardingTests | `three-step-guidance-light-and-dark`；三步×浅深图 | run11 对应 case/六原图 PASS，652×608 pt；真实授权弹窗 NOT_RUN |
| 真实历史、未测量不是 0 B；清空只有一次 Main 确认且保留所有内容 | SettingsCenter：`NoStorageMeasurement…`；Host：`ExternalActionsPassThrough…` | `history-real-records`；清空确认与原图保留需实录对应操作，未执行就单列 | run11 history case/原图 PASS；未执行的清空确认不得借用通过 |
| review UUID、根/marker/symlink/锁、只fixture来源、默认域分离、无Web/真实登录项 | [EnvironmentTests](../../Tests/RiftletAppTests/SettingsReviewEnvironmentTests.swift) | `environment-and-default-window`、`real-collector-synthetic-fixture`、`original-media-and-no-upload-operations` | run11 实际隔离路径 PASS；安全边界测试最终 CI 待收口 |
| 同包同 UUID 新进程重启；配置/SQLite/media 读回相同，不重跑 UI suite 或制造附件 | [原生 runner](../../scripts/run-settings-review.sh)、`SettingsReviewDriver.verifyRestart()` | d72 独立 restart-only、前后逻辑快照、新旧进程及同一 executable hash；原 run06 超时记录保持 | run11 自动完整 run→fresh-process restart PASS_SCOPED；不是生产升级 |

设置中心异步测试按**特定 host action 完成 ID**、实际保存 continuation 或 native sheet completion 作有界等待，结束后仍执行原结果断言。超时是失败，不通过增加 sleep、跳过断言或重跑到绿来替代状态确认。Host 的延迟 owner 使用明确 gate / expectation。

## 必须单独保留的真实平台边界

| 平台项目 | 需要的实际证据 | 本轮状态 |
| --- | --- | --- |
| 物理指针、触控板与状态栏外部点击 | 实际 native 窗口点击/切换轨迹、原控件动作/窗口归属；内部 `performClick` 不足 | NOT_RUN，除非附有本轮精确记录 |
| 中文/其他 OS IME | 真正输入法组合、候选选择、选区、刷新/保存/关闭；不以 `setMarkedText` 当系统输入法 | NOT_RUN |
| VoiceOver 与完整键盘路径 | 实际朗读次序、名称/值、开关/菜单/折叠/滚动/sheet、Tab/Shift-Tab/Space/Enter/Escape | VoiceOver/完整路径 NOT_RUN；已记录 CUA 的有限键盘分支不代替完整辅助功能验收 |
| 实际多屏热拔、缩放、Spaces、睡眠唤醒 | 原偏好保持、临时回退、原屏恢复动作及无遗失窗口；记录真实屏幕环境 | NOT_RUN；合成 display ID 与窗口 resize 不替代 |
| 系统提高对比度/减少透明/减少动态的运行时切换 | 已打开表面的真实重绘与动态行为；原设置前后恢复 | NOT_RUN；普通浅深色有实际解析；HC 测试读真实 effectiveAppearance，条件不足明确 XCTSkip/NOT_RUN；旧不可移植 fixture 不作 HC 证明，没有修改系统偏好 |
| 真实 ServiceManagement 登录启动 | 普通已打包身份下注册、系统批准/拒绝/撤销、注销、实际下一次登录；另行明确执行 | NOT_RUN；review 模式不执行 |
| 首次 TCC 与 Chrome JavaScript | 正常新身份权限弹窗、拒绝后恢复；文件来源/自动化/录屏各自测试 | NOT_RUN；preflight 与文案不等于授权成功 |
| Beta 2 真实附件与既有输入链 | 同一候选正常截图、原 click-time 草稿、正文/选区、START/吞噬、无重复/错投/自动发送 | review driver 明确不覆盖；旧 Beta 1 证据保留其原 SHA |
| 正式升级/回退、Gatekeeper、最低系统与 Intel 实机 | 最终包/签名身份、完整备份、实际旧→新过程、逐平台结果 | PENDING / NOT_RUN；CI编译或备份工具测试不等于生产升级 |

这些格子限制相应结论，不应阻止无依赖的编译、修复、审查和隔离验证。最终是否接受某项未实测限制，由实际本轮交付范围和最终外观决定明确记录，不能在矩阵中自行改为 PASS。

## 报告收口

每次 native driver 运行保留独立目录；检查 `completed`、逐 case 状态、`restorationFailures`、逐 frame 的 `RECORDED_NATIVE_WINDOWSERVER / NOT_RUN / FAIL`。总状态不承诺每张图存在。PNG 是精确 NSApp-owned window 的原始像素，必须与 App executable SHA、窗口/contentRect、backingScale、capture 方法一起审查；不只看缩略图或报告中的成功字符串。

最终合并证据需核对 G/tree 与完整 diff、独立非作者审查、仅准入变更的直接 H、实际 PR ordered parents/tree、五项正式 CI，再按获准的标准合并核对 actual main 与 main-push 结果。G/H、包和报告的完整身份由仓库外私有 `final-manifest` 与正式 PR 交付记录绑定，不在尚未形成的提交内猜测自身 SHA。外观决定、生产替换与对外发行按 [候选说明](../../docs/BETA2_CANDIDATE.md) 单独落事实。

本矩阵新增时没有填造最终 G、包名、hash、已完成 CI 或未执行的原生通过项。最终索引由集成负责人收口，原失败与未运行项继续保留。
