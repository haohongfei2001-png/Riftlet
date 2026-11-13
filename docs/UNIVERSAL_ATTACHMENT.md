# 无扩展附件引擎 · 首轮工程交接

公开下载仍是 0.3.5 (20)。本分支来自 `280be2f8422ccf6c0864f53b8f83e80552b2ec32`。在 build 18 上曾实测 Chrome 中的两张截图连续进入 ChatGPT 草稿，build 20 沿用那一版附件实现。本次修改了点击绑定，因此历史实测不能证明这个候选版本的首击、吞噬或速度。发布版本与候选版本都只需系统截图后点击微图，发送消息由用户决定。[已发布版本](https://github.com/haohongfei2001-png/Riftlet/releases/tag/v0.3.5-beta.1)

## 一次点击由谁负责

1. **应用和窗口。** 三种呈放形态继续走同一个鼠标按下或辅助功能调用入口。`ConversationClickRouter` 只调用与前台应用匹配的唯一已接入适配器。Chrome 和 Edge 的 `ApplicationHostAdapter` 按各自的脚本字典解析原进程、内核启动时间、窗口、活动标签和地址。Chrome 保留原来的 `ChromeAppleEventsExecutor`、`ChromeCommandRouting` 和历史 session 编码。未登记的宿主在读取聊天内容或准备文件前就被拒绝。
2. **草稿。** 普通 Chrome 点击同步在原标签上绑定文档、导航、编辑器及其容器。随后初始化 MAIN 页面并检查同一次点击的绑定，原生端在提交前复核当前宿主。活动标签变更、相同 URL 的新文档、原编辑器被替换均不能成为新的接收者。动态重建文件输入仍走既有附件入口发现。其他服务各有路由和界面选择规则；只读探针复核原文本、选区、原附件节点与文档，只向宿主返回枚举和计数。未得到服务真实样本的特征仍待校准。Edge 的原生读路径可组合这些探针，读回值不授予写入权。
3. **传输。** 编译期的 `AttachmentTransport` 接口将一次文件交付和其返回值配对，供 AX/WK 原型使用。正式截图仍走 `TransferCoordinator → WebAttachmentAdapter → ChromeAppleEventsExecutor`，沿用既有持久化意图、`TargetLease`、文件来源验证和独立输入回执。`NativeMacVerifiedFile` 复用打开的目录与文件描述符、inode 与哈希核验。供 WebKit 使用的 URL 仍有从返回 URL 到接收方实际打开文件之间的竞争窗口，原型在自有临时目录和回环服务器上核实实际到达的字节。
4. **状态。** 输入或选中行只代表尝试。已有产品的 `attachmentAccepted` 表示当前文件在原 ChatGPT 草稿出现了应用归属的接收迹象；它不会记录服务器已经收到字节。普通产品在 START 后停止管理该上传。新增服务需要标定自己的 START、最终确认和明确失败，不能借用 Chrome 的 profile 或用占位图触发吞噬。回环实验用不同的观测记录第一个正文字节、完整文件以及原草稿收到确认。失去确认保留 UNKNOWN，下一张图片可独立发起；超时、窗口关闭和进程退出都不会触发自动重传。

## 真实商业服务兼容性

表中每个格子表示**本分支经 Riftlet 实际点击并附加至对应商业服务**的结果。N 表示 NOT_RUN。各格的前台宿主、窗口及草稿、附件入口、指定图片、文本选区及原附件、START、最终状态、失败及 UNKNOWN、连续附加、额外操作十项都有独立字段。[32 个组合的逐项记录](../engineering/universal-attachment/live-matrix.json)

| 本机宿主 | ChatGPT | Claude | Gemini | Perplexity | Poe | 本轮可核实的宿主证据 |
| --- | --- | --- | --- | --- | --- | --- |
| Google Chrome 157.0.8103.51 | N | N | N | N | N | 发现三个运行实例；既有真实草稿证据限于较早版本 |
| Safari 27.0 | N | N | N | N | N | 已安装，本机采样时未运行；字典声明当前标签和索引，无标签类稳定 ID |
| Microsoft Edge 156.0.4314.58 | N | N | N | N | N | 一个运行实例；独立 Profile 无窗口引擎通过回环传输；本机 AE 测试在前台检查处停止 |
| Firefox | N | N | N | N | N | LaunchServices、运行列表与常用目录均未找到 |
| Brave | N | N | N | N | N | 同上 |
| Arc | N | N | N | N | N | 同上 |

| 原生目标 | 本轮真实草稿 | 本机观测 |
| --- | --- | --- |
| ChatGPT for Mac | NOT_RUN | 未发现 `com.openai.chat`；名为 ChatGPT 的现装应用实际为 `com.openai.codex` 26.1106.51428 (26605)，AX 核实后台进程拥有一个窗口。没有读取草稿内容或操作该窗口。 |
| Claude Desktop | NOT_RUN | 未发现登记、运行或安装的 `com.anthropic.claudefordesktop`。 |

内置浏览器未能建立专用 ChatGPT 测试草稿，访问 Claude 时报告 IAB 不可用。没有向商业服务发送测试消息，也没有使用个人浏览器会话绕过访问限制。已安装、已登录、允许自动化和能够证明目标草稿是不同事实。某服务的未执行不表示该产品无法支持。[宿主清单与复现命令](../engineering/universal-attachment/hosts/README.md) · [ChatGPT 标识应用的 AX 记录](../engineering/universal-attachment/native/installed-chatgpt-host.json)

## 可复现的原型结果

| 场景 | 直接验证的结果 | 范围 |
| --- | --- | --- |
| Edge 独立无窗口实例 | 服务器核实四次请求的图像字节。两次 201、一次明确 422、一次服务端收图后丢失回执，重复请求为零。另一个操作可成功；保留原文、反向选区及原附件节点。 | 测试网页主动运行同一交付程序。本机未证明 Apple Events 已送达 Edge；更未证明 Edge × ChatGPT。 |
| macOS 原生 WebKit | 两次实际文件选择代理回调、两个不同 PNG 的完整字节、两次草稿确认。未聚焦编辑器的文字、选区及第三张原有 PNG 均保留。拒绝同内容 inode 替换和重复交付。 | 自有非持久 WKWebView 的公开代理接口，窗口未显示；外部 Safari/原生 App 的代理由对应应用拥有。 |
| 五个对话表面 | 在真实 WebKit 引擎上分别运行五种服务形态的受控 HTML，覆盖多文档、相同地址、导航离开再返回、编辑器重建、焦点、已有附件和歧义入口。 | 静态服务特征尚未在对应账号草稿上认证。 |
| 外部 AX 与系统文件面板 | 托管 Mac 探针分别测试受控 AppKit 文件列表和真正的 NSOpenPanel。只有相同进程/窗口、唯一原草稿与可核验选中 URL 同时成立，才允许最终操作。 | 每个探针的实际结果记录在 PR 对应 Actions 日志的 `externalAX` 字段。XPC 面板或无法证明的行必须单独记为未验证。 |
| 系统剪贴板 | 继续使用独立命名板测试 NSPasteboard 的实际读写、完整多类型快照、所有者标记、changeCount 和外部复制后放弃恢复。 | 其他进程可能在检查与写入之间复制，AppKit 未提供跨进程原子比较与写入。一般剪贴板不作为普通点击备用路径。 |

运行真实 macOS 检查使用 `bash Tests/ConversationSurfaceHost/run.sh`、`python3 -B Tests/UniversalNativePickerHost/run.py`、`python3 -B engineering/universal-attachment/edge/verify.py --mode headless`。Chrome/Swift/XCTest 随正式 Native ARM64/Intel 工作流运行。Safari 和 Edge 的前台实验只在临时托管 Mac 上执行。独立过程的 capability 拒绝均在日志中列出。脚本使用中性生成图片、临时文件夹、独立 Profile 或非持久数据，浏览器只接触自有测试页。[Edge 实验](../engineering/universal-attachment/edge/README.md) · [WebKit 日志](../engineering/universal-attachment/surface/run.json) · [原生文件交付](../Tests/UniversalNativePickerHost/README.md)

## 权限及发行

- 官网 Developer ID 渠道沿用现有 Apple Events entitlement 和面向 Chrome 的用途说明。新原型没有修改签名、Info.plist、发行包或系统设置。新接收方获准使用前，要为该接收进程验证 Automation 授权及浏览器自身的 JavaScript 开关。TCC 授权按实际发送方和接收方检查，开发工具的授权不能移植到安装包。[Apple Event 权限](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events)
- AX 辅助功能授权用于读取或操作其他进程的界面。该授权本身无法证明选中的草稿、面板或文件；探针仅被动检查现有授权。普通系统截图文件收录使用既有目录访问与书签。内置屏幕捕获按原流程处理录屏权限。新适配器没有为识别窗口增加录屏权限。[辅助功能信任检查](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions) · [安全作用域书签](https://developer.apple.com/documentation/foundation/nsurl/bookmarkcreationoptions/withsecurityscope)
- Mac App Store 要求 App Sandbox。目标须提供适用的 scripting access group，否则发送 Apple Events 通常要逐目标申请临时例外并说明理由。现有 Developer ID entitlement 不能证明沙箱外部 AX、跨 App 文件访问或商店审核通过。后续应使用单独的沙箱测试包验证授权、重新启动后的书签解析和失权时的降级。[App Sandbox](https://developer.apple.com/documentation/security/app-sandbox) · [Apple Events 沙箱例外](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html)

## 下一次可执行验收

优先在隔离的正常用户 macOS 会话中为 Edge 建立专用未发送 ChatGPT 草稿，核验原生 AE 从按下到原文档、附件入口和第二次提交，再独立标定服务端接收与最终确认。Safari 需先验证两同址标签切换、标签移位及重建时仍能复核原文档。Claude、Gemini 依次从已绑定的精确草稿采集脱敏的真实状态，只在能排除错投、重放、伪 START、文字/选区丢失时注册对应路由。对未安装的客户端先取得独立安装环境和受支持公开接口，再运行同一组验收。当前没有公开发行或主线合并操作。
