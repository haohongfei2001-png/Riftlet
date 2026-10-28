# 现有原生界面审查 — 设计输入，不是原生验收

审查基线：`1920e0562db893a3292af89a89270a26ddb46a5f`。审查日期：2026-10-28（北京时间）。本文件仅由读取现有源码得出，没有启动实际 macOS App、没有重新上传截图、没有执行产品 CI，也没有改变任何准入。本轮只写入独立设计目录。

## 1. 核心结论

现有工程已经正确区分了可见队列、上传事实、内部历史和反馈的本地保存；这些语义应成为最终设计的底层约束。视觉尚未成为统一系统：裂缝使用可调的 R2 研究尺寸，首次使用是一张密集的状态长表，历史保留英文文本与表格布局，反馈又采用另一组字号与纵向堆叠。设计应重新安排层级、明确共同材质与间距、解决极端截图比例下的命中与识别，而不是重新实现上传。

两个容易在效果图中被掩盖的实际问题必须进入 100% 尺寸评审：

1. `minimumHitWidth/Height = 44` **没有为截图提供实际的 44×44 原生命中范围**。真正接收鼠标的是可见图片矩形和编号矩形，透明空间保持穿透。极端长图和极宽图会因此得到非常窄或非常矮的命中区域。
2. 当前正式工程没有悬停完整预览；只有系统 tooltip。历史设计稿中的“悬停约 320 ms 看完整图”不能被描述为已经实现。

## 2. 读取范围与来源

所有下列源码均以固定提交为依据，而不是动态分支链接：

- [RiftConfiguration.swift](https://github.com/haohongfei2001-png/Riftlet/blob/1920e0562db893a3292af89a89270a26ddb46a5f/Sources/RiftletUI/RiftConfiguration.swift)
- [RiftLayout.swift](https://github.com/haohongfei2001-png/Riftlet/blob/1920e0562db893a3292af89a89270a26ddb46a5f/Sources/RiftletUI/RiftLayout.swift)
- [RiftPanelController.swift](https://github.com/haohongfei2001-png/Riftlet/blob/1920e0562db893a3292af89a89270a26ddb46a5f/Sources/RiftletUI/RiftPanelController.swift)
- [RiftDisplaySelection.swift](https://github.com/haohongfei2001-png/Riftlet/blob/1920e0562db893a3292af89a89270a26ddb46a5f/Sources/RiftletUI/RiftDisplaySelection.swift)
- [ThumbnailCache.swift](https://github.com/haohongfei2001-png/Riftlet/blob/1920e0562db893a3292af89a89270a26ddb46a5f/Sources/RiftletUI/ThumbnailCache.swift)
- [RiftSetupController.swift](https://github.com/haohongfei2001-png/Riftlet/blob/1920e0562db893a3292af89a89270a26ddb46a5f/Sources/RiftletUI/RiftSetupController.swift)
- [SetupPresentation.swift](https://github.com/haohongfei2001-png/Riftlet/blob/1920e0562db893a3292af89a89270a26ddb46a5f/Sources/RiftletUI/SetupPresentation.swift)
- [RiftHistoryController.swift](https://github.com/haohongfei2001-png/Riftlet/blob/1920e0562db893a3292af89a89270a26ddb46a5f/Sources/RiftletUI/RiftHistoryController.swift)
- [HistoryPresentation.swift](https://github.com/haohongfei2001-png/Riftlet/blob/1920e0562db893a3292af89a89270a26ddb46a5f/Sources/RiftletUI/HistoryPresentation.swift)
- [RiftletMain.swift](https://github.com/haohongfei2001-png/Riftlet/blob/1920e0562db893a3292af89a89270a26ddb46a5f/Sources/RiftletApp/RiftletMain.swift)
- [ProductStatus.swift](https://github.com/haohongfei2001-png/Riftlet/blob/1920e0562db893a3292af89a89270a26ddb46a5f/Sources/RiftletApp/ProductStatus.swift)
- [ApplicationMode.swift](https://github.com/haohongfei2001-png/Riftlet/blob/1920e0562db893a3292af89a89270a26ddb46a5f/Sources/RiftletApp/ApplicationMode.swift)
- [FirstUsePreferences.swift](https://github.com/haohongfei2001-png/Riftlet/blob/1920e0562db893a3292af89a89270a26ddb46a5f/Sources/RiftletApp/FirstUsePreferences.swift)
- [LifecycleSettings.swift](https://github.com/haohongfei2001-png/Riftlet/blob/1920e0562db893a3292af89a89270a26ddb46a5f/Sources/RiftletApp/LifecycleSettings.swift)
- [FeedbackWindowController.swift](https://github.com/haohongfei2001-png/Riftlet/blob/1920e0562db893a3292af89a89270a26ddb46a5f/Sources/RiftletFeedbackUI/FeedbackWindowController.swift)
- [FeedbackHost.swift](https://github.com/haohongfei2001-png/Riftlet/blob/1920e0562db893a3292af89a89270a26ddb46a5f/Sources/RiftletApp/FeedbackHost.swift)

预测式截图入口属于独立开发分支，不在这个正式基线的 UI 中；其固定槽位、取消盖片和预测规则由同专项的入口审查单独记录。设计不能声称该入口已正式合流。

## 3. 裂缝：现有几何与绘制

`RiftConfiguration` 文件头明确称当前 R2「直截」只是起点，不是已批准的最终视觉规范。下表记录实际默认值，不把它们提升为用户裁决。

| 参数 | 现有值（逻辑 pt，除特别说明） | 实际意义 |
| --- | ---: | --- |
| `fitWidth × fitHeight` | 72 × 56 | 原图等比 fit 的最大包络，不是统一裁剪卡片 |
| `hiddenFraction` | 0.25 | 原图的右侧 25% 被固定边界遮挡，可见 75% |
| `rowPitch` | 60 | 实际 pitch 取 `max(rowPitch, max(fitHeight, minimumHitHeight) + 4)` |
| `lineWidth` | 0.7 | 一条笔直竖线；无波形、曲线、开合 |
| `lineExtension` | 8 | 首尾行外各延长 8 |
| `outerInset` | 8 | 边界位于选定屏幕 `visibleFrame.maxX - 8`；非整个屏幕 frame 的固定 8 |
| `firstCenterFromTop` | 180 | 首图中心的偏好位置距 visibleFrame 顶 180；多图会为容纳底部向上移动 |
| `screenPadding` | 12 | 上下保留空间 |
| `numberFontSize` | 11 | 系统等宽数字，regular，secondaryLabelColor |
| `numberGap` | 6 | 编号右边到可见图片左边之间的透明间隔 |
| `leftPadding` | 4 | 绘制行的左侧留白 |
| `minimumHitWidth/Height` | 44 / 44 | 仅用于行几何包络；实际鼠标窗口并没有覆盖该包络 |
| `emptyTraceLength` | 24（仅解码旧设置） | 零图时被明确忽略，lineFrame 归零 |

`RiftLayout.fit` 计算 `s = min(72 / pixelWidth, 56 / pixelHeight)`；全图尺寸为 `(pixelWidth × s, pixelHeight × s)`，不对小图片禁止放大。全图右部置于遮挡边界之外，`imageClipFrame.width = fullWidth × 0.75`。

在默认值下，不同原图的实际可见和点击尺寸如下。这是由源码公式直接计算的几何，**不是实际鼠标验收**。

| 原图比例 | 完整 fit 尺寸 | 可见图片 / 图片输入窗口 |
| --- | ---: | ---: |
| 16:9 横图 | 72 × 40.5 | 54 × 40.5 |
| 4:3 横图 | 72 × 54 | 54 × 54 |
| 1:1 方图 | 56 × 56 | 42 × 56 |
| 3:4 竖图 | 42 × 56 | 31.5 × 56 |
| 9:16 竖图 | 31.5 × 56 | 23.625 × 56 |
| 1:8 长图 | 7 × 56 | 5.25 × 56 |
| 8:1 宽条 | 72 × 9 | 54 × 9 |

一位编号宽按 `11 × 0.65 = 7.15` 估算，高为 `11 + 2 = 13`；两位编号宽 14.3。编号与图片都可点击，但两者间的 6 pt 空隙不属于命中范围。

队列容量由 visibleFrame 高度决定，最大高度不由“典型 2–3 张”硬编码。首槽中心会在偏好位置、顶部限制和容纳整个队列所需的底部限制之间夹取；因此从少量图增长到大队列时，首图可能向上移，不是无条件稳定的 y=180。溢出时不删除旧截图；新增截图会移至可见分页尾部，滚轮累积 8 单位后按一行滚动。已有“最早 / 最新”菜单操作。

### 材质与空间感的现状

- 微图直接绘制原始缩略图，没有统一卡片背景、圆角、边框、阴影或玻璃材质。
- 编号为 `secondaryLabelColor`；裂缝线是 `secondaryLabelColor × alpha 0.48`。目前只是创建时给 layer 设置 CGColor，没有单独的材质系统或背景对比策略。
- transferring 在编号下绘一条 0.7 pt、最长 8 pt 的小横线；unknown 绘两条，第二条再向下 3 pt。missing 用 tertiaryLabelColor 画 0.7 pt 的轮廓。
- 这些极小状态记号没有独立的解释面板；文字通过 tooltip / AX help 和运行状态窗口表达。
- 没有悬停放大、完整图预览、悬停展示文件名、可见删除按钮或拖动排序。
- 系统完整标题栏、系统字体和语义色存在于辅助窗口，但裂缝尚无与其共享的 token。

### 必须保留的窗口与鼠标模型

`RiftPanel`：borderless + nonactivatingPanel；不成为 key/main；透明、无阴影、floating；`canJoinAllSpaces / fullScreenAuxiliary / stationary / ignoresCycle`；不随 App 失活隐藏。代码故意不使用 `sharingType.none` 冒充截图排除保证。

每一行实际有三个 NSPanel：一个绘制/AX 容器和两个鼠标输入岛。绘制容器始终忽略鼠标；图片输入岛精确覆盖 imageClipFrame；编号输入岛精确覆盖 numberFrame。裂缝线独立装饰窗口也忽略鼠标。不要用一个覆盖整个队列的透明大 NSPanel 替代它们，也不要把拒绝命中误当成对底层 App 的事件穿透。

图片的 alpha 透明像素仍处于图片矩形输入岛内；目前未做逐像素 alpha hit testing。宽高尺寸、行间空白、图片与编号间空白以及真正透明像素必须分别评审，不能写成同一个“透明区域已穿透”结论。

## 4. 动效与中断：现有行为

| 场景 | 当前行为 | 当前参数 |
| --- | --- | --- |
| 新图出现 | 三个行窗口从 alpha 0 到 1；不是源头磁力飞行 | 220 ms |
| 按下 | 图片向裂缝内平移，easeOut | 2.5 pt / 80 ms |
| 松开、拒绝或等待 | 回到 0 偏移；不永久保持按下姿态 | 180 ms |
| 已持久记录 uploadStarted 后吞噬 | 图片向右移 `clipWidth + 2`，三个行窗口同时淡出，随后关闭 | 120 ms |
| 补位 | 所有行及两个输入岛一同移动，easeOut | 180 ms |
| 可见 failed 更新 | 同返回动画；新建行仍走出现淡入 | 180 ms / 220 ms |
| Reduce Motion | 每个动效取 `min(正常时间, 100 ms)` | 仍有位移；目前不是完全消除空间运动 |

`animateImage` 从 CALayer presentation 层当前位置读起，支持中途切换目标而不从旧模型值跳回。CALayer 位移动画使用 easeOut，窗口 alpha 动画没有自定义 timingFunction。补位动画结束后才调整两位/一位编号几何，防止 10→9 的途中横向跳动。

显示组件只能读取已提交的可见性；只有 `.swallowed + .uploadStarted` 且前态可见才启动吞噬。最终 succeeded 不重复动画。hold / selection / transition 时会延迟投影，并在安全边界合并最新 snapshot；generation 防止隐藏、重排或销毁后旧计时器重新显示窗口。

现有设计改动的正确接入点是参数、绘制层和已有呈现事件，不能通过“动画播完”“收到点击”或“等待了某个时长”创造 uploadStarted 或 success。

### 原点击和连续点击保护

- 点击需 clickCount==1；共享 gate 抑制 doubleClickInterval 内、距上一点≤4 pt 的替补行二次选择。
- mouseUp 跟随原 down 窗口，重新检测原截图的图片/编号联合范围，不检测松开时替补到指针下的另一张。
- selection visibilityRevision 在异步操作前冻结；已接受选择在 durable prepare 或确定取消前保持保护。
- App 用 selection owner 和 visibilityRevision 保护异步反馈更新；清除等待反馈仅删除精确匹配的旧文字，不能擦掉较新的取消/错误。
- 在转场期间当前实现拒绝新的 row selection。设计可以缩短、简化呈现阻塞，但不能为了演示“连续点击”跨越真实 gate 或添加自动重试。
- 归档保护覆盖 hover、mousedown、selected、菜单、动画；屏幕变化/唤醒也不允许绕过已延迟的归档。

## 5. 首次使用与运行状态

现有 `RiftSetupController` 是一个普通、可缩放、可最小化 NSWindow，初始内容 610×660，最小 window size 560×440，标题“Riftlet — 开始使用与运行状态”。居中打开；仅首次普通使用或用户主动菜单动作激活 App，刷新状态不会前置窗口。

布局是一个可滚动竖直 NSStackView：外边距 20，元素间距 9，标题 20 semibold，分组标题 12 semibold，正文 12，隐私和路径 11（路径等宽）；动作按钮行间距 8。底部固定“重新检查 / 完成”，右边距20、底边距14；Return 是“完成”，首次焦点也在完成。

分组及能力：

1. 截图来源：实际系统截图位置、目录读取状态、查看位置、主动授权当前位置。
2. 显示与待核实记录：可见数量、隐藏状态、pending数量、隐藏/暂停/历史。
3. 当前附件能力：普通本地模式/内部候选/合成验收明确区别；Chrome权限独立；完整支持范围长说明。
4. 本机存储：默认未测量，用户主动测量逻辑文件大小；不足/不可用准确区分。
5. 关闭窗口只记录呈现/关闭，不构成权限授权或上传同意。

状态模型很好地分离了“收录开关开着但来源不可读”“用户明确暂停”“无图”“隐藏”“权限允许但目标尚未验证”“普通模式未启用上传”。这些是新设计的信息基础，不应浓缩为一个含糊的绿色“已就绪”。

视觉改进机会：将首次使用的两个或三个必要动作与日常运行状态分开呈现，使用同一窗口组件但有明确页面层级；长支持说明移到可展开的准确范围，而非主画面全量堆叠。任一折叠都不能隐藏当前阻断原因、范围或下一步动作。权限按钮必须是主动操作，不能随动画或进入页面自动触发系统授权。

## 6. 内部历史

现有窗口720×500，最小560×340，标题英文“Riftlet — Screenshot History”。上方搜索与过滤，下方标准 NSTableView 和操作行。外边距16；搜索至少250；图片列固定92；描述列最小320；行高68，行间隔2；图片上下边距6、左右8；预览实际最大76逻辑像素乘 backingScaleFactor。标题12，副标题11，cell内部间距5。交替行背景、bezel边框；没有统一玻璃或卡片样式。

数据只读取一页最多200条，搜索只针对本页；日期/ID/文件名/序号/状态/尺寸/详情可匹配，不做图片内容检索。支持“全部、待核实、已吞噬、已归档、已失败、已移除”；页面文字目前全部英文。双击调用Finder定位，不上传。

三项主要操作：Show in Finder、Return to Rift、Remove from Rift。恢复只作用于获 Core 允许的 archived/removed 且 pending/failed 条目；存在操作时必须匹配当前 failed 操作。used/unknown/swallowed 不获得新恢复或新输入授权。界面中不能为了“历史体验完整”把这些条目均做成可重新附加。

历史的 confirmed failure 判定会同时检查原 operation/asset/attempt/target/hash、definitiveFailure、hasError、safeToRetry、belongsToOriginalDraft、not uploading/not positiveReady。单纯 `.failed` 可能是输入前取消，不可显示为已发生的远端上传失败。最终设计至少应区分：本机未附加、附加处理中、结果待核实、已附加、明确失败可再次点击、原件不可用。

改进机会：统一中文与语义图标；用稳定预览+时间+状态为主，技术ID按需显示；给UNKNOWN准确解释并保持无重试动作；明确搜索本页而不是假装全库；用当前Core资格驱动动作，不把颜色当权限。

## 7. Feedback v0.1

当前窗口560×560，最小500×520；标题“反馈与建议”；外边距20，纵向间距12。标题16semibold；正文输入14；状态12；隐私11secondary。正文最小150高，内边距8，原生纯文本NSTextView；不富文本、不导入图片、不自动引号替换。类型“遇到问题 / 改进建议”。

基本结构：标题→类型→正文→单次诊断勾选→诊断预览→隐私说明→状态→保存并关闭/发送反馈→已有记录下拉→查看/刷新/取消或删除→移除已解决本机正文。

这是一组完整的功能，但主次操作在单一页面连续堆叠，“写反馈”“浏览记录”“数据删除”三种不同任务没有视觉分层。成熟版本宜保留一个主编辑区，将记录与生命周期操作放到明确的次级区域或页面，而不删除任何已有能力。

### 绝对要保留的行为

- 草稿编辑后120 ms自动保存；revision保护防止旧保存结果覆盖较新状态。
- 点击关闭和“保存并关闭”都走同一异步保存；保存失败不能假装关窗成功。
- 第二次打开再关闭仍必须保存；不能用一次性的mayClose标记绕过。
- 保存/退出期间锁定文字、类型和诊断编辑；成功后退出流程仍需等outbox stop和clean mark。
- IME marked text存在时不提交、不关闭；Return留在编辑器，不是提交快捷键。
- 诊断默认不选；勾选时冻结当时的白名单快照，之后新事件不悄悄加入本次提交。
- 用户主动提交才enqueue；关闭不发送。
- `FeedbackHost.endpoint = nil`，实际使用DisabledFeedbackTransport；目前只能本机保存待发送，不能画出服务端接收、Issue创建或“开发者已收到”。
- 记录和Keychain命名空间独立；删除反馈不会改任何截图。
- 未尝试发送的queued可取消；已投递/尝试过的记录走删除申请；只有cancelled/deleted才允许移除本机正文与凭证。
- 文本上限4,000 Unicode字符且16KiB；错误时原文保留。

现有按钮在未配置服务时仍叫“发送反馈”，虽状态文案准确，主按钮意图可进一步统一为“保存待发送”，并持续显示“服务尚未连接”。这是呈现分支，不是部署或修改投递语义。撤销/删除的二级动作应随选中记录的真实状态给出明确文案，避免对一条从未发出的本地记录展示不必要的云端删除说明。

诊断预览目前580×420，12等宽字体，可滚动只读文本。最终设计可以用更有层级的可读预览，但不能隐瞒待发送内容或加入默认勾选。

## 8. 菜单栏、暂停、隐藏和设置

菜单栏当前为可变长度文字：Riftlet / Riftlet SIM / Riftlet WEB TEST / Riftlet REAL TEST；没有已冻结的品牌图标。内部候选标识必须在新设计中保持清晰，不能只因美化改成与生产无差别的普通品牌状态。

现有菜单同时放置运行状态、反馈、文件权限、候选说明、隐藏、暂停、历史、清空、归档、最早/最新、检查、存储、演示和工程调校。没有独立设置窗口；几何参数需要打开JSON。闲置归档为NSAlert+220×24文本输入，可填小时，0关闭；当前默认24h被源码明确称为工程起点，不是用户最终保留时长。

分层建议：保留系统NSMenu触感与键盘行为，把每日动作（历史、暂停/继续、隐藏/显示）集中在上层，把显示、截图入口、动效、归档与权限状态集中到一个原生设置窗口。实验/工程入口放到底部的内部构建组，不能从内部版本删去必要的范围说明，也不能增加普通生产开关。

隐藏与暂停必须始终独立：隐藏立即生效且持久化；显现要等持久写成功；暂停会停止新收录并持久化；新图、唤醒和错误不得偷偷反转隐藏/暂停意图。清空只改变可见性，不删除本地文件，也不删除ChatGPT附件。设计切换不能把“清空可见队列”变成“清空历史/删除文件”。

## 9. 辅助功能、对比与适配

已有：系统字体和语义颜色；普通窗口可缩放；大部分控件AX标签；裂缝作为按钮；input islands从AX树隐藏、绘制行作为唯一AX元素；非激活点击保留ChatGPT前台；图像缓存以实际backingScaleFactor生成；有屏幕断连fallback；Reduce Motion读取系统偏好。

尚未形成完整设计：中文AX/tooltips统一；高对比/减少透明度专用token；减少动态时用无空间位移替代，而不只是缩短；极端比例图片的可达性；焦点/按下/等待/取消状态的多通道区分；长文本和较大系统文字测试；全键盘访问和VoiceOver实际使用验证；跨屏/旋转/Spaces的完整视觉评审。

可落地要求应写成明确规则：焦点环只在键盘/AX交互时出现，不让普通鼠标获得额外chrome；语义不能只靠青色或琥珀色；说明不能只在悬停才能读取；原生重要窗口保持可复制文本和明确焦点顺序；无图时连装饰和无效输入窗口也清零。

## 10. 当前源码到最终设计的建议实施边界

| 层 | 可以在后续视觉实现中改变 | 必须保持 |
| --- | --- | --- |
| RiftConfiguration / Layout | 经批准的尺寸、边界、行距、像素对齐；准确的新token | 等比显示或明确裁剪策略；屏幕边界；零图零线；不丢资产 |
| RiftPanelController | 绘制、材质、动效曲线、反馈呈现、已批准的预览 | 非激活；原点击/selectionRevision；真实input islands；generation中断；状态只读投影 |
| RiftSetupController | 首次使用和状态分层、排版、图标、统一控件 | 主动权限；不自动前置；真实范围与错误区分；隐藏/暂停独立 |
| RiftHistoryController | 中文、版式、局部信息层级、动作层级 | 200条分页事实；Core资格；UNKNOWN无重试；Finder定位不上传 |
| FeedbackWindowController | 统一窗口、编辑/记录层级、未配置状态文案 | 草稿/关闭/重开/IME/单次诊断/显式提交/删除语义 |
| RiftletMain / ProductStatus | 以最小接线输出视觉token或组件状态 | owner/revision保护；Feedback全部hooks；原target/ACK/原点击；闭集文案映射 |
| Core / Adapters / Capture / SQLite /准入 | 本设计专项不改 | 全部现有安全与数据语义 |

后续实施应以当前最新正式分支重新核对共享文件，而非把整份旧Main覆盖进去。设计原型必须用合成状态、明确注明模拟；失败重生和重试可以作为目标状态演示，但现实准入仍关闭，不能借设计演示解除UNKNOWN或自动补传。

## 11. 原生实施前值得集中解决的有限问题

1. 在实际桌面比例下完成72级微图及极端宽高比的选择；任何扩大命中必须和可见设计一致，并仍保留空隙穿透。
2. 统一色彩/字体/材质/图标/间距，优先修正历史的英文、设置的密度和反馈的任务层级。
3. 磁力只用于截图入缝；上传开始的120ms快吞噬是独立生命周期动作，不受“无入缝动效”误关，也不等待磁力动画。
4. 等待/无效点击只给轻反馈；最终成功无Toast；UNKNOWN只在历史解释。
5. 不用展示更漂亮的动画掩盖真实工程缺口：无ACK冷首击、物理鼠标、跨屏/全屏、截图自包含、系统浮动缩略图协同仍各自需要真实证据；设计不替它们签字。

本次审查不建议再跑常规上传回归。设计完成后，原生实施阶段应针对发生变化的几何、动画、辅助功能和窗口生命周期做有限而真实的验证，再进入创始人的实际体验。
