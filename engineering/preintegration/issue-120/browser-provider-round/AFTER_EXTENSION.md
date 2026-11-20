# 安装 Edge 扩展后的验收与交付

**PARTIAL。** 在现有正常配置确认了 Edge 的官方扩展。build 53 的两个全新草稿 canary 和 G1、G2、真实服务 G4 均为 NOT_RUN。#122 修复了旧附件被替换仍可能确认 START 的缺陷，产品提交为 `b20cefbf`。正式矩阵仍为 0/16。[本机收据](after-extension.json) · [支持矩阵](../matrix/results.json)

## 浏览器控制

| 检查 | 实际观测 |
| --- | --- |
| Chrome | 浏览器正在运行，四个配置中两个已启用扩展，选择的配置已启用，原生消息清单正确。此前桌面设置显示 Chrome 已连接。 |
| Edge | 浏览器正在运行，两个现有配置中一个已启用扩展，选择的配置已启用，原生消息清单正确。桌面设置中的 Edge「管理」状态仍未读到。 |
| 官方连接 | 本会话以 Edge 和 Chrome 为目标的两次独立连接，以及新执行上下文对 Chrome 的握手，均在创建浏览器句柄之前报告 `Trusted RPC service is not configured: browser`。桌面安全控制拒绝 Computer Use 操作桌面 App 自己的设置。可单独管理的 CLI app-server daemon 未连接。 |
| 原生备选 | 无提示探针两次实测 AX 和事件发送预检为真，对 Chrome、Edge 各一个运行进程查询 Apple Events 的 get 权限均返回 0。公开 AX 键盘方法接受应用或系统对象，CoreGraphics 发送目标为进程。可读取窗口/标签的 Apple Events 权限不足以将下一次真实按键投递到该标签。Tabbit 的控制入口对应独立的浏览器产品。 |
| 现场影响 | 正常用户配置新增 QA 窗口 0、向浏览器发送真实按键 0、Riftlet 截图点击 0。既有登录未变更。 |

检查顺序可在已安装两个扩展的 Mac 上重放。先运行 `node Tests/LiveDraftAcceptance/installed-controller.cjs`，再按验收目录说明通过官方客户端连接指定浏览器。校验原生替代通道时，先编译并执行同目录的 `native-permission-preflight.m`；该探针不发送键盘/Apple Event，也不申请授权。只有可信服务返回指定浏览器并成功建立原标签身份，才开始原有 canary。操作人需在桌面对话选择官方 Chrome 浏览器控制插件，若桌面弹出已有 Edge 配置的连接确认，仅完成此项授权。[QA 入口](../../../../Tests/LiveDraftAcceptance/README.md) · [OpenAI 桌面浏览器使用说明](https://developers.openai.com/training/walkthroughs/using-your-computer-and-browser) · [Apple AX 键盘接口](https://developer.apple.com/documentation/applicationservices/1462057-axuielementpostkeyboardevent)

### 1.0.7 实站余项

没有产生新的登录草稿操作。保留原 Edge 操作的 UNKNOWN，历史库确认零 START；实站原预览来源、解码尺寸、原卡与 Remove 的关系仍未知。G4 缺同一真实服务附件的明确失败，也就没有可以合法归属的原图恢复和明确新点击成功。现有本地服务失败和 SQLite 回归继续按各自层级记录。无需为本轮重新测试已验证的 1.0.7 安装/升级。重新核对原 build 53 的 DMG SHA-256 和 Gatekeeper 公证结论，App 同时包含 x86_64、arm64 且 deep/strict 双架构验签通过。[原签名包身份](../build53-recheck.json)

## 新 Provider 和宿主

旧实现可能在有新图时忽略旧图丢失。修复保留输入前已有卡和图像预览的身份及有效来源，首次确认 START 时核对它们。首次 START 后仍可单独续查本图的失败；前次 UNKNOWN 不占用下一张图的输入机会。原有属性按相同值重写时可正常接受，新图不需要旧文件的内容或旧任务的成功状态。独立审核发现并修复了只核对旧卡名称漏掉预览替换，以及同值属性重写导致误拒两个问题。

从最终 ARM64 开发 ZIP 提取资源，在非持久、本机回环 WKWebView 中执行。8 次输入各有一次 change，零错投、零发送、原选区保留。原卡不变和同值重写均得到受控 START。旧卡或旧图被移除再放回、名称或图片源改后还原、响应式有效源改变均保持 UNKNOWN。非作者在新图摘要等待期间替换再还原旧图，确认旧操作多次读取仍为 UNKNOWN，重复原票输入被拒，同稿另一张独立截图可成功接收。焦点和可见性由本地夹具提供。Claude、Gemini 及其余公开站点均未增加写入准入。

Brave 的可选全属性回包缺失时，现只向原进程和绝对窗口/标签描述符读取 URL 一次。过期、可变索引、错标签和畸形回包拒绝。编译代码在 AppKit 自收发探针上实际运行，独立复核确认正确属性回包不产生补读。Brave 实站页面执行、异步回执及写入仍待验。Safari 沿用上轮同窗口页面替换反例，原生标签定址仍待验；Firefox 维持无扩展验证的原边界。[Brave 宿主证据](../hosts/README.md) · [Safari 客机证据](../hosts/safari-epoch/receipt.json)

新 ZIP 使用独立应用标识、ad-hoc 签名，仅本地交付，未公证。解包后核对可执行文件和网页资源，执行包内自检。正式双架构候选、签名公证、升级和同包登录验收均须先满足 W0 并在实际 main 继承最终 1.0.7。两 PR 保持 Draft，公开版本仍是 v1.0.5。[本包收据](development-b20cefbf.json)
