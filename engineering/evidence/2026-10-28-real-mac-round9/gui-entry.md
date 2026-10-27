# 第九轮 GUI 最小入口与输入来源

本轮不重复已经通过的软件 IMAGE/NUMBER/CLEAR/GAP 与 HOLD 批次，不改正式 UI/Core/App，也不重新要求用户参与。真实物理鼠标目前仍为 **NOT_RUN**；以下只是已有 helper 的可用人工入口，不代表有人实际完成。

## 已有人工入口

运行现有 `RiftletGUIAcceptance`，不带 `--software-*` 或 `--press-acceptance-asset`。需要指定屏幕时可用 `--probe-display-id <当前实际显示ID>`。在控制窗选 `3 images`、`Keep pending`；Show Controls 菜单用于显式找回控制窗，Dump Coordinates 输出实际图像/数字输入窗口和底层靶点。不要根据缩放猜坐标。

若以后有独立真人操作记录，只需一次连续过程：点击 helper 文本框；单击 IMAGE 后输入一个测试字符；点 GAP、CLEAR 小靶心；点“准备按住补位”，按住 HOLD 第二张，提示“可以松开”后释放。最后普通双击可以记录基本双击行为，但只有日志证明第二次 down 实际落到**不同的补位资产/输入窗口**且在系统间隔内，才属于“双击到补位图”用例；不要将同图双击泛化为替换防误选验收。所有素材均为生成图片，不调用产品上传。

`source=mouse` 只说明 AppKit 鼠标回调路径。没有本工具 token 的 NSEvent 记录为 `unattributedNSEvent`，既可能是硬件，也可能由其他自动化注入，日志本身无法证明真人。只有可信操作来源说明与原始事件相符，才可标物理执行；当前没有这样的本轮新证据。`source=accessibility` / `helperAX` 与带 token 的 `CGEvent` 均属于软件输入。同进程测试编辑器焦点不代表跨应用 ChatGPT 编辑器焦点保持。文本内容及键码不输出。

## 唯一软件增量：快速双击到补位图

入口为现有 helper 的 `--software-double-probe`，可附加既有显示/尺寸参数。此模式与 `--software-pointer-probes`、`--software-hold-probe` 互斥，共用一次 batch 限制；最多两对 down/up，不转发、不向 PID 直接投递、不重试，不复跑已通过的批次。

1. 新建三张生成图场景，等待稳定，核对既有授权、helper 前台/key、无已按按钮/修饰键、所有权和实际坐标。
2. 在第一张 A 与补位后 B 都可覆盖的图像点，发 token1 / clickState=1 的一对原生事件。实际 receipt 必须确认 A 原窗口 down/up、accepted/select 各一次。
3. 用 helper 既有 `SyntheticScene.displaying(.used)` 更新 A 的显示状态。此状态不是上传完成回执。重新读取实际布局，要求 A 退出、B 保持原 asset/window 身份并补到该点。
4. 仅当前台、窗口覆盖、无干扰和时间守卫都满足，且仍留在 `NSEvent.doubleClickInterval` 内，才发 token2 / clickState=2。以实际原生事件时间差及 B 窗口收件为最终范围依据；只要 B 被 accepted/select 就失败。原资产只选择一次、B 零选择才可产生 `PASS_SOFTWARE_DOUBLE_REPLACEMENT`。

配对 up 在无 await 的发送函数 defer 中发出，正常终止还有统一清理；不宣称 SIGKILL 能执行清理。第二对的前提不足则不发，保留第一对已执行事实并标 INCONCLUSIVE / secondPair NOT_RUN，不为取得 PASS 再点击。

**clickState=2 由 CGEvent 明确提供**，这验证产品对收到的快速第二击在补位窗口上的处理，不是实际硬件或 WindowServer 自动判定双击的证明。物理真人、跨应用焦点、OS 双击分类均仍 NOT_RUN/NOT_TESTED。源码自检、构建与之后协调者实际 GUI 运行须分别记录确切 SHA；本文不预先写软件运行 PASS。

实测工具修正：逻辑布局提交不代表 WindowServer 已提交补位窗口。在保留原点和原 firstDown 期限的前提下，最多64次、每次5ms yield 的只读采样核对新图原生 frame/窗口栈；截止仍为原 firstDown + 系统双击间隔 −20ms。不是重发第一击或延长双击期限。最终23becda软件样本第二次采样就绪，两对事件间隔124.964ms，A选1、补位B选0；人工及系统硬件双击分类仍未验。
