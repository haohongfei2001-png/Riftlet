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
