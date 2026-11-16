# 设置项完整台账与迁移规则

基线 **B = `3f8149e2313fd81bbaee5a7bbbdbb1efca2fc81b`**。本页逐项对应1.0.3真实代码，决定1.0.4的保留、移动、合并、自动化、隐藏和移除；REMOVE只移除界面入口，不代表删除既有偏好或数据。总设计见[DESIGN_SPEC.md](DESIGN_SPEC.md)，任务见[IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)。

## 1. 结构与保存原则

四个紧凑的**顶部工具栏页签：通用／外观／截图／帮助**。默认内容640×560pt，最小600×460pt；加宽后有效正文最多720pt并居中。继续使用AppKit原生控件、现有`SettingsProductHost`及`SettingsStateModel`；不另建设置框架、第二份状态或第二个持久化owner。

- 普通有效选择即应用并保存；失败就地显示仍生效值和一次重试动作。连续外观调整实时预览，结束手势后通过原owner提交；不按每个像素落盘。
- 外观页展示与实际托盘共用绘制逻辑的无副作用样例，保留一份小型位置示意。样例不创建真实资产、采集或附加操作。
- 普通界面没有pt、色相角度、遮挡率、动画毫秒或命中区参数。重要控制权保留；旧非默认几何仅在该用户的“旧版自定义”中渐进呈现，恢复范围必须明确。
- 截图、历史、权限、更新分别由既有owner处理；改变相机颜色不能写归档策略、显示器、队列或浏览器状态。正常状态少解释，错误时给对应下一步。

### 源码索引

以下为本台账实际审阅的固定基线来源；行号只辅助定位，函数名为稳定入口。

| 简称 | 固定基线来源及责任 |
|---|---|
| Pages | [RiftSettingsCenterPages.swift](https://github.com/haohongfei2001-png/Riftlet/blob/3f8149e2313fd81bbaee5a7bbbdbb1efca2fc81b/Sources/RiftletUI/RiftSettingsCenterPages.swift)：四页全部控件、条件恢复动作、numericRow、disclosure |
| Render | [RiftSettingsCenterRendering.swift](https://github.com/haohongfei2001-png/Riftlet/blob/3f8149e2313fd81bbaee5a7bbbdbb1efca2fc81b/Sources/RiftletUI/RiftSettingsCenterRendering.swift)：状态显示、条件隐藏、实际容量、有效值 |
| Config | [RiftConfiguration.swift](https://github.com/haohongfei2001-png/Riftlet/blob/3f8149e2313fd81bbaee5a7bbbdbb1efca2fc81b/Sources/RiftletUI/RiftConfiguration.swift)：布局字段、旧值解码、三种形态、主题、常用键 |
| Model | [SettingsStateModel.swift](https://github.com/haohongfei2001-png/Riftlet/blob/3f8149e2313fd81bbaee5a7bbbdbb1efca2fc81b/Sources/RiftletUI/SettingsStateModel.swift)：意图、分域确认、草稿、字段适用性及重试 |
| Host | [SettingsProductHost.swift](https://github.com/haohongfei2001-png/Riftlet/blob/3f8149e2313fd81bbaee5a7bbbdbb1efca2fc81b/Sources/RiftletApp/SettingsProductHost.swift)：单一快照、外观／登录项／历史视图owner接线 |
| Prefs | [RecoverablePreferences.swift](https://github.com/haohongfei2001-png/Riftlet/blob/3f8149e2313fd81bbaee5a7bbbdbb1efca2fc81b/Sources/RiftletApp/RecoverablePreferences.swift)：布局与归档字节保护、未知字段、局部补丁及坏文件恢复 |
| Onboarding | [RiftOnboardingController.swift](https://github.com/haohongfei2001-png/Riftlet/blob/3f8149e2313fd81bbaee5a7bbbdbb1efca2fc81b/Sources/RiftletUI/RiftOnboardingController.swift)、[FirstUsePreferences.swift](https://github.com/haohongfei2001-png/Riftlet/blob/3f8149e2313fd81bbaee5a7bbbdbb1efca2fc81b/Sources/RiftletApp/FirstUsePreferences.swift)：首用步骤、完成／延期、文件夹bookmark |

PR #101／#103已实现的四页、自然宽度按钮、真实状态保存、明确“稍后设置”、托盘容量约束和核心中英文文案继续保留。此台账不把旧缺陷重新标成全部未修。

## 2. 通用页及应用级偏好

| 1.0.3控件／事实 | 字段／owner与当前默认 | 1.0.4裁决 | 保存与兼容要求 |
|---|---|---|---|
| 登录时启动Riftlet | `LoginItemPreferences`／`SMAppService`；读取系统实际状态，不默认自行注册 | **KEEP** 通用主层 | 沿用已注册状态；更新不能擅自开启；等待系统批准不能呈现为已开启 |
| 登录项重试／打开登录项设置 | 同owner，条件动作 | **KEEP** 仅失败／等待批准 | 不在正常状态显示第二排解释和按钮 |
| 窗口外观 | `app-presentation-settings.json`的`appearance`；system/light/dark，默认system | **MOVE** 外观页“窗口外观” | 继续保存用户已有light/dark；系统模式实时响应系统；不借改外观覆盖文件其他内容 |
| 外观保存重试 | 外观owner的pendingSelection／failure | **KEEP** 原控件旁 | 正常隐藏；暂时显示不能被宣称已保存 |
| 当前版本 | Bundle `CFBundleShortVersionString` | **KEEP** 通用页，与检查更新成组 | 面向用户只显示版本；构建与技术详情折叠；不能拿源码plist的development标记冒充发布包状态 |
| 检查更新 | `ApplicationUpdater`／Sparkle | **KEEP** 通用页及原四项菜单 | 两入口共用owner；保留安装由用户选择 |
| 每天检查更新 | Sparkle `automaticallyChecksForUpdates`；Info.plist默认`SUEnableAutomaticChecks=true`、间隔86400秒 | **KEEP** 一个开关 | 不新增频率选择；保持默认每天检查、自动安装关闭 |
| 从官网下载 | 更新不可用／失败时的替代动作 | **KEEP** 条件恢复 | 正常更新可用时隐藏；不与检查更新并列竞争 |
| 当前页／历史路由 | `SettingsPage`中的general/display/capture/help；motion→display、history→capture | **MERGE** 新四个顶部分组；display文案改“外观” | 旧深链继续定位正确分组和控件；无须新建配置系统 |

依据：Pages `generalContent()`；Render `renderLogin()`与`render()`；[ApplicationPresentationPreferences](../../../Sources/RiftletApp/ApplicationPresentationPreferences.swift)、[ApplicationUpdater](../../../Sources/RiftletApp/ApplicationUpdater.swift)、[Info.plist](../../../Resources/Info.plist)。

## 3. 外观页与托盘个性化

| 1.0.3控件／字段 | 当前默认／行为 | 1.0.4裁决与位置 | 迁移与不可破坏行为 |
|---|---|---|---|
| 显示桌面截图；SQLite metadata `user_hidden` | 默认false，即显示；隐藏不停止收录 | **MOVE** 从截图页移至外观主层 | 保留既有隐藏值及入口联动；关闭后仍能从设置恢复；不加第二个日常暂停开关 |
| 桌面形态；`desktopForm` | 无字段解析为microSlit；legacy edgefolio/pocket解析tray | **KEEP** 托盘／风铃／微缝 | **真正新档案**选托盘、每页3张；所有已有档案保持现有解析结果，包括缺字段的microSlit与未知raw值；不能以字段缺失判新用户 |
| 风铃排列；`windChimeArrangement` | windChime且无排列字段时aligned；其他无值回退staggered | **KEEP** 只在风铃显示 | 旧aligned不能被新默认覆盖；切换形态仍保持已选择排列 |
| 屏幕边缘；`placement`、`placementSource` | 新配置leftMiddle；旧解码缺值为legacy位置 | **KEEP** 六点位置选择，外观主层 | 旧位置直到用户明确选择才转预设；不因设置重排重写旧absolute布局 |
| 显示器；`preferredDisplayID`＋`preferredDisplayUUID` | 首次由可用主屏建立默认；已选屏幕断开临时fallback | **KEEP** 多屏或已选屏幕断开时显示；普通单屏隐藏选择器 | 以稳定身份匹配；临时fallback不写回偏好；菜单展开期间屏幕变化不误选 |
| 回到已选显示器 | 条件恢复命令 | **KEEP** 仅有恢复必要时 | 不为正常用户常驻一行 |
| 几何示意图、`layoutPreview.detail` | 高92pt；样例最多4张，材质／相机绘制与实际不完全相同 | **REPLACE** 同渲染器外观样例＋紧凑位置示意 | 不创建资产、上传或改变实际队列；AX仍提供形态／位置／数量；普通界面不重复数字汇报 |
| **新增：托盘背景透明度** | 1.0.3无该用户字段；颜色强度不等于透明度 | **ADD** 仅托盘，外观主层一个滑杆 | 只调背景材质层；图片、相机、边框、文字、按钮与命中区不随窗口alpha变淡；默认、范围及系统覆盖见设计规范 |
| **新增：相机实体颜色** | 1.0.3无独立用户颜色字段 | **ADD** 仅托盘，外观主层颜色选择 | 只改变相机主体材质；保留镜头、轮廓、体积、阴影和交互态；不是背景区域染色；不能迁移trayTintHue来冒充新字段 |
| 每页截图上限；`visibleCountPreference` | 默认3；托盘有效最大4，其他按屏幕容量且最多10 | **ADVANCED** “更多”中的紧凑数量选择 | 保留用户控制；托盘只给实际1–4；旧盘上大于实际容量的值不自动改写，当前有效值如实显示 |
| 出现动效；`arrival-motion-settings.json`的`mode` | none/magnet；无值有效fallback none，未选与显式none不同 | **ADVANCED** “更多”，只保留无／磁力吸引 | 缺省有效为无；保留旧显式选择；Reduce Motion只覆盖effective值，不改原偏好；不让用户配置毫秒 |
| 托盘材质；`trayTheme` | system/violetGlass/custom，默认system | **LEGACY** 移出普通设置；已有非默认才出现“旧版自定义” | 保留violetGlass/custom及未知raw；不要强制变为系统主题，不把旧整盘色套给新相机实体 |
| 玻璃色调；`trayTintHue` | custom默认255°，范围0–360 | **LEGACY** 仅旧非默认／custom相关配置 | 保留精确值；普通用户不见degree数值；改新颜色不连带修改此字段 |
| 色彩强度；`trayTintStrength` | custom默认0.65，界面显示65% | **LEGACY** 同上 | 不视为opacity；不量化丢失旧值 |
| 缩略图遮挡；`trayOcclusion` | 默认0，范围0–0.9 | **LEGACY** 普通层移除数值；旧非默认可查看、调整／恢复 | 新默认0；已有非零不静默清零；保持缩略图和点击区域对应 |
| 藏入边缘；`hiddenFraction` | 微缝默认0.25 | **LEGACY** 仅有旧自定义时提供 | 仍只对微缝生效；藏入比例不影响托盘透明度 |
| 边缘内缩；`outerInset` | 新构造6pt；旧文件缺字段解码14pt | **LEGACY** 同上 | 保留新旧缺省差异；不得把解码默认统一成6导致升级位置改变 |
| 连线距边；`windChimeLineInset` | 风铃默认18pt | **LEGACY** 只对风铃旧非默认 | 不在普通设置增加细节参数 |
| 恢复本形态默认数值 | Model `restoreVisibleDefaults`同时涉及共享字段 | **REPLACE** “恢复旧版自定义”且列明将恢复字段 | 用户明确触发才写；shared count/outerInset不能宣称只改变一个独立形态；不重置形态、屏幕、位置、归档、动效或截图资料 |
| 布局无法读取恢复 | `RecoverablePreferences.layout`问题域 | **KEEP** 条件恢复 | 先保留原始字节；只修该域；数据库不能作为外观重置对象 |

依据：Pages `displayContent()`、`captureContent()`；Render `renderDisplay()`、`countCapacity()`；Config 99–306；[ArrivalMotionPreferences](../../../Sources/RiftletApp/ArrivalMotionPreferences.swift)、[QueueStore](../../../Sources/RiftletCore/QueueStore.swift)。新增字段与范围统一由[设计规范](DESIGN_SPEC.md)定义，接入既有配置owner，不另用UserDefaults绕过确认语义。

## 4. 截图、归档与本机存储

| 1.0.3控件／事实 | 当前字段／行为 | 1.0.4裁决 | 迁移与完成要求 |
|---|---|---|---|
| 截图文件夹完整路径 | 系统实际截图位置，`ScreenshotFolderAccess`保存对应bookmark | **SIMPLIFY** 正常只目录末级名称与小型打开／显示位置动作 | 完整路径按需展开／显示；授权仍只针对系统实际位置，不能伪称改变macOS保存目录 |
| 在Finder中打开 | 当前source URL | **MERGE** 路径行附属操作 | 路径不可用时不给死按钮；不扩大为常驻主按钮 |
| 允许访问截图文件夹 | 显式folder picker，校验同一实际截图目录 | **KEEP** 仅未授权或失效时 | 授权完成自动刷新事实；已有有效bookmark不重复要求 |
| 重新检查截图文件夹 | 只在状态异常或未确认时需要 | **KEEP** 对应问题的下一步 | 正常页面隐藏；不同时堆授权／重试／扫描多个近义按钮 |
| 继续收录截图 | SQLite metadata `capture_paused`；默认false | **KEEP** 仅旧暂停偏好用户的恢复动作 | 不新增日常暂停选择；收录与桌面隐藏仍是不同事实 |
| 显示内置截图入口 | `capture-entry-settings.json`的`builtInScreenshotEnabled`；默认true，兼容旧`isEnabled` | **KEEP** 截图主层 | 保留已有false；旧字段canonical优先级不改；启用入口不等于已经取得屏幕录制权限 |
| 默认截图方式 | 同文件`defaultMode`，默认window，另region/fullScreen | **KEEP** 入口开启时显示 | 不自动改为最近用过模式；设置关闭不删除原选择 |
| 常用键1、2、3 | `trayFavorite1`／`trayFavorite2`／`trayFavorite3`；缺值automatic、null为空、mode三种、未知raw保留 | **ADVANCED** 托盘且入口启用时显示“自定义常用键” | 保留每槽自动／留空／模式及次序；保留主默认键位置和原自动映射；其他形态隐藏但不清值 |
| 屏幕录制状态／设置 | `CGPreflightScreenCaptureAccess`事实，仅内置截图需要 | **KEEP** 功能相关且未授予时提示 | 系统截图收录不要求该权限；只使用系统截图的首用不被阻断 |
| 闲置后归档 | `lifecycle-settings.json`的`archiveAfterSeconds`，默认120秒 | **KEEP** 截图页“闲置后从桌面收起”；1／2／5／10分钟／关闭 | 保留默认2分钟及已有关闭；交互中不归档；归档不删除原图或副本 |
| 自定义归档时间输入 | 旧版允许1–10分钟小数 | **CONDITIONAL** 仅已有合法非预设值显示精确当前自定义项 | 初次普通界面不提供自由数字编辑；旧3.5分钟仍显示并保持3.5，不能默改2或5；用户明确选新预设才替换 |
| 恢复损坏归档设置 | `RecoverablePreferences.archive` | **KEEP** 仅读取失败时 | 自动归档先暂停；保存原坏文件，再恢复归档域；不改变布局／历史 |
| 检查用量按钮＋未检查文本 | `SetupSnapshot.storage`的测量状态 | **AUTOMATE** 折叠“本机存储”首次展开时后台按需测量、缓存 | 显示Riftlet本机副本总用量；计算中／失败如实呈现，不假设0；普通设置刷新不能全库hash |
| 存储细节段落 | 原文含文件逻辑大小、captures/media字节、不可回收说明 | **MERGE** 简短主值＋展开细节 | 只读已占用空间，不冒称可释放空间；“归档不会删除图片”最多说明一次 |
| 重新检查本地截图副本 | 现有`.recheck`，按原UUID和内容验证 | **MOVE** 帮助的诊断或缺文件恢复上下文 | 只在显式动作后运行；不清UNKNOWN、不自动附加；不当作“清理” |
| 仓库视图：列表／网格 | UserDefaults `historyDisplayStyle`；默认`.current`（列表），PR #103已共享owner | **REMOVE** 设置中重复选择；仓库工具栏保留 | `HistoryDisplayPreferences`及旧值继续；删控件不能把网格用户重置列表 |
| 打开截图仓库 | `.openHistory` | **KEEP** 截图页一处入口，原菜单入口保留 | 不再另设“仓库设置”区块重复选择；打开不改变筛选／视图／归档规则 |
| 待核实数量与说明 | 真实未确定附件结果的只读投影 | **CONTEXTUAL** 截图仓库及确有问题的帮助提示 | 正常START不归入待核实；不能为了少提示把旧UNKNOWN改为成功或允许重传 |

依据：Pages `captureContent()`、`archiveSettings()`；Render `render()`、`refreshDraftPresentation()`；[ScreenshotEntryPreferences](../../../Sources/RiftletApp/ScreenshotEntryPreferences.swift)、[LifecycleSettings](../../../Sources/RiftletApp/LifecycleSettings.swift)、[HistoryDisplayPreferences](../../../Sources/RiftletApp/HistoryDisplayPreferences.swift)。**本版不实现永久删除、自动清理或保留期限迁移。**

## 5. 帮助、权限与首用的全部入口

| 现有项目 | 1.0.4裁决 | 不可混淆的事实／兼容要求 |
|---|---|---|
| Chrome连接状态、自动化状态、JS菜单步骤、附件状态四段文案 | **MERGE** 一个简短连接状态＋当前需要的下一动作 | “已连接Chrome”不是“已附加到ChatGPT”；问题变化立即重新投影，不保留过时成功提示 |
| 检查Chrome权限 | **KEEP** 状态要求时作为唯一主操作 | 仍需用户显式授权；不在正常打开设置时触发TCC弹窗 |
| 检查Chrome连接 | **KEEP** 已授权后的连接验证；状态相关地替换权限按钮 | 只读探测不创建附件；未运行／失败／JS关闭不能显示已连接 |
| Chrome不运行／未安装／被拒／JS未开 | **CONTEXTUAL** 对应单一步骤，细节按需展开 | 保留本机收录和仓库；不为未使用能力强迫多次权限决定 |
| 重新查看引导 | **KEEP** 帮助页 | 查看不重置首用完成，不修改权限或资产；能继续未完成步骤 |
| 反馈与建议 | **KEEP** 帮助页，短入口 | 现有私有反馈owner；诊断默认关闭；不新建账号或公开奖励／上传机制 |
| 诊断摘要、显示数据目录 | **ADVANCED** 默认折叠 | 展开才呈现技术状态和目录；不把数据库、journal、operation等术语放普通页面 |
| 首用“截图文件夹→Chrome→位置”第三步 | **REMOVE** 必经位置页，位置由默认值工作 | 保留可选“调整位置”；不要求用户在第一次成功前决定偏好 |
| “稍后设置” | **KEEP** 明确延期 | 继续沿用`FirstUsePreferences`持久延期；不把延期当已授权 |
| 用户点红色关闭／原生关闭窗口 | **FIX** 与主动延期同义 | 源码1.0.3仅显式Later调用onDefer；started状态重启还会再弹。补用户关闭路径；程序teardown、成功完成和退出不能误记延期 |
| “先使用本机截图” | **ADD** 首用次要路径 | 本地就绪即可使用；不写Chrome权限成功，不伪造实际附件成功；之后可在帮助中继续连接 |
| 首次截图／预览／附加／找回 | **SIMPLIFY** 在真实完成上下文给一次简短指导 | 不强制快捷键，不自动上传样例，不自动发送，不用勾选“我已完成”代替事实 |
| 布局延后应用说明 | 当前操作结束后才安全应用新布局 | **KEEP** 仅确有延后时 | 设置预览不抢浏览器目标，实际托盘变更不得破坏已经冻结的click-time操作 |
| 每个domain的验证／写入错误与重试 | **KEEP** 相应控件旁 | 继续保留actual/attempted区分、原有IME与关闭保护；不新增常驻诊断仪表盘 |

首用展示记录保持 `Riftlet.firstUse.presented.v1.<mode>` 和 `Riftlet.firstUse.setup.v2.<mode>` 兼容；截图bookmark保持 `Riftlet.sourceAccess.v1.<mode>`。如增加“本机使用”展示状态，必须有明确旧状态解码和回退，不更名清空旧记录。

## 6. 已隐藏字段与工程参数：保留兼容，禁止重新暴露

下列不是1.0.3普通设置仍存在的控件。UI减法后仍需原样解析和保存；无用户动作不得重写。凡不属于真正旧非默认几何，继续保持内部实现参数。

| 字段 | 当前构造默认 | 1.0.4处理 |
|---|---:|---|
| `fitWidth`／`fitHeight` | 72／56pt | 保留微缝／风铃旧几何，不把此数值生搬到托盘缩略图；旧自定义路径可恢复，普通页不显示 |
| `rowPitch` | 60pt | 保留；不能用全局新间距覆盖历史非默认 |
| `lineWidth`／`lineExtension` | 0.5／8pt | 内部，按实际backing scale绘制；无新增边框数值设置 |
| `emptyTraceLength` | 24pt | 保留旧解码；不重新启用已退出的空队列线条 |
| `firstCenterFromTop` | 202pt | 仅`placement=nil`旧位置适用；选择六点位置才退出其有效性，原值仍保留 |
| `screenPadding` | 12pt | 内部屏幕适配，不公开 |
| `numberFontSize`／`numberGap`／`leftPadding` | 11／8／4pt | 兼容已有；普通页不提供编号排版编辑 |
| `minimumHitWidth`／`minimumHitHeight` | 44／44pt | 内部可访问性命中区，不允许通过透明度把命中区域变淡或缩小 |
| `arrivalDuration` | 0.220秒 | 内部；不新增第三种出现效果 |
| `pressDuration`／`inwardDistance` | 0.060秒／1.5pt | 内部；实际按压与状态反馈不能删除 |
| `swallowDuration`／`shiftDuration`／`returnDuration` | 0.120／0.160／0.180秒 | 内部；动画不决定START证据与恢复权限 |
| `reducedMotionDuration` | 0.080秒 | 系统辅助功能覆盖有效动画，不写用户偏好 |
| 未识别JSON字段、未知主题／形态／常用键raw | 无统一缺省 | 保存原内容；只补丁写本次明确变化键，不能全文件重编码清掉未来字段 |
| 用户hidden／旧paused／其他metadata | 数据库既有值 | 不合并成一个泛化“启用Riftlet”开关，不重建数据库 |
| macOS自动化、屏幕录制、登录项状态 | 系统事实 | 不能以持久化布尔值冒充权限；不增加独立“已授权”选择 |
| Sparkle feed、签名公钥、升级identity | 已发布配置 | 不是消费者设置；本轮文档及开发不修改正式稳定更新源 |

## 7. 迁移与逐项关闭标准

1. **新档案与旧档案分开识别。** 新档案采用tray、左中、3张、2分钟闲置收起；旧配置保留当前形态、位置、屏幕、旧缺字段的解码行为。即使旧档案没有布局文件但存在截图库／其他偏好，也不能当成全新用户强制套默认。
2. **读取不触发重写。** 打开设置、改变系统外观、展开诊断、切换页面不写JSON或SQLite。用户修改一项只改变其字段。`RecoverablePreferences.write()`现有原字节比较、未知键保留和原子写入机制继续使用。
3. **外观迁移不触及业务数据。** 1.0.3→1.0.4对原图、私有媒体、六张核心表、UUID、START／UNKNOWN、bookmark、反馈草稿和凭据做同根升级比对；新外观坏值不得导致截图库重建。
4. **每项功能与失败都验。** 显式更改、重启、写失败、重试、活动文本编辑、中文IME、正在附加、屏幕断连分别检查。失败后保留有效值与用户意图；不能因重构丢掉旧关闭／保存保护。
5. **旧自定义有明确恢复范围。** 首次显示与旧版相同；只有用户明确恢复才变默认；说明哪些共享字段将变，不声称“仅本形态”却改动共享值。修改新相机实体色与透明度不改旧整盘tint。
6. **原生界面是关闭依据。** 所有四页在640×560与600×460、中英、浅深色、1×／2×、减少透明度／动态／高对比度和VoiceOver下检查；控件保持自然bezel与焦点，重要文本不裁切。涉及跨屏的样本须标真实硬件／虚拟显示器类别。
7. **移除控件不移除操作能力。** 仓库内仍可切换列表／网格；关闭桌面显示可恢复；常用键可调整；归档可关闭；已有自定义值可原样保持；Chrome未配完仍可使用本地截图；重要动作无需快捷键。

关联既有问题：设置后续精修[#88](https://github.com/haohongfei2001-png/Riftlet/issues/88)、首用关闭路径[#86](https://github.com/haohongfei2001-png/Riftlet/issues/86)、原生视觉与辅助功能[#92](https://github.com/haohongfei2001-png/Riftlet/issues/92)、只读存储[#95](https://github.com/haohongfei2001-png/Riftlet/issues/95)、中英文[#96](https://github.com/haohongfei2001-png/Riftlet/issues/96)、安装升级[#97](https://github.com/haohongfei2001-png/Riftlet/issues/97)。新个性化能力按实现计划关联新任务；不把交付本台账当成任何产品问题已关闭。
