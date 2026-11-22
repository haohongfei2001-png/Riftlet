# Riftlet 1.0.8 最终候选验收

**总体 PARTIAL。** 当前唯一网站验收候选为 build 59。冻结产品提交 `69b76cb025ab552b3480e3af095b627891874712`，树 `7289c35504d9a2a27b82e240fafe175b4779dd16`，页面 SHA-256 为 `b6eee615982d839285ea6af4abb16018939f9be91b18215554e847f4a6eb2215`。#120 保持打开。

| build 59 同包项目 | 状态 |
|---|---|
| G1 普通 Chrome × ChatGPT | PARTIAL。已登录临时草稿的冷首图通过，暖首图、三组双图及非空选区尚待单独核验。 |
| G2 普通 Edge × ChatGPT | PARTIAL。冷、暖首图及两组快速双图通过。首轮第三组第二张没有 AppKit 按下回执。 |
| G4 原卡明确失败、原图找回、显式新点击 | NOT_RUN |

## 普通 Chrome 的真实冷首击

从最终镜像安装的 App 在全新测试资料库启动。测试窗已核对普通 Chrome 厂商签名、进程出生、窗口、标签和账户菜单。第一张系统截图进入托盘后，验收器直接按下其原行，没有等待网页就绪。原始文档和编辑器的回执比 AppKit 收到的鼠标按下早 1,896.793 毫秒。网页收到同一份 5,516 字节 PNG，文件输入和变更各一次，发送和表单提交均为零。图片按原始 330 × 196 像素解码，原卡取得唯一 `attachmentAccepted`，托盘随后收起。鼠标事件由软件定向投递。

原验收器读取旧字段，第一次报告 `POSITIVE_START_NOT_VERIFIED`。非作者从原 SQLite 和现场页面事件读回当前字段 `attachmentAcceptanceEvidence`，核对了同一次操作、调用、卡片及原图。该图没有重投。草稿开场时没有旧附件，本次只计冷首图。[同包操作与证据哈希](evidence/build59/chrome-live-candidate.json) · [独立只读复核](evidence/build59/chrome-cold-independent.json)

## 普通 Edge 的真实草稿

同包冷首图和暖首图均进入已登录的原临时草稿，原生凭据分别比按下早 2,468.786 和 1,090.216 毫秒。前两组快速双图的实际按下间隔为 1,517.955 和 1,574.502 毫秒。加上第三组首图，共七张不同原图，每张的原卡、完整像素、一次输入和唯一 SQLite START 均被核实。末次检查仍能识别前六张附件，整个草稿零发送、零表单提交。[逐图、逐次点击及回执](evidence/build59/edge-live-candidate.json)

首轮第三组第二张的外部鼠标投递已记录。AppKit 没有对应按下，原图仍在，数据库没有为它创建投递操作。验收进程外层的 40 秒超时终止了运行器；后续再从原网页和 SQLite 只读确认现场。此次双图没有通过。这张图没有重投。[未到达的原鼠标事件](evidence/build59/edge-unconfirmed-mouse.json)

## 已复现和修复的实站缺陷

签名 build 58 在两款已登录浏览器均把一次文件输入送入原草稿，随后保留 UNKNOWN。Edge 两张独立系统截图揭示原因。ChatGPT 的最终附件卡把文件显示名改为相同操作 UUID 的 .webp，图片数据仍为 PNG。第二张截图的全部像素、图片 alt 和移除按钮的哈希均已独立核实。[build 58 实站原始记录](BUILD58_ACCEPTANCE.md) · [名称和像素对照](evidence/build58/edge-converted-display-name.json)

build 59 对这一种重绘同时核对原草稿、完整操作 UUID、新卡与移除按钮的归属及图像内容。候选卡出现竞争、局部明确失败或在解码中被替换时维持 UNKNOWN。两款真实隔离引擎各通过 22 项受控回归。双图各保留原草稿、选区和旧附件并各自得到独立回执。非作者审查已复核旧操作只读兼容、实际页面程序大小和原生轻量点击路径。[源码对照](evidence/build59/converted-source-regression.json) · [双架构 CI](https://github.com/haohongfei2001-png/Riftlet/actions/runs/44987854131)

[已登录草稿之前的原生路线与浏览器身份](PRECLICK_ARCHITECTURE.md) · [build 57 历史验收](BUILD57_ACCEPTANCE.md)

## 同一安装包

私有 DMG 大小为 13,775,789 字节，SHA-256 为 `666324176aadc4ffb9fd6fbfd0ca38772a169eb06394401f7abede374f7d3ee6`。App 和镜像各有独立的 Apple 公证票。另一名工程师从只读镜像另行安装，核实 arm64 与 x86_64 签名、Gatekeeper、三个旧版页面指纹及普通、网页、截图三项自检。[签名与安装](evidence/build59/installation.json) · [独立安装](evidence/build59/independent-install.json)

从同一签名 App 提取页面，在两款隔离引擎分别完成 19 项点击前凭据回归和 22 项改名预览回归。独立进程还分别读回 build 56、57、58 留下的待确认和已 START 两种状态。错误调用均被拒绝，续查没有再次输入。[原目标生命周期](evidence/build59/installed-page-results.json) · [改名预览](evidence/build59/installed-converted-previews.json) · [六个旧操作](evidence/build59/old-operations.json)

GitHub 的 arm64、x86_64 两项 CI 均在冻结提交上通过。每个架构执行 1,434 个 Swift 测试、19 项点击前凭据、22 项改名预览及 8 项离线恢复测试。原始 Actions 归档、架构与散列可逐项核查。[双架构作业记录](evidence/build59/ci.json)
