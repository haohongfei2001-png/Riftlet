# 安装与权限 / Installation and permissions

## 安装前 / Before installing

当前个人 Beta 3 是 ad-hoc 签名包，尚未完成 Developer ID、公证及面向陌生用户的 Gatekeeper 安装验收。本资料不是公开下载通行证。Apple 用 Developer ID 和公证帮助验证分发来源及检查恶意软件；公证也不是 App Review。见 [Developer ID](https://developer.apple.com/developer-id/) 和[公证说明](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。

拿到获准测试包后，按该次交付清单确认版本、架构、SHA-256、签名状态和来源；文件名或散列本身不能证明来源可信。退出旧版，再按交付说明把 App 放在指定的 Applications 位置。不要同时运行指向同一数据目录的两个版本。升级已有数据前先按[更新与回退](RECOVERY-AND-FAQ.md)完成备份。

标有 `REVIEW-NOT-NOTARIZED` 或 `REVIEW_ONLY` 的 ZIP/DMG 是私有评审材料。包内文件与候选清单匹配，只说明内容身份已核验，不代表安装、公证、Gatekeeper 或数据兼容性已通过。即使版本号和“Beta 3”标签相同，也应核对该次交付清单；这些标签不能替代精确包身份。

如果 macOS 阻止打开，保留系统提示并联系包的提供者，不要关闭 Gatekeeper、移除 quarantine 或重置整套隐私权限。Apple 的[安全打开 App 说明](https://support.apple.com/en-nz/102445)解释了不同提示；尚未验证的测试包不能用终端绕过步骤包装成“下载即用”。

**English:** Verify the approved delivery manifest, architecture, hash and signing status. Quit the old App and preserve its data before updating. A hash alone does not establish trust. A `REVIEW-NOT-NOTARIZED` ZIP/DMG is private review material; matching contents or version labels do not prove installation, Gatekeeper or data compatibility. If macOS blocks the App, report the exact alert to the maintainer; do not disable Gatekeeper or strip quarantine. The current personal package is not a notarized public installer.

## 只为正在使用的功能授权

| 功能 | 为什么需要 | 在哪里处理 | 拒绝或关闭后 |
| --- | --- | --- | --- |
| 收录系统截图文件 | 读取实际截图保存目录中的新截图，建立本地副本 | Riftlet「设置 → 权限与帮助 → 允许访问此位置…」；必要时系统「隐私与安全性 → 文件与文件夹」 | 该目录不可读取时不收录；原文件不删除 |
| 把图片交给 Chrome 的 ChatGPT | Apple Events 向选定 Chrome 进程请求页面连接 | 先正常打开 Chrome，再点「检查 Chrome 权限…」；系统「隐私与安全性 → 自动化 → Riftlet → Google Chrome」 | 不执行该浏览器附加；已有本地图片保留 |
| Chrome 页面 JavaScript | 找到当前草稿和附件入口，交给网页文件控件 | Chrome 菜单 **View / 视图（或显示）→ Developer / 开发者 → Allow JavaScript from Apple Events / 允许来自 Apple 事件的 JavaScript** | 仅给 macOS 自动化授权仍不足以连接页面 |
| Riftlet 内置截图 | 按你发起的窗口、区域或全屏截图请求读取屏幕 | 首次使用内置截图时按系统提示；系统「隐私与安全性 → 屏幕录制」或「屏幕与系统音频录制」 | 内置截图不可用；不因此阻止系统截图文件收录 |
| 登录后启动 | 可选的 macOS 登录项 | 「设置 → 通用 → 登录后启动 Riftlet」；如待批准，使用「打开登录项设置…」 | 可继续手动打开 App |

系统分类名称随 macOS 版本变化。文件访问和自动化是不同权限，屏幕录制也不授权 Chrome。Apple 分别说明了[文件与文件夹](https://support.apple.com/en-au/guide/mac-help/mchld5a35146/mac)、[自动化](https://support.apple.com/en-ie/guide/mac-help/mchl07817563/27/mac/27)和[屏幕录制](https://support.apple.com/en-kw/guide/mac-help/mchld6aa7d23/mac)设置。Chrome 的菜单位置来自 [Chromium 官方说明](https://www.chromium.org/developers/applescript/)。Riftlet 不代改 Chrome 的该选项。

当前普通收录和附件路径不要求先授予完全磁盘访问、麦克风、摄像头或全局键盘记录权限。现有辅助功能授权可用于 Chrome 活动变化提示，但它不是首次附加的强制前置；本指南不会要求为此开启所有系统权限。内置截图使用静态屏幕捕获，不录制系统音频。

## 恢复授权与登录项

新候选会在选择窗口中显示 macOS 当前的截图目录。找不到这个位置时，按 ⇧⌘5，在「选项」里查看截图存储位置。选错目录时可以留在窗口重新选；点「取消」会保留原有设置。若选择期间改变了系统截图位置，回到 Riftlet 点「重新检查」，再打开选择窗口。选择目录不等于授予 Chrome 自动化；已能读取该目录的 Mac 也可能完全不弹系统授权框。

修正对应权限后，回到 Riftlet 使用「重新检查」，再用一张新、不敏感的截图确认当前功能。若系统要求重启 App，先保存设置和反馈草稿，正常退出再打开。不要清除历史或 UNKNOWN 来恢复权限。

“已请求登录启动、等待系统批准”不等于已经启用；“macOS 暂未找到此应用的登录项”也不能解释成成功。当前代码回读系统状态，不保存一个虚假的已启用值。登录启动的实际系统兼容性正在本轮专项验证；没有成功回读和真实登录启动证据时，以手动启动为可用方式。不要自行添加 LaunchAgent 替代它。

**English navigation:** Settings → `权限与帮助` contains the folder, Chrome and screen-recording actions. `检查 Chrome 权限…` checks or requests Automation; the Chrome menu setting is separate. `重新检查` refreshes status after a change. `登录后启动 Riftlet` is optional; pending approval is not enabled, and “not found” is not success. Follow the operating system’s prompt, preserving local records.

**If the folder or Chrome is unavailable:** In the candidate, choose the exact path shown in the folder picker. Press Shift–Command–5 → Options to find where macOS saves screenshots. Choosing another folder will be declined; Cancel keeps the previous choice. A Mac that can already read the folder may show no permission prompt. For a denied Chrome request, open System Settings → Privacy & Security → Automation → Riftlet → Google Chrome. In Chrome, check View → Developer → Allow JavaScript from Apple Events separately, then choose `重新检查` in Riftlet. If there is no editable chat, bring your intended ChatGPT draft to the front in Chrome. The screenshot stays on your Mac.

## 私人维护包升级后又显示“无法访问截图位置”

同一个 App 名称、同一个安装位置，并不保证新版继承旧版对“下载”等目录的授权。未经 Developer ID 签名的个人构建尤其如此。不要反复重装或删除历史。保留旧 App 与最新数据备份，从“截图与收录”查看当前来源，在系统提供正常授权的条件下使用“重新检查”。如果无人值守升级后仍不能访问来源，应恢复可工作的旧 App，保留最新数据库和截图。无需关闭 Gatekeeper、重置隐私授权或授予完全磁盘访问权限。
