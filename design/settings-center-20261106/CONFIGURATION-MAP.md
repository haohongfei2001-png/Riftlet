# 设置配置映射｜实际 main 与设计目标

审计日期：2026-11-06。实现基线：main `b61fc46cf931bdbd14deec1b47d077e92db61e16`；设计审计起点：`e1a7286d7eb14ff47686804718f61a2515a8fd12`。本工作树 `Sources/` 相对该 main 无差异。这里只记录源码事实与既有 [INTERACTION-SPEC](INTERACTION-SPEC.md) 的映射，不修改产品行为，不读写生产配置，不把网页内存模拟当作原生实现。

## 1. 读表规则与保存边界

- **新建**指 `RiftConfiguration()` 成员默认；**缺失解码**指已存在 JSON 中缺少该键或值为 `null`。两者不总相同。首次 App 启动还会补入当时主显示器的 ID/UUID，所以结构体默认 `nil` 不表示实际新文件必为 `nil`。
- 所有几何值用 AppKit **pt**，时长持久化为**秒**，`hiddenFraction` 为 **0…0.9 的比例**；原型/设置可显示百分比或毫秒，保存必须换回原单位。除明确 `Int/UInt32` 外，不应把有效小数舍入成整数。
- 下表列出全部 **27 个 CodingKeys**。三个 Optional 键可在编码时省略，不能以“JSON 必须含 27 个键”判断文件损坏。现有解码忽略未知键，重新编码只写已知键；不要据此宣称未知未来字段已被无损保留。
- 现有文件按字段严格类型解码：错误类型、未知枚举、无效范围会抛错；没有自动重置为新默认的路径。缺失/`null` 与格式错误不同。已有文件读取成功不会仅因升级而重写；新文件才写初始配置。
- 当前持久文件：应用数据根下 `rift-configuration.json`。普通模式数据根为 `~/Library/Application Support/Riftlet/`；模拟、Web 验收、受限候选是独立根。设置页不能跨根搬运偏好或把工程运行模式做成用户开关。
- 当前 `applySettings` 对布局先合并 `rift.requestedConfiguration`、校验、原子写文件，再 `updateConfiguration`；有指针按下/选择或保护交互时可延后呈现。**已保存的请求配置、当前呈现配置和未提交草稿是三个概念**。显示器变更还会取消本次选择与截图/到达装饰。
- 当前原生只提供遮挡、距边、张数、六点位置、显示器等部分控件；其余有效数值保存在文件里。新设计必须合并最新请求值，保留未编辑字段、兼容字段和个性化。不要用一份推荐配置替换整文件。

源码：[RiftConfiguration.swift](../../Sources/RiftletUI/RiftConfiguration.swift)、[Main 保存与初始化](../../Sources/RiftletApp/RiftletMain.swift)、[RiftPanelController](../../Sources/RiftletUI/RiftPanelController.swift)。

## 2. RiftConfiguration 全部 27 字段

范围中 `∞` 表示**没有额外有限上界**，仍必须是有限 Double；`(0, x]` 不包含 0。状态“兼容保留”指当前生产呈现没有读取该配置值，不是可以删键。表中“原型”描述审计起点，修订后的终稿应按第 6 节消除误导。

| # / JSON 键 | 新建 / 缺失解码 | 源码接受范围 | 当前真实作用、原生 UI | 设计归属 / 原型对应 |
| --- | --- | --- | --- | --- |
| 1 `fitWidth` | 72 / 72 | `(0,256]` pt | 与高度一起等比例 fit；不是重采样/修改原图。原生常规页无数值控件。 | 位置与显示·详细；“微图最大宽度”，精确输入保留小数。推荐仍 72。 |
| 2 `fitHeight` | 56 / 56 | `(0,256]` pt | fit 上限，同时参与行距和页容量。原生无数值控件。 | 位置与显示·详细；“微图最大高度”。推荐仍 56。 |
| 3 `hiddenFraction` | 0.25 / 0.25 | `[0,0.9]` | 露出宽度为 fit 宽度×`(1-hiddenFraction)`；0 表示不遮挡。原生文本/滑块均 0–90%。 | 位置与显示·默认项。原型 current=25%，recommendation=0%；**0% 是设计建议，不是已改 main 默认**。 |
| 4 `rowPitch` | 60 / 60 | `(0,∞)` pt | 实际 pitch=`max(rowPitch,max(fitHeight,minimumHitHeight)+4)`；有效偏好可能被安全几何约束抬高。 | 位置与显示·详细；相邻微图中心间距。精确值无额外上限。 |
| 5 `lineWidth` | 0.5 / 0.5 | `(0,8]` pt | **兼容保留**。正式线宽由 `1/backingScale`，或高对比度时 1 pt 决定，不使用此值。 | 深层兼容参考。起点原型的“裂缝线宽”不能宣称当前会改变 native 线宽。 |
| 6 `lineExtension` | 8 / 8 | `[0,∞)` pt | **兼容保留**。正式线的上下端从实际图片几何推导；没有读取此值。 | 深层兼容参考。起点原型“裂缝上下延伸”不映射有效旋钮。 |
| 7 `emptyTraceLength` | 24 / 24 | `(0,∞)` pt | **兼容保留**。空队列始终无残留线。尽管不驱动呈现，`validate` 仍要求有限且大于 0。 | 不展示可调项；原型默认对象保留此键。不得恢复旧空缝，也不能把 0 当合法序列化值。 |
| 8 `outerInset` | **6 / 14** | `[0,256]` pt | 相对可用屏幕边缘；实际布局还受可用宽度约束。原生文本/滑块 0–256。 | 位置与显示·默认项。recommendation/current=6，legacy 缺字段=14；不能把旧 14 静默改成 6。 |
| 9 `firstCenterFromTop` | 202 / 202 | `[0,∞)` pt | **仅 `placement=nil` 的 legacy 布局生效**；从 `visibleFrame.maxY` 向下定位。 | 位置与显示·旧版深层参考/精确输入，只在保留 legacy 时有意义。选六点位置后保留原值而不再驱动落点。 |
| 10 `screenPadding` | 12 / 12 | `[0,256]` pt | **兼容保留**。此 `RiftConfiguration` 键无生产读值；截图入口另有同名配置，不能混用。 | 深层兼容参考；起点原型“屏幕安全留白”不代表 main 支持该控制。 |
| 11 `numberFontSize` | 11 / 11 | `(0,32]` pt | 编号字体与度量；窄小图另有编号 pad。原生无数值控件。 | 位置与显示·详细；编号字号。 |
| 12 `numberGap` | 8 / 8 | `[0,∞)` pt | 编号与露出图片之间的几何间隔。 | 位置与显示·精细；不得因快捷滑块较短而截断旧值。 |
| 13 `leftPadding` | 4 / 4 | `[0,∞)` pt | 行宽计算中的内侧留白；左右侧布局会反射。 | 位置与显示·精细；原型“微图内侧留白”。 |
| 14 `minimumHitWidth` | 44 / 44 | `(0,256]` pt | 实际是**行布局最小宽度**。真正鼠标窗口只有图片露出区和编号区，并不把整行 padding 变成点击区。 | 位置与显示·精细；字段名保留，面向用户不可承诺“最小可点击矩形宽度”。 |
| 15 `minimumHitHeight` | 44 / 44 | `(0,256]` pt | 行最小高度及容量计算；同样不保证整行高都捕获点击。 | 位置与显示·精细；应描述行尺寸，不能暗中扩大 native 输入岛。 |
| 16 `arrivalDuration` | 0.220 / 0.220 | `[0,3]` 秒 | **兼容保留**。磁力使用独立 `MagnetMotionParameters`（默认总计 0.560 秒），不读本值。 | 深层兼容参考；不是磁力时长控件，也不控制 START/吞噬。 |
| 17 `pressDuration` | 0.060 / 0.060 | `[0,3]` 秒 | 按下相关保护/复位调度与 imageOffset 回位；不是所有装饰层过渡的统一时长。 | 动效·精细；原型显示 60 ms。不能据此声称所有按压视觉都精确按此时长。 |
| 18 `inwardDistance` | 1.5 / 1.5 | `[0,∞)` pt | **兼容保留**；正式按下呈现没有读取此值。 | 深层兼容参考；起点原型“按下内移”不可作为已生效控制。 |
| 19 `swallowDuration` | 0.120 / 0.120 | `[0,3]` 秒 | 收到已提交的 uploadStarted 可见性变化后，控制吞噬呈现；0 有直接关闭路径，不伪造 START。 | 动效·精细；原型 120 ms。只改变呈现，不改变附件事实或重试规则。 |
| 20 `shiftDuration` | 0.160 / 0.160 | `[0,3]` 秒 | 合适的队列补位几何移动；减少动态时实际为 0。**分页**另用固定过渡，不全由此字段控制。 | 动效·精细；原型 160 ms。 |
| 21 `returnDuration` | 0.180 / 0.180 | `[0,3]` 秒 | 失败状态的 imageOffset 回位参数；不授予失败/重试判定。 | 动效·精细；原型 180 ms。 |
| 22 `reducedMotionDuration` | 0.080 / 0.080 | `[0,3]` 秒 | **兼容保留**。实际通用时长缩为 `min(0.08,normal)`、补位为 0，磁力有效模式为 none，不读取此值。 | 深层兼容参考。起点原型用它计算“减少动态淡变”与 main 不同，须取消有效性暗示。 |
| 23 `preferredDisplayID` | nil / nil | Optional UInt32；仅类型范围，无额外有效屏幕存在校验 | 新建 App 会填当前 `NSScreen.screens.first` 的 ID；界面按屏幕候选选，不手填数字。UUID 优先，ID 是兼容身份。 | 位置与显示·显示器选项的内部身份；保留断连时原值，不做数值控件。 |
| 24 `visibleCountPreference` | 3 / 3 | Int `1...10` | 页容量上限，还取决于屏幕空间/行距；不限制导入总量。原生文本/整数刻度均 1–10。 | 位置与显示·默认项；推荐 3，不能理解为只保留 3 张文件。 |
| 25 `placement` | **`.leftMiddle` / nil** | Optional 六值：`leftTop/leftMiddle/leftBottom/rightTop/rightMiddle/rightBottom` | nil 保留旧右边绝对布局；六点锚定实际 `visibleFrame`。中间位置由容量/行距及边界夹取，不是持久化的“40%”字段。 | 位置与显示·六点位置；左中/约40%是设计描述，不能改旧 nil 布局来凑该百分比。 |
| 26 `placementSource` | **`.initialRecommendation` / `.legacy`** | `initialRecommendation/user/legacy` | 来源元数据；用户选择位置或显示器时设 `.user`。不直接驱动几何，也不由每次刷新覆写。 | 不给消费者枚举控件；保留迁移意图。 |
| 27 `preferredDisplayUUID` | nil / nil | Optional String；非 nil 必须能被 `UUID(uuidString:)` 解析 | 新文件可写实际屏幕 UUID；有效但暂时未连接仍合法。匹配不唯一时不能靠 ID 猜一个屏幕。 | 位置与显示·内部身份；原型 builtin/external 的 UUID 是合成值，不能写入真实偏好。 |

几何及鼠标范围依据：[RiftLayout.swift](../../Sources/RiftletUI/RiftLayout.swift)、[RiftPanelController.swift](../../Sources/RiftletUI/RiftPanelController.swift)。动效依据：[MagnetMotionPlan.swift](../../Sources/RiftletUI/MagnetMotionPlan.swift)、[ArrivalMotionMode.swift](../../Sources/RiftletUI/ArrivalMotionMode.swift)。原生当前范围与提交方式依据：[RiftSettingsForm.swift](../../Sources/RiftletUI/RiftSettingsForm.swift)。

### 可编辑值与兼容值必须分开

7 个兼容保留字段是 `lineWidth/lineExtension/emptyTraceLength/screenPadding/arrivalDuration/inwardDistance/reducedMotionDuration`。可以在深层参考中显示当前保存值和“当前版本保留以兼容旧配置”；不要恢复本页时重置它们、删除它们，或做会提示“已生效”的旋钮。`firstCenterFromTop` 则是 **legacy 条件下仍有效**，与完全不读值的兼容项不同。

新设计的数值文本可覆盖上述完整有效域，滑块只是快捷输入。特别是 `rowPitch/lineExtension/firstCenterFromTop/numberGap/leftPadding/inwardDistance/emptyTraceLength` 没有额外上界，不能统一强制成 256。负数、非有限值、非法枚举及非整张数仍须拒绝。原生文本目前不接受科学计数法；起点原型接受指数形式。这是输入语法差异，不是底层 Double 范围变化。

## 3. 其他持久化域与真实默认

| 域 / 精确存储 | 新建与缺失/损坏行为 | 保存、生效与 UI 归属 |
| --- | --- | --- |
| **收录暂停**：`queue.sqlite` → `metadata`，key=`capture_paused`，字符串 `true/false` | 无行默认 false。读取只有精确字符串 `true` 才为 true；不是 JSON 设置。 | 菜单/通用的现有 host 命令；暂停只停止系统截图收录，不关闭内置截图、不隐藏已有卡。停止方向与恢复方向不同，见第4节。 |
| **用户隐藏**：同表 key=`user_hidden` | 无行默认 false。隐藏偏好与空队列、截图时临时曝光抑制不同。 | 菜单/通用；隐藏视觉及内置入口并取消当前选择/截图，不停系统收录、不删除图片。显示只在保存成功后恢复。 |
| **闲置归档**：`lifecycle-settings.json` → `archiveAfterSeconds: Double?` | 新建文件默认 **86400 秒（24h）**。该类型使用合成 Codable；已有 `{}` 或 `null` 解码为 **nil（关闭）**，不会采用成员初始化器的24h。非 nil 必须有限且 `>0`，无额外上限；错误类型抛错。 | 历史与存储。UI 用小时，0 映射 nil；实际 JSON 的0非法。原生接受有限非负小时且×3600仍有限。Return/保存提交，不因失焦保存；写成功后换运行值，并至少等30秒再归档。保存失败保留旧运行值。 |
| **入缝选择**：`arrival-motion-settings.json` → `{version:1,mode:"none"|"magnet"}` | 无文件=`unselected`，有效模式暂用 none；不是已选 none。文件≤4096字节；版本不为1、缺必填键、非法模式/不可读=`unreadable`，保留原文件并暂用 none。 | 动效页。显式选择先原子写，再更新 selectedMode、取消旧到达装饰并设置模式；失败旧运行选择不变。减少动态使有效模式none但不覆盖已选magnet。 |
| **内置截图启用**：`capture-entry-settings.json` → `builtInScreenshotEnabled` | 新文件 true；`version` 必须1，`defaultMode`必填。canonical开关键存在时严格 Bool（null也报错）；否则兼容同version1旧 `isEnabled`；两者都缺省才true。canonical优先。 | 截图页；关闭整个内置截图功能，不是单纯视觉开关。关闭取消未完成曝光/编辑入口；已完成曝光拥有原件，其导入仍可收尾。具体失败见第4节。编码只写canonical键，旧键不重写。 |
| **默认截图方式**：同文件 `defaultMode` | 新文件 `.window`；枚举 `window/region/fullScreen`。已有文件缺该键/null或无效值直接失败，不默补window。 | 截图页/入口更多菜单。先保存再更新默认；当前已展开会话的模式和固定顺序不被重排，下次展开才用新默认。保存失败仍采用旧有效默认。 |
| **内置截图文件版本**：同文件 `version` | 新建1；load要求存在且==1。未知版本保留为不可用，不静默迁移成1。 | 内部迁移元数据，无用户控件。首次创建该文件失败会使 host 初始化失败、entryAvailable=false，不应把它画成正常开启。 |
| **首次展示标记**：`UserDefaults.standard` key=`Riftlet.firstUse.presented.v1.<modeDirectory>` | 缺失 bool=false，自动引导尚未展示。自动窗口**实际展示时就写true**；不是第三步完成标记。 | 权限与帮助的“重新查看引导”不清标记。当前步数/窗口尺寸仅会话内；现有 `UserDefaults.set` 没有同步磁盘成功回执。不能把新原型 `onboardingCompleted` 等同现有键，升级不据此重跑。 |
| **系统截图目录读取书签**：`UserDefaults.standard` key=`Riftlet.sourceAccess.v1.<modeDirectory>`，Data | 缺失不造权限。仅接受用户选中目录与系统当前截图目录（标准化并解析symlink后）一致的 security-scoped 只读书签；恢复使用 withoutUI/withoutMounting。 | 截图/权限与帮助。接受时建立读取访问并生成书签；生成可能失败；UserDefaults写入无同步成功回执。stale书签尝试刷新但不删除旧数据。`startAccessing… == false` 不是权限拒绝，真实来源读取另查。 |
| **系统截图位置**：系统 `~/Library/Preferences/com.apple.screencapture.plist` 的 `location` | 文件确实不存在、键缺失或空字符串才回退Desktop；格式错误/不能读取不是默认Desktop。源码监听文件及父目录变化。 | 只显示并打开当前来源，或请求读取该来源。Riftlet **不写系统 location、不任意改收录目录**；“更换来源”不能借书签弹窗重新定义此行为。 |
| **反馈草稿**：`Feedback-v01/feedback.sqlite` → `draft(id=1,revision,payload)`；payload=`FeedbackDraft(kind,text,diagnostic?,revision)` | 新草稿 `.problem`、空正文、diagnostic=nil、revision0。存储可保留≤131072 UTF-8字节草稿；发送另限4000 Unicode标量/16KiB且非空，不能按前者宣称可发送。 | 独立反馈窗口；文字/类别/诊断选择自动延迟120ms保存；关闭必须完成保存，失败保留窗口及正文、提供重试/复制。反馈偏好不是全局设置。 |
| **本次附诊断**：上述草稿的 `diagnostic`，不是 UserDefaults Bool | 新草稿默认不附；同一未提交草稿重开会恢复已选诊断。成功入本机outbox后新草稿diagnostic=nil。 | 权限与帮助→反馈；“仅本次”指此草稿/报告，不等于每次重开窗口都清空选择。预览与用户显式提交仍保留。 |
| **反馈投递/删除能力**：Feedback SQLite的`reports/submissions/credential_intents/meta`；Keychain service=`com.riftlet.feedback.v1.<modeDirectory>`，account=报告ID | 这些是业务状态与每报告随机能力，不是用户偏好。`meta.running` 是运行/正常退出标记。endpoint 为代码中的固定配置。 | 复用既有反馈后端；不做“重置设置”或“清空历史”联动删除，不展示/导出Keychain内容，不增加endpoint编辑开关。 |

来源：[QueueStore](../../Sources/RiftletCore/QueueStore.swift)、[LifecycleSettings](../../Sources/RiftletApp/LifecycleSettings.swift)、[ArrivalMotionPreferences](../../Sources/RiftletApp/ArrivalMotionPreferences.swift)、[ScreenshotEntryPreferences](../../Sources/RiftletApp/ScreenshotEntryPreferences.swift)、[ScreenshotEntryHost](../../Sources/RiftletApp/ScreenshotEntryHost.swift)、[FirstUsePreferences](../../Sources/RiftletApp/FirstUsePreferences.swift)、[CaptureSourceBinding](../../Sources/RiftletCapture/CaptureSourceBinding.swift)、[FeedbackModels](../../Sources/RiftletFeedback/FeedbackModels.swift)、[FeedbackStore](../../Sources/RiftletFeedback/FeedbackStore.swift)、[FeedbackWindowController](../../Sources/RiftletFeedbackUI/FeedbackWindowController.swift)、[ReportSecrets](../../Sources/RiftletFeedback/ReportSecrets.swift)。

### 不应误造为长期偏好的状态

| 项 | 当前 main 事实 | 原型/新设置页边界 |
| --- | --- | --- |
| 截图延时、显示指针、截图后编辑 | `InteractiveScreenshotOptions(delay:0,showPointer:false,editAfter:false)`，只在会话内。delay标准化到0…60秒，非有限→0；当前菜单仅0/5/10秒。每次重新展开恢复initialOptions。 | 可说明已有会话选项；没有相应持久键，不能随“默认截图方式”顺带保存为新全局偏好。 |
| 当前截图模式/触发 | window/region/fullScreen 的运行选择；点击入口/菜单显式开始，取消/隐藏/关闭终止未完成会话。系统截图快捷键仍归macOS。没有可配置全局触发快捷键或“每次截图即自动附加”设置。 | 原型只模拟发起；不设计第二套捕获默认/自动上传，不能把入口开关叫成仅隐藏按钮。 |
| 曝光期间隐藏、菜单展开、busy、选择/悬停/预览保护 | 内存状态，独立于 `user_hidden`；曝光抑制结束可恢复，但不能改变持久隐藏意图。 | 不持久化临时抑制、不把临时隐藏显示为用户选择；按钮可用性读取host有效状态。 |
| Chrome自动化、脚本设置、内置录屏权限 | OS/TCC/Chrome拥有的真实状态。自动化inspect不请求、不启动Chrome；显式请求动作才可能申请。录屏在实际开始内置截图时先preflight再request。Chrome允许Apple Events JavaScript是浏览器选项。 | 只映射状态和现有定向动作；不能保存一个`permissionGranted=true`替代真实检查，不能把录屏/AX写成系统截图收录的统一前置条件。 |
| 外观、减少动态、减少透明度、提高对比度 | 当前App随系统effectiveAppearance与NSWorkspace无障碍选项；无应用内外观覆盖持久键。相关生产控件使用这些实时值。 | 原型appearance下拉和评审深浅色切换都是模拟；若保留应用内覆盖，标明新域待实施，不声称已有保存接口。系统减少动态不能被动画预览绕过。 |
| 登录后自动打开 | 当前main未实现SMAppService/登录项注册或持久偏好。 | 起点原型`launchAtLogin=false`仅模拟，不是实际OS状态。交接必须明确待实现，不用普通JSON Bool冒充系统注册成功。 |
| 选中显示器与当前实际显示器 | 前者持久化，后者由会话fallback决定；断连不改ID/UUID。重连只提供“回到已选显示器”，不会自动从指针下搬走。 | 原型断连/恢复切换只模拟；“使用主显示器”当前host会**立即解析并保存当时主屏的ID/UUID**，不是永久跟随未来主屏。不能改变这个语义而仍声称只是接线。 |
| 历史筛选、日期范围、检查磁盘用量、窗口尺寸/当前页 | 未发现这些现有UI状态的长期设置域；用量是按需检查结果。归档调度每30秒检查，并受唤醒/时钟变化静默期及交互保护约束。 | 原型固定历史/磁盘值不能保存成产品事实；不把归档变成文件删除计划。页面草稿和窗口状态不与数据历史混写。 |

相关实现：[InteractiveScreenshotTypes](../../Sources/RiftletCapture/InteractiveScreenshotTypes.swift)、[ScreenshotEntryController](../../Sources/RiftletUI/ScreenshotEntryController.swift)、[AutomationPermission](../../Sources/RiftletApp/AutomationPermission.swift)、[RiftDisplaySelection](../../Sources/RiftletUI/RiftDisplaySelection.swift)、[RiftSetupController](../../Sources/RiftletUI/RiftSetupController.swift)。

## 4. 暂停、隐藏、关闭内置截图：运行值与保存错误

以下是现有 host 的行为，不用一个乐观更新的网页开关替代。底层没有保证所有域都提供独立 `persistedValue` 属性；界面应保留最后确认的保存结果，不能在失败时猜测磁盘字节。

| 请求 | 立即运行行为 | 保存成功 | 保存失败 | 反向请求的特殊情况 |
| --- | --- | --- | --- | --- |
| **暂停收录** | 先 `await binding.stop()`，`captureIsPaused=true` | 再写 `metadata.capture_paused=true`，清collectionSettingFailed | 当前仍暂停；标记collectionSettingFailed；说明“本次已暂停，重启可能恢复此前设置” | **继续收录**先保存false；写失败仍维持暂停。写成功后`captureIsPaused=false`，再`binding.start()`；若start失败，应为**未选择暂停＋来源/运行故障**，不是保存失败，也不是人为暂停。 |
| **隐藏裂缝** | 取消未完成选择，`userHidden=true`；隐藏rift及内置入口 | 写`metadata.user_hidden=true`后清visibilitySettingFailed | 当前仍隐藏；保存意图未确认，重启可能恢复此前状态；收录不受影响 | **显示**先保存false；写失败保持隐藏，不假称已显示。成功才显示rift/入口。空队列显示偏好false仍可无可见裂缝。 |
| **关闭内置截图** | 立即把host有效enabled设false，禁用capture，cancel，收起entry、解除header anchor | 写新preferences后更新host、清preferenceSaveFailed | 当前仍关闭，保存错误可重试；不改变系统截图收录与隐藏偏好 | **启用**先保存true，成功才启用并按当前隐藏状态配置。保存失败不启用。相同有效值但仍有saveFailed时允许重试保存。 |

`ScreenshotEntryPreferences.save` 先原子写JSON，再设置0600文件权限；后一项失败也会返回保存错误。因此“保存失败”并不证明磁盘一定仍是旧内容。正确措辞是“当前生效状态…；保存尚未确认/重启可能恢复之前设置”，不要伪造一个已保存结果。

默认截图方式保存失败：有效defaultMode不改，entry恢复旧有效默认；`preferenceSaveFailed=true`，当前会话保持独立。布局、归档、入缝选择都先持久化后替换运行值，失败不得套用关闭方向的“本次已变更”。请求过程中维持既有 `changingHidden` / `CaptureControlGate` / host closed/busy 边界，不可因跨窗口状态刷新重复执行。

依据：[Main `toggleHidden/toggleCollection/applySettings`](../../Sources/RiftletApp/RiftletMain.swift)、[ScreenshotEntryHost `setEnabled/saveDefault`](../../Sources/RiftletApp/ScreenshotEntryHost.swift)、[RiftSettingsForm 保存回显](../../Sources/RiftletUI/RiftSettingsForm.swift)、[SetupPresentation](../../Sources/RiftletUI/SetupPresentation.swift)。

## 5. 设计建议、新默认与升级保留

| 场景 | 设计/原型值 | 真实 main / 保留要求 |
| --- | --- | --- |
| 推荐新用户场景 | 左中、3张、0%遮挡、6pt距边、72×56pt fit | 除0%遮挡外，接近当前结构体新建值；新main仍25%遮挡。不能把推荐场景用作升级reset。 |
| current场景 | `defaultConfig` 的27字段：包括25%遮挡、6pt、leftMiddle | 仅模拟结构体默认；真实首次启动会补具体屏幕ID/UUID，读取现存文件也可能是完整个性化值。 |
| legacy缺键场景 | nil placement、legacy source、14pt距边、合成屏幕身份 | 只有nil/legacy/14对应真实缺字段回退；原型21412/示例UUID仅为评审夹具。旧JSON显式保存的其他合法值仍优先。 |
| 恢复本页 | 修改本页草稿，再明确应用 | 不重置屏幕身份、其他页草稿、兼容字段、权限、暂停/隐藏、生命周期或反馈草稿。需合并最新请求配置，不能用完整defaultConfig覆盖。 |
| 系统减少动态 | 取消装饰空间运动并保留可理解状态变化 | 有效模式与已选模式分开；真正配置值仍按表保留，不能为减少动态改写arrival preference或27字段。 |

数字草稿、切页保留、关闭确认和失败后继续编辑是本设计目标。位置与显示、动效共用**全局配置草稿和一个应用动作**，应用会一起提交这两页的已编辑有效字段；恢复本页只改本页草稿，不清另一页更改。当前原生三项几何文本以Return/保存提交，滑块在结束追踪时提交；当前保存失败还会回显旧值。新设计保留未提交草稿并不意味着这些新语义已经存在于 main。无需从头重写设置持久层，但新增表单必须明确请求patch的字段归属和保存结果。

## 6. 原型与交接必须保留的界线

1. 审计起点原型的“精细显示/动效”把5个不生效兼容字段做成可编辑旋钮；终稿应将其移至兼容参考或清楚标为当前不驱动呈现。`emptyTraceLength`虽无控件仍要保留完整配置合法性；不要通过删除键解决。
2. `minimumHitWidth/Height` 的消费位置是真实行布局，不是扩大两个输入窗口的承诺。原型标签/说明须按第2节解释。
3. 起点原型`applyConfig`复制整份draft；全局草稿一起提交位置与显示/动效更改是已确认目标，不是跨页误提交。原生实施仍必须把这两页的已编辑字段合并进最新requestedConfiguration，保留即时保存的placement、placementSource、显示器ID/UUID和兼容字段，不能让旧草稿把它们覆盖。归档属于独立持久域，关闭时按明确流程处理；具体流程以最终INTERACTION-SPEC和实现交接为准。
4. 外观/登录项没有现成持久域，不能复用`rift-configuration.json`随意加键后宣称当前main支持；最终设计需明确其为新增偏好与OS动作。这里只列差异，不自行决定新key或注册策略。
5. 引导presented与设计completed不等价；书签允许访问与更改系统截图位置不等价；同一反馈草稿的诊断选择与全局永久同意不等价。应沿用各自实际owner。
6. 稳定原图、队列记录、UNKNOWN、反馈报告/能力、权限事实、截图原始位置均不属于“恢复默认设置”。不增加一键重传、文件删除或自动权限重置。

## 7. 审计覆盖与证据限度

本轮静态对照了全部27 CodingKeys及其初始化、解码、validate和生产读值位置；核对Main的保存/暂停/隐藏路径、Capture host及会话选项、SQLite metadata键、UserDefaults书签/首用键、反馈草稿与Keychain命名、系统权限及显示器fallback。现有prototype只读。没有执行App、真实权限请求、截图、文件保存失败注入或原生UI验收；上述“当前行为”来自明确源码路径，不包装成新的运行测试PASS。

后续实现以真实main字段和现有owner为依据，以[INTERACTION-SPEC](INTERACTION-SPEC.md)锁定交互；与[IMPLEMENTATION-HANDOFF](IMPLEMENTATION-HANDOFF.md)共同交接。只在设置呈现/偏好层落实本设计，不借配置迁移改动截图上传事实、历史保护或原目标绑定。
