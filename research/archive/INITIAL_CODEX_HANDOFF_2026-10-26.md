> HISTORICAL/SUPERSEDED. Original handoff predates Riftlet repository and user decision not to implement yet. Follow docs/DECISIONS.md instead.

---

# Screenshot Rift｜新项目上下文交接（2026-10-26）

> **本文件用于交给一个完全不了解之前聊天的新 Codex / 编程代理。**
> 附录保留用户上传的 Pro 审查回复文本，不等同于已经在本机执行过测试。
> 状态：**没有正式代码、没有项目仓库、没有已经运行的应用。只有需求讨论和 Pro 独立审查。**

## 1. 项目是什么

一款独立的原生 macOS 截图即时转交工具。用户用 macOS 自带截图方式完成截图，它自动进入屏幕边缘极细的竖向「空间裂缝」，然后用户在当前 ChatGPT 网页或 Mac 客户端前点击截图的小缩略图，该图即被追加为当前对话的**草稿附件**。不发送聊天消息。整个日常流程只有两次人工操作：**截图一次、点击一次**。

**不可退让的用户约束（以下来自用户亲自确定的需求）**：

1. 系统截图后尽可能无感、低延迟自动收录；保持用户现有的 macOS 系统截图操作，不要求用户换一套截图方式。
2. 裂缝是极细竖线、截图部分露出；截图显示非常小，约硬币视觉尺度，**原图等比例缩放**；只显示小图和数字，不显示长标题或大卡片。
3. 最早截图在上，之后按时序向下；截图成功消费后从待用裂缝中消失，下方自然上移。对溢出队列要保证刚刚截的图容易一击点到。
4. **单击代替拖放**，日常不允许要求拖动、粘贴快捷键、额外确认、文件选择器；首次安装或必要权限设置可以独立处理，不计入日常的两次操作。
5. 点击目标是用户当时正在使用的**正确 ChatGPT 对话草稿**，无论网页还是 Mac 客户端；是附加图片、不是发送消息；不能覆盖已有文字或附件。
6. 只有确认目标草稿中该特定截图真正处于 ready 状态，才把它吞噬；明确失败则重生；状态未知时**必须保留并核对**，不可误当成功/失败、不可盲目重传。
7. 截图平时保持在队列里，直到用户主动移除或一次成功的附加消耗。可以在独立管理界面查看日期、详细命名；裂缝只显示数字。
8. 操作极简、视觉极小、动画克制：不能退化为传统大悬浮截图架。

**未冻结/需要验证**：固定左/右边缘、精确 pt、遮挡比例、数字重编号还是稳定编号、成功后原文件是否还保留/档案策略、裂缝整体关闭的精确语义、溢出队列的细节、多显示器模式、ChatGPT Classic 是否纳入首版。Pro 提出的具体参数只是候选，不是用户已批准的最终设计。

## 2. 已有研究与共识

2026-10-26 的 Pro 审查建议：Swift/AppKit 为原生主体；网页版优先验证本地 App + 轻量浏览器扩展；Mac 客户端通过 NSPasteboard/Accessibility 候选路径；应用状态由本地可靠事务日志持有。它**未运行 macOS 真机端到端实验**，因此是研究判断，不是实测成功。

用户与助手还讨论过网页版另一条备选：Mac App 通过 Chrome AppleScript 执行当前标签页 JavaScript（需要开启 Chrome 的相关设置）。**不能提前认定这条路线胜出或已经能确认 ChatGPT ready**；应与扩展方案通过真实实验比较。不是所有浏览器都具备相同脚本能力。

候选可复用开源模块（详见附录 Pro 原文，使用前自行核源码与许可证）：
- `ssut/Sukurini`: 文件夹监听生命周期、缩略图缓存（Apache-2.0/NOTICE）。
- `m0ztop/Screenshoss`: 文件完整性检测、文件系统测试（MIT）。
- `alejandrobujan/tendedero`: 非激活细线悬浮窗口（MIT；注意私有 API 与品牌素材许可）。
- `steipete/oracle`: 网页附件数据输入、附件证据归属、上下文守卫与进度观察（MIT；不能照搬弱 ready 判定）。
- `p0deje/Maccy`: 剪贴板与图片表示参考（MIT）。

不是把这些项目整体 fork，也不是直接依赖某个项目的全部产品行为。

## 3. 技术问题的真实性边界

- macOS 截图的系统浮动缩略图可能使**最终文件落盘延迟**，文件夹监听无法消除落盘之前的系统等待；“无延迟”是体验目标不是已经得到验证的物理保证。
- Chrome 网页内 `FileList`/事件注入不等于站点已接受图片；DOM 里的占位卡、spinner 消失、按钮可点均不单独构成 ready 证据。
- 原生客户端的 Accessibility 树可能不暴露明确 ready 状态；**未经实际查看不能声称支持**。
- `UNKNOWN` 不能自动当失败：上传可能已经成功但回执丢失。避免重复附件的策略必须前置。
- 截图用 Mac 系统快捷方式完成，但产品**不能再要求用户通过额外快捷键触发上传**。
- 原生 App + WebAdapter/NativeAdapter 是模块化架构候选，网页扩展是否必需由验证决定。

## 4. 面向全新 Codex 的当前首个目标

**不是交付完整产品。** 先建立受控的 Mac 本地技术验证和最小原生裂缝原型，得到真实证据：

A. **实际环境**：检查当前 macOS、Swift/Xcode、Chrome、ChatGPT Mac（新版/Classic）、运行权限；不假定云端 Codex 能访问用户的 Mac GUI。

B. **网页严格证据链**：在用户授权的测试对话草稿中，使用合成图片研究一击插入、追加、不损坏文字/附件、正确目标、ready/error 观察；比较原生 AppleScript JS 与扩展路径。**绝不发送真实消息**。不读取其他私人聊天，不抓 cookies/tokens，不调用非公开账户接口。

C. **Mac 客户端**：先只读观测 GUI/Accessibility 能暴露哪些附件状态；如可用，再在合成测试图和空白草稿下验证输入和 ready；不把发出 Cmd+V 当作完成。

D. **独立原生最小原型**：本地隔离目录的 Swift/AppKit Panel + 模拟成功/失败/未知队列，再加入截图文件 watcher、等比小图、FIFO、吞噬和重生；不需要先有 GitHub 仓库。

E. **结论**：分别出具 VERIFIED/FAILED/NOT_TESTED，保留重现步骤、系统与客户端版本、实测截图/日志（须排除私人数据）；不凭文档推演冒充运行结果。

这两个工作线在具备环境时可以并行推进，但任何正式交付承诺都要以真实 ready 证据为前提。

## 5. 执行边界

- 这是**全新项目**，不存在需要继承的代码仓库、既定目录、先前分支或已批准的实现。
- 允许提出并创建一个**隔离的本地实验目录**（实际有本地访问能力时），但**不要擅自创建远程 GitHub 仓库、发布应用或修改其他项目**。
- 不要修改系统截图设置、浏览器全局安全设置或授予系统权限，除非用户明确完成一次性授权。
- 不读取私人截图/聊天，先用自己生成的合成测试图片；不能在未获准的用户对话中测试附件添加。
- Pro 的审查结果只证明有技术研究和源码参考，并不等于用户最终拍板了每个技术设计细节。

## 6. 来源：Pro 审查回复原文

以下为用户在当前对话上传的 Pro 回复文本（原样保留；其中提到的 23 页 PDF 另有 Library 链接，未包含在本交接文件中）。

---

# 核心裁决

**建议保留“两次操作”的产品目标，采用“独立 Swift／AppKit 应用＋轻量浏览器扩展”作为网页版主方案，并选择性复用成熟开源模块。现在适合进行关键链路验证，尚不适合直接投入完整产品开发。**

主要原因不是截图收录或裂缝动画难做，而是必须证明：

> **这张截图已经进入用户点击时所指的那个草稿，并且附件已经准备就绪。**

网页版有较强的技术依据实现这个目标；Mac 客户端具备输入手段，但其附件完成状态能否被可靠观察，仍是未通过的关键门槛。

完整审查报告共 **23 页**，包含固定提交版本的源码索引、许可证分析、交互规格、异常处理和最小验证清单：

[Mac_Screenshot_Rift_Review_2026-10-26.pdf](https://chatgpt.com/library?file_id=libfile_5a89b1d11c908191b9c8358c83dddaf5&account_id=personal)

**研究边界：**本轮实际阅读了官方资料、公开源码及部分测试代码；没有在 macOS 真机执行 ChatGPT 附件注入，没有发送消息、访问私人对话、创建产品仓库或修改既有项目。下文的性能数字和交互参数是建议规格，不是实测成绩。

---

## 一、两次操作分别能否成立？

| 目标 | 裁决 | 尚未解决的关键问题 |
|---|---|---|
| **ChatGPT 网页版＋浏览器扩展** | 有明确实现路径，是最值得验证的主方案 | 当前页面是否接受所选输入路径；如何识别该附件真正 ready |
| **网页版＋纯原生自动化** | 可以研究粘贴、Accessibility 等路径，但不宜作为默认方案 | 焦点、剪贴板、具体附件关联及成功观察更困难 |
| **新版 ChatGPT Mac 桌面** | 一次点击发起附加有可行手段；严格成功契约未获证实 | 实际 AX 树是否暴露附件身份、进度、错误和完成状态 |
| **ChatGPT Classic Mac** | 必须独立验证，不能继承新版客户端结论 | 同上，且输入框及窗口类型可能不同 |
| **官方 MCP 草稿扩展** | 已有真实能力，但覆盖范围和线程语义不符合“任意当前对话”的通用假设 | 入口是否已挂载、目标线程、生命周期和 ready 回执 |

这里的“两次操作”应当定义为：**完成一次性安装、权限与来源设置之后，日常使用只需系统截图，再点击缩略图。** 不应变成每次选择会话、打开扩展、选择文件或补按快捷键。

如果首发要求同时严格支持普通网页、新版 Mac 桌面和 Classic，当前证据不足以放行完整开发。如果允许先发布通过验证的平台，则网页版更有希望先达到要求。

---

## 二、必须建立比“粘贴成功”更严格的成功契约

### 1. 五种状态不能混为一谈

| 状态 | 能证明什么 | 产品应怎样处理 |
|---|---|---|
| **已触发输入** | 事件、AX 动作或文件输入操作已派发 | 留下在途标记，不能消费截图 |
| **附件已出现** | 正确草稿中出现与本次操作关联的新附件 | 继续等待，不视为上传完成 |
| **附件已就绪** | 经验证的完成判据确认该附件具备发送条件 | 完成吞噬，从待用队列消失 |
| **明确失败** | 有对应附件的错误，或确定尚未触发的前置失败 | 原序恢复，保留原图 |
| **结果未知** | 超时、导航、观察丢失、崩溃等使结果不可判断 | 保留截图；再次点击时先核对，不能直接重传 |

以下都不能单独作为成功证据：

- 已经发出 `Cmd+V`。
- `input.files` 中出现了文件。
- 看到了一个附件占位卡。
- 发送按钮处于 enabled。
- 一个 spinner 消失了。
- 某个网络请求返回了 HTTP 200。

例如，已有文字可能让发送按钮早已启用；模型正在回答又可能让按钮不可用。它们都不能独立说明**这张新图**的处理状态。

### 2. 每次点击必须绑定目标和操作身份

最少需要记录：

- 截图 `assetId`。
- 本次操作 `operationId` 和尝试 `attemptId`。
- 点击时的目标应用、窗口、浏览器会话及标签页。
- 页面／草稿代次、实际 composer 身份。
- 输入前的附件集合基线。

**目标在点击时固定，在实际注入前再次核对。** 用户切换到另一聊天后，不能把排队中的图片改投新的前台会话。

同图连点合并为一次操作；不同图可快速点击排队，但应按目标草稿串行注入，直到能唯一关联新增附件。原生粘贴路径还需要全局串行，防止多个任务争用系统剪贴板。

### 3. 超时不能自动等于失败

可以设定柔性等待提示和停止积极等待的阈值，但超时后应进入 `UNKNOWN`。

最危险的场景是：图片实际上已附上，但回执在导航或崩溃中丢失。如果重启后自动重播，或者让用户下一次点击立即重新上传，就会产生重复附件。

没有目标端幂等键时，本地日志不能保证远端严格 exactly-once。可以做到的是：

**不盲目重试、不误报成功、不丢失本地原图，并在重新派发之前先核对。**

---

## 三、网页版：推荐的输入链路与真实限制

### 1. 扩展为什么比纯原生方案更合适

OpenAI 官方说明 ChatGPT 支持通过添加、拖放和剪贴板输入图片，并列出 PNG、JPEG、非动画 GIF 及每张图片 20 MB 的限制。这证明产品具有这些输入能力，但不构成第三方稳定附件 API。[OpenAI Help Center](https://help.openai.com/en/articles/8400551-chatgpt-image-inputs-faq?utm_source=chatgpt.com)

扩展的价值在于：它可以直接定位当前页面的实际输入框与附件区域，建立“输入前—输入后”的对应关系，而不是仅从操作系统外部猜测发生了什么。

推荐链路为：

**原生私有图片副本 → Native Messaging host → 扩展 → 当前 composer 的真实文件输入路径 → 附件观察与回执。**

让 ChatGPT 页面自己的正常逻辑处理上传，不读取 cookies、不提取 token、不调用逆向私有接口，也不引入自己的云上传服务。

### 2. File、DataTransfer、文件输入和粘贴的边界

| 机制 | 可以做什么 | 不能据此假设什么 |
|---|---|---|
| `File`／`Blob` | 用已经取得的图片字节构造文件对象 | 一个磁盘路径字符串不会自动读取本地文件 |
| `input.files` | HTML 标准允许设置合适的 `FileList` | 赋值不代表 ChatGPT 的应用状态已经更新 |
| `input.value` | 文件输入有受限制的值语义 | 不能设置任意非空路径来模拟用户选文件 |
| `DataTransfer` | 容纳 `File`，提供 `FileList` | 不等于真实系统拖放或用户激活 |
| 合成 `change`／`input` | 可以触发页面处理器 | `isTrusted` 为 false；站点是否接受必须实测 |
| 合成 `paste` | 页面 handler 可能读取所提供数据 | 不会执行真实粘贴的默认插入动作 |
| 合成 `drop` | 站点自己的 drop handler 可能接收 | 不保证与真实拖入行为相同 |
| `navigator.clipboard` | 在权限、焦点和激活条件下工作 | 原生裂缝点击不当然成为页面的用户激活 |

这些限制来自 HTML、Clipboard 标准及 Chrome 扩展机制。尤其是合成 `paste`：**派发事件不等于浏览器执行真实粘贴。** [html.spec.whatwg.org](https://html.spec.whatwg.org/multipage/input.html?utm_source=chatgpt.com)

因此，首选应是：

1. 找到**当前 composer 实际使用的**文件输入。
2. 用真实字节构造文件。
3. 使用标准 setter 和经验证的事件路径。
4. 观察该 composer 新增的附件。
5. 验证该附件就绪。

不能插入一个与 ChatGPT 无关的新 `<input>`，也不能使用页面上找到的第一个文件输入——它可能属于项目文件、其他表单或隐藏界面。

### 3. 如何保留已有文字和附件

正确策略是调用页面的追加附件路径，而不是重建整个草稿。

需要特别注意：给 `input.files` 赋值会替换该控件的当前文件选择，但已有附件卡片通常由页面应用状态维护。**当前 ChatGPT 是否把此次选择处理为追加，必须实测，不能靠标准推导。**

也不要简单合并旧 `FileList`：旧文件可能被再次上传。

应禁止：

- `Cmd+A` 后替换内容。
- 改写 composer 的 `innerHTML`。
- 为“初始化状态”清空全部附件。
- 出错后恢复整段旧文本，覆盖用户刚输入的新内容。

### 4. 如何识别当前活动对话

仅调用 `tabs.query({active: true, lastFocusedWindow: true})` 不够。浏览器的窗口／标签页状态有自己的作用范围，多个 profile 和多个浏览器也可能各有活动标签页。[developer.chrome.com](https://developer.chrome.com/docs/extensions/reference/api/tabs?utm_source=chatgpt.com)

建议建立由原生端与扩展共同确认的目标绑定：

- 点击前的前台应用。
- 对应浏览器／profile 的连接会话。
- `windowId`、`tabId`、`documentId`。
- 页面路由和草稿代次。
- 实际 composer 元素身份。
- 页面可见性、焦点状态和最后一次有效观测。

URL 也不够：SPA 可以在同一文档内切换对话，新聊天路径可能复用。

此外，原生面板点击不会自动授予扩展 `activeTab`。Chrome 明确规定了能触发该权限的扩展调用方式。因此应采用一次授权、限定在 ChatGPT 站点的访问权限，而不是依赖每次点击扩展按钮。[developer.chrome.com](https://developer.chrome.com/docs/extensions/develop/concepts/activeTab?utm_source=chatgpt.com)

### 5. Native Messaging 有一个很容易踩中的尺寸限制

Chrome 的 host → 浏览器单条消息上限是 **1 MiB**，反向上限是 64 MiB。高分辨率截图再经过 base64，通常不能塞进一条消息。[developer.chrome.com](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging?utm_source=chatgpt.com)

建议使用有序分块、大小上限、校验和、ack 和背压。192–256 KiB 原始字节一块可以作为初始参数。

扩展需要与浏览器启动的最小 host 建立连接；host 再通过受限本地 IPC 与主程序通信。原生应用并不能凭空“调用扩展”。

本地事务日志应由原生端持有，不能依赖 service worker 的常驻内存。浏览器关闭、worker 重启、连接断开都必须可以恢复核对。[developer.chrome.com](https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle?utm_source=chatgpt.com)

### 6. 找到了有价值的附件源码：Oracle

本轮实际阅读了 [steipete/oracle 的固定提交](https://github.com/steipete/oracle/tree/fde96271db1611c0287fcfde3053c19325280d10)，MIT 许可。最值得借用的不是整个自动化工具，而是下面几个模块：

| 文件 | 真实机制 | 对 Rift 的价值 |
|---|---|---|
| [attachmentDataTransfer.ts](https://github.com/steipete/oracle/blob/fde96271db1611c0287fcfde3053c19325280d10/src/browser/actions/attachmentDataTransfer.ts) | 字节转 Blob／File／DataTransfer，设置文件输入，派发事件 | 证明存在具体、可研究的输入实现 |
| [attachmentEvidence.ts](https://github.com/steipete/oracle/blob/fde96271db1611c0287fcfde3053c19325280d10/src/browser/actions/attachmentEvidence.ts) | 记录既有控件基线，认领新附件，绑定实际 DOM 节点和 composer | 比“数量增加一”可靠 |
| [attachmentContext.ts](https://github.com/steipete/oracle/blob/fde96271db1611c0287fcfde3053c19325280d10/src/browser/actions/attachmentContext.ts) | 导航前后核对上下文，避免不明确情况下重复派发 | 防错对话、防盲重试 |
| [attachmentProgress.ts](https://github.com/steipete/oracle/blob/fde96271db1611c0287fcfde3053c19325280d10/src/browser/actions/attachmentProgress.ts) | 在 composer 范围检查 pending、uploading、aria-busy、progressbar | 可作为完成观察的基础 |

但必须指出一个反例：该项目的 [attachments.ts](https://github.com/steipete/oracle/blob/fde96271db1611c0287fcfde3053c19325280d10/src/browser/actions/attachments.ts) 仍有 input-only fallback——文件名稳定一段时间，再结合发送按钮状态，可能被视作完成。

**这个兜底不足以满足 Rift 的严格成功契约，不能继承。** 清空既有附件、暂存提示词和发送消息的代码也必须排除。

这说明开源实现能减少探索成本，但不能代替独立判断。

---

## 四、Mac 客户端：最难的是观察，不是发按键

### 1. 不能继续沿用旧客户端架构假设

当前官方资料已经区分新版 ChatGPT desktop app 与 ChatGPT Classic：2026 年 7 月的说明把此前客户端称为 Classic，迁移资料说明新版由 Codex app 更新而来。[OpenAI Help Center](https://help.openai.com/en/articles/9703738-chatgpt-macos-app-release-notes?utm_source=chatgpt.com)

Codex 团队成员的第一人称说明确认 Codex app 使用 Electron。因此“新版桌面来自 Electron 路线”是有依据的推断；但本轮没有检查用户安装包、具体 composer 或 AX 树。也不能从 Electron 推导出 Chrome 扩展可以直接注入该客户端。[Hacker News](https://news.ycombinator.com/item?id=46859673\&utm_source=chatgpt.com)

### 2. 最接近目标的原生路径

候选路径是：

1. 非激活 `NSPanel` 接收点击。
2. 固定前台应用、窗口和 composer。
3. 用 AX 验证并聚焦正确编辑器。
4. 把图片表示写入 `NSPasteboard`。
5. 通过可用的菜单 AX 动作或 `CGEvent` 执行粘贴。
6. 观察该 composer 的附件状态。
7. 仅在 ready 后消费队列。

裂缝应使用 `nonactivatingPanel`，不成为 key／main window，并接受首次鼠标点击。不能先激活 Rift，再让用户第二次点击完成业务动作。Apple 的 `acceptsFirstMouse` 与窗口激活行为是相关基础，但具体组合仍要验证。[Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nsview/acceptsfirstmouse%28for%3A%29?utm_source=chatgpt.com)

图片可候选使用 PNG、TIFF；file URL 是否被具体客户端识别，需要分别测试。多种表示属于同一图片时应放在同一个 pasteboard item，不能意外变成多张附件。

### 3. 已有文本和选区必须实测

“空白输入框能贴图”不是充分条件。

至少需要测试：

- 已有中文、多段文字和 emoji。
- 输入框中有选中文字。
- 已有一个或多个附件。
- 模型正在生成回复。
- 普通窗口、快捷小窗及多个会话窗口。

如果图片粘贴会替换选区，应研究在可靠识别 composer 的前提下安全折叠选区。不能靠出错后重写全文恢复，因为那会覆盖用户的并发编辑。

### 4. AX 能读什么，由目标应用决定

Apple 提供属性、动作与通知机制，但应用决定暴露哪些具体语义。不能从“支持 Accessibility”直接推导出“能读取附件上传完成”。[developer.apple.com](https://developer.apple.com/library/archive/documentation/Accessibility/Conceptual/AccessibilityMacOSX/OSXAXmodel.html?utm_source=chatgpt.com)

如果真实 AX 树能提供：

- 新附件节点或文件名；
- 对应进度；
- 具体错误；
- 正向完成状态；

就有机会建立严格回执。

如果只暴露一个没有状态的图片占位符，则结果仍可能未知。AX 通知不支持、读取失败，也不能被映射成上传失败。

OCR 可以作为辅助观察，但它增加屏幕录制权限和误判成本，不能靠“没识别出 spinner”严格证明 ready。**不建议用 OCR 去掩盖主观察链路缺失。**

### 5. 剪贴板恢复不能用一个固定延时解决

较合理的恢复策略是：

- 读取旧内容时核对 `changeCount`。
- 写入图片及自己的操作标记。
- 确认目标已经消费所需图片数据。
- 仅在剪贴板仍属于本次操作时恢复。
- 用户期间复制了新内容，就立即让出，绝不覆盖。

但它仍有边界：检查后再写入不是原子操作；lazy provider、file promise、动态类型和 Universal Clipboard 的生产者语义也不能靠字节快照完整恢复。[developer.apple.com](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/PasteboardGuide106/Articles/pbReading.html?utm_source=chatgpt.com)

**固定 50、100 或 300 毫秒后恢复不可靠。** 数据提供回调也可能来自剪贴板管理器，不能当作 ChatGPT 已消费的证明。

如果无法判断消费时刻，较诚实的兼容模式是让图片暂留系统剪贴板，用户下一次复制即可覆盖；这仍保留两次操作，但不能宣传“剪贴板完全无扰动”。

[Maccy 的 Clipboard.swift](https://github.com/p0deje/Maccy/blob/54fb9f00b828a4ec367e706c0e276df90febe76a/Maccy/Clipboard.swift) 值得参考图片表示、类型过滤、键盘布局和事件投递；它不是 ChatGPT 附件验证器。

### 6. 官方 MCP 路线值得关注，但还不能替代主方案

实际阅读的 [OpenAI MCP Extensions 规范](https://github.com/openai/mcp-extensions/blob/36f8b38df179144b44d157133bbc5f7c6e353ace/docs/spec.md) 已提供 `ui/message` 的 `send:false`，支持向草稿添加内容。

因此不能笼统声称 OpenAI 没有官方草稿能力。

但其限制非常关键：

- 它是已初始化 MCP App view 与 host 之间的协议。
- Web 支持矩阵指 Work browser，不包括 classic ChatGPT。
- global 入口的 `active` 是该入口自己的线程。
- thread 入口依赖具体会话中的实例。
- 返回的 `isError` 不等于特定附件 ready。
- **默认 `send:true`，任何候选实现都必须显式固定为 `false`。**

只有证明无需逐会话额外打开、目标映射正确、后台生命周期可靠、附件回执足够明确，才适合把它提升为主方案。

---

## 五、原生截图收录：低延迟可做，但系统等待不能被文件监听消除

### 1. 必须拆开三个时间点

- **T0：**用户完成截图操作。
- **T1：**源文件首次完整可读。
- **T2：**Rift 私有副本和索引提交完成，缩略图可点击。

系统浮动缩略图可能位于 T0 与 T1 之间。用户悬停、进入标记、改变去向，都可能继续延迟最终保存。

Apple 官方说明了该生命周期；Dropover 官方也明确写出浮动缩略图消失后才最终保存，并建议关闭它以改善及时收录。[Apple Support](https://support.apple.com/en-us/102646?utm_source=chatgpt.com)

因此：

**监听最终保存目录不能消除系统保存前的等待。**

建议在一次设置中说明关闭“显示浮动缩略图”的效果，不静默修改用户偏好。保留该功能时，Rift 应承诺保存后及时收录。

本轮没有找到覆盖所有原生截图入口、稳定公开且直接提供早期结果像素的第三方回调；这不等于证明系统内部不存在临时数据，也不等于所有未来技术都不可能。

### 2. 推荐收录机制

低延迟主路径采用目录 `DispatchSource`，可靠性来自：

- `write / rename / delete / revoke` 生命周期处理。
- 先监听再扫描，扫描中变脏则补扫。
- 文件身份、size／mtime 和 ImageIO 完整性检查。
- 有限退避重试。
- 复制前后核对源版本。
- 临时文件原子改名与本地索引提交。
- 唤醒、事件丢失和目录失效后的重扫。

FSEvents 可以合并或丢失细粒度事件，因此事件应作为“需要核对目录”的信号，而不是一事件对应一张截图。[developer.apple.com](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/UsingtheFSEventsFramework/UsingtheFSEventsFramework.html?utm_source=chatgpt.com)

`NSMetadataQuery` 和截图元数据适合补扫、分类，不宜作为唯一的低延迟入口。

首次安装应建立既有文件基线；新截图自动入队，历史导入由用户主动触发。后续重启依据持久化检查点补漏，不能把桌面旧截图全部重新灌入队列。

### 3. 不能忽略的来源边界

**目录变更：**发现新目录不等于拥有读取权限。切到未授权受保护目录时，需要一次性授权，不能无声绕过。

**剪贴板截图：**轮询 `changeCount` 只能看到当时内容。两次轮询之间被覆盖的上一张图无法追回。它还难以区分系统截图和普通复制图片，应作为用户开启的兼容来源，不默认收集全剪贴板。

**格式：**保留原始编码，上传时按目标支持生成派生文件。HEIF／HDR 到 PNG／JPEG 必须真正解码并处理色彩，不能只改扩展名；超过限制时保留原件，不无条件压缩到文字不可读。[Apple Support](https://support.apple.com/en-us/102646?utm_source=chatgpt.com)

**排序：**文件事件到达顺序不等于绝对截图顺序。尽可能用可信捕获时间，缺失或相同时用持久化收录序号；`firstSeenAt` 不能冒称 `capturedAt`。

**去重：**相同内容的两次有意截图仍应保留为两个条目。源文件事件去重、内容 hash 和截图身份需要分开。

### 4. 建议的延迟目标

以下全部是**待实测目标**：

| 指标 | 建议 |
|---|---|
| T1 → T2 | 本地可用、已授权、应用运行中的约定样本，p95 ≤ 300 ms |
| T0 → T2 | 关闭浮动缩略图后，探索 p95 ≤ 500 ms |
| 开启浮动缩略图 | 系统最终保存后尽快达到同一收录目标 |
| 空闲开销 | 文件事件驱动，避免持续解码和高频全量扫描 |
| 缩略图缓存 | 初始可设约 32 MiB，优先缓存可见项 |

T1 必须由独立探针定义，不能从 watcher 收到回调才计时，否则会隐藏监听延迟。

### 5. 裂缝被截图截入，是独立风险

当前 Apple 对 `NSWindow.SharingType.none` 的说明已经不支持把它当作隐藏窗口、排除截图的保证。[Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum/none?changes=_1\&utm_source=chatgpt.com)

ScreenCaptureKit 的排除窗口参数控制的是**使用该配置的捕获过程**，不能替第三方控制 Apple 系统截图。

监听截图快捷键后临时隐藏值得验证，但：

- `Cmd+Shift+3` 是瞬时截图，有先后竞态。
- 截图工具栏、菜单、定时截图和改键不是同一路径。
- 截获并重新投递快捷键会增加权限和复杂度。

正式产品必须对声称支持的 OS 和截图入口逐项验证。不能以一行 `.sharingType = .none` 宣布解决。

---

## 六、竞品与源码复用裁决

### 1. 指定产品都研究了，但它们解决的是不同问题

| 产品 | 查到的相关能力 | 对 Rift 的实际价值 |
|---|---|---|
| **Screenshoss** | 自动收录、边缘 shelf、本地存储与文件稳定性源码 | 借用完整性检查和几何；不能继承移动源文件、英文前缀识别等假设 |
| **Screenshot Shelf／Bert Devriese** | 系统或自选目录、边缘排列、拖到 AI 工具、隐藏设置 | 体验参考；未取得可验证产品源码 |
| **Dropover** | 自动截图 shelf、连续追加、目录设置 | 证明文件型收录的产品可用性；没有当前 ChatGPT ready 回执证据 |
| **ScreenFloat** | 自身截图、浮图、全屏／Space、完整浏览器 | 参考窗口品质与档案浏览；不能推断被动捕获所有系统截图 |
| **Shottr** | 自有快速截图、pin、标注、S3 上传 | 自有截图速度不能移植成系统截图监听指标；S3 上传也不是当前草稿附加 |
| **Sukurini** | 目录恢复、缩略图队列、最近截图粘贴 | 收录模块最有复用价值之一 |
| **Tendedero** | 极细线条、小图悬挂、非激活面板 | 形态接近，但有私有 API 和容量淘汰行为应排除 |

其中 Screenshot Shelf 存在同名项目，不能把 [KanishkVashisht 的 MIT 仓库](https://github.com/KanishkVashisht/screenshot-shelf) 归到 Bert Devriese 的产品名下。官方产品行为分别可见这些资料。[Bert Devriese](https://brtdv.com/en/screenshot-shelf/?utm_source=chatgpt.com)

### 2. 最值得复用的具体模块

#### Screenshoss：借完整文件判定

仓库：[m0ztop/Screenshoss](https://github.com/m0ztop/Screenshoss/tree/8ef6ef7cf721a2eb29f76a94815e6992d3d3a1ac)，**MIT**。

实际阅读：

- `Sources/ShossApp/ScreenshotLibrary.swift`
- `Sources/ShossApp/ScreenshotImportService.swift`
- `Sources/ShossApp/ScreenshotItem.swift`
- `Sources/ShossApp/ScreenshotStorageService.swift`
- `Sources/ShossApp/ShelfPanelController.swift`
- `Tests/ShossTests/ScreenshotFilesystemIntegrationTests.swift`

有价值的是 size／mtime 与 ImageIO complete 的组合检查、扫描变脏处理和测试案例。

不能照搬的地方是：移动源截图；主要依赖英文截图名前缀；逐文件等待稳定可能放大连拍延迟；面板展开时可能成为 key。

#### Sukurini：优先借 watcher 和缩略图 loader

仓库：[ssut/Sukurini](https://github.com/ssut/Sukurini/tree/c74210f81347a1df4ef407523361e7a45c12ab3e)，**Apache-2.0＋NOTICE**。

重点文件：

- `Sources/Sukurini/Core/FolderWatcher.swift`
- `Sources/Sukurini/Core/ScreenshotStore.swift`
- `Sources/Sukurini/Core/ThumbnailLoader.swift`
- `Sources/Sukurini/Core/LatestScreenshotPaster.swift`

`FolderWatcher` 处理目录重命名、丢失和 FD 生命周期；`ThumbnailLoader` 有下采样、并发限制、请求合并、成本缓存和取消机制。

粘贴模块的 `changeCount` 条件恢复值得借鉴，但**固定 300 ms 恢复、无目标绑定、无 ready 回执**，不适合作为正式上传模块。

#### Tendedero：借非激活窗口，排除私有 API 和淘汰语义

仓库：[alejandrobujan/tendedero](https://github.com/alejandrobujan/tendedero/tree/32a3e47187fdea7b2fd43b3ab5a913f0ed33724a)，**代码 MIT**。

重点文件：

- `Sources/Tendedero/LinePanel.swift`
- `Sources/Tendedero/ScreenshotWatcher.swift`
- `Sources/Tendedero/ClipboardWatcher.swift`
- `Sources/Tendedero/FullScreen.swift`
- `Sources/Tendedero/Line.swift`

`LinePanel` 的不抢焦点结构接近目标。应排除：

- `CGSMainConnectionID / CGSCopyManagedDisplaySpaces` 私有调用。
- 满容量后 `letGo`，以及某些来源下 `trashItem` 的语义。
- 作为必经步骤的悬停展开。
- 风吹摇摆和声效。

许可还明确限制名称、图标作品和 docs 图片；不能把代码许可理解成品牌素材也能自由复制。

#### 其他模块

- [Clipy/Screeen](https://github.com/Clipy/Screeen/tree/f8f4bfa6cb38cb69ec1ee104fb5ad949a92b2ae3)：`Lib/Screeen/ScreenShotObserver.swift`，MIT。适合作为元数据补扫参考。
- [Maccy](https://github.com/p0deje/Maccy/tree/54fb9f00b828a4ec367e706c0e276df90febe76a)：`Maccy/Clipboard.swift`，MIT。借图片表示、类型过滤和键盘布局处理。
- 前述 **Oracle**：MIT。借附件身份、上下文守卫和局部进度观察，拒绝不严格的完成兜底。

### 3. 为什么不建议整体 fork

这些项目把自己的产品假设写进了数据模型：

- 自动移动文件。
- 最新在前。
- 有限容量自动淘汰。
- 拖出或复制就算完成。
- 大面板、搜索、OCR 或编辑。
- 全局剪贴板习惯。

Rift 需要的是长期待用队列、准确目标、可靠回执和未知状态恢复。整体 fork 后，这些核心仍然要改，额外功能还会增加状态数量和维护负担。

**选择性抽取模块比完整 fork 更合理。**

MIT 和 Apache-2.0 都允许商业复用，但应保留相应版权、许可证及适用 NOTICE，标记修改，并单独审查品牌素材和第三方依赖。

---

## 七、空间裂缝的正式交互建议

以下是独立设计判断，参数需要真机校准。

### 1. 缩略图应该大部分露出，不依赖悬停展开

我建议保留遮挡感，但只遮住很小一部分：

**约 90% 以上图像始终可见，遮挡量取图宽的约 6%–10% 与 4–6 pt 中更小的值。**

只露出一道窄切片，会让用户经历“接近—等待展开—重新定位—点击”。即使没有增加一次鼠标按键，也增加了动作阶段。

主目标的位置和大小应保持稳定。悬停可以显示可选提示或预览，但不能是完成点击的前提。

### 2. 初始规格

| 项目 | 建议 |
|---|---|
| 裂缝 | 1 pt 核心线，最多约 2 pt 光学厚度 |
| 位置 | 主显示器可见区右侧外缘内约 4–6 pt；可一次改到左侧 |
| 材料 | 中性、高可辨识度线条，极轻局部阴影；不做大玻璃底板 |
| 图片 | 最长边 48 pt，等比 fit |
| 命中区 | 固定 48×48 pt，约 56 pt 行距 |
| 编号 | 10–11 pt 等宽数字，局部高对比底 |
| 数字语义 | 稳定序号，不因上方消失而全部重编号 |
| 可见数量 | 初始最多八行，并受屏幕可见高度限制 |
| 空队列 | 只留安静的短线段，不做无意义动画 |

缩放规则为：

\[
s=\min(48/W,\;48/H)
\]

显示尺寸为 \(sW \times sH\)。极端长图会变薄，应通过稳定命中区与编号补足，而不是拉伸或裁成方形。

48 pt 也不是固定毫米大小；显示器与缩放会改变物理感受。“硬币大小”适合作为感觉，不适合作为硬编码物理规格。[developer.apple.com](https://developer.apple.com/library/archive/documentation/GraphicsAnimation/Conceptual/HighResolutionOSX/APIs/APIs.html?utm_source=chatgpt.com)

### 3. 点击区域必须和透明窗口行为分开设计

透明不等于鼠标穿透。`hitTest(nil)` 也不自动把点击交给下层其他应用。

建议：

- 装饰线使用完全忽略鼠标事件的窄窗口。
- 可见截图使用边界明确的小面板或已验证命中结构。
- 行间空隙不放接收输入的窗口。
- 只创建有限可见项的面板池，不为全部历史各开窗口。

这比一张覆盖整条屏幕边缘的大透明面板更容易验证。

### 4. 动效必须忠实表达事务

- **点击：**立即轻微内移，留下在途标记。
- **上传中：**保持安静，不循环夸张吸入，不显示虚构百分比。
- **ready：**完成吞噬。
- **明确失败：**反向恢复原位。
- **未知：**保留，并说明“未确认，截图已保留”。

建议 ready 后的完整吞噬约 180–240 ms，恢复约 160–220 ms，作为初始调校参数。

最重要的不是时长，而是**指针下的身份稳定**：鼠标按下捕获 `assetId`，直到释放都不能换成下一张图。成功重排、新图到达、失败恢复和溢出切换，都要遵守这一规则。

### 5. 无限历史不能全部挤在有限边缘

建议溢出时显示：

**最早一项＋中间隐藏数量＋最新若干项。**

可见项仍按时间升序，最新图始终直接可点；中间历史通过滚动或主窗口访问。

必须承认：有限面积不能让无限历史同时保持一击可达。不要自动删最旧截图，也不要把所有项缩小到无法点击。

### 6. 全屏、多 Space、多显示器

非激活面板、accessory activation policy 和适当 collection behavior 有公开技术依据。Apple DTS 也提供过在 macOS 26 的特定全屏应用上验证可见的组合，但这不代表所有应用、版本和窗口级别都已获保证。[Apple Developer Forums](https://developer.apple.com/forums/thread/826308?utm_source=chatgpt.com)

建议默认固定一块显示器，可一次开启其他显示器镜像；镜像共享同一队列与操作身份。处理 Dock、菜单栏、混合缩放、拔屏和合盖，不让裂缝跟着鼠标不断跳位置。

主窗口只需要日期分组、完整预览、待用／已用状态、主动再次使用和明确删除。首版不需要 OCR、标签系统、编辑器或 AI 命名。

---

## 八、推荐架构与三条路径的取舍

需要先指出：**A／B 是上传通道，C 是源码起点，二者并不互斥。** 最合理的组合是 B 加精选开源模块，而不是从“纯自写”和“整体 fork”中二选一。

| 维度 | A：纯原生系统能力 | B：原生＋浏览器扩展 | C：整体 fork 截图项目 |
|---|---|---|---|
| 两次操作 | 可候选，依赖 AX、焦点、剪贴板 | 网页最有希望 | 上传难题仍需独立解决 |
| ready 验证 | 受目标 AX 暴露限制 | 可直接观察 composer 与具体附件 | 没有现成严格回执可继承 |
| 初始开发 | 演示简单，可靠产品复杂 | 中等，边界较明确 | 看似省事，核心重构较多 |
| 长期维护 | OS 和客户端双重变化 | 网站适配器与扩展生命周期 | 还要承担 fork 差异 |
| 性能 | 可很低，但 AX 轮询需控制 | 局部 observer、按需传图，可很低 | 可能带入图库、OCR 等负担 |
| 权限 | 来源访问、辅助功能及剪贴板相关行为 | 来源访问、限定站点、nativeMessaging | 容易继承多余权限 |
| 商业化 | 自有代码及小型许可依赖 | 同左，另处理扩展分发 | 逐项审查 LICENSE、NOTICE、素材 |
| 更新风险 | 焦点与 AX 结构 | DOM 与浏览器权限 | 上述风险加上游整合成本 |

推荐的模块边界是：

- **来源与导入：**监听、完整性检查、格式处理。
- **本地档案：**不可变图片副本。
- **队列与事务：**FIFO、操作身份、状态日志、恢复。
- **AppKit 面板：**只负责命中和状态呈现。
- **目标路由：**固定当前草稿。
- **WebAdapter／MacAdapter：**输入与回执。

本地 SQLite 足够承担状态索引，不需要云数据库。图片独立保存，不必塞进数据库。

Web 主路径不需要默认申请 Accessibility、剪贴板读取、屏幕录制、所有网站权限或 debugger。Mac 适配器的额外权限应按其确实使用的能力申请。

---

## 九、正式开发前只需解决七组关键验证

这些是放行门槛，不是开发排期。使用带编号的合成图片、隔离草稿，**不发送消息**。

| 验证 | 必须得到的答案 |
|---|---|
| **网页实际输入** | 当前 ChatGPT 是否接受该 FileList／事件路径，并追加图片而不破坏文本和已有附件？ |
| **网页 ready／error** | 能否区分占位、上传中、就绪、明确错误和未知？ |
| **Mac AX 可观测性** | 新版与 Classic 是否分别暴露可关联的附件完成状态？ |
| **目标与并发** | 连点、十图排队、多窗口、多 profile、导航和崩溃时，是否零错投、无盲目重复？ |
| **截图生命周期** | 浮动缩略图、中文名称、改目录、HEIF、多屏和唤醒下，是否不丢图且不移动源文件？ |
| **窗口与截图污染** | 首击是否有效、空隙是否穿透、全屏是否正常、自身是否被受支持系统截图入口截入？ |
| **剪贴板恢复** | 延迟消费、用户新复制、剪贴板管理器、目标退出时，是否保全新内容并正确处理未知？ |

最高优先级是前四项。

尤其应当先检查 Mac AX，而不是先做完整动画和图库后才发现目标应用根本没有提供足够的完成状态。

---

## 最后的四个明确判断

### 现在是否具备进入正式开发的条件？

**尚不具备无条件开始完整产品开发的条件；已具备进行有界最小技术验证的条件。**

网页版的输入、追加行为和 ready 判据通过后，可以进入正式开发。Mac 严格版必须另外通过实际状态观察和内容保全门槛，不能靠“能发出粘贴”一起放行。

### 哪些现成技术值得直接复用？

优先顺序是：

1. Sukurini 的目录监听生命周期和缩略图加载机制。
2. Screenshoss 的完整文件判定与测试案例。
3. Oracle 的附件基线、DOM 身份回执和导航保护。
4. Tendedero 的非激活小窗口结构。
5. Maccy 的图片表示、键盘布局和粘贴基础处理。
6. Screeen 的元数据补扫思路。

复用小模块，保留授权，重写不符合本产品契约的部分。

### 哪个环节最可能使项目长期无法交付？

**跨版本证明“这张图已经在这个草稿准备就绪”，尤其是 Mac 客户端。**

如果始终只证明输入动作发出了，项目就会不断增加延时、焦点修补和重试补丁，却无法消除误报成功与重复附件。

第二个容易低估的问题，是把“自身不被系统截图截入”误当作已有的可靠开关。

### 怎样用最少开发工作做出稳定而精致的产品？

先证明**正确目标、只追加、真实回执、未知可恢复**；选择通过门槛的平台兑现严格体验；用独立 AppKit 小外壳和成熟底层模块完成剩余部分。

保留极小裂缝、等比缩略图、FIFO、两次操作和绝不自动发送。修正悬停展开、提前表现成功、超时盲重试和无限历史的空间假设。推迟 OCR、编辑器、标签、云同步和通用自动化平台。

**这个产品最有价值的区别，是用户敢于相信：点过之后，图确实在正确的草稿里；没有确定成功，图就仍然在这里。**