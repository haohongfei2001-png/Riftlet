# 预测式截图入口与入缝动效：来源及实施审计

本文件是 2026-10-28 最终产品设计专项的只读源码审计；不批准新的视觉，不修改原生工程，也不构成真实 Mac、录屏权限、物理点击、透明穿透或上传验收。

## 1. 固定来源与优先级

| 来源 | 精确 SHA | 本轮地位 |
| --- | --- | --- |
| 正式工程 | `1920e0562db893a3292af89a89270a26ddb46a5f` | 已集成产品行为、安全边界及原生底座 |
| 预测式入口独立分支 | `5d6a683652d255af8c1d3e0d9533587fcc27a24d` | 有用户批准外观与交互的独立实现；本轮只读，不自动合流 |
| 无／磁力吸引设计分支 | `0b73291652c11f5cb7b6e2792d001eb3340c988b` | 两种模式获批；560 ms 等具体参数仍为设计候选 |
| 早期真实比例原型 | `8b2937e05c6ca2e4c33a7c59fd1dce0cca05f3aa` | 历史几何对照；其上传和空队列行为已过时 |

来源路径均相对于上述对应 Git 树。最新用户指令高于旧文档。本轮必须明确区分“截图入缝设置”和“上传开始后的快速吞噬”；旧两模式文档将 `none` 扩展为关闭 press/swallow/reflow/rebirth 的写法不能直接继承。

## 2. 必须原样保留的入口决定

预测分支 `design/capture-entry/README.md` 与 `docs/CAPTURE_ENTRY_2026-10-28.md` 将以下内容明确记为最新用户决定，而非设计者另提选项：

- 保留细窄中性玻璃、空间裂缝意象、相机锐利线条和向上展开；不是另造四枚独立浮动按钮。
- 相机线条与玻璃背景是两个独立 alpha 通道。线条更早、稳定、完整可见，不用图标模糊、缩放或横向滑入代替。
- 点击入口即开始默认模式，没有额外“开始／确认”按钮，输入不等待展开动画结束。
- 窗口／区域／全屏有固定物理槽。切换只更新语义与活动取消盖片，原模式图标不换位。
- 成功截图保留同一选择会话、当前模式和展开工具条，可继续截图；明确 X／Escape 才退出。
- 取消后收回原底部入口，保持当前实际光学值；附近仍可见，离开更远的退出范围才淡去，不闪灭后重现。
- 用户改变默认模式只影响下一轮会话。正在展开的目标不能在指针下重排。
- 已展开时，队列仍可操作；点击队列不穿透为另一次截图。

### 固定槽表（从底部到顶部）

| 默认设置 | anchor | near | far | more |
| --- | --- | --- | --- | --- |
| 窗口 | 窗口 | 区域 | 全屏 | 三点 |
| 区域 | 区域 | 窗口 | 全屏 | 三点 |
| 全屏 | 全屏 | 区域 | 窗口 | 三点 |

活动模式的槽立即变成取消动作；盖片是不可交互的视觉层，其移动不推迟按钮语义。原生来源：`ScreenshotEntrySession` / `ScreenshotEntryController.setMode`。

## 3. 入口真实实现参数

### 3.1 几何

来源：`Sources/RiftletUI/ScreenshotEntryModel.swift`、`ScreenshotEntryController.swift`。

| 项 | 原生分支实际值 | 说明 |
| --- | --- | --- |
| 主入口 | 36 × 36 pt | anchor 本身位置固定 |
| 展开玻璃 | 36 × 132 pt | `height = 36 + 3 × 32 × progress` |
| 上方命中区 | 30 × 30 pt | 每槽独立输入面板；不是整条面板吃点击 |
| 槽中心间距 | 32 pt | anchor、near、far、more |
| 配置默认 anchor | 屏幕右侧 32 pt，屏幕顶部以下 246 pt | Host 可基于队列提供实际位置，不能当通用硬编码 |
| 边界安全距 | 8 pt | `visibleFrame` 内夹取 |
| 装饰窗口余量 | 14 pt | 仅容纳阴影，完全穿透 |
| 圆角 | `10 + 2 × progress` pt | 单一玻璃表面 |
| 活动盖片 | 30 × 30 pt，radius 8 | 不移动基础图标与点击槽 |
| glyph | 17 pt footprint | 24 单位路径、stroke 1.65；实际视觉笔画约 1.17 pt |

展开 rail 完全放不下时 `ScreenshotEntryLayout.make` 返回 nil；该路径应在最终多尺寸规格中明确，而不是静默缩小全部 UI。

`ScreenshotEntryPreferences.initialLayout` 只在原配置仍为 `72×56 / rowPitch60 / outerInset8 / firstCenterFromTop180` 时，采用 `72×48 / rowPitch62 / outerInset14 / firstCenterFromTop332`。已有用户自定义值不覆盖。

Host 实际布局不是缩放 560 px 插画桌面：

```text
rowHeight = max(fitHeight, minimumHitHeight)
anchorY = visibleFrame.maxY − firstCenterFromTop + rowHeight/2 + 62
anchorX = clamp(visibleFrame.maxX − outerInset − 18,
                visibleFrame.minX + 26, visibleFrame.maxX − 26)
```

`anchorY` 再夹到 `visibleFrame.minY + 62 + padding + rowHeight + 1` 与 `visibleFrame.maxY − 122`。过短屏幕不把队列挤到消失，而把入口放到队列左侧，取消 header 限制。队列顶边在入口下方，裂缝仅有可见图片才显示；有图片时线可向上延伸到 anchor 上方 18 pt。

### 3.2 材质与色彩

原生采用 `NSVisualEffectView.material = .popover`、`.behindWindow`、`.active`。其实际外观随系统和背景变化，不能把浏览器固定 blur 18 px 等同于 AppKit 实际光学结果。

| 项 | 浅色 | 深色 |
| --- | --- | --- |
| 玻璃边线 | white alpha .58，0.75 pt | white alpha .20，0.75 pt |
| 阴影 | black alpha .13 | black alpha .22 |
| 阴影几何 | offset (0, −3) pt，radius 8 pt | 相同 |
| 盖片填充 | labelColor alpha .065 | labelColor alpha .10 |
| 盖片边线 | labelColor alpha .12，0.5 pt | 相同 |
| 正常 glyph | labelColor alpha .90 | 相同语义色 |
| 忙碌的非取消 glyph | labelColor alpha .35 | 相同 |

浏览器参照配色：`--rf-glass #f4f6facf / #282e3cdb`、`--rf-edge #ffffffce / #a3b2cd45`、`--rf-selected #d9dfe9aa / #67748d80`、`--rf-shadow #1f264233 / #00000050`；背景 blur 18 px、saturation 1.15。它们是审美参照，不是原生固定截图采样值。

### 3.3 双光学通道与预测

来源：`ScreenshotEntryOpticalConfiguration`、`ScreenshotEntryOptics`。

设 `d` 为指针到 anchor 的距离，`W` 为当前屏幕宽度。距离曲线使用 quintic smoothstep `S(x)=6x⁵−15x⁴+10x³`。

| 参数 | glyph | glass |
| --- | --- | --- |
| 完全可见距离 | .35W | .08W |
| 入场外半径 | .60W | .46W |
| 退出外半径 | 入场外半径 ×1.5 | 入场外半径 ×1.5 |
| 上升时间常数 | 18 ms | 96 ms |
| 下降时间常数 | 170 ms | 150 ms |
| 每60Hz帧上升限幅 | .26 alpha | .065 alpha |
| 每60Hz帧下降限幅 | .08 alpha | .06 alpha |

帧间隔夹为1–34 ms。每帧按 `Δ=(target−value)×(1−exp(−dt/τ))` 求增量，再施加独立限幅。记忆值与扩大退出场形成空间迟滞；不是鼠标停住后固定计时消失。

速度以 pt/ms 表示，28 ms 指数滤波。只有原始速度确实朝 anchor 时才预测；alignment 从 .5 到 .96 渐显，预计到达在180–700 ms间衰减，偏离路径按 `exp(−miss²/10000)` 衰减，速度 .02–.18 pt/ms渐显，最大空间门为 .82W–1.35W。预测记忆按240 ms衰减。预测只最多给玻璃 `0.18 × prediction`，不会把整个玻璃和线条一起提前点亮。

离队列命中矩形30 pt内，空闲入口可用性从0渐增，避免争抢微图注意力；展开／实际按下时两通道直接以1为目标。普通鼠标按住拖过桌面不触发空闲入口显示。

### 3.4 动效和中断

| 行为 | 原生 | 浏览器参照 | 统一规格要点 |
| --- | --- | --- | --- |
| 开合 | 180 ms quintic smoothstep | 同 | 从当前进度反转；剩余距离缩短时长，下限64 ms |
| X盖片迁移 | 100 ms quintic | 105 ms cubic-bezier(.2,.7,.2,1) | 两者尚不一致；最终明确一个值，不声称完全一致 |
| Reduce Motion | 开合／盖片直接到端点 | 有限 CSS 动效关闭 | 不延迟动作，不变成第三种模式 |
| 暂时自排除 | 保留alpha、展开进度、mode和session，shift clock | 合成源复制 | 曝光恢复不是新一次展开／入场 |

原生动画时钟仅未收敛时启动60Hz Timer，tolerance2 ms；收敛后停止，没有常驻闲置循环。

### 3.5 命中、无障碍、键盘与窗口

- 装饰 `NSPanel` 无边框、不激活、无原生阴影、透明，`ignoresMouseEvents=true` 且AX隐藏。四个真正输入区分开。
- 面板不成为key/main；`acceptsFirstMouse=true`。鼠标按下记录pressed，必须同一输入区内有效释放才调用；禁用／切换／隐藏会清除pressed，晚释放不能误触新动作。
- 入口是否可点依几何和角色，不等alpha或动画完成。空闲只在指针实际进入入口且不在队列范围时接鼠标；其余外部透明区域穿透。
- 每槽提供中文AX标签和tooltip；active槽标签立刻变成“取消…截图”。AX Press遵守可见／enabled条件。
- 默认floating；展开期间选择层为statusBar，入口和队列高一级。加入所有Spaces、fullScreenAuxiliary；这些是源码策略，不是实际Spaces已验收。
- 选择层只在主动截图时拥有本地键盘接收能力。Escape取消、菜单／标注暂停选择，关闭后需新的完整down/up；无全局快捷键截获、无旧点击回放。
- 曝光前短暂隐藏自身其他窗口，WindowServer确认不可见／透明才执行；不是`sharingType.none`或固定delay保证自排除。此技术机制也不能宣传所有普通系统截图都能排除Riftlet。

## 4. 磁力吸引：继承内容与未批准参数

来源：到达动效分支 `design/arrival-motion/two-modes/README.md`、`Riftlet-Arrival-Two-Modes.html`。

用户已明确只保留 `none` 与 `magnet`。尚未批准一个全局默认模式；旧原型初始none只是评审起点。

### 当前560 ms候选

| 阶段 | 时间 | 源码／设计参数 |
| --- | --- | --- |
| 原地凝缩 | 0–123 ms | 原图的非交互副本从至多240×150 pt缩到58×46 pt上限；保持比例；全屏截图不全屏闪烁 |
| 定向微颤 | 123–224 ms | 1.5次阻尼周期，主方向最大1.85 pt，tilt≤.008 rad；沿目标方向而非随机噪声；终点回到稳定源中心 |
| 加速吸引 | 224–484 ms | 近直线，归一化位移t²·²⁵；图像尺寸连续过渡到最终fit大小 |
| 穿过遮挡面 | 484–560 ms | 源副本完全被固定边缘遮挡后，目标图以outCubic落位；不瞬移、回弹、爆光或粒子 |

空间来源是可选信息。`kMDItemScreenCaptureGlobalRect` 只被提出为候选读取来源，Riftlet未证明所有macOS版本、截图类型、Spaces、多屏和Retina情形可靠。不能为动效截获系统截图快捷键或假装原图正在物理移动。

以下情况该次立即降为none：无可信源矩形、过期或不能安全转换的矩形、未验证跨屏变换、屏外路径、Reduce Motion、装饰overlay创建失败。保留用户magnet偏好；不增设第三种替代特效。

### 交互中断必须保留

- 从`assetReady`开始排队且可点击；560 ms只影响装饰，不延迟收录、原点击或上传。
- 最多一个源端飞行副本；新截图将旧装饰收束到最终图态，不移除旧资产，也不排队等动画。
- pointerDown立即取消该资产装饰飞行；hide/close/换代取消旧回调。动效回调不能复活或重排资产。
- 与click-time target、唯一输入、`uploadStarted`、最终完成、UNKNOWN的状态机独立。

## 5. 旧参照的明确冲突：不要机械复用

| 旧材料 | 发现 | 本轮处理要求 |
| --- | --- | --- |
| capture-entry `source.html`，更新alpha处 | `assets.length ? 1 : surfaceAlpha*.45` 使无图时仍有36px裂缝 | 新统一原型必须令裂缝本体仅在visibleCount>0出现；独立预测入口允许靠近显示 |
| capture-entry浏览器consume | 点击后约80ms退出，明确是synthetic示意 | 新原型须显式区分waiting与模拟uploadStarted；不能借用timer当真实准入 |
| 两模式README的none | 把到达选项扩展为关闭press、swallow、补位、重生 | 本轮最新要求已明确分离；在新决策账中公开修正范围，不能静默当用户批准 |
| 两模式交互源 | 有旧探索绘制辅助函数残留，但MODES只有none/magnet | 不再暴露或推荐任何淘汰模式；新稿只实现两个到达模式 |
| interactive-rift-v1 | 基于485fa87；240ms吞噬在`used`后开始、UNKNOWN可见双下划线、空队列24pt残线、动画时全队aria-disabled | 历史行为已淘汰；只可借鉴真实比例评审方法，不可继承状态机 |
| capture-entry README vs native | cover105ms Bezier／100ms quintic；HTML blur18／AppKitpopover；HTML三图分页／原生适配容量滚动 | 最终规格须分别说清来源与最终建议，不把模拟渲染视作原生实测 |

## 6. 可供视觉审阅的现有材料

- 预测入口：`design/capture-entry/Riftlet-Capture-Entry.html` 为可直接离线打开的完整HTML；`source.html`为可编辑源。Finder／Notes／壁纸／Dock是作者绘制的合成桌面，canvas捕获是局部白名单渲染，不读取OS画面。
- 预测入口图标：22个inline SVG，继承Lucide／Feather；对应`THIRD_PARTY_NOTICES.md`必须随复制保留。原生独立绘制固定路径，不应声称完全采用同一SVG。
- 两模式：`Riftlet-Arrival-Two-Modes.html`包含1440×900逻辑点canvas、分镜导出、源丢失／跨屏／减少动态的合成fallback。可作运动参照，不是本地屏幕录制影片。
- 旧比例评审：`design/prototypes/interactive-rift-v1/qa/Riftlet-Review-Immersive.jpg`、`Riftlet-Review-Workspace.jpg`及dist HTML；只是旧source视图。
- 正式树已有round-02 SVG/PNG/MP4：72pt直截、54/90比较、context与motion keyframes。它们未获最终视觉批准；不得把被淘汰round-01 B/C或弯曲开合方案复活。

## 7. 对统一主方向的实施建议（设计建议，不是新增用户裁决）

保留入口已批准的一面玻璃与固定空间关系，成熟度提升应集中在边线／盖片的光学一致性、glyph像素对齐、减少透明层叠加和全局type/spacing token，而非重新设计入口。

裂缝与入口无需画成一根可操作toolbar：入口负责主动capture、图片队列负责existing assets；两者共享一条稳定接触平面和材质语汇。无图时移除裂缝与队列，不为了入口而留下常驻痕迹。

磁力保持可说明的四段空间因果，优先验证端点位置和中断连续性，避免用更长时间或更大的晃动表现“物理感”。实际快速吞噬应继续以现有严格start事件驱动，作为独立短运动；成功只在原ChatGPT草稿体现，Riftlet不出现成功Toast。

物理鼠标、AX/WindowServer、真实自排除、多屏、系统材质和最终App体验均留给后续原生实施验证。本轮交互原型须持续标注合成行为，并用明确的开发演示入口展示安全失败／重试的未来状态；不能在模拟中暗示正式候选已经开放这些准入。
