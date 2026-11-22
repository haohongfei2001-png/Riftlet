# Riftlet 1.0.8 最终候选验收

**总体 PARTIAL。** 当前唯一网站验收候选为 build 59。冻结产品提交 `69b76cb025ab552b3480e3af095b627891874712`，树 `7289c35504d9a2a27b82e240fafe175b4779dd16`，页面 SHA-256 为 `b6eee615982d839285ea6af4abb16018939f9be91b18215554e847f4a6eb2215`。#120 保持打开。

| build 59 同包项目 | 状态 |
|---|---|
| G1 普通 Chrome × ChatGPT | NOT_RUN |
| G2 普通 Edge × ChatGPT | NOT_RUN |
| G4 原卡明确失败、原图找回、显式新点击 | NOT_RUN |

## 已复现和修复的实站缺陷

签名 build 58 在两款已登录浏览器均把一次文件输入送入原草稿，随后保留 UNKNOWN。Edge 两张独立系统截图揭示原因。ChatGPT 的最终附件卡把文件显示名改为相同操作 UUID 的 .webp，图片数据仍为 PNG。第二张截图的全部像素、图片 alt 和移除按钮的哈希均已独立核实。[build 58 实站原始记录](BUILD58_ACCEPTANCE.md) · [名称和像素对照](evidence/build58/edge-converted-display-name.json)

build 59 对这一种重绘同时核对原草稿、完整操作 UUID、新卡与移除按钮的归属及图像内容。候选卡出现竞争、局部明确失败或在解码中被替换时维持 UNKNOWN。两款真实隔离引擎各通过 22 项受控回归。双图各保留原草稿、选区和旧附件并各自得到独立回执。非作者审查已复核旧操作只读兼容、实际页面程序大小和原生轻量点击路径。[源码对照](evidence/build59/converted-source-regression.json) · [双架构 CI](https://github.com/haohongfei2001-png/Riftlet/actions/runs/44987854131)

[已登录草稿之前的原生路线与浏览器身份](PRECLICK_ARCHITECTURE.md) · [build 57 历史验收](BUILD57_ACCEPTANCE.md)

## 同一安装包

私有 DMG 大小为 13,775,789 字节，SHA-256 为 `666324176aadc4ffb9fd6fbfd0ca38772a169eb06394401f7abede374f7d3ee6`。App 和镜像各有独立的 Apple 公证票。另一名工程师从只读镜像另行安装，核实 arm64 与 x86_64 签名、Gatekeeper、三个旧版页面指纹及普通、网页、截图三项自检。[签名与安装](evidence/build59/installation.json) · [独立安装](evidence/build59/independent-install.json)

从同一签名 App 提取页面，在两款隔离引擎分别完成 19 项点击前凭据回归和 22 项改名预览回归。独立进程还分别读回 build 56、57、58 留下的待确认和已 START 两种状态。错误调用均被拒绝，续查没有再次输入。[原目标生命周期](evidence/build59/installed-page-results.json) · [改名预览](evidence/build59/installed-converted-previews.json) · [六个旧操作](evidence/build59/old-operations.json)
