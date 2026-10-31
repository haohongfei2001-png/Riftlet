# Riftlet｜独立技术裁决

2026-10-26；基于 Riftlet main 3c988ddaff2922594fa6c6ed7d0fe24bad9d7ada。只处理上一轮未闭合的事实问题，不变更产品与视觉决策。

## 1. 上传路线裁决

**网页版最值得推进的比较单位是“同一个附件 adapter＋两种传输”，不是“模拟粘贴对浏览器扩展”。纯 Mac App 存在更强的 Chrome JavaScript 路径；扩展仍是当前更适合分发的候选，但不能先宣告必需。**

| 路线 | 已确认的输入机制 | 如何取得回执 | 一次安装／权限负担 | 本轮裁决 |
| --- | --- | --- | --- | --- |
| 原生 App＋Chrome Apple Events JavaScript | 指定 window/tab 的 execute JavaScript 在独立 world 执行；可尝试构造真实 File/DataTransfer，给实际 input 使用原生 files setter 并触发页面处理 | 同一 world 的 DOM observer＋按需读取结果；是否暴露足够正向状态待测 | Automation 许可；用户手动启用 Chrome 的 Allow JavaScript from Apple Events；企业策略可能禁用 | **强候选，SOURCE-VERIFIED；目标输入与 READY 均 NOT_TESTED。** 若 DOM 足够，可能省掉扩展、helper、剪贴板与 AX |
| 原生 App＋剪贴板／AX 粘贴到网页 | 系统能写图片／文件 URL并请求目标应用 Paste；具体 ChatGPT 接受情况未测 | AX 或另外叠加 Chrome JS；单独 AX 能否识别特定图片 READY 未证实 | Accessibility；共享剪贴板竞争；键盘布局／焦点风险 | **不作为网页首选。** 保留为真机输入实验；发出 Paste 不等于附件成功 |
| 原生 App＋MV3 扩展＋Native Messaging | 扩展获得指定页面上下文，将收到的字节构造成真实 File；同样须证明当前 composer 接受并追加 | DOM observer；必要时经过验证的 MAIN-world 观察器被动观察页面自己的文件生命周期 | 扩展安装、chatgpt.com host 授权、nativeMessaging、用户域 host manifest；通常不需要 AX／Automation | **当前推荐的分发候选，SOURCE-VERIFIED；目标输入与 READY 均 NOT_TESTED。** 稳定身份与页面生命周期较容易管理，但仍依赖页面实现 |
| 新版 ChatGPT Mac／Classic 原生适配器 | 单独验证唯一文件名的 fileURL 与 PNG 表示；AX Paste 菜单动作优先，必要时再测定向 CGEvent | 目标 composer 内逐附件 AX 身份＋正向 READY；尚未取得真实树 | Accessibility；适用系统的剪贴板访问策略；恢复只能尽力而为 | **候选，尚未获严格模式准入。** 新版 Chat、Work、Classic 分别判断 |
| 官方 MCP App 草稿能力 | host 明确广告 openai/message 扩展并支持 image 时，已初始化、已挂载的 MCP view 才可依赖 ui/message 的 send:false 追加语义 | 协议返回不保证逐图片 READY；还须证明目标及附件关联 | 插件／view 挂载、生命周期和目标 thread 约束 | **有价值但当前不是替代方案。** 不满足任意前台聊天的透明绑定，不能为采用它增加日常打开插件步骤 |

### 1.1 纯原生路线的具体突破

固定 Chromium 为 **db9f85854cec51a4bc8903d978f4cfe89b45b656**：

- [tab_applescript.mm](https://github.com/chromium/chromium/blob/db9f85854cec51a4bc8903d978f4cfe89b45b656/chrome/browser/ui/cocoa/applescript/tab_applescript.mm) 109–130 用 SessionTabHelper 取得 tab ID；369–401 检查 profile 开关／DevTools 策略，并在 primary main frame 的 ISOLATED_WORLD_ID_APPLESCRIPT 执行 JavaScript。
- [window_applescript.mm](https://github.com/chromium/chromium/blob/db9f85854cec51a4bc8903d978f4cfe89b45b656/chrome/browser/ui/cocoa/applescript/window_applescript.mm) 提供窗口 SessionID、active tab 等属性。不能把会随重排改变的位置编号当长期身份。
- [Chromium 官方 AppleScript 说明](https://www.chromium.org/developers/applescript/) 明确要求用户启用 JavaScript from Apple Events，也建议扩展＋Native Messaging 作为替代。

由此得到的实现候选是：Swift 锁定目标 → 分段传入不可变图片字节 → 同一指定页面中同步核对 composer 并进行一次输入 → observer 仅记录该操作的证据 → Swift 在操作期间按需读取。无需为了网页路径先获取 AX、改写剪贴板或模拟键盘。

限制也很具体：隔离 world 不能直接替换页面 MAIN world 的 fetch；主 frame 执行不保证子 frame composer 可达；Apple Events 的有效载荷上限与大图延迟未测。若严格 READY 只能从页面自身请求状态获得，扩展可能明显更合适。不要将调试端口、跨 origin 注入或绕过浏览器策略当补救。

### 1.2 扩展没有免除的工作

Native Messaging 是 Chrome 启动 helper，并非原生 App 随时主动唤起扩展。扩展须先 connectNative，保持可用端口；helper 用受限本地 IPC 接入已经运行的原生 App。只需一个随 App 打包的小 Swift stdio helper，无需 HTTP 服务或 Node/Python runtime。

[Chrome 协议](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging) 是四字节长度前缀＋JSON；host→Chrome 单消息上限官方表述为 1 MB，反向 64 MiB。建议图片按不超过 256 KiB 原始字节分块，连同序号、总长度和内容校验；重发尚未交给 composer 的传输块，不等于重新添加附件。不要把整个 PNG base64 放进一条消息。connectNative 可使 MV3 worker 保活；端口断开仍须恢复连接和查询原操作，不能自动重传到页面。

最小权限候选：仅 chatgpt.com 的 host、nativeMessaging，确有持久状态时使用 storage。MAIN-world 程序化注入若需要再加 scripting；不默认要求 debugger、广泛 tabs、clipboard 或所有网站权限。activeTab 的授权来自扩展自身的用户手势，原生裂缝点击不会自动授予它，因而不能单靠 activeTab 满足日常体验。

若普通 File/input 路径失败，chrome.debugger＋DOM.setFileInputFiles 是受支持的进一步实验候选，但不应默认采用：固定 Chromium [debugger_api.cc](https://github.com/chromium/chromium/blob/db9f85854cec51a4bc8903d978f4cfe89b45b656/chrome/browser/extensions/api/debugger/debugger_api.cc) 的 MayReadLocalFiles 检查 AllowFileAccess；[dom_handler.cc](https://github.com/chromium/chromium/blob/db9f85854cec51a4bc8903d978f4cfe89b45b656/content/browser/devtools/protocol/dom_handler.cc) 未授权就返回 Not allowed。这并不是省掉分块的免费捷径，还涉及 debugger 授权、文件访问选择与调试连接生命周期。当前未尝试授权或绕过。

维护策略应是一个按页面 surface／版本记录能力的 adapter、少量已观察 DOM fixtures、明确的 capability probe；未知结构停止输入或保留 UNKNOWN。不要无限扩张通用 selector 猜测链。扩展改善部署、document 身份和观察手段，不能消除 ChatGPT 页面变化。

## 2. Oracle：可借鉴输入思想，不能继承其成功定义

固定 **steipete/oracle@fde96271db1611c0287fcfde3053c19325280d10**，MIT，package version 0.22.1。

[attachmentDataTransfer.ts](https://github.com/steipete/oracle/blob/fde96271db1611c0287fcfde3053c19325280d10/src/browser/actions/attachmentDataTransfer.ts) 展示真实字节→File→DataTransfer→input setter→change 路径。这证明源码里有具体插入方法，未证明 Riftlet 当前目标接受它。不要继承伪造 input.files getter 的 fallback，也不要把 change 分派成功当作上传完成。

源码还揭示两个关键边界：

- [attachmentContext.ts](https://github.com/steipete/oracle/blob/fde96271db1611c0287fcfde3053c19325280d10/src/browser/actions/attachmentContext.ts) 与 attachments.ts 入口会拒绝 Work（含 /c/WEB… 与 Work toggle 的检测）。它不是 Chat 和 Work 通用证据。
- [composerRoot.ts](https://github.com/steipete/oracle/blob/fde96271db1611c0287fcfde3053c19325280d10/src/browser/actions/composerRoot.ts) 的首个可见输入框策略，不是 Riftlet 所需的确定目标绑定；现有英文／日文 removal control 识别也不是所有语言保证。

本轮实际运行原函数＋上游 FakeDOM 得到：

| 离线构造 | 原函数结果 | 精确意义 |
| --- | --- | --- |
| 只新增 unrelated-user-added.png，却确认 wanted.png | wanted 被记为 PRESENT | claim 时只要求恰有一个新 removal control，没有核对它真的属于 wanted；**身份关联反例** |
| input.files 有 wanted，既无卡片也无 send button | 模拟 1750 ms 后 completion 返回 | 文件输入控件残留不能证明页面已接纳 |
| 匹配卡片带合成 data-state=error，send 可用 | 模拟 2000 ms 后 completion 返回 | 此判据没有识别本实验构造的错误标记；不是对真实 ChatGPT 错误 DOM 的断言 |
| 有匹配卡片，send button 缺失，无正向 READY | completion 立即返回 | “卡片存在＋按钮缺失”不足以证明就绪 |

**VERIFIED 仅覆盖上述离线函数行为。** 没有运行 Chrome、macOS、真实草稿或网络上传；未证明 Oracle 完整管线在实际环境中触发这些状态。原函数、日志、准确字节哈希和复现命令见 04_EVIDENCE.md。

可保留的是“限定 composer、记录实际节点、节点脱离／替换后使旧证据失效”的思想；必须在认领新节点时先验证准确文件名或相关 fileId。Riftlet 串行自己的上传不能阻止用户同时手动添加另一张图。

## 3. 严格 READY：把问题缩到一个可以真实证伪的证据链

**完成回执必须同时证明：图片是本次图片、草稿是原草稿、页面已正向认可图片可用。**

推荐的合成判据：

1. 本次 operationId 对应不可变私有文件；上传名包含独立 UUID，扩展名和 MIME 必须与实际编码一致。只有实际解码并转换成 PNG 的派生副本才可叫 Riftlet_{UUID}.png，不能只改后缀。原始截图仍保留。UUID 仅避免名称冲突，自己生成文件名不等于页面已经认领。
2. attachment identity 能从实际目标中观察，且能与本次真实输入唯一关联；可用准确文件名、服务端 fileId，或另一个经测试可靠的标识。哈希只做传输完整性，不能盲目合并两次内容相同的截图。
3. 目标文档、surface、聊天／未发送草稿代次及 composer 仍匹配。用户正常输入文字不应导致新代次；新建聊天、切换 thread、重建 composer 等需要失效旧 lease。
4. 同一附件出现已验证的正向 READY，且仍是该草稿的有效成员。相关 error／uploading 状态阻止成功。
5. 凡是没有足够证据，返回 UNKNOWN，不靠计时推断。

一个新发现是 OpenAI 自己的 [Codex files.rs](https://github.com/openai/codex/blob/970111f6cb62cc02fe36a82ea7d71b37a2889c97/codex-rs/codex-api/src/files.rs)，固定 970111f6cb62cc02fe36a82ea7d71b37a2889c97：

- 创建文件记录取得 file_id；
- PUT 文件字节完成；
- 另行进行 /files/{file_id}/uploaded 最终确认，只有 status=success 且具备 download_url 才返回成功；retry 与失败另行处理。

这是 **SOURCE-VERIFIED 的 Codex MCP 文件存储实现**，不是公开的 ChatGPT composer 合同。它提供了下一轮更具体的问题：页面自己的正常图片上传是否也暴露“输入对象→fileId→最终接受→原草稿附件”的可观测链？若有，可被动关联；不调用这些内部接口，不读取认证，不重放请求，不继承 use_case=codex 或其文件大小上限。

**PUT 200、最终存储 success 仍不是草稿 READY。** 网页可能重编码图片、换名字、在 worker 内请求，或没有可观察的草稿成员关系；这些都会使候选链失效。MAIN observer 也不是官方稳定 API。优先验证纯 DOM 是否已经足够；缺少明确语义时才评估这一更强的观察目标。

## 4. 目标绑定、网络失败与防重

### 网页

点击时冻结的 target lease 至少含 browser app／profile connection、windowId、tabId、documentId 或原生注入 nonce、surface、route 与 draft/composer generation。扩展从真实 MessageSender 取身份，不能相信页面 payload 自报。原生路线使用 Chrome 暴露的 tab/window session ID；这些身份跨浏览器重启失效。

必须将 macOS 前台浏览器与实际 focused 窗口、active ChatGPT tab 对齐。不能使用“Chrome 里最近活跃的 ChatGPT tab”替代“用户当前正在使用的聊天”。多 profile 由各 native port 的本地连接身份隔离；拿不到唯一目标就不输入。

documentId 不会因全部 SPA 路由变化而改变；空白新聊天也可能复用 URL 和 DOM。没有可信 draft epoch 时不能把原 URL／原节点当绝对草稿身份。把即时目标复核与 input dispatch 放在同一段同步页面执行中，减少中间竞态；随后仍要观察导航和草稿变化。

### 原生 Mac

冻结 PID、bundle/version、AX window、目标 composer 与当前选择。PID 只指应用，不指其中某个聊天。定向 Paste 前再次验证，不能通过激活 App、Cmd+A、AXValue 替换全文或恢复旧整段草稿来消除竞态。独立测试 fileURL 与 PNG；如果粘贴会替换选中文本，只在目标支持可写选择区且已验证时折叠选择到末端，保留原文。否则该输入方式不能通过准入。

剪贴板内容只暂存在内存；用自身 marker 与 changeCount 避免覆盖用户后来的复制。恢复只能在确认目标已消费数据后进行；严格 READY 足够。NSPasteboard 没有原子 compare-and-swap，某些延迟提供的内容也不能完整往返，不能承诺百分之百透明恢复。固定 300 ms 后恢复不是可靠机制。

还需核实目标 macOS 的剪贴板隐私行为：Apple 当前 [NSPasteboard.AccessBehavior 文档](https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-swift.enum/alwaysdeny) 区分 ask／allow／deny，并说明用户发起且与粘贴相关的访问有例外。不能假定 Riftlet 为恢复而读取原剪贴板、或合成 Paste 都自动属于例外。对提供该策略的系统记录实际 accessBehavior 和提示结果；不把复制旧内容当作无权限前提。这也强化了网页直接传字节路线的价值。

### 所有适配器共用

持久化顺序：先写入 operation／target／dispatch-intent，再执行外部输入；确认 READY 后再提交 consumed。主 App 是状态唯一写入者。helper 和扩展只有传输及版本受控的证据报告职责。

- 同一截图的连续点击合并为一个未决操作；同草稿的不同截图按点击顺序串行。排队等待时 target 变化，尚未发出的项保留，不自动转投新聊天。
- 输入已分派后，timeout、断线、worker／App 重启、导航及证据丢失都进入 UNKNOWN；恢复后仅查询原操作。
- 不在 UNKNOWN 后切换粘贴、DataTransfer、CDP 等机制重传。已经对远端产生副作用的操作没有可用幂等键时，本地日志不能提供全局 exactly-once。
- 明确终止失败可以重生，但不自动重传。下一次正常点击先核对并安全处理本次失败条目；不能删除本次操作前已存在、或不属于本次操作的附件。若失败条目仍会被页面自动重试，则结果仍不够终局。
- 用户移除、替换本次附件应被识别；它不是上传成功。晚到回执必须仍属于原 operation 和代次。
- 只有 READY 才驱动成功吞噬。UNKNOWN 必须继续保有截图并禁止盲重试；具体视觉语言由视觉专项决定。

## 5. 新版 ChatGPT Mac、Classic 与官方草稿能力

[OpenAI 当前迁移说明](https://help.openai.com/en/articles/20001276-moving-to-the-new-chatgpt-desktop-app) 区分整合 Chat／Work／Codex 的新版桌面与仍受支持的 Classic。应用名称不能替代 bundle ID、版本和 surface；本轮未检查安装包或 AX 树，也不假设新版一定采用某个 UI 框架。

正式接口确有更好的草稿语义，但尚未形成 Riftlet 的直接通道：

- 固定 [openai/mcp-extensions spec](https://github.com/openai/mcp-extensions/blob/36f8b38df179144b44d157133bbc5f7c6e353ace/docs/spec.md) 支持 image content 与 ui/message 的 send:false；省略 send 的默认值反而是 true。必须先确认 host 广告 openai/message 扩展能力及 image 支持；仅初始化／挂载不够。能力缺失时不得调用并假定 host 会遵守该 metadata，以免基础 ui/message 被当作发送操作。
- Desktop global entrypoint 的 active 指 entrypoint 自己的 thread。thread entrypoint 要在特定 thread 中打开；没有提供任意 threadId／draftId 参数或原生系统 RPC。
- 固定 [ext-apps schema](https://github.com/modelcontextprotocol/ext-apps/blob/266a9e3b70dbd4a4f0546dda95da2a2c1a8be4b7/src/generated/schema.ts) 的 message 结果只有通用 isError 等交付语义，不保证逐文件 READY／操作回查。
- 官方 [widget uploadFile](https://developers.openai.com/plugins/reference) 返回 fileId，不等于将该文件放进任意前台草稿。它要求相应的已挂载 widget 上下文。
- 官方 [desktop deep links](https://learn.chatgpt.com/docs/reference/commands) 可打开已有本地 thread；prompt/path 等描述的是新聊天，未找到对任意现有 ChatGPT 草稿追加图片并取得回执的公开参数。

本地 MCP 可以使用 STDIO，不能把“必须有云服务器”作为排除理由。真正缺口是持续挂载、正确目标和逐图片回执。若未来官方补足这三个契约，它应优先替代 UI 自动化；当前不据此增加插件打开／确认步骤。

**当前结论：新版与 Classic 都没有已证实的严格 READY 判据，也没有证据证明它们必然不暴露该判据。** 本轮无真实 Mac GUI，运行验证为 BLOCKED；输入、身份、READY 各自为 NOT_TESTED。即使未来只证明可靠输入而不能证明 READY，也不能按当前产品契约自动吞噬。

## 6. 原生系统实现：可减少哪些复杂度

| 系统事项 | 技术裁决 |
| --- | --- |
| 非激活单击 | AppKit accessory＋borderless/nonactivating NSPanel；canBecomeKey/Main=false；内容 view 的 acceptsFirstMouse=true。这些是分开的机制。当前 ChatGPT 焦点保持仍需真机检查 |
| 真正透明区域 | Apple 的 windowNumber(at:belowWindowWithWindowNumber:) 按 mousedown 规则跳过该点透明的窗口。优先测试一个真正透明的点击画布＋全穿透装饰 panel；若实际 backing／阴影不可靠，再用每图一个小 panel，空隙没有输入窗口 |
| 点击策略 | NSView.hitTest(nil) 不等于把点击交给下层应用。不引入 Tendedero 30 Hz 指针轮询；不等待 doubleClickInterval；装饰窗口始终 ignoresMouseEvents |
| 全屏／Spaces | 优先公开 collection behavior；Apple DTS 的 macOS 26 案例提供 canJoinAllApplications＋canJoinAllSpaces＋fullScreenAuxiliary＋stationary 的具体可行配置。层级从最低有效值验证，不能默认用高层级压过系统截图 UI |
| 多显示器 | 几何与屏幕身份、缩放解耦；屏幕变化／唤醒时重新锚定。截图保存有延迟，不用保存完成时鼠标位置推断截图来自哪个屏幕 |
| 系统截图自身污染 | sharingType.none 的当前官方文档明确不能用于隐藏／排除捕获内容。SCK 的排除项只控制调用者自己的捕获。未找到覆盖所有系统截图入口的可靠公开前置通知；不能承诺监听快捷键后隐藏就一定成功 |
| 低资源 | ImageIO 下采样；CALayer 只在需要时动画；文件与生命周期事件驱动；无常驻指针轮询、全盘索引、无限图库或第三方追踪 SDK。实际 CPU／内存尚未测，不给虚构数字 |

主要官方依据：[透明点命中](https://developer.apple.com/documentation/appkit/nswindow/windownumber(at:belowwindowwithwindownumber:))、[非激活 panel](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel)、[Apple DTS 全屏案例](https://developer.apple.com/forums/thread/826308)、[sharingType.none](https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum/none)。

截图最快可靠感知应是：用户授权的来源目录 → 目录事件 → 有界候选集合 → 文件身份／大小／mtime 稳定窗口＋ImageIO 完整性 → 复制到私有 staging → 再验来源与副本并成功解码 → 原子提升 → 入队。正常截图不移动原件；不按英文文件名前缀判断。metadata 未到的候选暂留 pending，成功持久收录后再记 seen。

首次启动建立存量基线，重启／唤醒按 checkpoint 有界补扫；换目录或目录失效重建 watcher。目录级 DispatchSource 不提供逐文件变更，也不证明内容写完。若使用截图 xattr，读取真假而不是只测属性存在。明确由用户指定的专属截图目录能减少分类工作，普通自定义目录不能自动当作专属。

系统浮动预览可能让文件稍后才保存。[Dropover 官方说明](https://dropoverapp.com/kb/screenshots) 与 [Apple 截图帮助](https://support.apple.com/en-us/102646) 均说明等待预览后保存的行为。测量必须拆开“捕获完成→文件可用”和“文件可用→裂缝可点”。文件尚不存在时，提高扫描频率没有帮助。保存到 Clipboard／Preview 也不属于目录路径；一次性设置可指导使用本地目录，不能静默改变系统截图设置。

## 7. 推荐架构与工程准入

**原生主体零第三方运行库；网页 adapter 只实现最终胜出的一个生产 transport。**

| 必要模块 | 输入 → 输出／责任 |
| --- | --- |
| SourceAccess＋CaptureIngestor | 授权来源 URL／bookmark → 不可变 Asset；目录 watcher、完整性检查、私有副本与恢复 |
| QueueStore | 系统 SQLite 的小型 Asset／Operation 状态，单写入者；文件独立保存。无 ORM、无限历史或事件溯源平台 |
| ThumbnailRenderer＋RiftPanel | Asset → 下采样图／点击 assetId；只反映状态，几何参数由视觉成果提供 |
| TransferCoordinator | assetId＋当前目标 → operation、目标 lease、串行化、恢复／防重／三态回执 |
| WebAdapter | surface-specific composer 定位、append 和 receipt；共享语义，transport 在 Apple Events 或扩展中选一 |
| MacAdapter | fileURL／PNG、AX 目标与回执；只有相应版本三项证明齐备才启用严格模式 |

Asset 与 Operation 不应混为一物：同张截图可有失败后的明确重试，已分派但未决的操作不能用新 UUID 掩盖。持久队列只需少量活跃项及必要的已用标记，归档／物理删除仍是未定产品决策。

浏览器扩展若胜出，增加一个 stdio helper 和浏览器自身 worker 即可；不增加本地 HTTP 服务、后端、模型 API、云账号或屏幕录制。网页 Apple Events 路线只加 Automation；Mac AX 路线才请求 Accessibility。来源目录授权与所需签名权限在具体分发模式中验证，不因为“截图 App”就申请全盘访问、Input Monitoring 或屏幕录制。

| 模块 | 技术上是否可以进入正式工程 |
| --- | --- |
| 队列状态模型、不可变 asset、目录 watcher、解码／缩略图、日志脱敏、恢复框架 | 可以。接口与依赖风险低；按本包补齐边界测试即可。**当前用户尚未批准正式开发，本轮没有创建它们** |
| 非激活 AppKit shell、参数化 panel 和动画接口 | 可以准备实现；先用短真机检查收口点击与 Spaces，不固定任何 pt 尺寸或艺术造型 |
| 网页 transport 的最终选择、composer 输入和 READY profile | 必须先做真实 A/B；不存在已经通过的端到端路径 |
| 新版／Classic Mac 严格 adapter | 必须先取得 INPUT、IDENTITY、READY 三项证据，分别准入 |
| 系统截图排除自身的承诺 | 必须真机验证并由产品确认支持边界；不能把未证实的 hiding 技巧写成已解决功能 |

## 8. 真正可能阻碍交付的四个问题

1. **当前 Chat／Work 是否存在精确到本图、本草稿的正向 READY 证据？** 只解决 FileList 不够；两种网页 transport 都受此约束。
2. **新版／Classic Mac 能否给出对应证据？** 若 AX 与正式接口都没有，当前严格原生客户端支持不能准入，而不是靠延长等待伪装成功。
3. **SPA 新草稿、同 App 多窗口／profile、分派瞬间切换和断线后，能否保持唯一目标并回查未决操作？** 不能证明时要保持 UNKNOWN；若常用路径频繁落入 UNKNOWN，体验不达标。
4. **系统截图自包含与浮动预览延迟的实际表现如何？** 若常用入口会截入裂缝，应据真机结果确认可接受行为与支持边界；不能把尚未验证的排除机制写成已经实现。本轮不新增“所有入口绝对排除”的产品承诺。

其它诸如缓存容量、数据库建表、动画曲线、编号字体均不是本轮核心阻塞。

## 9. 独立裁决的直接答案

- **纯 Mac App 能否满足网页版？** 有具体源码支持的候选路径，不能再以“只能粘贴”否定；当前还不能说已满足，缺实际输入与严格回执。
- **扩展是否真正必要？** 尚未证明必要。若足够的 READY 在可读 DOM 中，原生 JS 可能最省工程；若需要更强页面观察及生命周期，扩展优势变成决定因素。两者共用实验，不能先做两套产品。
- **新版 Mac 是否已有可靠 READY 判据？** 本轮未取得，NOT_TESTED；没有把工具不能操作等同于 API 不可行。
- **哪些代码直接复用？** FolderWatcher 生命周期、小型 fileSignature／ImageIO complete 检查、LinePanel 非激活骨架／acceptsFirstMouse。其它以机制参考为主。
- **哪些模块可安心开始？** 原生基础、队列／事务边界、私有图片、缩略图、参数化窗口；仍需等待用户对正式开发的统一授权。
- **哪些必须先验证？** 当前各 composer 的 append、身份、READY、目标竞态，以及系统截图自包含。
- **有没有显著简化的新路径？** 有：纯原生 Apple Events JS 可省扩展；fileURL＋UUID 可简化 Mac 附件身份；透明画布可省指针轮询；公开 collection behavior 可省 Space 私有 API；小片段复用可省掉整套截图管理器。它们分别有明确证据边界，不能合称已经完成的产品突破。
