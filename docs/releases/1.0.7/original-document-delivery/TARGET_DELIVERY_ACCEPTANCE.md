# Riftlet 1.0.7 build 56 原目标投递验收

**最终产品准入结论为 BLOCKED_TECHNICAL。** 已验证在原始网页接收器建立以后，旧操作不能改投替换文档。物理鼠标按下至第一个浏览器接收器建立之间，现有无扩展接口无法证明当时的原编辑器一直有效。本机普通 Chrome 的官方客户端归属也未能确定。真实 ChatGPT 的 G1、G2、G4 均为 **NOT_RUN**。本候选仅作内部验收，#120 保持打开。

## 最终安装包

| 项目 | 结果 |
|---|---|
| 冻结产品源码 | `2717fa6aaa7cb3750041ca1a0779c6dab65961cc`，版本 1.0.7，build 56 |
| 最终 DMG | 13,445,118 字节，SHA-256 `4d20dc369e6cf548c57def04a1975201333503f5fe69e3b47b7a32fa0ef56b98` |
| 安装验签 | 从最终 DMG 只读挂载并复制 App 到独立目录。ARM64、x86_64、Developer ID、嵌套签名、App 与 DMG 的公证票据及 Gatekeeper 均通过。安装副本的三个自检退出码均为 0 |
| 安装副本中的完整页面程序 | 117,213 字节，SHA-256 `61669b502526bd01b71b6c9aead85c224d9f3a50263ff121997769527368e2c5` |
| 首击时传输的文档凭据程序 | 实际加载的 pinSource 为 19,799 字节，SHA-256 `0d4677f873089685306079fc7c025cebeecb9100a1fe4e06a3b82cafeeefcfb3`。20 KiB 约束适用于这个程序。Apple Event 另有封装 |

Build 55 在 ARM64 和 Intel 都触发了原有的 20 KiB 断言。build 56 修正了传输体积，保留全部程序标记和换行。下表采用 build 56 重新运行的记录。[安装验签](evidence/installation.json) · [原生加载指纹](evidence/native/pin56.json) · [build 55 失败记录](https://github.com/haohongfei2001-png/Riftlet/actions/runs/44913048921)

## 普通浏览器

| 环境 | 实际结果 | 范围 |
|---|---|---|
| 本机普通 Edge，已安装扩展的原有配置 | **通过自建页面双文档对照**。A 的独立测试字段收到可信 q 的 keydown、input、keyup。原生进程生存期、窗口、标签和随机本机地址在 A、B 相同；网页文档和编辑器标识均改变。B 执行来自 A 的旧操作，文字、setter、input、change、submit 全为 0。A、B 各自的新授权都正向写入一次测试文字和 PNG，保留选区及旧附件，零提交 | 真实桌面、正式扩展控制、顶层同 URL reload。语义文本使用绑定在原 textarea 对象上的方法。仅 A 独立按键框接受一次真实 q。没有把系统键盘作为产品通道 |
| 本机普通 Chrome，原有配置 | **NOT_RUN**。官方启动器返回已打开普通 Chrome。正式家族选择器重连后仍看不到选定原生窗口。两个连接均登记为 Chrome，新的实例核对器在操作前返回 `AMBIGUOUS_BROWSER_FAMILY`。Chrome 网页记录中事件数为 0 | 未认领个人标签，未向该浏览器发送测试按键。可用唯一的普通 Chrome 连接，或由真实 tab-v1 引用确认扩展实例，才可恢复本机此格 |
| 托管 macOS 普通可见 Chrome | ARM64、Intel 的独立 GUI 运行均通过 17 项接收器对照 | 临时配置、无扩展、测试专用管道。运行的是冻结源码中与安装资源同哈希的页面资产。该范围不包含本机登录配置或官方选择器 |
| 独立 macOS 客机 | 两款浏览器均正常启动。原生窗口创建请求超时，未取得操作该界面的授权证据。页面和按键均为 **NOT_RUN** | 客机已正常关闭。未更改权限 |

Edge 的 A 回执、替换屏障、B 完成回执分别为 14:37:22.612、14:37:39.212、14:37:56.409 UTC。挂起操作为 `7adb437b-0fe4-4954-9eb0-ac8e3e3be9b9`，测试 PNG 的 SHA-256 为 `431ced6916a2a21a156e38701afe55bbd7f88969fbbfc56d7fe099d47f265460`。A、B 的原生采样均处于系统前台，独立校验了测试页随机地址。文档 UUID 来自页面，原生采样器按时序关联它们。用完后关闭 Edge 专窗，独立确认窗口消失。[Edge 原始事件](evidence/ordinary/edge.json) · [原生关联及私有原件哈希](evidence/ordinary/edge-native-correlation.json) · [Chrome 选择器](evidence/ordinary/chrome-selector.json) · [客机记录](../../../../Tests/OriginalDocumentDelivery/guest/guest-capabilities.json)

普通 Edge 的完整 HTTPS 站点适配器在两个本机文档均正确返回 `PAGE_ROUTE_UNSUPPORTED`，全部事件计数为 0。页面正向对照使用从该安装资源逐字提取的接收器。完整页面程序的正向文件路径另在下列受控环境测量。

独立复核者用两份原始采样离线重放了归属核验。验收器要求两次都匹配私有测试地址和系统前台，且严格满足“原页采样、原页动作、替换屏障、新页采样、完成回执”的顺序。同一毫秒内无法确定先后的记录会被拒绝。重放生成的收据与归档逐字节一致，SHA-256 为 `55e5ba5d015c83c41e59b80ce89049572456fd1638d07489288744f88cbf1645`。已有同名收据和新采样未处于前台的对照均以失败结束，原收据保留。[原生采样归属核验](../../../../Tests/OriginalDocumentDelivery/official/correlate-native.cjs)

Chrome 的启动请求没有在家族选择器中形成可确认的新窗口。同一原生枚举接口在启动前后返回相同的既有窗口号。无法确认的窗口未作关闭；这次 Chrome 空白启动请求的最终窗口状态标为 UNKNOWN。桌面端的浏览器开关控制是否出现在提及菜单，真实标签提及可精确指定标签。[官方浏览器说明](https://learn.chatgpt.com/docs/chrome-extension#bring-tabs-and-selected-text-into-a-chat)

## 最终包资源与原生状态

| 测量 | Chrome | Edge | 判据 |
|---|---:|---:|---|
| 原文档接收器 | 17/17 | 17/17 | 绑定和实际副作用间有确定性屏障。覆盖原页正向、同 URL 替换与重载、真实页面前后导航和 BFCache、标签与焦点往返、iframe、编辑器或祖先移回、重入、两个操作交错及一次性消费 |
| 完整页面程序的新回归 | 5/5 | 5/5 | 两种正常菜单均保留原文、选区与旧附件，各一次 setter/input/change，零发送。焦点进入第二编辑器或闭合 shadow 后返回，旧操作在写入前退休。input 回调中移动并还原文件容器，计数为 1/1/0/0，状态 UNKNOWN；重复 commit 被拒绝 |
| 既有完整页面回归 | 13/13 | 13/13 | 使用相同安装资源和原有验收器；覆盖标签 ABA、真实同地址重载、pagehide、BFCache、编辑器更换、菜单和文件容器变化。首次输入之前失效的案例记录全零 |
| 关闭窗口和重启后的受控页面 | 2/2 | 2/2 | 已有独立窗口及进程运行记录。读操作缺少原始身份时不能恢复写入 |
| 与冻结源码链接的原生驱动和 SQLite | 通过已测路径 | 通过已测路径 | 每个浏览器真实关闭一个自有窗口，随后重启自有进程。原操作未进入页面分派。只读打开两份 SQLite，各有一张原图、一个 operation、一个 invocation、一次 dispatch、零 START，均为 UNKNOWN。磁盘 PNG 与原记录哈希一致 |

实际重启产生不同 PID。同一 PID、不同出生时间属于构造的拒绝对照；实际 PID 重用、原生窗口编号重用和已缓存前台写通道在关窗瞬间的执行均未得到实机证明。原生拒绝后网页事件不可观测，保留 null。对于已经进入 setter 的程序，后续页面变动允许保留 UNKNOWN。[Chrome 接收器](evidence/renderer-chrome.json) · [Edge 接收器](evidence/renderer-edge.json) · [Chrome 完整页面](evidence/product-chrome.json) · [Edge 完整页面](evidence/product-edge.json) · [继承回归](evidence/inherited-page.json) · [窗口和重启](evidence/inherited-host.json) · [SQLite 与原图](evidence/native/independent-sqlite.json)

## 双架构与独立复核

冻结提交的两个 GitHub macOS 作业均成功。每个架构发现 1,415 个 Swift 单元及集成用例，1,393 个进入并行分组，22 个窗口动画用例串行执行。每个架构另通过 384 个页面程序用例和 8 个故障恢复用例。存储、包体及更新规则也完成。本文没有将 Swift 的发现数写成物理交互通过数。本机命令行工具缺少 XCTest，完整 Swift 结果取自两个托管架构。[双架构作业](https://github.com/haohongfei2001-png/Riftlet/actions/runs/44914124179) · [分组与原始制品指纹](evidence/ci.json)

非实现者审查了最终页面程序、Swift 首击传输、一次性消费和生命周期退休。又从安装副本重算资源哈希，直接核对原始 SQLite、PNG、Edge 页面事件和独立原生采样。结论为可签署内部候选，现有证据不足以批准真实网站或公开推广。[实现及审查](TARGET_DELIVERY_IMPLEMENTATION.md)

## 真实 ChatGPT 与剩余边界

| 准入项 | build 56 状态 | 缺少的证据 |
|---|---|---|
| G1 Chrome × ChatGPT | **NOT_RUN** | 普通 Chrome 的正式控制身份和点击时原编辑器连续性，随后才可验证冷暖首击及三组快速双图 |
| G2 Edge × ChatGPT | **NOT_RUN** | 点击时原编辑器连续性，随后才可验证冷暖首击、双图及归属原卡的正面 START |
| G4 原卡明确失败、原图找回、用户显式再点击 | **NOT_RUN** | 同包实站授权路径和可安全观察的真实服务原卡失败。SQLite UNKNOWN 保存与只读恢复已有独立证据 |

点击发生在 macOS，而 Chromium 的 Apple Event 会在脚本执行时解析标签的当前主文档。在首次浏览器凭据出现前，旧文档和同地址新文档可以给出相同的原生窗口、标签和地址。即使时间上界成立，同一文档也可能已经换了编辑器。已确认的外部按键反例和本次原目标文件投递属于不同路径，未观察到 build 56 在真实网站发生错投。

可验证的后继方案是在点击前由浏览器建立可永久退休的原文档和编辑器凭据，并让 Mac 在鼠标按下前确认已经收到它。缺少这一确认时保留截图。若必须让无预热首击也可用，需要浏览器在文档创建时就参与记录，并以原文档标识与编辑器代际完成交接。扩展和平台原生支持分别涉及新的安装成本或浏览器能力；两条路线都需要重新验收。[系统接口、源码与架构裁决](TARGET_DELIVERY_ARCHITECTURE.md)
