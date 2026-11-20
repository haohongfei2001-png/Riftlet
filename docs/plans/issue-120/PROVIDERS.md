# Provider 能力、适配边界与同轮验证

调查日期：2026-11-20（Asia/Shanghai）。本文是架构研究证据与实施建议，不是兼容性通过报告。未登录任何 AI 账户，未操作真实草稿，未调用付费 API，未发送任何消息。所有新 Provider 的网页 DOM、上传事件和登录实测均为 `NOT_RUN`；官方产品文档只能证明服务宣称具备的功能。

## 1. 技术裁决

1. 采用一个共享事务运行时和站点专属 `ConversationProvider`。浏览器执行脚本、进程/窗口/标签身份属于 `BrowserHost`；站点的会话/编辑器/附件成员/成功与失败语义属于 Provider。Provider 代码不得分叉成 Chrome/Edge/Safari/Brave 四份。
2. 接收、处理完成、视觉理解是三件事。`acceptedIntoDraft` 证明本图已进入原草稿；`processingReady` 只说明网站给出了本附件的可发送/处理完成信号；模型是否理解图像不是 Riftlet 附加功能的验收目标，也不应通过自动发送来验证。
3. 不能继承“DeepSeek 一定只支持 OCR”的旧结论。当前第一方 API 文档既包含视觉输入，也区分纯文字解析和含图解析；这些不能推出当前网页版、当前账号、当前模式开放了哪一种能力。对该平台采取运行时模式能力检查，标记 `visual / textRecognition / unknown`，不偷偷切换模型或模式。
4. 国内千问与国际 Qwen 分开登记（`qianwen-cn`、`qwen-international`）。同品牌不意味着同源、同登录状态、同上传组件或同附件回执。Kimi 的官方帮助存在 `kimi.ai` 与 `kimi.com` 的域名和路径变化，也必须按实际最终 origin 验证，不能通配所有子域。
5. 扩展候选都在本轮调查/实施预算内；核心四平台优先。Kimi、国内千问、豆包优先反映中国用户价值，Perplexity 具备清晰官方图片上传文档，可作为另一独立实现。国际 Qwen 与 Grok 根据剩余实施与实测成本纳入，不能靠已写代码把未经测试组合标为支持。
6. 官方网页上传能力不是对 DOM 注入的稳定 API 承诺。上线需要各 Provider 的实际已登录草稿验证及对照失败场景；不要建立“找到任意 file input 即可上传”的通用插件。

## 2. 第一方证据与范围

以下 URL 在本次研究中检索或打开过。检索结果中的第三方千问仿站、阿里云社区用户文章、第三方 DeepSeek 新闻均未用作核心能力证明。限制值属于网页文档快照，只用于准备测试，不应写死成永久规则。

| Provider | 第一方功能证据 | 具体实现必须另证的内容 | 本轮建议 |
|---|---|---|---|
| ChatGPT / `chatgpt.com` | S1/S2：网页支持图片输入及照片/文件添加；PNG、JPEG、静态 GIF；文档列出单图 20 MB，套餐/账户有配额差异 | 保留当前已验证回执语义；临时与保存会话、项目内聊天、编辑已有消息是不同 surface；不能将上传到 Library/项目知识库算进入草稿 | 核心；沿用 1.0.7 最新已验证实现作默认 Provider |
| Claude / `claude.ai` | S3：聊天区通过加号添加图片/文件，支持拖放与粘贴；PNG/JPEG/GIF/WebP；区分聊天附件与 Project 文件 | 当前 editor 类型、精确 input、临时卡片/处理中/错误、附件与原文作用域，均未实测 | 核心；先只支持已验证的普通对话草稿，不误写 Project Files |
| Gemini / `gemini.google.com` | S4：网页图片/文件上传要求登录；单次提示可加多文件，配额与账户类型相关；Gemini in Chrome 是另一产品 surface | main web app 与浏览器侧面板、Canvas、Gems 配置、Drive picker 不应混为一格；账户/地区允许与现有 DOM 必须探测 | 核心；主网页普通草稿先行，拒绝配置页和不可确认的侧面板 |
| DeepSeek / `chat.deepseek.com` | S5/S6：第一方 API 提供图片输入、文件解析，官方说明包含网页/App 类似能力；纯文字解析与图文解析不同 | 2026-11-20 网页读取返回 403；不能证明 live DOM、目前模式/账户限制、选图入口或处理回执 | 核心开发；真实探查前能力 `unknown`，不写“仅 OCR”，不从 API 限额推导网页限额 |
| Kimi / 最终 origin 待实测确认 | S7：官方概览明确网页及图片文件；S8：当前入门指南描述原生多模态及图像理解 | 默认聊天、Agent、Swarm、PPT/文档等 surface 有区别；帮助域名与聊天域名不能互当 allowlist；具体模式、账户配额未验证 | 本轮扩展优先；能力与编辑器按实际 surface 认证 |
| 国内千问 / `www.qianwen.com` | S9：官方首页确认品牌/站点，正文仅有一行，未提供足够上传细节 | 图片输入、模式、文件限制、草稿身份及 DOM 均待真网页确认；不将百炼 API、千问办公或国际 Qwen 当替代证明 | 本轮扩展优先；证据不足保持 `NOT_RUN` |
| 国际 Qwen / `chat.qwen.ai` | S10：官方 Qwen 发布文描述 Qwen Chat 的图片输入/编辑；S11：目标页抓取结果为系统不支持/下载入口 | 本次无法证明桌面正常上传 UI；不能据抓取 UA 的提示判定 macOS 不支持；必须真实桌面浏览器复验 | 与国内千问分开；复用公共工具，不共享未经证明 selector |
| 豆包 / `www.doubao.com` | S12：第一方隐私文本说明对话包含图片、文件输入；仅支持功能存在的有限证明，不证明 Web DOM | 最新政策更新 11-19、11-26 生效；当前网页版与 App/桌面版 surface 差异、上传限额均未实测 | 本轮扩展优先，须真实网页原草稿确认 |
| Perplexity / `www.perplexity.ai` | S13/S14：官方 Help 明确桌面图片上传、附加按钮及拖放；图片可作为查询上下文；S15 说明不同计划限额不同 | 首屏查询输入与会话 follow-up、Project 文件库、图像生成不是同一个 composer；跨模式变更要使旧 ticket 失效 | 本轮扩展；文档充分，仍需登录实测 |
| Grok / `grok.com` | S16：官方 FAQ 明确网页聊天图片和文件上传 | 与 X 内 Grok、Imagine/编辑器、Grok Bot 不混用；当前草稿和 DOM 未测 | 可选扩展，不能侵占核心风险修复时间 |

### 来源索引

- S1 https://help.openai.com/en/articles/8400551-chatgpt-image-inputs-faq
- S2 https://help.openai.com/en/articles/8555545-uploading-images-and-files-in-chatgpt
- S3 https://support.claude.com/en/articles/8241126-upload-files-to-claude
- S4 https://support.google.com/gemini/answer/14903178?co=GENIE.Platform%3DDesktop&hl=en
- S5 https://api-docs.deepseek.com/zh-cn/guides/vision/
- S6 https://api-docs.deepseek.com/zh-cn/guides/document_parsing/ and https://api-docs.deepseek.com/zh-cn/guides/build_a_chatbot/
- S7 https://www.kimi.ai/zh-hans/help/getting-started/overview
- S8 https://www.kimi.ai/zh-hans/help/getting-started/agentic-chat
- S9 https://www.qianwen.com/
- S10 https://qwen.ai/blog?id=qwen-vlo (search-index content available; opened body unreadable)
- S11 https://chat.qwen.ai/
- S12 https://www.doubao.com/legal/privacy
- S13 https://www.perplexity.ai/help-center/en/articles/10354840-uploading-images-on-perplexity
- S14 https://www.perplexity.ai/help-center/en/articles/10354807-file-uploads
- S15 https://www.perplexity.ai/help-center/en/articles/11187416-which-perplexity-subscription-plan-is-right-for-you
- S16 https://docs.x.ai/grok/faq

## 3. Provider 最小契约（补充建议，最终接口以 ARCHITECTURE.md 为准）

最终接口和副作用边界见 [ARCHITECTURE.md](ARCHITECTURE.md)，工作分工见 [WORK_PACKAGES.md](WORK_PACKAGES.md)。

Swift 保存声明与打包资源；JavaScript 运行时执行同一 Provider 定义。避免 Swift/JS 各自维护一份能力语义。Swift 类型的最终命名由集成人与现有代码对齐。

```swift
struct ProviderManifest: Codable, Sendable {
    let id: String
    let version: Int
    let allowedOrigins: [String] // 精确 https origin；不匹配相似域/任意子域
    let supportedSurfaces: [String]
    let runtimeResource: String
}

struct ProviderCapability: Codable, Sendable {
    let providerID: String
    let surface: String
    let canAttachImage: Bool
    let semanticMode: ImageSemanticMode // visual, textRecognition, unknown
    let reason: CapabilityReason?
}

```

`ConversationProvider` 公共协议只在 [ARCHITECTURE.md §4](ARCHITECTURE.md#4-swift-接口草案) 定义；本节不定义第二套并行接口。以下 probe/prepare/observe 是 ProviderProgram 内的页面职责，由共同运行时调用。

不让 Provider 任意调用 native 上传。所有有副作用的入口都必须经过共享运行时的单次输入许可；Provider 只提供被严格校验的目标绑定与证据提取规则。`probe`/`observe` 不得触发文件选择、改文、自动换模式、发送消息或重新赋 file input。

页面侧接口职责：

- `matchSurface`: 精确 origin + 页面路由 + 正在使用的聊天 surface。登录页、项目资料库、账号头像上传、反馈窗口、图像生成器、嵌入 iframe 均不得被通用 input 规则接纳。
- `probeComposer`: 返回唯一正在使用的 editor/root，及图片上传可用/明确禁用/未知；找到多个可用编辑器而无法识别原编辑器时拒绝。支持 textarea/contenteditable 的公共工具，不能猜各站一定使用哪种框架。
- `bindDraft`: 生成 document nonce、composer nonce、draft epoch、route fingerprint、active surface/mode fingerprint，保存现存附件集合与原文/选区的内存快照。URL 只是辅助，不是草稿唯一身份。
- `prepareInput`: 选择归属该 composer 的明确 input，验证 `accept`、disabled 状态、已有 FileList 和附件库存。若站点异步创建 input，可在同一目标下有限等待并重新校验；不得尝试多个 input。
- `commitOnce`: 共用原子 fence 先写，再执行已验证的一种传输动作。禁止 `change` 未观察成功就补发 `input`、`drop`、paste、第二次赋值等“兜底”。方法完成仅表示本地调用完成。
- `collectEvidence`: 只返回归属于 ticket 的结构化候选；共享 verifier 决定是否接受。Provider 不可直接让原图消失。
- `observeOriginal`: 只读观察旧 operation；原节点替换必须提供经测试的同草稿/同附件关联规则，不能用相近文字/位置/时间自动认领。

## 4. 状态与证据：防错投、假成功及误恢复

每次明确附加拥有新 operation ID；相同截图重复点击不能复用旧成功回执。必须区分以下事实轴，避免一个巨型“成功/失败”枚举掩盖歧义：

| 事实轴 | 值示例 | 含义 |
|---|---|---|
| input | notAttempted / mutationPossible / attemptedOnce | 浏览器边界前写 `mutationPossible`；超时或崩溃后不重试 |
| draft acceptance | unproven / acceptedIntoOriginalDraft | 存在对应本图、原 composer 的正面证据；不是仅有 spinner |
| provider processing | unknown / processing / ready / explicitFailure | 已接收后仍可能失败；单独持续观察 |
| target continuity | live / changed / unavailable | 切窗口/标签/模式/新聊天使当前 mutation 失效；不改投 |
| user disposition | retained / userRemoved / userSent / unknown | 用户主动删除或发送不是服务失败；不要把图重新塞回 |

接收证据必须同时满足原 target/document/draft/composer 未变化、附件在原 composer 的新成员关系、与本次图片的可靠关联。全页出现新图片、文件名相同、附件数量增加、按钮变可点击、send 按钮 enabled、无 error、时间过去都不能单独证明成功。

内容关联允许经过独立负例验证的 provider 专属办法：原图/原始 Blob 内容证明、精确像素证明，或网站暴露且能明确绑定本次输入对象与附件卡的稳定标识。现有精确图片证明可以保留，但不可强制所有网站缩略图字节等于输入 PNG：站点可能压缩、缩放或显示通用文件卡。无法形成可靠关联时保持 `unproven`，不能退到文件名即成功。

文件名宜在传输副本中携带 operation 唯一短标识以辅助归属，保留本地原图；文件名只是辅助证据。相同内容的两次合法显式操作仍须独立 operation/card，不以 SHA 去重吞掉用户第二次意图。

明确失败必须来自本附件，不能读全页红字或邻卡错误。旧附件失败不应否定本操作；本图上传后同卡失败必须恢复本图可处理入口。若卡片突然消失但无法区分用户移除、用户发送、站点重绘，保持未知，绝不自动回填或再上传。

严格“唯一”承诺应针对 Riftlet 每 operation 的文件注入动作和原草稿的观测结果；不能承诺网站内部网络层绝不重试。网络重试不等于 Riftlet 第二次输入。

## 5. DOM 生命周期与保留草稿

- 架构应预期（不是声称已观察所有站点）SPA 路由切换、组件重建、模式切换、附件卡替换、异步图片解码、单页同时有多个编辑器、用户输入法 composition、站点限流/离线恢复。
- `MutationObserver` 在输入前安装且限定原 composer/附件容器；保存有限事件环与单调序号，Swift 轮询读取摘要。快速出现又消失的 START 不得只靠轮询命中；持续从全站 DOM 扫描会产生错认和性能问题。
- 路由变化不一定意味着用户切换草稿（网站可能为新草稿分配 ID），但不能无条件继承。Provider 必须记录并验证允许的原位身份演进；未知变化使 ticket 失效。
- 应保持文字和选区，优先完全不聚焦、不改 editor。若兼容操作不可避免改变选区，只有在原 editor 仍连接且 text/selection revision 未被用户改变时做最小恢复；禁止用旧快照覆盖用户新文字、IME 内容或新选区。
- 原有附件库存用于差分观察和保留验证，不通过重写 input 的 FileList 来重放旧附件。已有附件与 file input 暂存列表不一定一一对应。
- 注入脚本只使用打包的已审代码，禁止抓取并执行远端“热修复 selector 脚本”、读取 cookie/token、调用网页私有上传 API。能力失效仅隔离受影响的 Provider/surface。
- Provider 返回 `unsupportedSurface`、`loginRequired`、`quotaExceeded`、`inputUnavailable`、`targetChanged`、`receiptUnproven` 等结构化原因；用户看到短文案与一处恢复入口，不看到 runtime、DOM、observer、hash。

## 6. 开工时的实际研究包与退出条件

每个平台先在 Chrome 用签名候选完成以下一个纵向链路，再复用其他 Host；这只是开发顺序，不能取代逐组合验收：

1. 用授权测试账号及无敏感测试草稿，记录实际最终 origin、app version/构建标识（若公开）、模式、语言、账号层级、composer 树的最小脱敏片段。不得提交完整用户 DOM、cookie、会话 URL 或私人截图。
2. 验证空草稿、含文字与选区及既有附件草稿；注入单图后确认原文件卡，不按发送。独立观察者用截图/脱敏卡片证据核验，不能把产品自身回执视为唯一 oracle。
3. 两张不同图小于 2 秒点击；每图一次输入、独立卡片与回执。验证相同内容不同 operation、同名不同图、一像素差图、相邻卡失败、嵌套图片/头像/历史消息图片阴性对照。
4. 验证新聊天/切模式/换标签/input 重建发生在 prepare 与 commit 间；mutationPossible 后断链只读续查。验证码、未登录、限额、地区不可用、用户移除、页面导航只记录准确原因，不绕过限制。
5. 三层报告分离：合成 DOM / 实际浏览器 fixture / 已登录线上服务。新 Provider 无真实线上通过之前，不进入默认支持白名单。
6. 若原生图片输入不支持当前 surface，保留图并给“当前页面暂不能添加图片”；若可输入却无法可靠证明原草稿接受，标 `receiptUnproven`，继续研究更强关联；不能用自动 paste/网络 API 降低验收。

网络/账号暂缺与工程不可行要区分。前者为 `BLOCKED_ENV`，不停止其他 Provider；后者必须给出最小复现、试过的方法、违反哪个产品不变量及可行替代，记录 `BLOCKED_TECHNICAL`。只有证据充分的组合进入正式支持清单，其余保留计划状态。
