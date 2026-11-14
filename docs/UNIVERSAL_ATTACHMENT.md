# 无扩展附件引擎 · 首轮工程交接

任务开始时的正式产品是 0.3.5 (20)，远端基线为 `280be2f8422ccf6c0864f53b8f83e80552b2ec32`。开发期间主线合入 1.0.0 首次使用与连接检查，本分支先同步了 `bc314340692b1db7246127e4b6fb9dd02a446568`，又同步了正式下载入口 `427c5325` 、官网语言选择 `8a648237` 与内置更新器 `5da42a221fb3e6496585c127e6cf11b8e836840f`。更新器退出期间的点击仍被拒绝。公开版和发行资源由各自的发行任务管理。在 build 18 上曾实测 Chrome 中的两张截图连续进入 ChatGPT 草稿，build 20 沿用那一版附件实现。本次修改了点击绑定，因此历史实测不能证明这个候选版本的首击、吞噬或速度。发布版本与候选版本都只需系统截图后点击微图，发送消息由用户决定。[已发布版本](https://github.com/haohongfei2001-png/Riftlet/releases/tag/v0.3.5-beta.1)

## 一次点击由谁负责

1. **应用和窗口。** 三种呈放形态继续走同一个鼠标按下或辅助功能调用入口。`ConversationClickRouter` 只调用与前台应用匹配的唯一已接入适配器。Chrome 和 Edge 的 `ApplicationHostAdapter` 按各自的脚本字典解析原进程、内核启动时间、窗口、活动标签和地址。Chrome 保留原来的 `ChromeAppleEventsExecutor`、`ChromeCommandRouting` 和历史 session 编码。未登记的宿主在读取聊天内容或准备文件前就被拒绝。
2. **草稿。** 普通 Chrome 点击同步在原标签上绑定文档、导航、编辑器及其容器。随后初始化 MAIN 页面并检查同一次点击的绑定，原生端在提交前复核当前宿主。活动标签变更、相同 URL 的新文档、原编辑器被替换均不能成为新的接收者。动态重建文件输入仍走既有附件入口发现。延迟选择器回调在实际写入前复核文档仍然可见且处于活动状态，不要求光标位于编辑器。同步点击阶段的原生查询共用一秒截止时间。候选版本真实首击延迟尚未测量。其他服务各有路由和界面选择规则；只读探针复核原文本、选区、原附件节点与文档，只向宿主返回枚举和计数。未得到服务真实样本的特征仍待校准。Edge 的原生读路径可组合这些探针，读回值不授予写入权。
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

内置浏览器未能建立专用 ChatGPT 测试草稿，访问 Claude 和 Gemini 时报告 IAB 不可用，后者在导航前就已停止。没有向商业服务发送测试消息，也没有使用个人浏览器会话绕过访问限制。已安装、已登录、允许自动化和能够证明目标草稿是不同事实。某服务的未执行不表示该产品无法支持。[宿主清单与复现命令](../engineering/universal-attachment/hosts/README.md) · [ChatGPT 标识应用的 AX 记录](../engineering/universal-attachment/native/installed-chatgpt-host.json)

## 可复现的原型结果

| 场景 | 直接验证的结果 | 范围 |
| --- | --- | --- |
| Edge 独立无窗口实例 | 服务器核实四次请求的图像字节。两次 201、一次明确 422、一次服务端收图后丢失回执，重复请求为零。另一个操作可成功；保留原文、反向选区及原附件节点。 | 测试网页主动运行同一交付程序。本机未证明 Apple Events 已送达 Edge；更未证明 Edge × ChatGPT。 |
| macOS 原生 WebKit | 两次实际文件选择代理回调、两个不同 PNG 的完整字节、两次草稿确认。未聚焦编辑器的文字、选区及第三张原有 PNG 均保留。拒绝同内容 inode 替换和重复交付。 | 自有非持久 WKWebView 的公开代理接口，窗口未显示；外部 Safari/原生 App 的代理由对应应用拥有。 |
| 五个对话表面 | 在真实 WebKit 引擎上分别运行五种服务形态的受控 HTML，覆盖多文档、相同地址、导航离开再返回、编辑器重建、焦点、已有附件和歧义入口。 | 静态服务特征尚未在对应账号草稿上认证。 |
| 外部 AX 与系统文件面板 | 托管 Mac 探针分别测试受控 AppKit 文件列表和真正的 NSOpenPanel。只有相同进程/窗口、唯一原草稿与可核验选中 URL 同时成立，才允许最终操作。 | 首轮托管 Mac 的两个探针均因无法核实接收进程的前台身份而停止，零文件提交。后续改用 LaunchServices 启动独立签名的测试宿主，并核实实际前台进程、启动时间和关键窗口；在 macOS 15.8.2 上，第二轮成功找到原草稿并按下附件入口，自有文件列表仍未证明文件选择，系统面板查询返回 `-25204`，两种路径均未提交图像。第三轮已核实自有文件列表的目标行和干扰行，在提交前拒绝，现有日志无法区分是在按下目标行之前还是之后；系统面板仍无法证明属于原窗口，均未产生文件交付。随后的分阶段诊断证实，此测试文件行未向外部进程提供 `AXPress`，因此该次在选择之前拒绝。自有应用可以显式实现 AppKit 的辅助功能按钮动作；本机两个不激活窗口的独立进程已验证一次选择与一次确认，接收端按原操作标记和 69 字节中性 PNG 的哈希给出回执。跨应用可行性取决于目标应用公开的操作。在随后的一次托管 macOS 15.8.2 实测，外部 AX 进程在有干扰文件的自有文件列表选中指定 PNG，回环服务器确认首字节和完整文件，原草稿确认接收且保留文字、选区和原附件。系统 NSOpenPanel 仍无法证明属于原窗口，实测零次传输。[托管结果、源码与产物摘要](../engineering/universal-attachment/hosted-macos-results.json)XPC 面板或无法证明的行必须单独记为未验证。 |
| 系统剪贴板 | 继续使用独立命名板测试 NSPasteboard 的实际读写、完整多类型快照、所有者标记、changeCount 和外部复制后放弃恢复。 | 其他进程可能在检查与写入之间复制，AppKit 未提供跨进程原子比较与写入。一般剪贴板不作为普通点击备用路径。 |

运行真实 macOS 检查使用 `bash Tests/ConversationSurfaceHost/run.sh`、`python3 -B Tests/UniversalNativePickerHost/run.py`、`python3 -B engineering/universal-attachment/edge/verify.py --mode headless`。Chrome/Swift/XCTest 随正式 Native ARM64/Intel 工作流运行。Safari 和 Edge 的前台实验只在临时托管 Mac 上执行。托管 Mac 上，Safari 与 Edge 的 Apple Events 被动授权预检均返回 `-1744`（需要用户同意），因此没有向目标草稿执行脚本。macOS 15 的 WebKit 缺少该表面探针要求的 Navigation API，测试确认了拒绝；同机独立 WK 文件交付仍完成了两次接收。脚本使用中性生成图片、临时文件夹、独立 Profile 或非持久数据，浏览器只接触自有测试页。[Edge 实验](../engineering/universal-attachment/edge/README.md) · [WebKit 日志](../engineering/universal-attachment/surface/run.json) · [原生文件交付](../Tests/UniversalNativePickerHost/README.md)

## 权限及发行

- 官网 Developer ID 渠道沿用现有 Apple Events entitlement 和面向 Chrome 的用途说明。新原型没有修改签名、Info.plist、发行包或系统设置。新接收方获准使用前，要为该接收进程验证 Automation 授权及浏览器自身的 JavaScript 开关。TCC 授权按实际发送方和接收方检查，开发工具的授权不能移植到安装包。[Apple Event 权限](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events)
- AX 辅助功能授权用于读取或操作其他进程的界面。该授权本身无法证明选中的草稿、面板或文件；探针仅被动检查现有授权。普通系统截图文件收录使用既有目录访问与书签。内置屏幕捕获按原流程处理录屏权限。新适配器没有为识别窗口增加录屏权限。[辅助功能信任检查](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions) · [安全作用域书签](https://developer.apple.com/documentation/foundation/nsurl/bookmarkcreationoptions/withsecurityscope)
- Mac App Store 要求 App Sandbox。目标须提供适用的 scripting access group，否则发送 Apple Events 通常要逐目标申请临时例外并说明理由。现有 Developer ID entitlement 不能证明沙箱外部 AX、跨 App 文件访问或商店审核通过。后续应使用单独的沙箱测试包验证授权、重新启动后的书签解析和失权时的降级。[App Sandbox](https://developer.apple.com/documentation/security/app-sandbox) · [Apple Events 沙箱例外](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html)

## 下一次可执行验收

在隔离的托管 macOS 上，普通 Riftlet 1.0.1 (23) 已确认前台 Edge 的进程启动时间、可执行文件及中性测试窗口。两张不同的系统截图都带有 macOS 截图标记，普通 App 的队列也按各自 SHA-256 收录了两条记录。外部辅助功能探针在 14 秒内未能唯一定位第一枚可按下的微图，实际点击为零。普通 App 的行 UUID、接收点击的窗口与命中区域映射目前只在进程内可读。下次自动验收可先为该映射提供仅用于验收的只读观测，再对自有窗口做命中核验。[分阶段实测及原始产物](../engineering/universal-attachment/acceptance-20261114.json)

本轮复核普通 App 的注册表后确认，Edge 目前只能检查草稿。即使准备好已登录的 Edge 会话，现有微图入口也无法向它交付图片。Chrome 是当前唯一注册的宿主，本轮隔离浏览器超时，未能建立已登录的专用草稿。两张图片的点击、START 和最终完成分别保留为未执行。[逐图验收记录](../engineering/universal-attachment/acceptance-20261114.json)

Edge 的下一步是在受控原型上把进程、窗口、标签、文档与编辑器冻结贯通到普通 App 的单次文件交付，并取得独立授权测试环境。然后用包含中性文字、选区和已有附件的专用 ChatGPT 草稿，从实际微图连续操作两张不同截图，分别观测真实上传开始和最终确认，保留未发送状态。Safari 需先验证两同址标签切换、标签移位及重建时仍能复核原文档。Claude、Gemini 依次从已绑定的精确草稿采集脱敏的真实状态，只在能排除错投、重放、伪 START、文字/选区丢失时注册对应路由。对未安装的客户端先取得独立安装环境和受支持公开接口，再运行同一组验收。当前没有公开发行或主线合并操作。
