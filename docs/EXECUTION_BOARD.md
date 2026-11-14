# Riftlet 当前工程队列

2026-11-14 质量重整继续 [PR #101](https://github.com/haohongfei2001-png/Riftlet/pull/101)。工程与精确源码记录见 [progress.json](../engineering/quality/2026-11-14/progress.json)，逐项状态见 [ITERATION_STATUS.json](quality/ITERATION_STATUS.json)。[质量台账](quality/ISSUE_REGISTER.md)与原始审计证据保留初审问题和失败结果。

R1 修复、四页设置、历史投影、性能和核心双语已实现。当前已审 HEAD `2048b32` 的五项正式 CI 全部通过。英文控制中心标题布局已修正并完成中英文原生复查。

隔离 ARM64 macOS 27.2 的 Chrome 156 已在专用匿名 ChatGPT 草稿完成源码 `624e1b5` 私有公证候选的三张不同系统截图附加。每图一次操作，第三张的实际 GUI 双击仍只生成一个操作。已观察页面开始接收、附件可见和对应 START、吞噬；`positiveReady=false`，没有宣称服务端最终可用状态。本次回执见 [真实附件记录](../engineering/quality/2026-11-14/actual-chatgpt-attachment.json)，独立证据复核已通过。一次目标切换期间安全拒绝发生在 setter 之前；该次伴随匿名登录提示，范围按回执记录。

官网下载 1.0.1 经真实 Sparkle 更新到私有 1.0.2 的执行包仍对应源码 `31258e2`，见 [升级记录](../engineering/quality/2026-11-14/actual-private-sparkle-update.json)。312→624 的产品界面差异是控制中心标题布局，另有验收截图工具语言匹配；更新器、数据与附件实现相同。两个实测保持各自源码、包和环境身份。

下一步完成本次附件证据复核，将版本元数据设为 1.0.2／24，形成新源码审查与准入提交，执行正式 CI、main 集成、stable 包和签名 feed 的发行核验。现有 `Riftlet QA` 包的签名、公证及测试记录保留原身份，正式产物记录自己的字节与回执。共用 RiftletMain 与 Core 接口由集成负责人串行修改。

#83 远端保护仍为独立治理缺口。#92 的实体 Intel、最低系统、更多显示器和完整 VoiceOver 覆盖保留实际状态。#95 本轮为只读容量和清理语义，永久删除未实施。#77 保持独立候选，不能计入本 PR 的已集成功能。

此前 QA 浏览器网络超时、零提交的 NOT_RUN 记录保留在工程进度及当前状态的历史字段中。本次成功仅覆盖实际执行的匿名草稿、截图与操作，未执行的矩阵项不随之改为 PASS。

旧任务板完整保留在 [历史快照](quality/history/docs_EXECUTION_BOARD.before-20261114.md)。
