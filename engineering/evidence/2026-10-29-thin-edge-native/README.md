# 「薄界」原生实施候选 — 2026-10-29

已实现可运行的 AppKit 候选，**不是创始人最终视觉批准或发行验收**。本轮只验证原生呈现与输入边界，没有重做/重测真实上传，没有启用普通生产、safe failure 或 retry。

## 固定来源与交接

- 独立分支：`codex/riftlet-real-mac-acceptance-thin-edge-20261029`。
- 正式起点：`1920e0562db893a3292af89a89270a26ddb46a5f`。交付前只读核对正式远端已到 `0e7ea8be148e1124b387e799fd886a7830e96559`；未覆盖、合并或重置该分支/PR #1。
- 设计：`7e03bd2c26c6aa43dbac07b073e00d08d1951b71` 的 `design/final-system-20261028/`，以原字节留存。已阅读 HANDOFF、SOURCE_DELTA、APPKIT_SPEC、TOKENS、MOTION_SPEC，并运行独立交互原型作对照。网页未进入 App bundle。
- 按祖先合入预测入口 `5d6a683652d255af8c1d3e0d9533587fcc27a24d` 和入缝基础 `d552a7388af3890bf693bb3fb24f4b8fc5bc12e7`；没有重建入口、Presenter 或上传机制。
- 主实现 `46a909a35df16b76b6153fcb772a48740fb07ac6`；位置修复 `888a4b0075bc8faf944a3e7a75ebd9a7a7ff3acf`；最后原生源码 `ad4854c849448bb37c387528bddf673732d8e362` 补齐预览淡入、入口像素描边/动态Reduce Motion和主动重开引导。
- 审查后的完整树、CI 与最终交接提交见 [results.json](results.json)。正式 Pro 应按最新正式头审查组合，重新固定其组合树；不要把本分支 pin 直接当作未来正式树的批准。

## 五阶段实际结果

| 阶段 | 已完成 | 限定结果 |
| --- | --- | --- |
| 统一视觉 | 共享浅深颜色/字体/间距；首次使用三页、设置五组、三栏历史、Feedback 和入缝偏好；保留原生标题栏及系统菜单 | PASS 原生窗口绘制；菜单接线源码复核，未做完整菜单人工遍历 |
| 裂缝/微图 | 每屏 visibleFrame 固定首槽202pt、外14pt、60pt节距、1/backing hairline；实际编号宽度；极端比例可见编号垫片；原生分页及完整等比 hover 预览 | PASS 2x 横屏/90°竖屏、极端横竖图、16图分页；不代表所有分辨率 |
| 预测入口 | 复用固定模式槽、移动取消盖片、光学通道与系统捕获接线；中心对齐为 E−18/C0+66；旧默认锚点迁移，用户自定位置保留 | PASS 原生展开布局；本轮未调用真实捕获，连续真实截图和系统浮层协同 NOT_RUN |
| 入缝动效 | 复用 source geometry、偏好与可中断 Presenter；123/101/260/76ms 四相；none 与上传后吞噬分离 | PASS 合成输入事实驱动的真实 AppKit 录屏；缺失源静态，Reduce Motion 无空间飞行；不是 OS 来源证明或真实上传证据 |
| 整体品质 | 100%逻辑尺寸绘制、原像素截图、浅深主题、编号/透明区路由、按住补位、双击替换保护、动画取消 | PASS 限定软件原生验收；人工、VoiceOver、真实 Spaces/全屏/跨应用焦点仍 NOT_RUN |

## 修复了哪些实际问题

- 原布局以队列长度和入口位置挪动第一槽；现在首槽稳定，只有真实溢出才保留分页空间。分页器使用两个独立箭头输入岛，计数与背景不截获鼠标。
- 极端窄/扁图不扩大不可见命中区，改用明确可见的编号垫片；完整预览保持原比例且全窗口穿透。移除普通 tooltip，避免与完整预览叠加；450ms停留后80ms淡入，离开100ms后80ms淡出。
- 同图重新悬停、迟到解码、分页/几何变化时取消旧预览；截图隐藏后分页器恢复；隐藏期间的迟到磁力解码不能重新显示浮层。
- 补位动画中按下仍冻结原 asset 和原释放区域；10→9 时保留旧行宽度/编号直至动画末尾，遮挡面不漂移。
- 入口玻璃描边按实际backing更新至1物理像素，浅/深白色alpha .48/.14；提高对比度为1pt实色。系统Reduce Motion变化立即结束入口及取消盖片的空间插值；不改session/捕获/输入。透明度交原生材质处理，系统选项动态实机切换尚未验收。菜单增加主动「使用引导」入口，不自行请求权限。
- 原生 Auto Layout 曾使初次窗口超出目标尺寸，短内容被推到底部；已按标题栏外框恢复尺寸并顶部对齐。后续用户缩放及合法跨屏摆放保留，完全离屏才恢复到屏内。
- 磁力时间基准固定在 assetReady，图像解码/建窗延迟不重启560ms。取消/隐藏/真实状态变化均可抢占装饰，来源不可信仍静态降级。
- 接线只修改呈现与现有入口：未改 Web、Chrome、QueueStore、Coordinator 或 Feedback 存储/传输。继承预测入口的 Core 小增量仅增加 `applicationScreenshot` 来源及拒绝借用开始/完成/重试准入，不扩大权限。

## 原尺寸窗口与 WindowServer 证据

环境：Apple Silicon、macOS 27.0 (26A428)、本地 Swift 6.4。横屏1920×1080逻辑点@2x；左侧旋转90°屏800×1280@2x，负坐标原点。截图由 WindowServer 直接产生，未缩放；在1图像像素=1显示像素的查看器中检查，不能以 Markdown 自动缩略图判断尺寸。

| 外框 | 浅色 | 深色 |
| --- | --- | --- |
| 首次使用560×520 | [截图](screens/setup-light.png) | [截图](screens/setup-dark.png) |
| 设置680×520 | [截图](screens/settings-light.png) | [截图](screens/settings-dark.png) |
| 历史760×560 | [截图](screens/history-light.png) | [截图](screens/history-dark.png) |
| Feedback600×540 | [截图](screens/feedback-light.png) | [截图](screens/feedback-dark.png) |
| 入缝偏好468×372外框 | [截图](screens/motion-light.png) | [截图](screens/motion-dark.png) |

[浅色长队列](screens/queue-light16.png) · [深色入口/队列](screens/queue-dark16-entry.png) · [旋转竖屏](screens/portrait-retina.png) · [极端竖图完整预览](screens/extreme-hover-safe.png) · [末页3–16/16](screens/pager-last-page.png)。原生窗口尺寸见 [windows.json](windows.json)，每个文件的来源 SHA、原像素尺寸和 SHA-256 见 [asset-manifest.json](asset-manifest.json)。

截图/影片均为既有 GUI helper 调用真正产品 controller、panel、Presenter，素材为合成图。为防止其他应用内容进入公开证据，helper 的 `visualClean` 使用不透明 floating 背板，并仅在 helper 内提高辅助窗口层级。**这个隔离不属于产品代码，不证明跨应用前台/焦点或产品层级正确**；产品正常层级未据此改动。

## 动效与路由

[磁力](motion/magnet.mov) · [无入缝](motion/none.mov) · [减少动态](motion/reduce-motion.mov) · [途中取消](motion/interrupt.mov) · [缺失来源](motion/missing-source.mov)。每段约8秒、3840×2160原像素、无音频、可变帧率。不是设计影片：来自真实 WindowServer/AppKit；业务事件则明确是 `syntheticOnly=true, receiptEvidence=false` 的 helper 投影。

原始单调时钟回调经白名单脱敏保存在 [motion-timing.json](motion-timing.json)。计划吞噬120ms；实际 AppKit start→close：磁力126.426ms、none126.935ms、取消127.338ms、缺失源129.620ms；Reduce Motion 配置80ms，实际87.980ms。调度尾差单独保留，不以这些数据宣称点击到上传或截图收录延迟。磁力装饰 started→ended 545.014ms；该区间不含开始前解码和已经流逝的 ready 时间，不能替代560ms设计总时钟。none 没有入缝飞行，仍独立执行开始投影后的快吞噬；最终成功投影没有第二次动画。

[软件路由证据](software-routing.json)：IMAGE/NUMBER各1次 down/up、原 asset 各选择一次；CLEAR/GAP底层各收到1次 down/up、选择0次。按住时布局稳定，释放后选择原第二图，补位正确。双击替换测试间隔153.304ms，第二个事件显式携带 `clickState=2`，新补位图选择0次。它验证产品防重复保护，**不是操作系统自动双击分类或人工物理输入**。焦点检查限于 helper 的键盘接收窗口；跨应用 NOT_RUN。

## 构建、自动化与非作者审查

- 最终源码本地完整 release App build PASS；bundle布局、权限文字、资源、许可检查 PASS；包内 `--self-check` PASS。开发 ad-hoc 签名，未公证/发行。
- 本机仅 CLT SDK，`swift test` 无法解析 XCTest：本地全套 NOT_RUN（前置条件缺失），不是测试通过。完整原生 XCTest/离线 Web/Feedback/打包由独立 macOS CI执行，状态见 results.json。
- 21项临时 Git fixture 的组合审计正反例 PASS。三份历史审计按原 blob 在原 SHA 执行，原脚本保持不变；新 gate 固定完整独立审查树，只允许 gate自身及两条明确的交接元数据作为后续更新，拒绝新文件/删除/改mode/symlink等。
- 原 d552 的两条 CI `40717446445`/`40717446400` 未获 runner，0步骤取消；这不构成源码失败证据。其原源码已单独完整本地构建 PASS。新组合实际编译、测试错误以本次 CI 为准，不刷旧运行。
- 非作者：thin_windows审查 motion/Main，thin_acceptance审查Panel/pager/peek与选择边界，thin_motion审查窗口/Feedback/Main及最终888a4b0。发现的迟到overlay、预览回返、10→9宽度、分页恢复、错误失败文案、初次尺寸和跨屏重开问题均修复；ad4854c最后小修经thin_motion非作者复审无阻断；窗口/CG证据保留46a909a来源，五段录屏保留888a4b0来源，入口/队列/hover/pager四图在ad4854c重拍。888a4b0 的跨屏重开修复已源码复审，本轮未再进行物理跨屏拖动复测。没有把源审查写成实机人工通过。

## 已知差异与剩余验收

新精确参数（14/202/60、编号垫片、450ms预览、窗口组织、颜色、160ms补位等）仍待最终视觉裁决。设置中的入缝偏好仍打开既有独立窗口，截图入口选项仍打开原生菜单；没有新增显示器选择控件，归档配置仍在菜单，尚非全部设置内嵌。普通与高对比/减少透明度动态切换仍需系统实机验收。1x/其他分数缩放、真实多屏切换/拔插、全屏、Spaces、VoiceOver完整操作、系统辅助功能实时切换、真实鼠标及最终正式组合App跨应用焦点，本轮 NOT_RUN。历史完整预览继续复用既有768px缓存，超大Retina预览的清晰度未扩大保证。安全失败重生仍未准入；没有为视觉验收启用。

系统截图自包含、无ACK冷首击、真实上传速度、MID、旧UNKNOWN观察和生产端到端均没有在本轮重测或改判。没有向用户请求重复上传或创始人体验。没有安装浏览器扩展、部署Feedback云端、发送消息或新增生产profile。

## 数据与复现

历史工作树、真实系统PNG/私有媒体、候选SQLite v3、旧UNKNOWN/锁/补偿/审计未打开供本轮GUI写入，也未清理、迁移、替换。helper只使用独立临时合成 fixture；Feedback使用临时 sidecar、内存secret和DisabledTransport。私有原始取证日志保留，公开仅合成画面和白名单字段/哈希；未提交用户系统截图、聊天正文、目标/浏览器身份、路径、数据库或原始日志。

在本分支构建后，既有 helper 可复现：

```sh
bash scripts/build-macos.sh
.build/release/RiftletGUIAcceptance --self-check
.build/release/RiftletGUIAcceptance --visual-clean --visual-scene 16 --appearance dark --visual-entry --visual-entry-expanded
.build/release/RiftletGUIAcceptance --visual-clean --visual-scene 3 --appearance light --visual-window settings
.build/release/RiftletGUIAcceptance --visual-clean --visual-timeline --visual-magnet
.build/release/RiftletGUIAcceptance --software-pointer-probes
.build/release/RiftletGUIAcceptance --software-hold-probe
.build/release/RiftletGUIAcceptance --software-double-probe
```

界面和软件鼠标命令必须串行，且独占桌面；均不上传。可选 `--visual-reduced-motion`、`--visual-cancel-arrival`、`--visual-missing-source` 及本机有效的 `--probe-display-id`。候选 `build/Riftlet.app` 交正式 Pro 组合与独立质量验收；不得按本视觉证据直接开放生产上传或发布。
