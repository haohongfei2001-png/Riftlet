# 安装与权限

Riftlet 1.0.1 的安装包名为 `Riftlet-1.0.1.dmg`，支持 macOS 13 及以上的 Apple 芯片和 Intel Mac。请从 [riftlet.com](https://riftlet.com/) 下载磁盘映像。如需校验，请在[对应版本的发行记录](https://github.com/haohongfei2001-png/Riftlet/releases)查看文件名和 SHA-256。开发者团队 ID 为 `ZB9D4T66QB`。

1. 打开下载的 DMG，将 **Riftlet.app** 拖入 **Applications（应用程序）**。如果无法写入共享的「应用程序」，可以在 Finder 的个人主文件夹中创建 `Applications` 文件夹，将 App 拖入那里。如果原来安装的是 1.0.0，请先正常退出、备份截图库，再用新版 App 覆盖原安装位置一次。1.0.1 起可在 App 菜单栏或设置中使用「检查更新…」安装后续版本。[更新与恢复](RECOVERY-AND-FAQ.md)
2. 推出磁盘映像，从安装位置打开 Riftlet。macOS 首次询问是否打开下载的应用时，核对应用名并点「打开」。若系统提示已损坏或无法验证开发者，请停止安装并核对下载来源。
3. 在引导中依次设置截图文件夹、连接 Chrome，并选择缩略图在桌面出现的位置。以后可以从「设置 → 权限与帮助」重新打开引导。

| 想用的功能 | 设置方法 | 检查结果 |
| --- | --- | --- |
| 收录 macOS 截图 | 引导会显示 Mac 的截图保存位置。需要访问权限时选择同一个文件夹。若想核对系统设置，打开 macOS「截屏」App，在「选项」查看保存位置。 | 新截一张图片并存为文件，桌面边缘和截图历史中应出现这张图。仅复制到剪贴板的截图没有生成文件。 |
| 点截图附加到 ChatGPT | 打开 Chrome。在 Riftlet 的引导中检查 Chrome 权限，允许 macOS 的自动化请求。然后在 Chrome 菜单栏「显示 → 开发者」勾选「允许 Apple 事件中的 JavaScript」，回到引导检查连接。 | 在 Chrome 前台准备一个可编辑的 ChatGPT 草稿，点一次缩略图。图片应出现在当前草稿的附件区。 |
| 用 Riftlet 自带的截图按钮 | 在「设置 → 截图」开启桌面截图入口。首次使用时，根据 macOS 提示授予「屏幕录制」或「屏幕与系统音频录制」权限。系统要求重启时，退出再打开 Riftlet。 | 从桌面截图入口截取一个窗口、区域或全屏，在「截图历史」中查看。用 macOS 自带的「截屏」保存文件时无需向 Riftlet 授予录屏权限。 |
| 登录时启动 | 在「设置 → 使用与历史」开启登录项。若显示待批准，打开系统设置的「通用 → 登录项」或「登录项与扩展」确认。 | 在设置中查看登录项是否已启用。 |

**曾拒绝权限时。** 截图文件夹可从引导或「设置 → 截图」重新选择。若 macOS 拒绝了 Chrome 自动化请求，可前往「系统设置 → 隐私与安全性 → 自动化」，在 Riftlet 下开启 Google Chrome，再回引导检查连接。Chrome 的 JavaScript 开关对所有获准控制 Chrome 的应用生效，可随时关闭。本地截图收录和历史仍然可用。正式签名版本替换早期个人开发版本时，macOS 可能会再次请求权限。

**English.** Download the disk image from [riftlet.com](https://riftlet.com/). Open it, drag Riftlet.app into Applications (or the Applications folder in your home directory if you cannot write to the shared one), eject the disk image and open the installed app. If upgrading from 1.0.0, quit the old App, back up your library and replace the App in its original location once. From 1.0.1 onward, choose Check for Updates inside Riftlet for later releases. Follow setup to allow access to your screenshot folder, connect Google Chrome and choose a thumbnail position. For Chrome, allow the macOS Automation request and enable **View → Developer → Allow JavaScript from Apple Events**. Screen Recording is needed only for Riftlet’s built-in capture. [English quick start](QUICK-START.en.md)

[Apple 文件与文件夹权限](https://support.apple.com/en-au/guide/mac-help/mchld5a35146/mac) · [Apple 屏幕录制权限](https://support.apple.com/en-kw/guide/mac-help/mchld6aa7d23/mac) · [Chromium AppleScript 说明](https://www.chromium.org/developers/applescript/)

隐私请求可发至 [privacy@riftlet.com](mailto:privacy@riftlet.com)。[隐私政策 / Privacy policy](PRIVACY.md)
