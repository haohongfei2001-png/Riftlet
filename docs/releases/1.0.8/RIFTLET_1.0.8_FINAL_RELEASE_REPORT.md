# Riftlet 1.0.8 最终发行报告 · 2026-11-22

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
