# Riftlet 1.0.8 最终发行报告 · 2026-11-23

**RIFTLET 1.0.8 — NOT RELEASED**

当前候选是 build 60。签名包、独立安装和双架构回归均已完成。实站准入在文件输入前停止，G1、G2 和 G4 仍缺少这份签名包的完整证据。公开稳定版本为 1.0.5（31）。

## 2026-11-23 · Build 60

| 同包项目 | 核验结果 |
| --- | --- |
| 候选 | 1.0.8（60），产品源码 `711cee3a1c7033ce4925082a83099b00da7087c6`。私有 DMG 为 14,092,837 字节，SHA-256 为 `5a934119d6e65cbe82a62f5f208a2b95a200fa0cf170225ccd4e9016b1c0b54e`。 |
| 原生与网页回归 | ARM64、Intel 各完成 1,436 个 Swift 测试。完整网页套件 384/384，两款浏览器在独立受控页面各通过 19 个原草稿和 22 个预览用例，另有 8 个故障测试与 24 个打包验证。 |
| 签署与分发字节 | 统一 App、DMG 的 Developer ID 签名、Apple 公证、staple 及 Gatekeeper 均已确认。非作者从只读镜像独立安装，完整目录树比对通过，两个架构和三个 App 自检通过。 |
| 历史保留 | 在三份 build 59 实站故障库的独立副本上，迁移、取消、延迟回执及重启后，原操作、调用、收据与 START 记录均保持一致。原存档逐字节摘要不变。 |
| 用户知情恢复 | 截图仓库在确认前告知潜在重复风险。新的原生点击必须获得同一原窗、标签、Document、Composer 和草稿代际的许可。受控测试验证仍有旧卡、出现不明附件、旧附件被替换或目标变化时均停止输入。首次恢复在输入前撤回后，可以继续发起新的显式选择，旧账本保持只读。 |

[双架构 CI](evidence/build60/dual-architecture-ci.json) · [受控测试](evidence/build60/local-regression.json) · [签名及公证](evidence/build60/signed-candidate.json) · [独立安装](evidence/build60/independent-install.json) · [非作者源码复核](evidence/build60/independent-source-review.json) · [原图与历史库](evidence/build60/g4-page-review.json)

### 实站结果与发行裁决

| 项目 | build 60 结果 | 本轮观察 |
| --- | --- | --- |
| Chrome、Edge 冷暖首图、快速双图、非空原文与选区 | NOT_RUN · BLOCKED_ENV | 在这两个浏览器均无法同时证明专窗已选中、位于系统前台、原始页面可见。没有投递第一张图，不能沿用 build 59 的成绩。 |
| G4-A · 具名原卡失败与恢复 | NOT_RUN | 没有发生可归属的实站文件输入或故障，没有新的原卡错误、旧失败库或成功恢复库可供核对。 |
| G4-B · 上游 4xx、原卡消失与恢复 | NOT_RUN | 同包实站没有原 PNG 对应的上游 4xx。自有服务器的 413、503 仅用于浏览器网络对照。缺少独立等价放行所必需的上游与恢复证据。 |
| G4-C · UNKNOWN 的知情重选 | 产品和存储验证通过；实站 NOT_RUN | 正向恢复及原卡仍在时的负向保护均缺少同包真实 AppKit 点击。受控对照与三份历史库已分别审计。 |
| B4 · 正常图片大小限制 | 受控准备完成；实站 NOT_RUN | 2880×2816 的离线图案编码为 23,329,506 字节。真实系统截图及普通站点上传以原窗可见为前提，本轮没有取得实站限额或响应。 |

本轮共七次专窗准备。Chrome 两次止于自有本机文档；Edge 五次中有两次到达真实 Temporary Chat，验证了浏览器签名、原生窗与标签、登录状态、原编辑器和上传入口。窗口未最小化，页面报告不可见。Mac 会话已登录，显示器已醒，系统前台为 UserNotificationCenter 的系统对话框。浏览器原生活动请求、标准 Apple Event 及厂商新窗途径均未建立可靠前台。Chrome 的新窗及原标签能通过本轮本机文档确认，仍未取得选中、前台、可见的联合证据。WindowServer 采样时这两款浏览器均无可命中的屏上普通窗口。系统对话框用途未确定。所有准备均停在产品文件输入前。

七次均未启动候选的实站 GUI，未触发文件输入、故障注入、发送或表单提交。123 份原始准备与清理记录已单独私有归档并逐件验算，归档 SHA-256 为 `0d3a76182546d9f6af64bea1a763c939f84553d0a056d067c1636414d51b3698`。

七个 QA 监听器均已退出，各自端口均无监听，独立安装路径下的候选 GUI 进程为零。六次恢复原窗口集合。Edge 厂商新窗同时有两个标签，只能证明其中一个来自本轮，已关闭该标签并保留另一个。没有接管个人聊天、点击系统对话框、改变权限、修改登录信息或开启调试。当前连接的远程设备与本机相同，仓库没有已注册的自托管 Actions runner。恢复实站的条件是获得可呈现、可匹配原生窗口的已登录普通浏览器测试会话。

[七次实站与清理回执](evidence/build60/site-and-cleanup.json) · [非作者独立发行裁决](evidence/build60/independent-release-verdict.json) · [Edge 原草稿准入回执](evidence/build60/g4c-edge-preflight.json) · [协议对照与各路线条件](G4_PROTOCOL_AND_STATE_MACHINE.md) · [分支依赖与 PR 状态](evidence/build60/governance.json) · [公开稳定版本、官网及签名更新源](evidence/build60/public-stable-baseline.json)

PR #124 保留 Draft，Issue #120 保持打开。正式合并、1.0.8 Release、官网与 Sparkle 切换、发布后的公开下载及应用内升级验收均未执行。公开下载的 1.0.5 DMG 与 GitHub 资产摘要相符，并已用稳定更新源签名复核。

## 2026-11-22 · Build 59 历史报告

**RIFTLET 1.0.8 — NOT RELEASED**

build 59 的 G1、G2 已通过。G4 在三个不同的原生上传时机各中断一条可唯一归属的真实请求。三次均未观察到 ChatGPT 自身的原卡明确失败，故无法验证从该失败显式重选并成功附加。**BLOCKED_TECHNICAL — G4 NOT PROVEN**。候选保留在 Draft PR #124，公开发行版本为 **1.0.5（31）**。

## 冻结候选和产品验收

| 项目 | 经核验的结果 |
| --- | --- |
| 产品身份 | 1.0.8（59），源码 `69b76cb025ab552b3480e3af095b627891874712`。私有 DMG 为 13,775,789 字节，SHA-256 为 `666324176aadc4ffb9fd6fbfd0ca38772a169eb06394401f7abede374f7d3ee6`。 |
| G1 · 普通 Chrome × ChatGPT | 冷首图、暖首图及快速双图 PASS。三组两次 AppKit mouseDown 分别相隔 552.323、532.494、531.391 ms。 |
| G2 · 普通 Edge × ChatGPT | 冷首图、暖首图及快速双图 PASS。同路径三组分别相隔 499.982、485.296、479.162 ms。 |
| 文字、选区及旧卡 | 两款浏览器均 PASS。真实 Temporary Chat 的原文逐字符一致，选区为 `preserve this original draft`，anchor/focus 保持 12/40、正向，端点仍在原编辑器的原节点。已有附件保留，新附件各出现一次。 |
| 成功系列计数 | 该轮原生复验封存 26 张不同原 PNG，22 张实际投递，各有一次 input、一次 change 和唯一持久化 START。零错误附加、重复输入、发送点击及表单提交。G4 另计。 |
| 历史数据 | 独立进程分别读回 build 56、57、58 的待确认及已 START 操作。六条历史操作保留，续查未重新输入。 |
| G4 · 原卡失败后的显式恢复 | **NOT_RUN**。三种真实传输中断均已完成；原卡错误及后续恢复尚无合格样本。 |

[两款浏览器同包验收](PRECLICK_ACCEPTANCE.md) · [逐图原始时序审计](evidence/build59/NATIVE_RAPID_AUDIT.md) · [非空草稿与选区审计](evidence/build59/NATIVE_SELECTION_AUDIT.md) · [原生系列计数](evidence/build59/native-round-accounting.json) · [历史兼容](evidence/build59/old-operations.json)

## G4 实验和停止位置

| 故障时机 | 实际执行范围 | 结果 |
| --- | --- | --- |
| 1 · 目标 XHR 开始，尚未看到响应 | 普通 Edge 的已登录专用临时草稿。先用单独的正常操作校准，完整 5,516 字节匹配，HTTP 201。故障轮使用新的系统截图，完整 5,513 字节匹配原 File、operation、唯一创建回执和实际 PUT 地址。 | 原生 send 已返回，有一次受信 loadstart、abort 和 loadend，status 0。取消前传出字节数未知。原卡约在取消后 12 ms 移除；从点击意图起观察 54.549 秒，未取得明确失败卡。 |
| 2 · 目标 XHR 的部分字节进度 | 首次使用新的 2,255,260 字节系统截图，创建请求的文件信息未能与原文件完整匹配，取消次数为零。使用不同草稿和新操作复核时，188,726 字节系统截图的全部字节、原 File、原 XHR 和实际 PUT 地址均已核对。 | 在受信 progress 事件的 **81,875 / 188,726** 字节处取消一次；浏览器尚未观察到响应。54.966 秒观察内未出现明确原卡失败。 |
| 3 · 目标 XHR 请求体发送完成、响应尚不可见 | 另建专用登录草稿、原操作和系统截图，核对完整 5,516 字节原 File 和唯一 PUT。 | 在受信 upload.load 的 **5,516 / 5,516** 字节、readyState=1、尚未观察到响应时取消一次。约 21.9 ms 后原卡移除控件消失；54.918 秒观察内未出现原卡明确失败。 |

首次中断有一次 input、一次 change、零发送点击和表单提交。SQLite 保留原 operation、invocation 和原 PNG，状态为 `unknown`、`hasError=false`、`safeToRetry=false`，START 为零。观察期间没有自动重投。独立审计取得同一终态备份 SHA-256 `3f1176fe3da464277c4ae2552c9a4ecee799b8d7aa4d1b5b7337b5b097c1e926`。这份备份的时点在退出候选后；两份规定时点的恢复快照及其哈希均缺失。显式重选、新 invocation、新 START 和旧失败记录留存这组要求仍待验证。[原故障回执](evidence/build59/g4-final-network-receipt.json) · [原卡观察](evidence/build59/g4-final-card-observation.json) · [数据库审计](evidence/build59/g4-final-recovery.json) · [非作者独立复核](evidence/build59/g4-final-independent.json)

最初三次 Edge 和一次 Chrome 预检止于本地原窗无法取得前台。自动审批因可能读取私人通知而拒绝了检查系统提示内容的诊断。普通桌面恢复后，三个新建、已登录的专用 Edge Temporary Chat 依次完成大图匹配试验、请求体已发送试验和部分进度复验。每个草稿均独立核验原文档、编辑器、输入、操作与系统截图。大图匹配试验取得一次普通 attachmentAccepted START；大图原文件和站内预览的完整像素摘要不同，无法据此归属其实际传输字节。该轮旧版收据只能定位到创建请求，具体哪个字段不匹配未知。[四个早期预检窗](evidence/build59/g4-unattended-preparation.json) · [大图原始审计](evidence/build59/g4-progress2-live.json)

三次实际取消均为客户端传输故障，服务器端最终处理结果未知。每个故障草稿各产生一个原操作、一次 input、一次 change；三张原 PNG 和原 invocation 均保留，最终均为 UNKNOWN、`hasError=false`、`safeToRetry=false`、零 START。观察期内零自动重放、零发送点击、零表单提交。由于始终没有取得错误原卡，两份规定时点的恢复快照均为 NOT_RUN。没有发起显式重选，也没有恢复 invocation 或新 START。非作者在各轮独立核对原图、原始事件、SQLite 和窗口清理。增量的三个实站专窗均关闭，候选子进程和本机监听器均退出，网络函数均已恢复。[请求体已发送时中断](evidence/build59/g4-body3-live.json) · [部分上传时中断](evidence/build59/g4-midproof-live.json) · [三种策略总账](evidence/build59/g4-final-strategies.json)

三种已授权的故障时机均已取得真实样本。现有证据未定位到产品缺陷，亦不足以审计失败后的显式恢复。新的发行判定需要在同一原操作上同时取得网站明确失败卡和带错误收据的 UNKNOWN，再用一次新的 AppKit 选择证明恢复。原签名 build 59 和全部私有原始资料已封存。


## 工程和安装包

- ARM64、Intel 在冻结产品提交上均通过。每个架构完成 1,434 项 Swift 测试、19 项点击前凭据、22 项改名预览和 8 项离线恢复测试。另有独立网页回归记录。G4 网络验收工具在增加创建请求诊断字段前通过 132 项离线测试，最终版本通过 144 项；数据库恢复验证器 4 项单测通过。[冻结源码 CI](https://github.com/haohongfei2001-png/Riftlet/actions/runs/44987854131) · [CI 归档](evidence/build59/ci.json) · [网页回归](evidence/build59/independent-web-regression.json)
- App 和 DMG 的 Developer ID 签名、Apple 公证、staple 和 Gatekeeper 均已核实。非作者从只读镜像独立安装，验证 arm64、x86_64 及三项本机自检。此次重新核对了镜像和可执行文件哈希；可执行文件 SHA-256 为 `6fb94534e7b34533f10abb00c2b91369787e6ca1a516ae3c1fe818fe03a53ff7`。产品源码、资源、打包脚本均与冻结提交一致，本轮使用原签名候选。[签名公证](evidence/build59/installation.json) · [独立安装](evidence/build59/independent-install.json) · [同包和双架构复核](evidence/build59/independent-package-ci-recheck.json)

## GitHub、官网和应用内更新

- 当前 main 为 `9fd8ad15fca043915069904113e5fb67d82b4948`。已核实候选依赖次序为 main → #119 → #123 → #124。#122 与 #123 分叉，未进入候选。四个 PR 在依赖审计时均为 Draft，GitHub 已提交的正式 review 数均为零。G4 未放行，1.0.8 正式整合、合并和发布后独立安装均未执行。#124 保持 Draft，#120 保持打开。[分支与发布渠道审计](evidence/build59/final-release-baseline.json) · [实施 PR #124](https://github.com/haohongfei2001-png/Riftlet/pull/124) · [总任务 #120](https://github.com/haohongfei2001-png/Riftlet/issues/120)
- 当前公开版本为 1.0.5（31）。官网首页和 stable appcast 均返回 HTTP 200，内容与 main 一致。使用 main 随 App 分发的公钥验过 appcast 及其 DMG 条目的 Ed25519 签名。留存的正式 1.0.5 镜像与 GitHub 资产摘要一致。1.0.8 没有公开下载、正式 Release 或升级记录。公开支持范围仍为 macOS 13 及以上、Apple silicon 和 Intel、普通 Google Chrome 的可编辑 ChatGPT 草稿。[官网](https://riftlet.com/) · [稳定更新源](https://riftlet.com/updates/stable.xml) · [1.0.5 Release](https://github.com/haohongfei2001-png/Riftlet/releases/tag/v1.0.5) · [公开 DMG](https://github.com/haohongfei2001-png/Riftlet/releases/download/v1.0.5/Riftlet-1.0.5.dmg)
