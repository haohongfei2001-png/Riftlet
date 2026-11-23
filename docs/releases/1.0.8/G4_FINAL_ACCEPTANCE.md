# Riftlet 1.0.8 build 59 · G4 最终实站验收

2026-11-23 的当前候选为 build 61。新候选在普通 Edge 已取得一次原图附加和一条 START。受控故障次数为零，原操作的结果为 uploadStarted。另一次 23,233,638 字节的真实系统截图上传留下原 UNKNOWN、完整 PNG 和同名预览。两次独立数据库备份相同，没有重选或新 START，G4 仍未放行。[build 61 大图与恢复裁决](evidence/build61/size-boundary-independent.json)

本文下方为 build 59 的历史证据。[build 61 实站原操作](evidence/build61/g4c-original-live.json) · [当前发行报告](RIFTLET_1.0.8_FINAL_RELEASE_REPORT.md)

**放行结论为 PARTIAL。** 已在已登录的普通 Edge Temporary Chat 中中断唯一一条发送原 PNG 的真实 XHR。ChatGPT 随后移除了原进度卡。观察期内没有出现属于该操作的明确失败卡，Riftlet 也没有记录原卡错误收据。因此 G4 的原卡失败及显式恢复保留为 **NOT_RUN**。

本轮使用签名产品提交 `69b76cb025ab552b3480e3af095b627891874712`，验收起点为 `77044e526864f93da2827257a0e9a5a6c7bb6797`。实际运行器校验安装副本、产品资源及最终镜像。DMG SHA-256 为 `666324176aadc4ffb9fd6fbfd0ca38772a169eb06394401f7abede374f7d3ee6`。改动仅涉及 QA 工具和验收记录。

| 现场步骤 | 实际结果 |
| --- | --- |
| 正常上传校准 | 专用原窗、原标签、原编辑器及登录态通过身份核验。签名 App 的一次 AppKit 按下产生一次 input、一次 change、一个持久化 START。唯一的创建请求通过 `file_name` 对应原操作 UUID，返回唯一的 `upload_url`。XHR 以该地址 PUT 同一 File，全部 5,516 字节匹配原 PNG，HTTP 201。 |
| 单次传输故障 | 在另一专用草稿，以新系统截图重建全部关联。文件为 5,513 字节，完整 SHA-256 为 `fa734c39ae34bca70281f0f67439349402d7e9099465c6f7010148af77a1b469`。创建请求 HTTP 200，目标 PUT 有一次受信 loadstart。原生 send 返回后，在响应可见前调用一次 abort，浏览器回报一次受信 abort、一次 loadend，status 为 0。未观测到正上传进度，线上实际传出字节数未知。此项只证实客户端传输取消。 |
| 网站原卡 | 点击前绑定的具名原卡观察器记录到新进度卡。取消后约 12 ms，观察器记录到该原卡节点被移除。自点击意图起观察 54.549 秒，原 Document 和编辑器有效，未观察到属于该操作的具名失败卡。故障草稿有一次 input、一次 change、零发送点击、零表单提交。 |
| Riftlet 原状态 | 原 asset、operation 与 invocation 仍可查。数据库有 1 个 asset、1 个 operation、0 个 START。操作 phase 为 `unknown`，收据 outcome 为 `inputTriggered`，`hasError=false`、`safeToRetry=false`。原图仍为 visible，磁盘源 PNG 和保留媒体的完整哈希均匹配。 |
| 显式重选与双快照 | 明确原卡错误的前提未满足。新操作、新 invocation、新 START 均为零。未执行 beforeSTART 或 afterSTART 的失败恢复。两份规定时点的恢复快照均为 NOT_RUN，哈希均为 null。 |
| 清理 | 终态事件之后约 0.1 ms 自动移除故障监听，恢复原 fetch/XHR 函数；待处理观察任务为零，目标 XHR 已结束。两扇专用窗口均按创建身份关闭，浏览器原窗口集合复原。所有本轮私有 Riftlet 进程及临时本地监听器已退出。 |

原故障操作为 `4F739270-3638-4598-BBAE-C2AFBC37980E`，invocation 为 `5CB048BB-88D0-4F93-93EC-B612ED70C3C7`。网络观察器撤除后，仍持续观察 Riftlet 文件输入、原卡和操作账本。此次只能证实观察期内没有 Riftlet 自动重投。故障轮终态 SQLite 一致性备份 SHA-256 为 `3f1176fe3da464277c4ae2552c9a4ecee799b8d7aa4d1b5b7337b5b097c1e926`，采集时点为退出私有候选之后。原始 PNG、媒体及数据库均保留在私有验收档案。公开收据仅保留上传地址的散列。

非作者独立读取浏览器、AppKit 和 SQLite 原始记录，并独立创建了终态数据库备份。两份终态备份的 SHA-256 相同。非作者确认此次客户端中断成立，原卡错误和恢复均未通过。被动校准与一次性故障工具分别通过 39 项和 35 项离线控制；非作者另以四种 XHR 复用情形验证了对后续请求的保护。

[网络回执](evidence/build59/g4-final-network-receipt.json) · [原卡回执](evidence/build59/g4-final-card-observation.json) · [恢复及快照审计](evidence/build59/g4-final-recovery.json) · [窗口与进程清理](evidence/build59/g4-final-cleanup.json) · [校准非作者复核](evidence/build59/g4-live-passive-audit.json) · [最终非作者复核](evidence/build59/g4-final-independent.json)

## 后续两种真实传输中断

前台恢复后，签名 build 59 在新的已登录 Edge 临时草稿完成另外两种实站中断。一次在受信部分进度 81,875 / 188,726 字节处取消；另一次在受信上传 load 读到 5,516 / 5,516 字节、尚未观察到响应时取消。两次均产生一次 input、一次 change，保留完整 PNG 与原 UNKNOWN。两次均未取得属于原操作的明确错误卡，也未进行显式重选。另一次大图身份比对不符，取消数为零。合计三种真实中断，G4 为 **BLOCKED_TECHNICAL — G4 NOT PROVEN**。逐轮结果见[最终发行报告](RIFTLET_1.0.8_FINAL_RELEASE_REPORT.md)和[三种策略总账](evidence/build59/g4-final-strategies.json)。
