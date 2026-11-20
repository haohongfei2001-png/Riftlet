# 浏览器技术裁决与必须先做的验证

2026-11-20。所有新 Host 的本轮原生/真实网站结果均为 **NOT_RUN**。官方能力、标准可行、受控原型通过、签名产品真实验证是四种不同结论。

## 1. 路线选择

保留 Chrome / Edge / Safari / Brave 四个核心目标。生产首选 **Apple Events → 受审查页面运行时 → File / DataTransfer → 原 composer 的文件输入**，不触碰系统剪贴板或网站凭证。Chrome/Edge 继承最终 1.0.7；Safari 独立 Host；Brave 复用 Chromium Host 的机制，保持自身能力和权限描述。

Brave 作为第四项基于预计复用成本与可维护性；本次没有找到足以支持改成 Arc / Opera / Vivaldi 的第一方工程证据。这不是浏览器份额排名，也不是 Brave 已兼容的承诺。Firefox 同轮研究但不能预先计入第五项正式支持。

| 浏览器 | 一手依据 | 剩余关键问题 | 本轮裁决 |
|---|---|---|---|
| Chrome | Chromium sdef 提供 window/tab 与 execute javascript；JS AE 需显式开关（B3/B4） | 最终 1.0.7 当前包、冷首击、世界桥接及恢复 | 保留其已验证行为并无回退验收 |
| Edge | 项目 #119 是实现与验收权威；不能以 Chromium 共性取代实际包证据 | 进程/世界 witness、只悬停出现的移除按钮、原附件卡关联 | 继承最终收口代码，不回移旧 #69 全分支 |
| Safari | Apple 明确支持 JS from Apple Events；Navigation API 于 26.2 加入（B1/B15） | 实际 sdef、tab locator、执行世界、File输入/事件、真实原草稿证据 | 必须实施；先做 S0–S3；初始能力门槛 Safari 26.2+ |
| Brave | 官方品牌配置给出 `com.brave.Browser`；Chromium 公开自动化模型（B3/B5） | 实际二进制 sdef、签名接收方、执行世界、默认 Shields、多 profile | 第四核心目标，按受控和线上门槛实证 |
| Firefox | 官方源码有 `NSAppleScriptEnabled`；已连接 geckodriver 要先启用 Marionette（B6–B9） | 未建立普通会话的等价网页 JS 路径；AX 能否证明原稿/原附件 | 有边界同轮原型，全部不变量通过后才扩大矩阵 |

## 2. Safari 的两个架构约束

### 2.1 不能用 WebDriver 替代原窗口

Apple 官方说明 Safari WebDriver 的 Automation 窗口与普通浏览窗口、用户数据隔离（B2）。它可用于受控测试，不满足“向已登录原草稿附加”的生产目标。Playwright WebKit 也是修改版 WebKit，不能用它的通过代替实际 Safari（B14）。

### 2.2 必须校验 Navigation API 与执行世界

已审 #119 的 JS `pinTarget` 直接要求 `navigation.currentEntry`，并用 `currententrychange`、pagehide、blur、visibilitychange 等失效原 pin。Apple/WebKit 明确在 **Safari 26.2** 加入 Navigation API；26.2 的官方 macOS 列表含 26.2、Sequoia、Sonoma，不含 Ventura（B15/B16）。

所以本周期优先实现 Safari 26.2+，同时运行时检查所需 API 和事件语义。**Riftlet App 最低 macOS 13 与 Safari 附件支持范围分开标示**。不是要求所有用户升级系统，也不是把未测试的未来 Safari 全部声明通过。

旧 Safari 的 `history/document epoch` 可做一个同周期附加原型：必须证明 pushState、replaceState、popstate、hashchange、同 URL 新草稿、reload、BFCache、document replacement、原 operation 观察都不错误接续。仅 patch history 或轮询 URL 不够；不得删掉 pin 校验或伪造 navigation ID。失败则如实限定 Safari 版本，继续其他工作包。

Chromium 当前第一方源码的 AppleScript 执行使用 `ExecuteJavaScriptInIsolatedWorld`（B17）。保留现有 Chrome MAIN-world relay 与 Edge witness；Brave 不能仅替换应用名称。Safari 文档没有在本次检索中给出足够的 realm 契约，仍标 **UNVERIFIED**。需要实际 page sentinel、跨调用状态、File 字节与事件处理关联探测；不能用 WKWebView 文档推断 Safari AE。

## 3. Safari S0–S3：由实现者自动完成

用安装的正式 Safari 二进制和普通签名 Riftlet App，记录 macOS/Safari 版本、app build/hash、CPU 架构及默认/私密窗口范围。测试脚本只用于布置和独立观察，真正输入必须走产品路径。

### S0：签名 App 权限

- 检查 `NSAppleEventsUsageDescription` 与实际 Hardened Runtime Apple Events entitlement；由 Riftlet 请求控制 Safari，而非用 Terminal 已获权限冒充（B10/B11）。
- 区分 Automation 同意与 Safari JS 开关，测试拒绝、开关关闭、撤销、恢复、浏览器升级后能力重查。
- 只要求官方 JS-from-Apple-Events 开关；不关闭跨域/本地文件限制，不启用 Remote Automation，不替用户修改安全设置。
- 权限失败保留截图，焦点改变不自动重放；完成连接后新的正常点击只有一次。

### S1：原生身份与页面只读绑定

- 从安装的 Safari `sdef` 读取真实命令和定位形式；不可假设拥有 Chromium 数字 tab ID。
- 固定 bundle/PID/processBirth、窗口、tab locator、origin 和轻量 document/composer witness。若 tab 仅有索引，索引只作定位提示；被寻址页面必须先匹配已存在 nonce 才能接触 input。
- 标签重排/移动、另开同 URL、切 profile、窗口关闭、浏览器重启、同 URL 重载、A→B→A、SPA 新草稿、BFCache 均不能改投。
- 只能用原 nonce/draft 证明找到原页面。找不到即身份失效，不能用标题或 URL 唯一匹配来补授权。初次冷启动与暖状态均要覆盖。
- 执行世界探针须证明跨 AE 调用的状态和页面处理器关联。异步 Promise 回执采用原 invocation 的轮询读取，不重新执行原命令。

### S2：真实 Safari + 受控网页

- 使用普通 Safari 窗口载入合成无敏感 fixture，触发 Riftlet 实际托盘及 Apple Events 通道；禁止用 `setInputFiles` 或 WebDriver 文件命令代替产品上传。
- 由 native 读原图，页面构造 File/DataTransfer、一次 FileList setter 和经认证事件配方。HTML 允许 FileList setter，不允许把任意本地路径塞入 file input 的 value（B12）。
- 覆盖小图、常用 1080p/4K、Retina、alpha/16-bit/色彩配置、接近站点限制的大图；分别核对原件与 payload 的长度/hash、传输时延和内存。不能猜 AE 的可靠 payload 上限。
- 保留 per-operation chunk 顺序、大小和身份校验。staging 不触发 input；超时后不偷偷换整包/分块策略再 commit。
- 合成 JS 事件的 `isTrusted` 为 false（B13）；网站可能拒绝它。不能伪造 trusted，也不能由事件 dispatch 返回成功推断站点已接收。
- 注入重复命令、回执丢失、intent 后 app 崩溃、浏览器卡顿、两张图 <2秒连续点击；验证一次输入、原图关联、原文选区旧附件保留及零发送。

### S3：真实登录 AI 原草稿

- 先 ChatGPT 和一个不同核心 Provider，再完成 Safari 四平台整行。
- 冷/暖首图、3组快速双图、原文+非空选区+旧附件；支持时分别验证新/临时及普通保存会话；不发送消息。
- 接受结果由独立观察核验原稿各图各一次，不只相信产品自己的回执。
- 同卡后续失败在 S2 强制注入验证；线上确实观察到才记线上失败覆盖。无法自然制造某错误不伪造，也不无限等待。

**Safari 放行：S0–S3 均有实际证据、正确目标和关键反例通过。** S2 成功而某站 S3 失败只阻塞对应格；Host 自身原稿绑定无法证明则阻塞 Safari 行。其他 Host/Provider 继续。

## 4. Brave 原型

检查实际安装的 `scripting.sdef`、代码签名、bundle ID、执行命令、JS 开关和接收方。默认 Shields 开启完成受控和真实四平台；不得通过全局关闭 Shields 偷换运行条件。正常与私密、多 profile/窗口、标签移动、Chrome/Edge/Brave 同时运行、权限恢复纳入统一用例。

复用 Chromium Host 工具和当前执行世界策略，Provider 仍是同一份。若受默认保护影响，只能精确标记失败原因、修复适配或不支持该格，不能成为要求用户配置大量技术开关的隐性条件。

## 5. Firefox 有边界预研

不能写“Firefox 完全不支持 AppleScript”：当前第一方 macOS plist 开启 NSAppleScriptEnabled（B6）。但未建立用户普通会话的网页 JS 入口；基本 app/open-URL 事件不等于可执行网页程序。官方 geckodriver 的 `--connect-existing` 要求目标已启用 Marionette，Mozilla MCP 也说明给运行中的普通 profile 再加启动参数不能无感启用协议（B8/B9）。因此默认 WebDriver/BiDi/调试端口路线不符合本轮体验。

W6 首轮验证预算为 **一个工程工作日**，用于限制低概率路径的机会成本，不是交付时长承诺；若已获得明确有价值的正面进展，由集成人延长一次并记录理由。步骤：

1. 检查当前正式 Firefox 二进制和官方脚本接口；记录实际能力，不能只靠历史 bug 判否。
2. 在受控普通窗口试 AX + 原生文件选择器：必须从被绑定原 composer 的上传按钮进入，确认对话框属于原进程/窗口，路径只能输入该文件对话框。
3. 不用全局坐标/盲按快捷键，不粘贴到未知编辑器。保留原文、选区和已有附件；对焦点变化、用户取消、双窗口、重启、标签无 AX 名称做阴性对照。
4. **仅“选中文件并出现一个卡片”不足**；必须证明本图、本 operation、原稿、一次输入及后续错误归属。AX count/name 无法证明这些即技术未通过。
5. 全部通过受控与签名 App 后，再验真实四平台；通过才增加 Firefox 四格。不能先开正式支持后补证据。

技术失败记 `BLOCKED_TECHNICAL` 并附最小复现、缺失原语、尝试结果和违反的不变量；环境/账号缺口用 `BLOCKED_ENV`。保留截图/历史并提示 Firefox 暂不支持直接附加，用户可自行在支持的浏览器继续；不自动迁移对话。未来扩展或显式调试模式属于改变需求的另一个方案，本轮不暗中启用。

## 6. 第一方来源

检索/核对日期 2026-11-20；当前二进制必须再验，文档不是产品 PASS。

- B1 [Apple Safari Developer settings](https://developer.apple.com/documentation/safari-developer-tools/developer-settings)
- B2 [Apple Safari WebDriver](https://developer.apple.com/documentation/safari-developer-tools/webdriver/)；[WebKit 关于隔离 Automation windows](https://webkit.org/blog/6900/webdriver-support-in-safari-10/)
- B3 [Chromium scripting.sdef](https://chromium.googlesource.com/chromium/src.git/+/lkgr/chrome/browser/ui/cocoa/applescript/scripting.sdef)，本次检索 blob `405776f0fc96b8335dbf02fb0a7142547e242f57`
- B4 [Chromium AppleScript](https://www.chromium.org/developers/applescript/)
- B5 [Brave 官方 BRANDING](https://github.com/brave/brave-core/blob/master/app/theme/brave/BRANDING)
- B6 [Firefox macOS Info.plist](https://searchfox.org/firefox-main/source/browser/app/macbuild/Contents/Info.plist.in)
- B7 [Mozilla MacApplicationDelegate](https://searchfox.org/firefox-main/source/toolkit/xre/MacApplicationDelegate.mm)；[历史 bug 287447](https://bugzilla.mozilla.org/show_bug.cgi?id=287447)
- B8 [geckodriver connect-existing](https://firefox-source-docs.mozilla.org/testing/geckodriver/Flags.html#connect-existing)
- B9 [Mozilla Remote Agent security](https://firefox-source-docs.mozilla.org/remote/Security.html)；[Mozilla Firefox DevTools MCP](https://github.com/mozilla/firefox-devtools-mcp)
- B10 [NSAppleEventsUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription)
- B11 [Apple security entitlements](https://developer.apple.com/documentation/bundleresources/security-entitlements)
- B12 [WHATWG input.files](https://html.spec.whatwg.org/multipage/input.html#dom-input-files)；[WebKit DataTransfer constructor record](https://bugs.webkit.org/show_bug.cgi?id=215837)
- B13 [WHATWG Event.isTrusted](https://dom.spec.whatwg.org/#dom-event-istrusted)
- B14 [Playwright browser boundaries](https://playwright.dev/docs/browsers#webkit)
- B15 [Apple Safari 26.2 release notes](https://developer.apple.com/documentation/safari-release-notes/safari-26_2-release-notes)；[WebKit Safari 26.2 announcement](https://webkit.org/blog/17640/webkit-features-for-safari-26-2/)
- B16 [Apple Safari 18.6 release notes](https://developer.apple.com/documentation/safari-release-notes/safari-18_6-release-notes)
- B17 [Chromium tab_applescript.mm](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/chrome/browser/ui/cocoa/applescript/tab_applescript.mm)
