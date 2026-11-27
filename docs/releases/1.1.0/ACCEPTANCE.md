# Riftlet 1.1.0（68）验收

## 签名候选实站结果

以[实站验收记录](https://github.com/haohongfei2001-png/Riftlet/blob/ad837a3801049d0798b7c46e55433b6e809bdace/docs/releases/1.1.0/ACCEPTANCE.md)和[逐项 JSON 矩阵](https://github.com/haohongfei2001-png/Riftlet/blob/ad837a3801049d0798b7c46e55433b6e809bdace/docs/releases/1.1.0/evidence/website-matrix.json)为准。候选 DMG 的 SHA-256 为 `9f654539619b87ead785828e83cde631896089abc055602bed805588544511f1`；公开稳定版仍为 1.0.11（67）。

| 组合 | 实站状态 | 已核验范围 |
| --- | --- | --- |
| ChatGPT · Chrome、Edge | PASS | 单图、连续双图、历史重挂及原生拖放、取消；原草稿正文和已有附件保留，未自动发送。补充的反向选区测试仅 Edge 通过，Chrome 未运行。 |
| ChatGPT · Safari | PARTIAL | 原生拖放在原编辑器生成附件。点击受 Safari 的 Apple Events JavaScript 开关阻挡（错误 8）；未运行页面级发送和提交计数。 |
| 其余 54 个组合 | NOT_RUN | 未建立符合条件的已登录专用草稿并完成签名候选实站验收。预检与受控夹具不计作实站通过。 |

## 后续游客态检查

本轮新增云浏览器检查只用游客态，不登录账户。其结果记录为网页观察；即使游客页面显示草稿或附件入口，也不提升上表的签名候选实站状态。上表两项通过和一项部分通过均来自以前的已登录实站记录，不是本轮游客态结果。

## 早期浏览器预检（不是签名候选实站结果）

本表覆盖普通 Chrome、Edge、Safari 与 19 个对话平台。表中两列记录系统核验过的普通浏览器、独立新建的单标签窗口和草稿准入情况。首轮两扇窗口均已核实关闭。可见编辑器和 HTTP 成功状态不能证明账户已登录。实际点击、双图、正文和原附件、唯一输入、无错投、零发送、原图找回及站内接收原生拖放分别需要签名候选回执。

| 平台 | Chrome 专用入口 | Edge 专用入口 | Safari 点击 | 本次预检是否运行签名候选网站测试 |
| --- | --- | --- | --- | --- |
| ChatGPT | Temporary Chat 已登录，有编辑器 | Temporary Chat 已登录，有编辑器 | 浏览器脚本开关关闭 | NOT_RUN |
| Claude | 重定向至账户或登录入口 | 专用入口发生重定向 | 浏览器脚本开关关闭 | NOT_RUN |
| Gemini | 专用入口发生重定向 | 专用入口发生重定向 | 浏览器脚本开关关闭 | NOT_RUN |
| Microsoft Copilot | 专用入口发生重定向 | 专用入口发生重定向 | 浏览器脚本开关关闭 | NOT_RUN |
| Perplexity | 页面提供登录 | 页面提供登录 | 浏览器脚本开关关闭 | NOT_RUN |
| Grok | 账户未确认 | 账户未确认 | 浏览器脚本开关关闭 | NOT_RUN |
| Poe | 重定向至账户或登录入口 | 专用入口发生重定向 | 浏览器脚本开关关闭 | NOT_RUN |
| DeepSeek | 账户未确认 | 专用入口发生重定向 | 浏览器脚本开关关闭 | NOT_RUN |
| Kimi | 页面提供登录 | 页面提供登录 | 浏览器脚本开关关闭 | NOT_RUN |
| 通义千问 | 页面提供登录 | 账户未确认 | 浏览器脚本开关关闭 | NOT_RUN |
| 国际 Qwen | 页面提供登录 | 页面提供登录 | 浏览器脚本开关关闭 | NOT_RUN |
| 豆包 | 账户未确认 | 页面提供登录 | 浏览器脚本开关关闭 | NOT_RUN |
| 腾讯元宝 | 专用入口发生重定向 | 专用入口发生重定向 | 浏览器脚本开关关闭 | NOT_RUN |
| 智谱清言 | 页面提供登录 | 页面提供登录 | 浏览器脚本开关关闭 | NOT_RUN |
| 讯飞星火 | 账户未确认 | 账户未确认 | 浏览器脚本开关关闭 | NOT_RUN |
| Meta AI | 页面提供登录 | 页面提供登录 | 浏览器脚本开关关闭 | NOT_RUN |
| Mistral Vibe | 页面提供登录 | 专用入口发生重定向 | 浏览器脚本开关关闭 | NOT_RUN |
| 百度文心 | 账户未确认 | 账户未确认 | 浏览器脚本开关关闭 | NOT_RUN |
| Z.ai | 账户未确认 | 账户未确认 | 浏览器脚本开关关闭 | NOT_RUN |

普通 Safari 27 收到针对独立本地 QA 标签的 `sfri/dojs` 事件后返回原生错误码 8。系统级 Apple Events 预检返回 0。Safari 的设置位于“设置 → 开发者 → 自动化”，选项名为“允许 Apple 事件中的 JavaScript”。Safari 原生拖放可独立运行，站内接收需另行测量。[Apple 开发者设置](https://developer.apple.com/documentation/safari-developer-tools/developer-settings)

AppKit 测量覆盖三种托盘外观各 41 张截图，以及四次原生拖放手势。接收器拒绝和取消各零次交付，接受活动图和历史图各收到一次原文件 URL。签名候选的站内输入和网页附件身份另行验收。[本机 AppKit 收据](evidence/timeline-native.json) · [浏览器准入收据](evidence/browser-preflight.json)

Chrome 另核对了 10 个官方入口，专用单标签窗口已关闭。Edge 的同项补查收到 Apple Events 超时（−1712），首轮 19 项结果仍按上表记录。两轮均未选择文件或发送消息。

修订后的附件程序在隔离的 Chrome 和 Edge 中各通过 39 项。真实网站与候选的结果由各自的签名包收据判定。[受控浏览器记录](../../../Tests/ConversationProviders/controlled-results.json)
