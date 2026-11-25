# 1.1.0 现场验收矩阵

本表覆盖普通 Chrome、Edge、Safari 与 19 个对话平台。表中两列记录系统核验过的普通浏览器、独立新建的单标签窗口和草稿准入情况。两扇窗口均已精确关闭。可见编辑器和 HTTP 成功状态不能证明账户已登录。实际点击、双图、正文和原附件、唯一输入、无错投、零发送、原图找回及站内接收原生拖放分别需要签名候选回执。

| 平台 | Chrome 专用入口 | Edge 专用入口 | Safari 点击 | 签名候选网站验收 |
| --- | --- | --- | --- | --- |
| ChatGPT | Temporary Chat 已登录，有编辑器 | Temporary Chat 已登录，有编辑器 | 浏览器脚本开关关闭 | NOT_RUN |
| Claude | 专用入口发生重定向 | 专用入口发生重定向 | 浏览器脚本开关关闭 | NOT_RUN |
| Gemini | 专用入口发生重定向 | 专用入口发生重定向 | 浏览器脚本开关关闭 | NOT_RUN |
| Microsoft Copilot | 专用入口发生重定向 | 专用入口发生重定向 | 浏览器脚本开关关闭 | NOT_RUN |
| Perplexity | 页面提供登录 | 页面提供登录 | 浏览器脚本开关关闭 | NOT_RUN |
| Grok | 账户未确认 | 账户未确认 | 浏览器脚本开关关闭 | NOT_RUN |
| Poe | 专用入口发生重定向 | 专用入口发生重定向 | 浏览器脚本开关关闭 | NOT_RUN |
| DeepSeek | 账户未确认 | 专用入口发生重定向 | 浏览器脚本开关关闭 | NOT_RUN |
| Kimi | 页面提供登录 | 页面提供登录 | 浏览器脚本开关关闭 | NOT_RUN |
| 通义千问 | 页面提供登录 | 账户未确认 | 浏览器脚本开关关闭 | NOT_RUN |
| 国际 Qwen | 页面提供登录 | 页面提供登录 | 浏览器脚本开关关闭 | NOT_RUN |
| 豆包 | 账户未确认 | 页面提供登录 | 浏览器脚本开关关闭 | NOT_RUN |
| 腾讯元宝 | 专用入口发生重定向 | 专用入口发生重定向 | 浏览器脚本开关关闭 | NOT_RUN |
| 智谱清言 | 页面提供登录 | 页面提供登录 | 浏览器脚本开关关闭 | NOT_RUN |
| 讯飞星火 | 账户未确认 | 账户未确认 | 浏览器脚本开关关闭 | NOT_RUN |
| Meta AI | 页面提供登录 | 页面提供登录 | 浏览器脚本开关关闭 | NOT_RUN |
| Mistral Vibe | 专用入口发生重定向 | 专用入口发生重定向 | 浏览器脚本开关关闭 | NOT_RUN |
| 百度文心 | 账户未确认 | 账户未确认 | 浏览器脚本开关关闭 | NOT_RUN |
| Z.ai | 账户未确认 | 账户未确认 | 浏览器脚本开关关闭 | NOT_RUN |

普通 Safari 27 收到针对独立本地 QA 标签的 `sfri/dojs` 事件后返回原生错误码 8。系统级 Apple Events 预检返回 0。Safari 的设置位于“设置 → 开发者 → 自动化”，选项名为“允许 Apple 事件中的 JavaScript”。Safari 原生拖放可独立运行，站内接收需另行测量。[Apple 开发者设置](https://developer.apple.com/documentation/safari-developer-tools/developer-settings)

AppKit 测量覆盖三种托盘外观各 41 张截图，以及四次原生拖放手势。接收器拒绝和取消各零次交付，接受活动图和历史图各收到一次原文件 URL。签名候选的站内输入和网页附件身份另行验收。[本机 AppKit 收据](evidence/timeline-native.json) · [浏览器准入收据](evidence/browser-preflight.json)
