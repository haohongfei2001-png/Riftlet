# Riftlet 品牌专项：真实产品与可宣称范围

核对日期：2026-10-30（北京时间）。本报告为只读核查，不触碰真实 Mac、Chrome 或任何工程分支。事实来自 GitHub 插件实读 PR、精确提交文件和最新专项交接；设计建议与工程验收分开。

## 1. 实时工程基线

| 对象 | 实际 HEAD | 当前状态 |
| --- | --- | --- |
| main / 旧官网 | `eba1a4fc77648a665e1d5c1f2609df1314c3b079` | 未改变 |
| 正式原生 PR #1 | `98e66a956d55b5fac71718bc627dd89705b2a506` | Open / Draft / 未合并 |
| 统一交接 PR #15 | `623d3725d0b3096f1dc7332e6cae11f47f7002c2` | Open / Draft / 未合并；相对正式产品只有两份交接文件 |
| 自然首击独立分支 | `fcfd86780d1fe3e993caa23ad02d2fceeadf8954` | 本地捕获与隔离恢复交接；没有新 Web 首击成功 |

来源：[PR #1](https://github.com/haohongfei2001-png/Riftlet/pull/1)、[PR #15](https://github.com/haohongfei2001-png/Riftlet/pull/15)、[最新协调评论](https://github.com/haohongfei2001-png/Riftlet/pull/15#issuecomment-6497693995)、[自然首击分支](https://github.com/haohongfei2001-png/Riftlet/tree/fcfd86780d1fe3e993caa23ad02d2fceeadf8954)。

不能从 main 的早期 README/AGENTS，或设计目录当时写下的“尚未原生实现”“反馈尚未部署”，推断当前产品状态。设计目录的来源基线是 1920e056，现已发生正式集成；原始文档不应改写历史，官网应使用当前核实结论。

## 2. 品牌必须承载的产品机制

Riftlet 的价值不是增加另一种截图快捷键，而是缩短“已经看见 → 作为上下文给 ChatGPT”的搬运环节。用户保留 macOS 截图习惯；刚截到的图自然在边缘等候；一次直接点击将其追加到点击瞬间的受支持当前草稿；最终发送仍由用户决定。

产品定义来源：[PRODUCT.md](https://github.com/haohongfei2001-png/Riftlet/blob/98e66a956d55b5fac71718bc627dd89705b2a506/docs/PRODUCT.md)、[交互契约](https://github.com/haohongfei2001-png/Riftlet/blob/98e66a956d55b5fac71718bc627dd89705b2a506/docs/INTERACTION_CONTRACT_2026-10-27.md)、[首版体验要求](https://github.com/haohongfei2001-png/Riftlet/blob/98e66a956d55b5fac71718bc627dd89705b2a506/docs/RELEASE_UX_REQUIREMENTS_2026-10-27.md)。

适宜的品牌理解：**屏幕内容进入对话的一个轻量入口。** 这是一种截图到草稿的交接工具；不把它描述为能解读屏幕、回答问题、生成内容的 AI 助手，也不承担通用剪贴板库、文件架或全能截图编辑器的承诺。

### 不可变的机制细节

- 原生 macOS 工具，非浏览器面板；当前实现不要求浏览器扩展。
- 正常目标行为只有“系统截图＋点击边缘微图”两步；不强制先聚焦发言框，不加日常确认、目标选择或拖拽。
- 图片保持原始比例，部分伸出极细且固定的垂直边界；不是统一裁成方形的图库。
- 点击瞬间的明确当前窗口/草稿绑定为目标，后续切换不得重定向；不能智能猜后台聊天。
- 追加未发送附件；保护现有文字、选区和已有附件；永不自动发送消息。
- 无待用图时边界本身完全消失；它不是永久挂在屏幕边上的装饰线。
- 历史保留与可见退出分离；移除/归档不删除系统原图，也不删除 ChatGPT 草稿附件。

## 3. 网页演示必须采用的状态顺序

1. 合成截图出现，等比例微图部分露在边缘。
2. 用户点击，仅产生轻微按压反馈；此刻不消失。
3. 模拟目标检查与附件实际开始的正向信号。必须明确为本地模拟；点击、排队、占位图不等同真实开始。
4. 收到模拟开始信号后立即快速吞噬，退出可见队列；原始素材与内部状态仍保留。
5. 模拟最终附件完成发生在稍后；草稿的原文字和旧附件维持原状；不得再次吞噬、弹成功 Toast 或自动发送。
6. 无有效目标或未开始：图留原位。
7. 已开始但结果未知：保持隐藏，进入历史待核实，不自动重传，不自动重生。
8. 明确且安全获准失败：目标设计要求恢复正常可点的图，用户再次点击才发起新尝试。但当前真实安全失败/重试准入关闭，网站可做“目标行为的条件模拟”，不能当成已验证功能。

**吞噬仅代表退出可见队列，不代表最终成功。** 官网的普通访客无需接触 READY、lease、nonce 等工程术语；可用“开始附加”“图片在草稿中”“由你发送”等自然语言。开发说明单列严格语义。

## 4. 当前实际能力与发布状态

| 能力 | 实际实现 / 证据 | 官网表述边界 |
| --- | --- | --- |
| 本地系统截图收录、微图、历史、隐藏/暂停 | 已进入正式 App；软件回归与部分原生窗口/本地恢复证据 | 可说“原生实现已具备”，配内部测试状态；不声称全场景实机验收 |
| 系统截图→Chrome ChatGPT 草稿→开始→快吞噬→完成 | 历史 F/H 新操作有受限真实样本；H为软件 CGEvent、预绑定场景 | 可以展示机制并说明受限内部 Beta；不能宣称普通用户现已稳定即用 |
| 普通 App 启动 | 默认 `.capture`；生产附件能力关闭 | 不使用“立即下载，开始使用”主 CTA；使用“体验交互”“查看测试进展/当前范围” |
| 受限附件范围 | Chrome 中文 ChatGPT 普通已有对话；单帧非交错 RGBA8 PNG≤8MiB，≤16,777,216像素 | 不推广到 Home新草稿、Work、临时对话、Safari、其他浏览器或原生 ChatGPT App |
| 安全失败恢复/重试 | Core/设计有相应模型，但真实准入关闭 | 不宣传“失败自动恢复已可靠交付”；演示必须标明目标行为 |
| 内置区域/窗口/全屏截图 | 三模式及生命周期在正式工程；CI真实生产组件只有区域链路受限 PASS，窗口/全屏受外部重叠保护 NOT_RUN | 可说内置截图“已实现、实机验证中”；不作为全验收卖点 |
| 内置截图→ChatGPT | `applicationScreenshot` 来源仍未准入 | 演示中的系统截图与内置截图来源不能混淆，不宣称内置三模式现已可附加 |
| 无 / 磁力吸引 | 仅这两种新截图入场装饰，已实现；无正式产品默认裁决 | “两种入场方式”；别宣称磁力默认，更不能让此设置关闭独立快速吞噬 |
| Feedback | 正式 `FeedbackHost.endpoint` 已配置真实HTTPS；服务接收、持久化、私有投递和测试数据清理已验证 | 可说反馈系统已集成；完整 Mac 窗口到云端 E2E 仍未完成，不把历史 endpoint=nil 当当前事实 |
| 安装发行 | 0.1.0/build1，ARM与Intel CI包，ad-hoc；声明部署最低macOS13，CI主要macOS15 | 尚无 Developer ID/公证/Gatekeeper实机结论；没有公开发行承诺 |

受限范围的权威交接：[SYSTEM_SCREENSHOT_RESTRICTED_ADMISSION.md](https://github.com/haohongfei2001-png/Riftlet/blob/98e66a956d55b5fac71718bc627dd89705b2a506/docs/SYSTEM_SCREENSHOT_RESTRICTED_ADMISSION.md)。源码交叉核对：[ApplicationMode.swift](https://github.com/haohongfei2001-png/Riftlet/blob/98e66a956d55b5fac71718bc627dd89705b2a506/Sources/RiftletApp/ApplicationMode.swift)、[SystemScreenshotWebCandidate.swift](https://github.com/haohongfei2001-png/Riftlet/blob/98e66a956d55b5fac71718bc627dd89705b2a506/Sources/RiftletAdapters/SystemScreenshotWebCandidate.swift)、[FeedbackHost.swift](https://github.com/haohongfei2001-png/Riftlet/blob/98e66a956d55b5fac71718bc627dd89705b2a506/Sources/RiftletApp/FeedbackHost.swift)。

## 5. 最新自然首击专项不会改变官网发布口径

最新 `fcfd8678` 的 local-only 交接验证了真实系统 PNG 的隔离导入、原生微图和历史观察、无目标点击安全拒绝、隐藏/暂停/退出/重启保留。此运行使用明确 TEST-ONLY 四文件 overlay、独立 bundle/目录、普通 capture模式，不能充当正式统一 App 验收。

当前 Chrome 首次真实附加仍因测试资源占用而 BLOCKED；没有新 Web input/start/complete。自然物理首次点击为 NOT_RUN，没有成功率分母。内置三模式 CI 仍区域 PASS、窗口/全屏 NOT_RUN，合计 PARTIAL。两张来源未能归因的本地内置输出被保留，不能当成功样本或直接定性为 Bug。

独立已审 `c308d46` 原生修复和可选诊断尚待唯一负责人按14个路径合入并完成组合验证。本品牌任务不执行此合流，也不把专项分支修复宣称已在正式 App 发布。

来源：[本地隔离结果](https://github.com/haohongfei2001-png/Riftlet/blob/fcfd86780d1fe3e993caa23ad02d2fceeadf8954/engineering/evidence/2026-10-30-natural-first-click/local-only/README.md)、[原自然首击交接](https://github.com/haohongfei2001-png/Riftlet/blob/fcfd86780d1fe3e993caa23ad02d2fceeadf8954/engineering/evidence/2026-10-30-natural-first-click/README.md)。

## 6. “薄界”与网站视觉的可复用事实

正式源码 `RiftConfiguration` 默认：完整微图适配72×56pt，隐藏25%，60pt行距，细边0.5pt，外侧14pt，最小44×44pt命中；吞噬0.120s、补位0.160s、reduced motion0.080s。这些是可调工程起点，不是品牌应宣传的性能指标。`emptyTraceLength=24`只是旧配置解码字段，不能借它恢复空队列短线。

原生颜色已形成安静青绿体系：浅色背景#F7F9F8、深色#171E1C；文字#172521/#EEF4F0；强调#087F73/#58CDB8。文字使用系统NSFont，中文系统回退。网页可以扩展品牌色与标题字体，但不把产品截图染成品牌色，不为品牌特效扩大实际微图尺寸或添加整块图库底板。

推荐在官网使用两个视觉尺度：一处明确整体桌面位置，一处标明放大的交互细节。放大演示不伪装成原生真实大小。主视觉可用遮挡边界和内容跨边界运动建立品牌识别；不需要黑洞、发光粒子、科幻传送门。

来源：[RiftConfiguration.swift](https://github.com/haohongfei2001-png/Riftlet/blob/98e66a956d55b5fac71718bc627dd89705b2a506/Sources/RiftletUI/RiftConfiguration.swift)、[RiftVisualStyle.swift](https://github.com/haohongfei2001-png/Riftlet/blob/98e66a956d55b5fac71718bc627dd89705b2a506/Sources/RiftletUI/RiftVisualStyle.swift)、[ArrivalMotionMode.swift](https://github.com/haohongfei2001-png/Riftlet/blob/98e66a956d55b5fac71718bc627dd89705b2a506/Sources/RiftletUI/ArrivalMotionMode.swift)、[APPKIT_SPEC.md](https://github.com/haohongfei2001-png/Riftlet/blob/98e66a956d55b5fac71718bc627dd89705b2a506/design/final-system-20261028/APPKIT_SPEC.md)。

## 7. 文案可用 / 避免

### 可用主张（作为明确标注内部测试中的产品定位）

- 把屏幕上的这一刻，带进对话。
- 截图停在边缘，一点进入草稿。
- Your screenshots. One click closer to the conversation.
- A quiet handoff from your screen to your ChatGPT draft.
- 你照常截图，Riftlet 留在边缘；何时发送，由你决定。

其中“当前受支持的ChatGPT草稿”应在解释性副标题或范围区清楚出现，不能只写“任何AI”“所有对话”。页面一开始可显式标“内部测试中 / In development”，详尽工程限制放FAQ/状态区，既准确也不让首页变验收报告。

### 避免

- 首创、一切AI、全平台、所有截图格式、无限附件、从不失败、零等待、100ms上传、自动识别/理解屏幕、ChatGPT官方集成。
- 完全离线、永不联网：附加本身进入ChatGPT；反馈提交也会联网。可以准确说明本地截图队列与历史、仅用户主动操作发生相关传递。
- 所有系统截图都能排除Riftlet自身：当前没有全入口保证；不把内置捕获能力外推到Screenshot.app。
- 已公证、安全无权限、所有macOS版本支持、普通用户Beta全功能可用。
- 把本地交互演示说成正在连接真实ChatGPT；把模拟失败重生说成真实安全重试已开放。
- 虚构客户Logo、评价、下载量、性能倍数或获奖。

## 8. 最小页面状态说明建议

“Riftlet 正在内部测试。此页提供本地交互演示，不读取你的屏幕或对话，也不会向 ChatGPT 发送内容。当前附件流程仅在限定的 Chrome／ChatGPT 场景取得验证；公开版本尚未发布。”

英文可独立写为：“Riftlet is in internal testing. This local demo uses sample content; it does not read your screen or connect to ChatGPT. Attachment support is currently limited to specific Chrome and ChatGPT test conditions. A public release is not available yet.”

这段是网站状态说明，不需要成为整站不断重复的警告。主CTA仍可积极邀请体验机制，公开安装入口应留待真实发行后替换。
