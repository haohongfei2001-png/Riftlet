# 第七轮：既有 GUI helper 软件坐标命中协议

本文件是 helper 实现和可运行协议，不是 GUI 结果。root 是唯一 GUI、浏览器及真实数据库操作者。这里没有启动 GUI、发送指针事件或改变正式 Core/App/UI。人类物理输入仍为 **NOT_RUN**。

## 已有入口与本轮最小增量

- 无参数：启动既有 synthetic-only helper、3 图、底层 ClickProbe 和文本框。
- `--self-check`：现有合成 PNG/layout/status 自检，本轮另调用坐标变换和 routing verdict 纯夹具；不执行 GUI。
- `--press-acceptance-asset UUID --app-pid PID --app-path exact.app`：现有一次 AXPress，不能用于 CLEAR/GAP 穿透验收；本轮未改。
- 新 `--software-pointer-probes`：在既有 helper 启动后运行一次 IMAGE / NUMBER / CLEAR / GAP 批次；也可在 helper 菜单选择 `Run Software Pointer Probes (once)`。每个进程最多一批；整批开始时最多一次对齐既有 helper 控制窗以覆盖实际 row，不移动产品 panel。
- 新菜单 `Dump Coordinates`：读取当前 controller 的 diagnosticSnapshot，输出实际 panel/window/asset 与命名靶点，不激活、重排或创建窗口。已有场景创建和窗口变化后仍会自动输出坐标。

只改 `Sources/RiftletGUIAcceptance/AcceptanceMain.swift`，新增同目录 `SoftwarePointerProbe.swift`。没有独立工具、产品 UI 改动、自动上传或直接调用产品选择方法。

## root 执行命令

已编译的 debug helper：

```sh
/tmp/riftlet-round7-helper-build/out/Products/Debug/RiftletGUIAcceptance --software-pointer-probes > /tmp/riftlet-round7-software-gui.jsonl 2>&1
```

进程批次结束后仍保留正常 helper 控制窗口，不自动退出；由 root 按既有方式关闭。不要同时操作鼠标/键盘或运行另一 UI 自动化。该批次只有 helper 自有合成图，没有真实 App 目标，也不访问 Web 或 DB。

构建命令为 `swift build --scratch-path /tmp/riftlet-round7-helper-build --product RiftletGUIAcceptance`。本次实际构建和 `--self-check` 成功；CLT linker 提示缺少 Developer framework 搜索目录但构建退出 0。本次没有调用 XCTest，也没有把纯夹具记为 GUI 通过。首次 debug executable SHA256：`c8a958bf8ad584e08caf8b5d539a87f316089dff080cfc49fc1388737cd857e3`。底层覆盖修复后的当前 debug SHA256：`cc70c8f429943f824d19b1197bcf36d142e88f5958a250a60c4e49fa15b20d7d`。后续重建必须重新记录 hash。

## 坐标与真实事件

`probe_targets` 包含每个实际 row 的 assetID、ordinal、window、frame、image、number；target 包含 name、AppKit screen x/y、半径、Quartz x/y、predictedWindow 和 predictedUnderlyingWindow。预测只用于避免把软件事件投向别的应用，**不用于判定穿透 PASS**。

AppKit 屏幕点转换为 Quartz 全局点时使用首个 NSScreen 的 frame.maxY 翻转 y，x 不变；不乘 backingScaleFactor。首个 screen 是原点在 (0,0) 的主屏，不能把当前 key window 对应的 NSScreen.main 当作主屏替代。[Apple NSScreen.screens](https://developer.apple.com/documentation/AppKit/NSScreen/screens)。事件 location 使用全局显示坐标。[Apple CGEvent location](https://developer.apple.com/documentation/coregraphics/cgevent/location?language=objc)。多屏负坐标只做数学夹具，不等于多屏实测。

每个 case：

1. 将既有 synthetic helper outcome 置 Keep pending，重建 3 图场景，等待 1 秒后重新抓取实际 geometry。第一例额外将既有 helper 控制窗右对齐实际首 row 所在屏幕（只执行一次，未请求焦点），再等 650 ms 并重新核对实际覆盖；后续 case 不再对齐。不存在跨 case 复用旧 window/point。即使产品逻辑以后播放动画，也不能借旧坐标点补位后的其他图。
2. 仅读现有 `CGPreflightPostEventAccess`，不发系统授权请求。控制窗必须 visible、onActiveSpace、非最小化、occlusion visible、helper foreground/key；没有按住的左右鼠标键或 Shift/Ctrl/Option/Command。rift 不能 holding/transitioning，几何快照必须一致。
3. target 必须来自该 helper 的当前命名靶点；顶部窗口必须属于当前 helper，预计下层必须为本 helper ClickProbe 窗口。任一不足即 NOT_RUN，不重试、不激活窗口。
4. 创建一个私有 CGEventSource，为 down/up 设置同一随机 52-bit userData token、clickState=1。用 `post(.cghidEventTap)` 相邻发布一次 down/up，全局由 WindowServer 路由。没有 post-to-PID、AXPress、直接 view action 或按结果重发。
5. 600 ms 后对比真正收到的 local monitor mouseDown/up、底层 probeDown/up、accepted press asset 和 selected asset。记录窗口、原 NSEvent window-local 坐标、转换 screen 点、原 CGEvent location；坐标落出事件窗口或偏离预期靶心即 INCONCLUSIVE。外部未标记输入干扰也为 INCONCLUSIVE。

全局软件事件存在 OS 投递与窗口变化的竞态；这些 gate 限制实验范围，不能作为安全隔离沙箱保证。只应在 root 独占的合成 helper 会话执行。程序不根据事件 source PID、mouse 路径或“看起来像真人”推断物理输入。匹配本批次 tag 的原事件明确 `inputOrigin=CGEvent, physical=false`；其他 mouse 标 `unattributedNSEvent`。AX 仍为独立 accessibility 路径。

## 输出与结果规则

- `software_probe_batch_started`：固定四 case、最大 4 个 click pairs。
- `software_probe_post`：case/token/预期 asset/window、AppKit/Quartz 双坐标、当前所有 row assetIDs。
- `mouse_down` / `mouse_up`：tag、source、原事件时间/编号/窗口、local/CG/screen 坐标、窗口内判定、rowRegion、targetGeometryCurrent；不记录键码或正文。
- `underlying_probe_down` / `underlying_probe_up`：ClickProbe 本身实际收到的事件；仅 local monitor 收到不足以证明穿透。
- `thumbnail_press`：来自正式 UI 的已接受边界；CGEvent 关联要求与 monitor 原 down 的 event timestamp、eventNumber、window 全部一致，不读 NSApp.currentEvent。后续 `thumbnail_selected` 仍记录实际 asset。
- `software_probe_case`：接收窗口列表、down/up 数、底层 down/up 数、acceptedAssets/selectedAssets、coordinatesMatch、geometryStable、interference、focusEndpointsStable。
- `software_probe_batch_finished`：四 case results 及 passCount/failCount/inconclusiveCount/notRunCount；physicalVerdict 和 crossApplicationFocusVerdict 恒为 NOT_RUN。

IMAGE/NUMBER 的 **PASS_SOFTWARE_ROUTING** 要求收到一次 down 和一次 up、两个事件都在该原 row window、坐标命中、选择且仅选择原 asset、底层零接收。CLEAR/GAP 的同范围 PASS 要求底层真实 down/up 各一次、没有 thumbnail 接受/选择、收到的窗口确为 ClickProbe。另要求焦点端点不变；这只是同进程 helper 的端点观测，不证明跨应用焦点或连续无焦点跳变。

有正确投递但路由违反上述要求则 FAIL；坐标不符、没有完整事件对、额外输入、case 场景或几何变化则 INCONCLUSIVE 并停止后续批次；投递前 guard 不足则 NOT_RUN 并停止。其余未执行 case 自动列 NOT_RUN。没有 retry 或根据“失败”改变产品几何。

尤其第三轮 CLEAR 曾被工具送至 row、却 location 超出该窗口；本轮同类情况必须 INCONCLUSIVE，不准当作产品透明区 FAIL，更不能把工具坐标问题适配进产品。反之如果这次实际坐标正确、CLEAR 被 row 接受，允许报告该真实软件路由 FAIL，绝不伪装底层穿透。

## 后续验证边界

root 收到记录后可按四 case 精确统计；没有实际运行日志前所有 GUI case 仍 NOT_RUN。即使全部软件通过，也不替代物理 N1/N04/N05/N07、人类按住补位/双击、跨应用编辑焦点、真实截图或正式 Web 上传验收。当前批次 Keep pending、一次单击，只测软件几何路由。


## 首批 NOT_RUN 与覆盖修复

root 实际运行源码 f641 的首批记录为 `targetMissing`，四项均 NOT_RUN、没有 eventsPosted。此为 helper 前提不足，不是透明穿透/命中失败，也不是产品缩放缺陷。

日志明确：controlWindow frame = (223,0,1474,1080)，最右 x=1697；实际 row bounds x=1840…1912，首图 IMAGE 中心 x≈1884.15。原 `probe.bounds.contains` 因而排除全部靶点。单凭 controlWindow screenID=2 和这些坐标不足以证明另一屏错误，首批缺完整 screen inventory，报告不把疑似屏幕 ID/缩放原因写成事实。

修复限定在既有 helper：

- candidate 生成按实际 row window 的 NSScreen（或 row 中心所在屏幕）取范围，不依赖控制窗的 screen；生成后逐点保留 `candidateTargets` 与 `exclusion=outsideProbeContent/coveredByControlSubview/none`。
- 每批首次 fresh scene 之后，只执行一次 controlWindow.setFrame，将现有 helper 控制窗以当前尺寸右对齐实际 row 屏的 visibleFrame；高度/宽度仅在超出该屏时收小。不移动/重排产品 rows，不设置焦点，不增加窗口或工具。记录 `probe_control_alignment` before/requested/immediateActual，随后等待后仍以真实 frame 再核验；若 OS 再约束或仍覆盖不足，继续 NOT_RUN，不循环纠正或发事件试探。
- `probe_targets` 增加全部屏幕 AppKit frame/visibleFrame/backingScaleFactor/rotationDegrees、rowScreenID 与 probeContentFrameOnScreen。Quartz 变换仍以主屏全局坐标为基准，不乘缩放、不自行把旋转屏坐标再旋转。
- 无 GUI 自检加入首批窄窗算例：1474 宽窗口右对齐 1920 宽屏得到 x=446，包含真实 IMAGE 的 x=1884.15；另测负原点 portrait frame、右下 portrait frame、上方屏。只是算术测试，不冒充这些屏幕上的真实点击成功。

修复后 scratch build、`--self-check`、`git diff --check` 均通过。日志为 `riftlet-round7-helper-geometry-build.log`。修复后的实际单批结果待 root 重新执行；开发者没有控制 PID 或页面。

首批输入日志的本次读取 SHA256：`be9f4134ee16d31a07d534429d5ef7ca80b1280eeed36e8d23ee833a6489390d`（文件 basename `riftlet-round7-gui.jsonl`，这是读取时字节快照）。

## Observed CLEAR failure and limited selection guard

The fixed helper batch recorded IMAGE and NUMBER `PASS_SOFTWARE_ROUTING`, CLEAR `FAIL`, and GAP `NOT_RUN`. CLEAR's tagged CGEvent down/up arrived in row window 50371 at local `(1.5, 2)` and screen `(1841.5, 880)`, with matching coordinates, stable geometry, one accepted/selected synthetic asset, and zero underlying down/up callbacks. The point is row padding, outside both image clip and number rectangles. This is an observed product selection defect, not evidence of tool scaling error.

The narrow follow-up changes only selection eligibility: `RiftRowLayout.containsSelectionPoint` accepts the existing image clip or number rectangle; mouseDown outside them does not invoke the press boundary, and mouseUp outside them cancels the original hold. No layout, window ordering, AX path, lifecycle, event forwarding, pointer polling or `ignoresMouseEvents` switching changes. A rectangular native row window still receives padding events. Therefore this guard is **not a transparent cross-window routing fix**, and the prior CLEAR routing failure is retained until separately established otherwise.

`testObservedClearPaddingCannotBeginOrCompleteSelection` covers the measured CLEAR point, number/image gap, clipped image remainder, padding-down/image-up rejection, accepted IMAGE/NUMBER, and image-down/padding-up cancellation. The exact test body ran against the built UI module with standalone assertions: `CLEAR_HIT_REGION_SOURCE_CHECK_PASS; GUI_NOT_RUN`. Helper product build and fixture `--self-check` passed. Local CLT lacks XCTest; native XCTest remains a CI check. These checks do not establish pixels, native routing or physical input. The runtime coordinator will own any follow-up batch.

GAP was not posted: at host uptime 467488.704218917 its surface prediction was helper window 50351; the subsequent inventory at 467489.095762375 returned window 0 for every named target. The immediate `ownWindows.contains(top)` / underlying-window guard then refused `nonHelperSurfaceOrChangedGeometry`. Geometry and control visibility fields alone do not explain why the native window lookup returned 0. No routing PASS, scaling defect, or focus-loss cause is inferred, and no blind retry is authorized by this diagnosis.
