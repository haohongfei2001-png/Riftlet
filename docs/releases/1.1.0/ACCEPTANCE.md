# Riftlet 1.1.0（68）实站验收

磁盘映像 SHA-256 为 `9f654539619b87ead785828e83cde631896089abc055602bed805588544511f1`。本表覆盖 19 个网站、57 个普通浏览器与网站组合。每个组合的原草稿、输入次数、正文与旧附件、历史重选、原图、发送及拖放结果均可在逐项矩阵中核对。[逐项 JSON](evidence/website-matrix.json) · [签名和独立安装](evidence/signed-candidate.json) · [65 至 68 应用内升级](evidence/upgrade65to68-private.json)

| 平台 | Chrome 点击 | Chrome 拖放 | Edge 点击 | Edge 拖放 | Safari 点击 | Safari 拖放 |
| --- | --- | --- | --- | --- | --- | --- |
| ChatGPT | 单图、双图通过 | 通过 | 单图、双图通过 | 通过 | 脚本授权关闭 | 通过 |
| Claude | 登录入口 | 未运行 | 会话未核实 | 未运行 | 脚本授权关闭 | 未运行 |
| Gemini | 会话未核实 | 未运行 | 会话未核实 | 未运行 | 脚本授权关闭 | 未运行 |
| Microsoft Copilot | 会话未核实 | 未运行 | 会话未核实 | 未运行 | 脚本授权关闭 | 未运行 |
| Perplexity | 登录入口 | 未运行 | 登录入口 | 未运行 | 脚本授权关闭 | 未运行 |
| Grok | 会话未核实 | 未运行 | 会话未核实 | 未运行 | 脚本授权关闭 | 未运行 |
| Poe | 登录入口 | 未运行 | 会话未核实 | 未运行 | 脚本授权关闭 | 未运行 |
| DeepSeek | 会话未核实 | 未运行 | 会话未核实 | 未运行 | 脚本授权关闭 | 未运行 |
| Kimi | 登录入口 | 未运行 | 登录入口 | 未运行 | 脚本授权关闭 | 未运行 |
| 通义千问 | 登录入口 | 未运行 | 会话未核实 | 未运行 | 脚本授权关闭 | 未运行 |
| 国际 Qwen | 登录入口 | 未运行 | 登录入口 | 未运行 | 脚本授权关闭 | 未运行 |
| 豆包 | 会话未核实 | 未运行 | 登录入口 | 未运行 | 脚本授权关闭 | 未运行 |
| 腾讯元宝 | 会话未核实 | 未运行 | 会话未核实 | 未运行 | 脚本授权关闭 | 未运行 |
| 智谱清言 | 登录入口 | 未运行 | 登录入口 | 未运行 | 脚本授权关闭 | 未运行 |
| 讯飞星火 | 会话未核实 | 未运行 | 会话未核实 | 未运行 | 脚本授权关闭 | 未运行 |
| Meta AI | 登录入口 | 未运行 | 登录入口 | 未运行 | 脚本授权关闭 | 未运行 |
| Mistral Vibe | 会话未核实 | 未运行 | 会话未核实 | 未运行 | 脚本授权关闭 | 未运行 |
| 百度文心 | 会话未核实 | 未运行 | 会话未核实 | 未运行 | 脚本授权关闭 | 未运行 |
| Z.ai | 会话未核实 | 未运行 | 会话未核实 | 未运行 | 脚本授权关闭 | 未运行 |

“登录入口”表示独立 QA 页显示登录或跳到了登录路径。“会话未核实”表示这次未能确认专用已登录草稿。普通 Safari 的 Apple Events JavaScript 运行返回错误码 8。其余 18 站逐一核对了新会话入口，3 站出现登录控件，1 站重定向至登录页，3 站离开可验收的新草稿，11 站未能同时确认已登录的原草稿和附件入口。[Safari 逐站记录](evidence/safari-provider-landing-audit.json)

六次已核验的 Chrome 和 Edge 点击均产生一次输入、一次 change 及一条持久 START，且均为原草稿中的新附件。双图时保留了非空正文和旧卡，发送与表单提交合计为零。[签名候选点击收据](evidence/chatgpt-clicks68.json)

Chrome 和 Edge 均从历史中再次选中原 PNG，创建了新的操作和 invocation。在两款浏览器中，一次原生拖入分别得到一个可信 drop 和一张像素吻合的新卡。Esc 取消时没有 drop，原图仍在活动托盘。Safari 在原生编辑器内展示了唯一同名附件，九个预览像素样本与原图吻合。实站非折叠选区在准备环节未能核实，记为 NOT_RUN。[Chrome 与 Edge 读回记录](evidence/real-signed-chatgpt68.json) · [Safari 拖放收据](evidence/safari-signed-native-drop.json)

本机独立 AppKit 接收器还覆盖原生拖放接受、拒绝、取消，以及三种托盘形态分别滚动浏览 41 张截图。受控浏览器的每款 39 项回归记录另附。[本机时间线与拖放收据](evidence/timeline-native.json) · [受控网页回归](../../../Tests/ConversationProviders/controlled-results.json)

公开官网、GitHub Release 和 Sparkle 稳定源均继续提供 1.0.11（67）。[官网](https://riftlet.com/) · [公开发行](https://github.com/haohongfei2001-png/Riftlet/releases/latest) · [Sparkle](https://riftlet.com/updates/stable.xml)
