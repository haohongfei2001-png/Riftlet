# 设置中心与控制中心｜AppKit 实施交接

2026-11-06｜设计交接，不是原生功能完成声明。

本交接以正式源码 `b61fc46cf931bdbd14deec1b47d077e92db61e16` 为实现基线，读取设计工作树 `e1a7286d7eb14ff47686804718f61a2515a8fd12` 中的实际源码、六页原型与交互文档。该工作树的 `Sources/`、`Tests/` 相对上述 main 无差异。本文件只规定后续实施接线，不改源码、生产配置、安装包或历史记录；本次没有执行新原生界面验收。

## 1. 交付依据与不再重做的决定

先读 [CONTROL-CENTER-DECISION](CONTROL-CENTER-DECISION.md)、[INTERACTION-SPEC](INTERACTION-SPEC.md)、[MENU-ACTION-MAP](MENU-ACTION-MAP.md)、[CONFIGURATION-MAP](CONFIGURATION-MAP.md) 和 [TOKENS](TOKENS.json)。HTML 是视觉和合成交互参考；实际能力、字段效果和错误语义以源码审计及这些规范为准。本文件第 10 节列出的 HTML 差异不可照搬成原生行为。

- 菜单栏左键/键盘使用一个紧凑 `NSPopover`；右键/Control-click 使用同一命令源生成的 `NSMenu`；完整设置使用既有 AppKit 生命周期中的独立 `NSWindow`。不改成新的 SwiftUI App。
- 设置六页固定为：通用、位置与显示、截图、动效、历史与存储、权限与帮助。历史与反馈继续打开各自已有窗口。
- 暂停系统截图收录、隐藏裂缝、关闭内置截图入口是三个不同命令。保存故障、源不可用、队列为空也不是这三个用户意图。
- 显示与动效数字参数共用一个配置草稿和一个“应用更改”；切页不提交、不丢草稿。允许一次应用两个页面的配置改动。“恢复本页”严格限制字段集合，不等于重置整个配置。
- 几何草稿与即时控制、归档、首次使用标记、反馈草稿是不同领域。某域应用成功不清除另一域的错误，也不顺带提交另一域数据。
- 不增加截图管理器、磁盘清理计划、聊天选择器、上传/发送动作、旧结果重试、自动测试上传、额外截图快捷键或新入缝模式。

`CONTROL-CENTER-DECISION` 中“写入失败保留原状态”应按 `INTERACTION-SPEC` 3.1 的具体方向解释：暂停、隐藏、关闭入口会先停止当前运行；这三个停止方向的失败不能回滚成仍在运行。第 5 节给出准确矩阵。

## 2. 从哪些现有类接线

所有路径均相对仓库根目录。下表的“新增”是实施所需的小范围 UI/状态结构，不是当前已经存在的 API。

| 所有者/现有位置 | 继续复用 | 本次原生实施改动 |
| --- | --- | --- |
| `Sources/RiftletApp/RiftletMain.swift`：`installMenu`、`installSetup`、`updateSetup`、`updateControlTitles` | 主进程状态、模式边界、命令、异步门禁和持久化所有权 | 接一个同源的控制中心投影；将六页路由接回原 selector；提供必要的结果/进行中状态，不让 View 自己写文件 |
| `Sources/RiftletUI/SetupPresentation.swift`：`SetupSnapshot`、`SetupPresentation` | 来源、收录、隐藏、权限、存储、问题与支持信息的解释 | 普通四态投影只取真实事实；需要处理的能力和每域错误单独保留；不得从标题反解业务状态 |
| `Sources/RiftletUI/RiftSetupController.swift` | 单例设置窗口、首次使用容器、显式打开边界、注入回调 | 五页改六页；保留页/尺寸；增加未保存关闭 sheet；页面控件与草稿持久到窗口会话，后台更新不重建编辑器 |
| `Sources/RiftletUI/RiftSettingsForm.swift`：`RiftSettingsSnapshot`、`RiftSettingsChange` | 既有偏好值、屏幕信息、`onSettingsChange` 调用边界 | 将现有立即写入数字滑块改为草稿；扩展有效数字字段提交，而非串行调用多次三字段 `.geometry`；单次配置提交产生一个完整候选 |
| `Sources/RiftletUI/RiftConfiguration.swift`；App 的 `persistRiftConfiguration` | 27 字段 Codable、严格校验、原子写入、`requestedConfiguration` | 只 patch 用户编辑的有效配置字段，兼容字段与身份元数据逐值保留；不改解码缺省值以实现视觉推荐 |
| `Sources/RiftletApp/CaptureControlGate.swift` | 重新检查与暂停/恢复串行，owner token 结束规则 | Popover、设置、右键菜单共享同一门禁，不另开可交错任务 |
| `Sources/RiftletApp/ScreenshotEntryHost.swift`、`ScreenshotEntryPreferences.swift` | 入口启停、会话取消、默认方式、持久化失败事实 | UI 读取真实 `isEnabled`、`defaultMode`、`preferenceSaveFailed`；不模拟系统录屏授权或正在截图 |
| `Sources/RiftletApp/ArrivalMotionPreferences.swift`；UI 的 `ArrivalMotionMode`、`ArrivalPreviewView` | 两种入缝模式、独立保存、系统减少动态的有效模式 | 预览仅由明确播放按钮启动；停止切页/关窗预览；不把无入缝动效解释为关闭上传开始后的吞噬 |
| `Sources/RiftletUI/RiftPanelController.swift`、`RiftDisplaySelection.swift` | 显示器身份、会话回退、延迟应用配置、正在交互保护 | 使用既有 `restorePreferredDisplay`、`displayRestoreAvailable`；设置只请求变更，不强行重建输入窗口 |
| `Sources/RiftletApp/LifecycleSettings.swift`、`checkStorage` | 独立归档设置与按需存储检查 | 自定义小时数保留单独草稿/保存按钮；准确投影未检查、检查中、完整/部分统计、失败 |
| `Sources/RiftletUI/RiftHistoryController.swift` | 分页、当前页搜索、状态筛选、原图预览、状态限制 | 从设置/控制中心打开既有窗口；不复制为第二份历史数据库或新增无证据的恢复能力 |
| `Sources/RiftletApp/FirstUsePreferences.swift`、`ScreenshotFolderAccess` | 已呈现标记、当前截图来源匹配、security-scoped bookmark | 只调整三步内容与现有动作去向；旧标记不改义、不重跑升级引导 |
| `Sources/RiftletApp/FeedbackHost.swift` 与 Feedback 模块 | 独立草稿、诊断选择、发送/取消/删除状态 | 仅打开原窗口，不复制网络发送；诊断选择属于当前反馈草稿，不能升格为全局默认同意 |
| `Sources/RiftletUI/RiftVisualStyle.swift` | 系统字体、动态颜色、原生按钮、可达窗口框、顶对齐滚动区 | 映射本目录 token 到设置辅助表面；不改边缘裂缝/微图形态，不把新字号全局改到历史/截图面板 |

`installSetup` 已注入 `onRecheck`、`onOpenSource`、`onPermission`、`onChooseSourceAccess`、`onToggleHidden`、`onToggleCollection`、`onOpenHistory`、`onOpenFeedback`、`onSettingsChange`。继续由 App Host 注入；View 不直接取得 Chrome、队列数据库或原始截图能力。`onDismiss` 当前没有业务操作，不能借关闭设置恢复收录、解除隐藏或申请权限。

## 3. 一个状态源与同一套命令

### 状态快照

在 MainActor 上从同一轮 host 状态合成控制中心/设置/菜单所需快照，附单调 revision。现有 `SetupSnapshot` 和 `RiftSettingsSnapshot` 可作为两个子投影，不复制它们的持久化真值。异步回调必须验证所属命令/会话；旧结果不得覆盖新 revision。

至少保留以下不同事实：

1. 用户当前有效意图：收录是否暂停、裂缝是否隐藏、内置入口是否启用。
2. 实际运行：收录 watcher 是否运行、来源可访问否、内置截图会话是否存在、临时落在哪个屏幕。
3. 保存结果：域级 pending/成功/失败；已知已保存意图或“持久化结果未确认”，不得用内存值伪造磁盘值。
4. 能力与系统状态：应用模式、初始化、权限检查结果、Chrome 脚本设置说明、系统可访问性有效值。
5. 展示数据：可见/待核实计数、存储统计；零张和未统计各有独立表示。

只有提交中的相关命令不可重复；隐藏、历史等不受收录门禁控制的动作不跟着全页禁用。设置刷新只更新非编辑的派生控件；不显示/激活窗口，不移动光标，不开预览，不触发保存。

### 四个主视觉状态

| 投影优先级 | 显示条件与文案 | 不可产生的副作用 |
| --- | --- | --- |
| 1 需要处理 | 持久、可操作故障；主文案写具体来源/权限/保存问题，只提供相关处理入口 | 不把所有能力都置灰；不更改三个独立意图 |
| 2 暂停 | 用户意图为暂停；“已暂停收录”，已有图保留；若也隐藏，副文案同时说明 | 不隐式显示裂缝或关闭内置入口 |
| 3 仅隐藏 | 未暂停且用户隐藏；“裂缝已隐藏，仍在收录新的截图” | 不宣称来源实际运行成功；有来源故障时走第 1 项 |
| 4 正常 | 无上述情况；“正在收录截图”仅在实际运行时成立 | 启动/检查中另用短暂进度，不谎报已开始 |

没有可用 ChatGPT 输入区是点击时的使用情境，不是持续红色故障。空队列不显示裂缝，但不是 `userHidden=true`。恢复收录写入成功而 watcher 启动失败是“未暂停、来源不可用”，不是“已暂停”。

隐藏开关的辅助说明固定为“只隐藏边缘微图，不改变收录设置”，通用页与控制中心一致；不要照搬原型“收录继续进行”到暂停+隐藏状态。实际是否收录只由上述真实主状态说明。该文案冲突由独立视觉检查C5发现，未追改82项自动化结果。

### 命令路由

实现时用一个命令集合承接 [MENU-ACTION-MAP](MENU-ACTION-MAP.md)。保留 `showSetup`、`showHistory`、`showFeedback`、`beginScreenshot`、`showLatest`、`showOldest`、`clearVisible`、`recheckSetup`、`checkStorage`、`reload`、`openGeometry`、`quit` 的 host 语义。路由变更只有 `showArrivalSettings → 动效`、`configureArchive → 历史与存储` 以及旧五页到六页的对应。

暂停/隐藏开关与失败重试应携带明确的目标布尔值，仍复用现有 host 的停用顺序和门禁。当前 selector 以 `!effectiveValue` 计算目标，不能在“暂停已生效但未保存”时盲目重调 toggle 来“重试保存”，否则会变成恢复。为新 UI 的重试补目标值入口属于接线要求；失败记录必须保留该次目标值，不做自动循环重试。

## 4. 六页逐项接线

| 页面 | 真实数据与命令 | 提交/显示规则 |
| --- | --- | --- |
| 通用 | `SetupSnapshot.collection/isHidden`、暂停/隐藏命令；使用引导、Feedback；外观三值新域、系统登录项新域及系统可访问性 | 运行开关、外观与登录项分别立即请求 host，以各自结果显示；不能参加配置草稿“应用”；新域精确实施规则见 5.5 |
| 位置与显示 | `RiftSettingsDisplay`、配置、`displayRestoreAvailable`；`.preferredDisplay`、`.placement`、`.restorePreferredDisplay` | 显示器/六位置为即时持久化选择；有效数字改动仅更新全局配置草稿和合成预览；当前桌面仍使用成功保存的请求配置 |
| 截图 | 检测到的真实系统保存位置、文件访问、`entryAvailable/entryEnabled/defaultCaptureMode`；`.entryEnabled`、`.defaultCaptureMode` | 默认方式仅影响下次会话；不改变当前模式/槽位。收录暂停不等于入口关闭；隐藏按现有 host 抑制入口；不申请与当前动作无关的权限 |
| 动效 | `arrivalMode/hasArrivalSelection`、系统减少动态；`.arrivalMode`；有效时长参数 | 入缝模式即时保存；时长属于同一配置草稿。只提供无/磁力吸引，主动预览合成图；不改变 START/完成/失败判定 |
| 历史与存储 | `archiveAfterHours`、`SetupStorageState`；打开历史、`.archiveAfterHours`、`checkStorage`、确认后 `clearVisible` | 归档独立草稿；预设也需明确保存。清空只收起可见队列；存储值来自实际测量，不显示原型 36.8 MB；不增加批量撤销/删除 |
| 权限与帮助 | 实际来源、Automation 权限、Chrome JavaScript 帮助、内置截图权限、版本/支持范围；既有检查、授权、Feedback、引导和专家入口 | Automation 与 Chrome JavaScript 两行解释；系统授权通过不证明 Chrome 脚本开关通过。版本从 bundle/实际能力声明读取；诊断默认收起 |

权限按钮只调用与文字对应的正常系统流程。`chooseSourceAccess` 接受的文件夹必须匹配系统实际截图保存位置，不把“允许访问”改成任意文件夹监视器。`recheckSetup` 保留 `CaptureControlGate`：检查不能撤销暂停；不自动产生附件输入。内置录屏授权不作为普通系统截图收录前置条件。

通用页“登录后自动打开”和应用外观覆盖是本设计包含、main 尚无后端的两个待实施新域；保留设计控件，不删项或默认隐藏。整套设计仍待最终评审，不能因原型可点击就称已原生实现。实施范围锁定为这两项，不扩成新的外观编辑器或启动任务系统。

## 5. 草稿、应用、保存失败和关闭

### 5.1 配置草稿的边界

数字草稿至少保留：打开时/最新已保存基线、每字段原始文本、已编辑字段集合、可解析候选值、校验问题。保留空串、小数点、IME marked text、合法高精度值；文本失焦不保存也不替换，背景快照不能把已编辑但失焦的值重置。`controlTextDidChange`/结束编辑仅更新草稿与局部校验，禁止重建或移除当前保存/关闭按钮。用户输入归档小时后直接首击保存必须保存；直接首击关闭必须进入草稿确认，不得要求先 Tab 或第二次点击。

全局配置草稿的可编辑集合：

- 位置与显示：`fitWidth`、`fitHeight`、`hiddenFraction`、`rowPitch`、`outerInset`、`numberFontSize`、`numberGap`、`leftPadding`、`minimumHitWidth`、`minimumHitHeight`、`visibleCountPreference`；`firstCenterFromTop` 只在 legacy 绝对布局时可编辑。
- 动效：`pressDuration`、`swallowDuration`、`shiftDuration`、`returnDuration`。
- 显示器 ID/UUID、`placement/placementSource` 不在数字草稿 patch 中；其即时选择成功后刷新基线和预览元数据，不清除用户未提交文本。
- 七个只为兼容保留的字段不进有效控件和“恢复本页”写集合：`lineWidth`、`lineExtension`、`emptyTraceLength`、`screenPadding`、`arrivalDuration`、`inwardDistance`、`reducedMotionDuration`。完整往返仍保留其值并通过现有校验。

“应用更改”与非组字 Return 提交同一个全局配置草稿，不仅保存当前页。步骤固定：

1. 解析全部已编辑配置文本；百分比除以 100，毫秒除以 1000；采用当前 locale 小数输入，整串解析，不接受 `1abc` 前缀成功。校验单位与范围见配置映射。
2. 在提交时重新取得 host 最新 `rift.requestedConfiguration`，只覆盖可编辑的 dirty keys，保留所有未修改字段及即时更新的显示器/位置/兼容字段。
3. 对完整候选执行 `RiftConfiguration.validate()`；校验失败就地标记对应字段，不写文件、不动真实边缘。
4. 复用一个 `persistRiftConfiguration` 事务：原子写入成功后再更新 rift 和入口布局；不能逐字段保存形成部分几何。延迟到交互结束的配置是“已保存，等待当前交互结束应用”，不强迫鼠标下的对象移动。
5. 只在该请求成功后清除已提交 dirty keys。失败保留全部文本与预览；重试同一候选。没有改动不重复写盘。

若用户在保存过程中继续编辑，结果只确认提交时的版本；之后输入仍为新草稿，不被旧回包清空。若即时命令改变为六点布局，legacy `firstCenterFromTop` 从可操作控件中收起，不能借随后应用旧草稿恢复 `placement=nil`；兼容字段原值保留。

“恢复本页”只改该页有效数字草稿：位置/显示器和入缝模式不随之重置，另一页已有草稿保留。恢复值用当前 main 的数值默认；本轮仅展示的 0% 新安装推荐不替换 `.25` 的正式默认，也不覆盖已有安装。真正更改新安装默认必须在对应源码增量中单列并审查，不能附带在设置 UI 中迁移所有用户。

### 5.2 不同持久化域

| 域 | 何时提交 | 不可越界 |
| --- | --- | --- |
| 配置数字草稿 | 全局“应用更改”/Return；关闭时“应用并关闭” | 不写归档、pause/hide、入口/入缝文件或权限 |
| 显示器/位置 | 用户明确选择时立即请求，合并最新配置 | 不顺便保存数字草稿，不丢 UUID，不将临时回退持久化 |
| 暂停/隐藏/入口/默认方式/入缝 | 用户明确开关/选择；只重试原请求 | 不由切页、刷新、关闭或恢复本页触发 |
| 应用外观 | 三值选择后独立原子保存，成功再应用 | 不进入配置草稿、不写系统主题、失败不清布局错误 |
| 登录启动 | 明确开关后单次系统注册/注销，以系统回读为准 | 不另存假的 enabled Bool，不创建 LaunchAgent，不随启动/刷新自动注册 |
| 归档 | 独立“保存归档设置”或归档字段 Return；关闭时应用剩余草稿 | 小数小时先校验，0 转 nil；不覆盖几何草稿；不更改图片字节 |
| Feedback | 继续由原 Feedback 窗口管理 | 诊断选择跟随当前草稿，提交后新草稿默认不带；设置“应用”无权发送 |
| 权限/首次使用 | 现有具体按钮和实际呈现边界 | 非设置草稿；不能用配置保存结果替代系统状态 |

### 5.3 必须按方向呈现的错误

| 操作 | 保存前/失败后的真实状态 | 正确提示与后续 |
| --- | --- | --- |
| 暂停收录 | 先 `binding.stop()`，当前 `captureIsPaused=true`；失败仍停止 | “本次已暂停，设置未能保存，重启后可能恢复”；现有图不丢，重试仍为暂停意图 |
| 继续收录 | 先保存 false；保存失败仍暂停；保存成功后才 start | 保存失败不显示正在收录。start 失败则 paused=false + 来源故障，可重查来源；不能说人为暂停 |
| 隐藏裂缝 | 立即取消选中/入口会话并隐藏，再写 `QueueStore`；失败仍隐藏 | “本次已隐藏，设置未能保存，重启后可能恢复”；不改收录开关 |
| 显示裂缝 | 保存 false 成功才显示；失败仍隐藏 | “未能保存，当前仍隐藏”；零张时保存成功也不画空裂缝 |
| 关闭内置入口 | 立即禁用并取消当前内置截图，再写偏好；失败仍关闭 | “本次已关闭，设置未能保存，重启后可能恢复”；系统截图收录不变 |
| 启用入口 | 成功持久化后才启用 | 保存失败不启用。保存方法先 atomic write 再 chmod，失败不能据此声称磁盘一定是旧值；只报告当前有效状态与保存失败 |
| 默认方式/入缝/显示器/位置/数字/归档 | 保存成功才接受新值，失败保留上次成功的运行配置 | 对即时控件回显真实有效值；对草稿保留编辑；不得假装全部设置一起回滚 |
| 用量检查 | 不是偏好写入；结果可能未测量、部分统计或不可读 | 失败不能显示 0 B；只重试测量，不清理文件 |

现有 `applySettings` 对入口开关/默认方式可能正常返回一个 `capturePreferencesSaveFailed=true` 的快照；不能只靠是否 throw 判成功。持久化错误归属必须与发起命令对应，A 域成功不能清掉 B 域失败。禁止为了修保存错误删除配置、重置队列或恢复所有默认。

### 5.4 关闭与切页

红色关闭按钮、⌘W 等用户关闭路径统一经 `windowShouldClose` 的草稿判断。无草稿直接关闭；有任何配置或归档草稿展示同一 sheet：默认“继续编辑”，另外“不保存”“应用并关闭”。Escape 等同继续编辑。切页没有该 sheet，保留草稿。

- 继续编辑：关 sheet、焦点回原字段，文本/选区保留。
- 不保存：只丢未提交数字/归档草稿，并清除这些被明确放弃的候选值所产生的草稿保存错误；已成功生效的即时开关、显示器、位置不回滚。仍存在的 pause/hide/入口持久化不一致、来源故障或独立磁盘错误不能被一并清除。重新打开时没有被放弃的数字草稿，也没有其残留“保存失败”。
- 应用并关闭：先校验所有剩余草稿，校验通过后依次提交完整配置、归档。每域仍是原有独立文件，没有虚构跨文件原子事务。若配置已成功而归档失败，保留已成功配置、归档草稿和窗口，不重复成功域的写入；只在所有脏域成功后关闭。

有保存错误时不能静默丢草稿。`close()` 的 owner teardown 与用户关闭必须区分；不得把系统结束/清理回调当成授权应用草稿。打开反馈/历史等已有独立窗口不提交或丢弃设置草稿；从设置切换到复用容器的首次使用时，保留设置草稿，不能用 `rebuildPage()` 丢失它。

### 5.5 已设计的新域：外观与登录启动

以下是后续原生增量的确定接线，不是对当前 main 的事实声明。二者都在通用页即时操作，独立于布局草稿、彼此错误和“恢复本页”。

**应用外观**：新增每个既有应用数据根内的 `app-presentation-settings.json`，格式为 `{ "version": 1, "appearance": "system" }`；appearance 只允许 `system`、`light`、`dark` 三值，不含其他字段。不把此字段加进 27 字段几何文件。无文件时有效选择为 `system`，不因打开设置自动创建文件；读取严格校验版本/枚举，损坏或未来版本保留原字节，使用当前安全外观（冷启动为系统）并显示本域不可读，不能自动重置。用户显式选择可以通过一次成功原子保存替换旧文件。

选择后先验证并准备所需 `NSAppearance`，原子写入成功再更新 host 选择和 `NSApp.appearance`：system=nil、light=.aqua、dark=.darkAqua。失败则回显原有效选项，保持原外观，保留同目标重试。回到 system 必须清掉此前显式覆盖，继续随系统变化；不是保持刚才的深/浅色。应用外观作用于 Riftlet 窗口、panel、popover 的继承外观，既有动态色照常解析；不改变截图像素、系统主题、系统减少动态/对比度偏好或状态栏图标的模板规则。[Apple 的 NSApplication.appearance 语义](https://developer.apple.com/documentation/AppKit/NSApplication/appearance) 支持 nil 跟随系统和显式覆盖。

**登录后自动打开**：使用 `ServiceManagement.SMAppService.mainApp`，由系统维护注册/授权，不新增本地 `launchAtLogin` 持久布尔值；不写 `~/Library/LaunchAgents`，不加 helper、守护进程或定时任务。当前工程最低 macOS 13，可直接以该系统接口为实现基线。只在普通已打包的 Riftlet 应用上提供可执行注册；隔离模拟/验收模式不注册自身，保留能力不可用说明，不能改变普通应用的登录项。

| 系统回读状态 | 通用页显示/操作 |
| --- | --- |
| `notRegistered` | 开关关，未设置自动启动；用户开启才调用一次 `register()` |
| `enabled` | 开关开，可说明已允许下次登录打开；用户关闭调用一次 `unregister()` |
| `requiresApproval` | 已有系统注册请求，开关体现该请求且副文案明确“等待在系统设置中允许”；不得显示自动启动已生效。提供“打开登录项设置…”的定向动作，用户关开关则注销该请求 |
| `notFound`/无法确认 | 不伪造开或关的成功结果；显示此能力暂不可用、原因/重新检查，其他设置正常使用 |

按钮发起时仅该命令显示进行中。register/unregister 正常返回后仍重新读取 `status`，只有实际终态才报告结果；throw 时也回读并显示系统实际状态与本次错误，不能无条件回滚为旧 UI 值。`requiresApproval` 是待用户在系统设置允许，不是保存成功、也不是普通注册失败；打开系统设置只由该明确按钮调用 `openSystemSettingsLoginItems()`。设置页进入/应用重新激活时只刷新状态；系统撤销许可不会触发自动重新注册。同一目标已满足则不重复调用；注销主应用登录项不退出正在运行的 Riftlet。[Apple 的 SMAppService 状态与接口](https://developer.apple.com/documentation/servicemanagement/smappservice?language=objc%2Cobjc)、[enabled 的可运行含义](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum/enabled)、[主应用注销行为](https://developer.apple.com/documentation/servicemanagement/smappservice/unregister%28%29) 为接口依据。

实现为 host 可替换的外观持久化和登录服务适配器，便于注入失败测试；UI 不自行调用系统注册。真实登录启动验证必须针对正式打包身份单独记录，mock 返回 enabled 不能算完成系统登录验收。

## 6. 数据、默认值和迁移

精确字段、范围、读写消费者以 [CONFIGURATION-MAP](CONFIGURATION-MAP.md) 为单一清单。本节固定易错迁移规则：

| 数据 | 当前真实行为 | 后续界面必须保留 |
| --- | --- | --- |
| `rift-configuration.json` | 新建：左中、3 张、遮挡 .25、距边 6、Fit 72×56；旧 JSON 缺 `outerInset` 回退 14，缺 `placement` 为 nil/legacy | 新推荐 0% 只是设计候选；不在打开设置时写默认。27 个已知字段往返保留，缺省解码不要换成新对象默认 |
| 绝对旧位置 | nil placement 保留旧右侧绝对布局，`firstCenterFromTop` 有效 | 只有用户明确六点选择才迁移；仅改数字不迁移 placement/source |
| 入缝偏好文件 | 不存在表示未选择；显示有效回退 none。损坏/未来版本为 unreadable，保留原字节 | 不把显示 none 当作用户已选；只在明确且成功的选择时保存；不因启动补写默认 |
| `capture-entry-settings.json` | version 1；默认窗口/入口开；canonical `builtInScreenshotEnabled` 优先于旧 `isEnabled`，存在但 null/类型错必须失败 | 不因读错悄悄打开。仅两个 key 都不存在的旧 v1 才按既有规则 enabled=true；编码继续 canonical |
| `lifecycle-settings.json` | 新建 `LifecycleSettings()` 为 24 小时；合成 Optional 解码中缺 key/null 是 nil，即关闭 | 不把读取到的 nil 改为 24 小时；自定义小时精度保留，校验 seconds 换算有限；归档不是删除 |
| QueueStore 可见/收录元数据 | `user_hidden`、`capture_paused` 使用既有存储路径/隔离模式 | 不迁出到另一套 UI UserDefaults；保持当前安装的数据根、历史和并发所有权 |
| 首次使用/文件夹访问 | `Riftlet.firstUse.presented.v1.<mode>`、`Riftlet.sourceAccess.v1.<mode>` | presented 不是 completed/授权。旧 true 保留不重跑；bookmark 只用于匹配的真实来源，不扩成任意目录 |

恢复本页不碰模式隔离、数据库 schema、附件操作、历史可见性或 Feedback。错误/未来版本不能用“重新生成设置文件”掩盖；显示能用的能力，保留原数据与准确错误。

## 7. 显示器、深色与原生组件

### 多显示器

`preferredDisplayUUID/ID` 是用户长期偏好；实际窗口屏幕由 `RiftDisplaySessionSelection` 决定。UUID 唯一匹配优先；UUID 歧义不能用临时 ID 猜。拔屏后临时回退不写偏好；原屏回来时可留在 fallback，只有 `displayRestoreAvailable` 为真才出现“回到已选显示器”。恢复时沿用 held/selection/transition 保护，不能直接越过控制器 guard。

“使用主显示器”在 main 的 `.preferredDisplay(nil)` 会在点击当时解析主屏并保存具体 ID/UUID，不是永久跟随主屏；原生文案/状态必须按该语义。每次应用用实时 `NSScreen.visibleFrame`、backing scale，考虑菜单栏/Dock/旋转/Retina；预览比例只是示意。窗口尺寸恢复沿用 `RiftVisualStyle.reachableWindowFrame`，保证标题可达，不把过时屏幕坐标当偏好。

### 组件映射

| 设计元素 | AppKit 组件/实现约束 |
| --- | --- |
| 状态栏入口 | 现有 `NSStatusItem` 的模板图标；可访问名称 Riftlet、value 为当前短状态；不常驻技术长标题 |
| 控制中心 | 一个 `NSPopover` + `NSViewController`、`.transient` 为基础；336 pt 内容宽，17 pt 内边，13 pt 圆角参考；高度随两行错误说明调整 |
| 右键菜单 | `NSMenu`，直接使用命令集合的 title/enabled/action；不制作第二套状态；键盘与 Control-click 真机验证 |
| 设置框架 | 现有 `NSWindow`/控制器；目标 960×684 pt，184 pt 侧栏、53 pt 页脚；内容 27/31 pt 留白；不足空间时滚动，不压扁表单 |
| 六页侧栏与内容 | `RiftSidebarButton`/原生按钮 + `NSStackView`/顶部对齐 `NSScrollView`；选择态和焦点分开；后台状态刷新不 remove/rebuild 当前 field editor |
| 开关/选择 | 有明确 AX name/value 的原生 `NSButton` 开关、`NSPopUpButton`、两项单选；正反文案与真实可用状态一致 |
| 数字/滑块 | `NSTextField` 保留文本草稿；滑块只修改草稿，不写盘；数字字体使用等宽数字。小范围滑块不夹断精确输入的合法大值 |
| 六点与预览 | 原生可访问按钮组；合成绘制视图，无真实截图读写。显示未应用状态，0%/90%、1–10 张与左右锚点均可理解 |
| 错误/关闭确认 | 就地文本+图标；一个附属 sheet，默认继续编辑；错误不只靠颜色，sheet 内焦点与 Escape 完整 |
| 历史/Feedback | 既有控制器窗口，不在 Popover 叠窗口；打开前关 Popover，不销毁设置草稿 |

颜色取 `TOKENS.json` 的语义角色并映射动态 `NSColor`，字体用系统字体/本地化回退；标题 22/29、正文 13/19、行标题 12/18、次级 11/17 为目标。HTML 的 CSS pixel、阴影和浏览器圆角不等于原生材质验收。暗色切换时更新 layer/绘制颜色，避免缓存旧 CGColor；系统提高对比度、减少透明度和减少动态变化需立即重投影。系统减少动态覆盖装饰位移，但保留点击/开始/结果事件。

`minimumHitWidth/Height` 当前只参与行布局最小尺寸/容量计算，真实鼠标区域是图片与编号两个 island；不能写成“保证整块 44×44 可点击”。`pressDuration` 参与按下保护和回位调度，也不是全部装饰动画唯一时长。不要借设置实现修改已经验证的截图命中模型。

Popover 再次激活关闭；暂停/隐藏后保持打开显示结果；打开设置、历史、Feedback 或系统权限面板前关闭。普通关闭不回滚成功开关。`.transient` 对菜单和某些 panel 有平台例外，必须验收，不用主动激活/恢复 Chrome 来掩盖；控制中心不参与附件目标或 relay 生命周期。

## 8. 三步引导接线

1. **认识**：使用合成示意说明系统截图→边缘微图→点击→当前聊天附件。能力说明来自真实应用模式，演示不能写上传成功记录；“稍后设置”直接结束本次引导。
2. **连接**：分别显示当前截图保存位置访问、Chrome Automation、Chrome JavaScript 设置说明；点击相应按钮才走原请求。已授权不重复申请；缺少某项可继续。内置截图屏幕权限按需解释/请求，不作系统截图的前置门槛。
3. **摆放/开始**：复用实际屏幕列表与六点即时选择，同一 host 保存结果；合成三图预览。开始只完成本次引导并关闭，不截图、不附加、不发送、不恢复暂停或显示隐藏裂缝；缺少权限则准确提示可去帮助继续。

保留现有 `FirstUsePreferences.recordPresentation()` 的实际显示时点，旧 presented=true 禁止因升级重新弹出。原型 `onboardingCompleted` 是内存演示状态，不写回旧键、不假称用户已完成权限。当前基线不新增持久化“完成/步骤”域：本窗口会话可保留步骤，手动从帮助重新打开仍可走三步；需要连接的真实条件由权限快照表达。引导与设置不各存权限布尔值。

## 9. 实施顺序与完成条件

1. **冻结语义与状态接口**：先从 host 投影 revision、每域 pending/error、实际有效值和命令目标值；维持原门禁与模式。补可控失败场景测试，再接新 UI。
2. **草稿与持久化接线**：实现共享配置草稿、dirty-key 合并、完整单次校验/写入、独立归档草稿、关闭 sheet。先保证输入/失败/即时选择不会互相覆盖，再替换五页导航。
3. **六页 AppKit 外壳**：按原型层级和 token 复用组件，保留既有历史/Feedback/专家入口；兼容死字段只在说明中记录。停止原 `selectArrivalMode` 的自动播放，仅保留主动预览。
4. **控制中心与右键菜单**：复用 `NSStatusItem`，同一命令表、四态投影、关闭规则；保留前台 ⌘,、⌘Q 和现有编辑菜单 responder 路由。
5. **三步引导与迁移**：保持 first-use 旧键和数据根，不将视觉推荐写成升级迁移；处理真实屏幕身份和 fallback。
6. **新偏好接线**：按 5.5 实现外观独立文件与系统登录服务适配器，保留真实状态和结果层次，不把系统注册当作普通布尔文件保存。
7. **验证并交付**：针对受改状态/持久化加回归，做下节原生验收；记录实际源码 SHA、运行方式和失败。只有后续正式源码审查、合适的 CI/包验证和原生检查完成后，才可称该界面实施完成；设计 HTML 通过不代替其中任何一项。

现有测试起点：`Tests/RiftletUITests/RiftSetupControllerTests.swift`、`RiftLayoutTests.swift`、`RiftLifecycleTests.swift`、`ArrivalModesTests.swift`，以及 `Tests/RiftletAppTests/FirstUseTests.swift`、`ProductStatusTests.swift`、`CaptureControlGateTests.swift`、`ScreenshotEntryPreferencesTests.swift`、`ScreenshotEntryIntegrationTests.swift`、`ArrivalMotionPreferencesTests.swift`。这些是需保留/按改动扩充的测试位置，本交接没有声称已经重跑。

## 10. 已知 HTML 差异与原生裁定

继承 HTML/JS 保留作为设计候选。[本轮浏览器结果](evidence/20261106-browser-02/RESULTS.md) 实测 **82 项：69 PASS / 13 FAIL**；HTML SHA-256 为 `aded9ed13cd5ff54c0f0a2172bbe78c720c2f03f41f16ed11a864a09ef45fabf`。该结果来自独立 headless Chromium 的合成数据交互，不是原生验收。下表列源码审计及实测差异，不为“原型全绿”删除失败；逐项裁定见 [FAILURES](FAILURES.md)，后续实现按本表/该裁定处理。

| 差异与最小复现/定位 | 原生裁定/未来验收 |
| --- | --- |
| 位置页深层有 `lineWidth/lineExtension/screenPadding`，动效深层有 `inwardDistance/reducedMotionDuration`；修改后原型会作为有效旋钮/动画参数 | 这 5 项及另 2 项共 7 个字段仅兼容保留，不能提供有效旋钮；已保存值往返不丢。见配置映射 |
| `fieldLabels` 将 minimumHitWidth/Height 称为最小点击区域；预览还使用 lineWidth | 说明为行布局最小尺寸，预览不承诺全矩形命中；不扩大真实点击窗来追原型 |
| 历史与存储确认收起全部后出现“撤销”，`undo-clear` 还原合成记录 | main 只有 `clearVisibleQueue` 的当前能力；不落地批量撤销、不复活旧记录。原生仅确认后收起，保留已有单条恢复限制 |
| 原型选择“使用主显示器”把 ID/UUID 写 null | 实际调用 `.preferredDisplay(nil)` 时解析并保存当时主屏 ID/UUID；换系统主屏不无声迁移 |
| 原型 `applyConfig` 复制整份旧 draft，`state.issue=null` 全局清错 | 原生应用共享配置草稿是正确范围，但提交必须 patch 最新 host 配置；只清本域错误。用“编辑数字→即时改位置/显示器→另一表面刷新→应用”验证不覆写 |
| 通用页 `launchAtLogin`、`appearance` 只改内存；选择 system 也没有重算真实系统 appearance | 设计保留两项，按 5.5 落地独立外观文件与真实登录服务；不删控件、不宣称 main 已实现、不允许假成功 |
| 权限页主要用 `permissions.chrome` 一个布尔值；点击原型授权后即模拟连接 | 原生拆开 OS Automation 与 Chrome JavaScript 条件，后者不能由前者推断；真实请求结果再刷新，不设置演示 true |
| 固定 3/7/30 天、合成历史筛选与记录数；版本、36.8 MB 是静态演示 | 历史沿用本地有界分页和现有筛选/本页搜索，不添加未经实施的全库日期查询；版本/存储从真实 host 读，未测量不显示 0 |
| 原型 `onboardingCompleted` 为内存完成状态 | 保留真实 presented 键语义；不标记权限已完成、不升级重跑；见第 8 节 |
| 原型单个 saveFailure/issue 模拟多个故障，不能覆盖写入后 chmod 失败或 watcher start 失败 | 按第 5 节分别注入并断言有效值、磁盘结果知识、错误域、重试目标；不把任意保存失败都展示成“原状态未变” |
| X10：宽度改 96→注入保存失败→关闭→不保存→重新打开，原型仍残留 `issue=write` | 放弃候选草稿后清本草稿错误，其他域未解决故障仍保留；原生重开不继续报已经放弃的布局保存失败 |
| X11：控制中心打开历史弹窗，首个原图按钮 Shift-Tab 跳过前面两个 select | 原生历史仍用独立窗口；任何 sheet/窗口均用完整 key-view loop，包含所有 enabled/visible 的下拉、输入、按钮，正反 Tab 不遗漏 |
| X12/X13：归档自定义输入 2.5 后直接点击保存/关闭，blur→change 全量 render 移除了点击目标，首击无效 | 原生文字回调只更新草稿，不替换按钮/容器；首击分别保存 2.5h 或立即出现未保存确认，不靠预先 Tab、第二击或延迟重放补救 |

数字显示/动效共用草稿并一次应用不是差异缺陷；它符合现有交互规范。本交接不擅自改为按页提交。HTML 不能提供原生未实现行为的授权或能力证明。

## 11. 原生必验清单

下面全部是后续实施的 **NOT_RUN** 项；合成测试可检查状态机，真实 AppKit/OS 项另记结果，不互相替代。

| 检查组 | 必须观测到的结果 |
| --- | --- |
| 控制中心与菜单 | 左键/键盘打开且再次关闭；右键/Control-click 同源菜单；Escape、外部点击、打开菜单/panel 例外；暂停/隐藏后仍可看到结果；单实例 Popover |
| 四态/独立控制 | 正常、暂停、隐藏、故障及暂停+隐藏；来源失败不改用户意图；空队列无裂缝；入口禁用与系统收录互不改写；不可用动作只禁本项 |
| 精确失败方向 | 三种停止方向保存失败仍停止，三种恢复方向失败不假恢复；resume 保存成功/start 失败显示来源问题；chmod-after-write 失败不宣称磁盘旧值；重试不反转目标 |
| 数字编辑 | 空串、`.`、中文 IME、locale 小数、复制粘贴、选择区；切页/后台刷新/失焦保留；Return 组字不提交；NaN/Inf、越界/小数张数拒绝；合法精度不被 slider/格式化截断；归档输入2.5后直接首击保存成功/首击关闭询问 |
| 应用/关闭 | 跨显示+动效一次应用；即时位置/屏幕命令不提交数字；dirty patch 不覆盖最新元数据；恢复本页只改本页；失败草稿保留；关闭三选项默认继续；部分域成功后不重复提交；主动丢弃候选后只清该草稿错误 |
| 数据迁移 | 全 27 字段逐值保留；缺 placement/outerInset 的 legacy；入缝 unselected/unreadable；旧入口 isEnabled/canonical/null；归档 missing/null/24h；旧 presented 不重跑 |
| 多显示器 | 拔屏、重接、主屏变化、UUID 歧义/ID 变化；回退不改偏好；显式恢复且不打断按下/选择/动画；visibleFrame/Dock/缩放/旋转与窗口标题可达 |
| 深色与辅助功能 | 浅/深及系统切换、提高对比度/减少透明度/减少动态；文字非颜色传义；Tab/Shift-Tab 包含所有下拉/输入/按钮、可见焦点、VoiceOver name/value、sheet 焦点、较长本地化文字 |
| 新外观/登录域 | 外观三值独立读写、缺失/损坏/未来版本与失败回显、回到system真实跟随；登录notRegistered/enabled/requiresApproval/notFound、取消待批准请求、注册/注销throw后回读、系统外部变更、无重复注册；真实登录验收与mock分开 |
| 首次使用与权限 | 新安装实际呈现才写 presented；升级不重跑；三步无强制权限；每按钮只请求对应能力；关闭/开始不截图、不附加、不发消息、不解除 pause/hide |
| 历史/存储/Feedback | 清可见不删文件/附件/历史，不开放未知重试；实际统计失败/部分状态；Feedback 复用草稿诊断选择，设置应用不发网络请求 |
| 焦点与回归边界 | 更新快照不激活窗口；菜单操作不新建附件目标/切 Chrome tab/刷新 relay；截图入口打开宿主窗口前取消原选择；设置预览只用合成素材 |

交付报告分开记录：文档/HTML 检查、自动化状态/持久化回归、原生窗口/输入/辅助功能、真实系统权限/显示器。不得把浏览器截图、软件合成事件或已有个人 Beta 附件验收写成本设置中心的完整原生验收。
