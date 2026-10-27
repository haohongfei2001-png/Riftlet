# 第八轮：原生透明区穿透与按住补位

最终源码 `85250a869f06d99e3d3ab046116f560bac572fd9`，helper binary SHA256 `600b395bc9aa705e067cd0d074542237af8214a3afd08012c4ea69a6e347aa02`。本轮使用现有 `RiftletGUIAcceptance` 的生成图片场景，经 WindowServer 投递带 token 的 CGEvent；没有调用 transfer.select、转发点击或测试真实上传。配套 [脱敏逐事件证据](software-routing.json) 保留原文件 SHA256、原生窗口/坐标、token、结果和边界。

**默认尺寸竖屏的最终源码补测中，IMAGE、NUMBER、CLEAR、GAP 四项均通过软件路由；大尺寸竖屏 CLEAR 也通过，按住补位通过。** 这包括底层 probe 实际收到 down/up，已超出上一轮“仅阻止误选”的范围。紧凑横屏仅 IMAGE 取得一次通过，其余矩阵仍未闭合。物理真人、跨应用焦点保持、双击替换仍未运行。

## 逐批结果，保留原始未完成项

| 批次 | fitWidth × fitHeight（points） | 屏幕 | IMAGE | NUMBER | CLEAR | GAP |
| --- | --- | --- | --- | --- | --- | --- |
| default-portrait 原批 | 72 × 56 | 3，竖屏 2x | PASS | INCONCLUSIVE：额外未归属事件 | NOT_RUN | NOT_RUN |
| compact-landscape 原批 | 48 × 32 | 2，横屏 2x | PASS | NOT_RUN：失去前台/键窗口 | NOT_RUN | NOT_RUN |
| large-portrait 原批 | 128 × 96 | 3，竖屏 2x | PASS | PASS | PASS | NOT_RUN：失去前台/键窗口 |
| default-portrait-stable 有限补测 | 72 × 56 | 3，竖屏 2x | PASS | PASS | PASS | PASS |
| compact-landscape-stable 有限补测 | 48 × 32 | 2，横屏 2x | NOT_RUN | NOT_RUN | NOT_RUN | NOT_RUN |

表内 PASS 均指 `PASS_SOFTWARE_ROUTING`，不是完整产品或真人验收。两次补测后停止，没有覆盖或删除原批的不确定记录。五个最终源码 routing 批次共规划 20 个 case：9 PASS、1 INCONCLUSIVE、10 NOT_RUN、0 routing FAIL；另有 1 个 `PASS_SOFTWARE_HOLD`。规划项与实际发出事件数不能混算。

默认原批 NUMBER 的 tagged down/up 正确到窗口 50990，原图被选择一次，坐标与焦点端点稳定；但在该 case 观察期间另出现 `unattributedNSEvent` down/up（host uptime 475216.620428292 / 475217.038579417），因此 `interference=true`，保持 INCONCLUSIVE。无法据未归属 NSEvent 宣称是物理真人，也不能把这次干扰写成产品路由失败。

紧凑原批在 IMAGE 已通过之后，于 475221.949253875 / 475221.951475625 记录 helper resign-key/resign-active，前台变为 Codex；475222.394921083 的 NUMBER preflight 返回 `helperNotForegroundKey`，未发事件。补测则在任何 posting 之前，于 475490.860634875 / 475490.863130333 记录前台为 Chrome、helper 失去 key/active；475491.643858125 的 IMAGE preflight 安全拒绝，四项均未运行。日志给出失去前台资格的直接事实，未证明切换的发起者，不将其归因为产品抢焦点或缩放故障。

大尺寸 CLEAR 已于 475230.005080458 完成通过；较晚的 475230.813333708 / 475230.816336583 才记录前台变为 Chrome。475231.033216625 的 GAP 未发事件。后来的失焦不会倒写前面 CLEAR 为失败，也不替 GAP 补发输入。

## 实际路由、屏幕与形状边界

OS 为日志中的 `Version 27.0 (Build 26A428)`。屏幕 2 为 `(0,0,1920,1080)` points、rotation 0°、backingScaleFactor 2；屏幕 3 为 `(-800,-200,800,1280)` points、rotation 90°、backingScaleFactor 2。包括负原点及旋转屏，**没有 1x 实测**。48×32、72×56、128×96 是配置 fit 上限；图片按比例拟合，不能把这些数字当每张实际输入窗口尺寸。JSON 保留每个 post 时实际 frame 和 image/number input frame。

原视觉窗口固定忽略鼠标，图片露出区与数字区分别使用独立非激活原生输入窗口。原视觉绘制与唯一 AX button 保留。纯透明输入窗口在本机实测确实接收 IMAGE/NUMBER，无须改绘制或发起二次事件。Native frame 会对分数 point 取整；本报告验证指定坐标，不宣称穷尽所有边缘像素。

默认补测 CLEAR/GAP 的实际接收窗口均为底层控制/probe 窗口 51177，各只有一次 tagged down、一次 tagged up；`underlyingDownCount=underlyingUpCount=1`，accepted/selected asset 均为空。大尺寸 CLEAR 对应底层窗口 51037，同样各一次下/上事件、零缩略图选择。IMAGE/NUMBER 各自到对应输入窗口，原生成 asset 只选择一次。这些是实际事件回调，不是窗口查询预测、hitTest(nil) 或“没有错误选择”代替穿透。

上述 focusEndpointsStable 仅比较 helper 活动期间自身前台、key window 与测试编辑器端点，不能证明 Chrome/其他应用的文本焦点保持。

## 按住补位

`hold-portrait` 使用默认 72×56、屏幕 3。原第二图 `00000000-0000-4000-8000-000000000002` 在 input window 51117 按下。475234.712994417 的 accepted-hold 记录后，475236.225068125 请求将另一张首图标成 synthetic used，约 1512.074 ms；这只是 helper 显示状态，不是上传/开始回执。

475236.655445792 的释放前快照仍 holding、三行完整几何不变、selection=0、原窗口覆盖有效。475236.656810167 发出原坐标配对 up；down-post→up-post 日志间隔约 1975.290 ms。实际 down/up 均只一次并到 51117，原第二图仅选择一次。随后它从 ordinal 2 移至 1，frame y 从 812 到 872，仍是同一 input window；首图消失，第三图补位。`heldLayoutStable`、`reorderObserved`、`compactionCorrect` 均 true，得到 `PASS_SOFTWARE_HOLD`。这不是拖拽功能或真人长按证明，双击替换 `NOT_RUN`。

## Prototype 单独保留

较早 prototype 基于 `b0778e71608a1afb95af343c39e9ea4e97320cc0` 的未提交工作树，binary SHA256 `d0e486dc9e443ac33029f895a4917716c8f2600b008cae8274ba3cfe64863b8f`；逐源文件 hash 在 JSON。默认 72×56、同一竖屏 2x，四项均 PASS。其批次前已有一个未归属底层点击，不能混入 tagged case 计数。prototype 不是最终源码运行，也不用于覆盖最终源码各批次的 NOT_RUN/INCONCLUSIVE；最终默认四项通过另有同 SHA 的补测证据。

所有场景均 synthetic-only；未上传真实截图、未启用生产 profile，未验证截图自包含、生产 App 完整体验、像素动画时序或跨应用输入。公开材料只保留必要生成资产 ID、窗口/坐标、时间、结果与哈希，不发布输入文本、聊天内容、URL、机器路径或原始进程 ID。原日志一条非 JSON 诊断行仅计数，不原样公开。
