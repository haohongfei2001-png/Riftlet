# 六页设置中心：最终原生实现交接

**设计基线：** main `71d726c5d6416346b84e1ac93047af5bb321d925`，个人 Beta 2 `0.2.0 (2)`。  
**交付范围：** 六页信息架构、视觉、交互与状态规格；不包含已落地的 AppKit 改造。  
**直接查看：** [设置交互原型](prototype/index.html?view=settings&page=display) · [字段与设计映射](SETTINGS-MAP.md) · [设置组件](prototype/settings.js) · [设置样式](prototype/settings.css)

网页中的截图、显示器、权限与存储为演示数据，所有操作只改变原型内存。网页效果不构成生产设置已保存、Mac 权限已获准、截图已附加或原生无障碍已通过的证据。移交对象是现有原生设置系统的呈现层；继续复用既有 owner、配置文件与能力快照。

## 1. 应实现的整体界面

采用一块中性内容面、浅色分隔和精确对齐的设置行。只给外观小样、位置示意和动效预览必要的边界。六页共用标题、字号、行高、控件尺寸与选中表达，不把普通分组重新做成卡片墙。

推荐初始窗口 `780 × 584 pt`、导航 `176 pt`、内容边距 `32 pt`；与当前原生 `960 × 684 pt`、导航 `184 pt` 的区别见 [SETTINGS-MAP.md](SETTINGS-MAP.md)。内容允许纵向滚动，展开高级参数不横向挤压主标签。默认页优先显示常用选择；未编辑时不常驻大块保存提示，编辑后在内容底部提供稳定的应用区域。

| 页面 | 首层任务 | 折叠与次要入口 | 原生承载位置 |
| --- | --- | --- | --- |
| 通用 | 了解当前收录状态；选择外观；分别暂停收录、隐藏裂缝 | 登录项状态；使用引导；反馈 | `generalContent()`，`renderLogin()` |
| 位置与显示 | 选显示器与六位置；调数量及藏入比例；立即看示意 | 尺寸与留白；精细参数；适用时的旧版绝对位置 | `displayContent()`，`renderDisplay()`，`RiftSettingsCenterPreview` |
| 截图 | 沿用系统截图；了解收录位置；启停独立截图入口；选默认方式 | 打开位置、授权或恢复权限；进入截图 | `captureContent()`，`RiftSettingsSnapshot` |
| 动效 | 选“无／磁力吸引”；主动播放入缝及吞噬 | 轻按、吞噬、补位、回归的独立时长 | `motionContent()`，`ArrivalMotionMode` |
| 历史与存储 | 浏览历史；设置归档；按需检查存储；选择历史显示方式 | 小数小时；收起全部微图 | `historyContent()`，`LifecycleSettings`；新增独立 `historyDisplayStyle` 展示偏好 |
| 权限与帮助 | 看清每项权限的用途及下一步 | Chrome JavaScript 说明；版本和实际支持范围；诊断与配置 | `helpContent()`，`SetupPresentation` |

页面函数位于 [RiftSettingsCenterPages.swift](../../Sources/RiftletUI/RiftSettingsCenterPages.swift)，状态呈现位于 [RiftSettingsCenterRendering.swift](../../Sources/RiftletUI/RiftSettingsCenterRendering.swift)。导航继续使用 [SettingsProductPresentation.swift](../../Sources/RiftletUI/SettingsProductPresentation.swift) 的 `SettingsPage`，不创建第二套页面路由。

## 2. 所有个性化能力的源代码对应关系

本次重新从 `SettingsField` 提取原生字段，再与原型 `layoutDefaults` 比较：**原生 16 项、原型 16 项，缺失 0、额外 0。** 完整数值范围、单位和网页字段名已有 [字段表](SETTINGS-MAP.md)，以下补充实施时应连接的原生接口。

| 能力或字段集合 | 原生模型／命令 | owner 与源文件 |
| --- | --- | --- |
| 暂停收录、隐藏裂缝 | `.setCollectionPaused(Bool)`、`.setHidden(Bool)`，独立 domain | [SettingsStateModel.swift](../../Sources/RiftletUI/SettingsStateModel.swift) → `RiftletMain.saveSettings()` |
| 跟随系统／浅色／深色 | `SettingsAppearanceChoice`、`.appearance`、`.retryAppearance` | [SettingsProductHost.swift](../../Sources/RiftletApp/SettingsProductHost.swift)；不得借布局保存重置外观 |
| 登录时启动及失败恢复 | `SettingsLoginPresentation`；`.loginEnabled`、`.retryLogin`、`.openLoginSettings` | [LoginItemPreferences.swift](../../Sources/RiftletApp/LoginItemPreferences.swift)；受实际 capability 与系统状态约束 |
| 具体显示器、六位置 | `.selectDisplay`、`.selectPlacement`；`preferredDisplayID`、`preferredDisplayUUID`、`placement`、`placementSource` | [RiftConfiguration.swift](../../Sources/RiftletUI/RiftConfiguration.swift)、[RiftDisplaySelection.swift](../../Sources/RiftletUI/RiftDisplaySelection.swift) |
| 数量、藏入比例、边缘内缩 | `visibleCountPreference`、`hiddenFraction`、`outerInset` | `SettingsField` → `.layout([SettingsField: Double])` → `RiftConfiguration` |
| 微图大小、排列、编号 | `fitWidth`、`fitHeight`、`rowPitch`、`numberFontSize` | 同一 layout patch；不得按视觉示例覆盖现有偏好 |
| 精细几何 | `numberGap`、`leftPadding`、`minimumHitWidth`、`minimumHitHeight`、`firstCenterFromTop` | 同一 layout patch；最后一项只在 `placement == nil` 时适用 |
| 内置截图开关、默认方式 | `.setEntryEnabled`、`.setCaptureMode`；窗口／区域／全屏 | [RiftSettingsForm.swift](../../Sources/RiftletUI/RiftSettingsForm.swift) 中的 `RiftSettingsSnapshot` → 既有截图 owner |
| 入缝选择 | `.setArrival`；`ArrivalMotionMode.none / magnet` | [ArrivalMotionMode.swift](../../Sources/RiftletUI/ArrivalMotionMode.swift)；保留 `hasArrivalSelection` 与未选择状态 |
| 四项动效时长 | `pressDuration`、`swallowDuration`、`shiftDuration`、`returnDuration` | `SettingsField` → 同一 layout patch；界面 ms，持久化秒 |
| 自动归档 | `archiveAfterHours`；`.editArchive`、`.applyArchive`；`SettingsIntent.archiveHours` | [LifecycleSettings.swift](../../Sources/RiftletApp/LifecycleSettings.swift)；UI 小时，owner 使用秒；0 对应关闭/null |

### 新增：历史双样式偏好（独立于布局/归档设置）

- 默认 `current`：严格保留 Beta 2 现有 `RiftHistoryController` 的 `NSTableView` 列表呈现、列宽、分页与既有操作，不重建一套近似列表。
- 可选 `imageGrid`：新增图像网格 renderer。它消费同一 `displayed: [RiftHistoryEntry]`、`entries`、`pageOffset`、`hasEarlier` 和既有 `HistoryPresentation` 输出，不创建新的数据查询、分页器或 preview loader。
- 独立偏好 key：`historyDisplayStyle`，值为 `current` / `imageGrid`，默认 `current`。建议放在 `UserDefaults.standard`，不加入 `RiftConfiguration`、`SettingsField`、`SettingsStateModel` 的布局 patch，也不写入数据库/截图记录。设置页的选择立即保存并通知已打开的 `RiftHistoryController`；历史窗口内的切换也立即保存，设置页再次打开时反映同一值。
- 切换只替换列表/网格 renderer。必须保留当前 query、filter、pageOffset、selected `RiftHistoryEntry.id`、详情预览、preview zoom、恢复/移除/显示原图动作和 paging callbacks。样式切换不得调用重新载入全量历史或清空 `displayed`；切换时以 UUID 恢复选择。
- `HistoryPreviewLoader`、文件身份校验、预览取消和原图显示流程保持原样。网格缩略图可使用同一受控预览缓存/加载入口；不得直接解码任意历史路径或绕过 file identity 校验。
- 这项设置不进入「恢复本页默认值」、布局/动效草稿、归档保存事务，也不触发任何数据保留/删除行为。

真实保存与跨窗口动作由 [RiftletMain.swift](../../Sources/RiftletApp/RiftletMain.swift) 的 `saveSettings()`、`performSettingsAction()` 执行。外观和登录项由 `SettingsProductHost` 自己持有，不能从 Main 递归分派同一动作。

### 不得随视觉升级改变的内容

- `hiddenFraction` 的 UI 为 0–90%，原生为 0–0.9；0 是合法值。时长 0 ms、非负的小数归档小时也必须保留，不能用 `value || default` 替换。
- `rowPitch`、`numberGap`、`leftPadding` 等参数不新增原生没有的上限；输入范围以 `RiftConfiguration.validate()` 为准。
- 设计展示的 rowPitch `68 pt` 是推荐比例，基线默认 `60 pt` 和已有用户设置不得被迁移覆盖。旧数据 decode 的默认与新建配置默认不完全相同，不能重建整个配置对象后回写。
- 兼容字段 `lineWidth`、`lineExtension`、`emptyTraceLength`、`screenPadding`、旧 `arrivalDuration`、`inwardDistance`、旧 `reducedMotionDuration` 原样保留，不加入本次编辑词表，不因“恢复本页默认”重置。
- 减少动态效果、减少透明度、提高对比度读取 macOS 偏好，属于环境状态；不另存三个与系统相冲突的产品开关。
- 截图延迟、是否显示指针继续属于每次截图会话；历史保留、永久删除、附件目标与自动发送均不属于本次设置改造。

## 3. 即存、应用与失败保留

| 操作 | 提交边界 | 失败或并发更新时的要求 |
| --- | --- | --- |
| 开关、外观、入缝枚举、显示器、六位置 | 用户明确选择即提交该项；刷新视图本身不发送动作 | 保留原请求的目标值，以 owner 的实际生效状态呈现；不靠反转开关“重试” |
| 显示页数字、动效页数字 | 键入先进入草稿与示意；点击“应用参数”才提交当前页字段 | 未通过校验不提交；保留原始字符串与编辑状态，其他页草稿不变 |
| 归档预设／自定义 | 选择或键入先成为归档草稿；“保存时限”才提交 | 小数、0 与未完整输入分别处理；失败留在原处 |
| 恢复默认／放弃 | 只改变当前页草稿；恢复默认仍需应用 | 不清空另一页草稿，不重置兼容字段、显示器身份或已生效的即存项 |
| 关闭或退出 | 有草稿、未确认保存或正在保存时，沿用“继续编辑／不保存／应用并关闭” | 仅“应用并关闭”明确处理全部草稿；部分保存失败时窗口与说明仍可见 |

**原生需要落实的一处真实行为差异：** 当前 `SettingsStateModel` 的 `.applyLayout` 和 `.discardLayout` 作用于共享 layout 草稿。新设计要求设置页内按 `SettingsField.page` 选择字段集合；可在现有 model 增加带页参数的命令或等价的字段 patch 操作。保留同一个配置 owner，不拆成两个相互覆盖的配置文件。退出时的 `.applyDrafts` 继续处理全部；各域可能分别成功，不把它伪装成原子事务。

保存回执必须保留既有版本判断：后台刷新不覆盖正在编辑的原始文本；只清除本次请求成功且编辑版本仍相同的已提交字段。写入期间新输入的内容保留。恢复默认或放弃之前先按 `RiftSettingsCenterController.finishEditingForReplacement()` 结束或取消原生编辑，不能让迟到的 end-edit 回调把已放弃文本写回来。

**失败文案应是“这次更改尚未确认保存”。** 即存开关失败时，有效运行状态可能已经变化，例如先暂停收录、再持久化失败。不能统一声称“原设置仍保留”，也不能擅自自动回滚。控件显示 owner 的当前有效值，旁边提供重试原选择；其他域保存成功不能清除这项提示。网页中的简化错误状态不是持久化算法。

## 4. 旧版位置与显示器断开

`placement == nil` 有真实含义：沿用旧版绝对位置。此时才显示 `firstCenterFromTop`，不能为了点亮六位置按钮把 null 写成“左中”。用户明确选择六位置后，使用已有 `RiftPlacement` 布局公式并把来源记为用户选择；旧版字段不再生效，但旧值仍保留。若存在旧版位置草稿，应在原处说明不再适用并允许放弃，不能悄悄提交。

显示器使用具体 ID 与 UUID，不以显示名称作为身份。同名屏幕仍是不同选项；菜单正在跟踪时不重建其 represented object。断开后展示“当前临时显示在主屏，保留原选择”，不得把回退屏写入偏好。原屏恢复后提供“回到已选屏幕”，不在指针操作过程中自动搬动微图。调用既有 `RiftDisplaySessionSelection`，不复制一套按鼠标位置猜屏幕的规则。

网页的“主显示器／外接显示器”和屏幕示意只表达交互及比例；它们不是当前用户硬件清单，也不替代多屏热插拔验收。

## 5. 登录项、权限与帮助入口

### 登录项

本方案按当前 Beta 的不可用状态展示禁用开关和一句原因。正式实现必须读取 `SettingsLoginPresentation.available/status`，不把“当前不可用”写成所有未来版本的永久限制。`requiresApproval` 应显示“等待系统允许”，不能当作已获准；`notFound`、`unknown`、nil 保持禁用且不主动注册或取消。保存未确认时保留 `.failedTarget` 对应的重试；需要时仍能打开原生登录项设置。

### 权限的三类产品状态

| 用户看到的状态 | 原生事实 | 界面与动作 |
| --- | --- | --- |
| 已允许／可访问 | `.granted`，或截图来源 `.accessible` | 简短确认；只表示该权限，不扩张为当前聊天必然可附加 |
| 需要处理 | `.denied`、`.notRequested`、屏幕录制 `.notGranted`、来源未配置等明确事实 | 写出具体原因，提供对应授权或系统设置入口 |
| 尚未确定／前提未满足 | `.notChecked`、`.checking`、`.unavailable`，以及 Chrome `.notRunning/.browserUnavailable` | 分别显示“未检查／正在检查／未确认／Chrome 未运行／未找到支持的 Chrome”；不能统一画成拒绝，也不能自动补成成功 |

`notNeeded/notApplicable` 是不适用，按上下文隐藏授权催促或显示“当前功能不需要”，不是授权成功。检查期间只禁用对应操作，保持其他页面可用。状态同时使用文字与符号，颜色只作辅助。

三项用途仍然独立：截图位置用于读新保存的截图；Chrome 自动化用于主动附加；屏幕录制只用于内置截图，不阻止系统截图文件的收录。

**Chrome 的两个许可不能合并：** macOS 自动化允许后，还需要确认 Chrome「视图 → 开发者 → 允许来自 Apple 事件的 JavaScript」。把说明放在同一权限行的可展开内容中；保持当前聊天必须是实际活动目标的说明，不增加自动寻找或切换聊天行为。

### 保留全部既有恢复能力的轻量表达

截图位置行可以只有一个主要动作，但必须按事实切换到既有 `.openSource`、`.chooseSourceAccess` 或 `.openFilePrivacy`。不能把“查看”“允许访问”“文件访问设置”折叠为永远调用同一个动作。Chrome 被拒绝时使用已有“打开自动化设置”路径；屏幕录制行使用 `.openScreenRecordingPrivacy`；重新检查调用 `.recheck`。原型仅演示这些入口，不执行系统授权。

“关于”应保留实际 `version` 与 `SetupPresentation.supportText`，不要用品牌标语替代支持范围。诊断与配置中仍保留 `.reloadConfiguration`、`.openConfiguration`；存在配置草稿或保存进行中时，沿用当前 capability 和 busy 条件。普通页面不展示 owner revision、内部错误对象或事务术语。

## 6. 控件、焦点与原生编辑

| 状态 | 实施要求 |
| --- | --- |
| 常态 | 系统字体；主要文字 13 pt、说明 12/11 pt；数值与单位分离；统一窄控件右对齐 |
| 悬停／按下 | 控件局部轻微反馈，不抖动整行，不用连续动画吸引注意 |
| 选中 | 外观、位置与分段选择有明确轮廓或标记；深浅色均不依赖背景色单独区分 |
| 键盘焦点 | 保留清晰 focus ring；Tab 按阅读顺序；Space/Return 操作当前控件；不用自定义全局快捷键 |
| 重绘或状态刷新 | 保留当前控件身份、文本选区和滚动位置；原生优先更新现有控件，不重建正在编辑的 field editor |
| 操作后控件消失 | 键盘用户回到对应的稳定操作或输入；例如归档保存后回归档下拉，不任意跳到首控件 |
| 指针操作 | 不因一次重绘强制抢回键盘焦点，不激活无关窗口 |
| 禁用 | 说明能力或保存等待原因，使用真实 enabled 条件；不能只把颜色变灰却继续派发动作 |
| 校验失败 | 在当前字段／保存区域给出可改正的文字，保留输入；只把焦点定位到真实有错字段 |

网页 `redraw()` 已通过 id/data 属性保存身份，仅为键盘交互恢复焦点，并用 `preventScroll` 保持位置。AppKit 落地需继承 [RiftSettingsCenterController.swift](../../Sources/RiftletUI/RiftSettingsCenterController.swift) 的 first responder、IME、sheet、Escape 与编辑恢复机制；不要把网页的 `innerHTML` 重建策略翻译成每次重新创建全部原生控件。

深色强调色上的主要按钮使用深墨文字；警告色沿用当前统一色表，不能回到过浅的小字。减少透明度时取消非必要材质透出；增加对比度时加深文字及必要轮廓。减少动态效果改变呈现，不改用户选中的入缝偏好。

## 7. 本轮核对结果与实施验收重点

已核对六页全部偏好、16 个有效数值字段、7 个兼容字段、显示器身份、独立权限和恢复入口。原型与当前原生行为的差异已经明确写出：页面级应用／放弃需要落实到 model；权限与持久化仍由真实 owner 提供；网页样本不可写入生产配置。

原生实施时重点验证：

1. 显示页编辑后切到动效页，再应用或放弃其中一页，另一页草稿完整保留。
2. 输入 0 ms、0% 与小数归档时限，原值准确保存；无效或未完成输入留在原处。
3. 暂停／隐藏／外观分别保存失败，控件呈现实际状态并重试同一意图；别的域成功不掩盖问题。
4. 未保存关闭、保存等待、部分成功、继续编辑及中文组字期间的默认／放弃，不丢文本与选区。
5. legacy null 不被浏览设置或预览改写；同名显示器、断开／重连与恢复动作保留原意图。
6. 六页在深浅色、窄窗口、展开高级项、键盘及系统减少动态效果下保持可用。

这些是针对本次界面改造的验收点，不重新开发截图收录、附件输入或数据库。实现分支完成后，继续由 Codex 负责真实 Mac 验收；设计原型通过不代替该结果。
