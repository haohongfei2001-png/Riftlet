# 安装与权限

Riftlet 1.0.10 的安装包名为 `Riftlet-1.0.10.dmg`，支持 macOS 13 及以上的 Apple 芯片和 Intel Mac。从 [riftlet.com](https://riftlet.com/) 下载 DMG 文件。如需校验，可在[版本说明](https://github.com/haohongfei2001-png/Riftlet/releases/tag/v1.0.10)查看 SHA-256。开发者团队 ID 为 `ZB9D4T66QB`。

1. 双击下载的磁盘映像，将 **Riftlet.app** 拖入 **Applications（应用程序）**。如果无法写入共享的「应用程序」，可以在 Finder 的个人主文件夹中创建 `Applications` 文件夹，将 App 拖入那里。升级时先退出旧版、备份截图库，再替换原安装位置的 App。[更新与恢复](RECOVERY-AND-FAQ.md)
2. 从安装位置打开 Riftlet。macOS 首次询问是否打开下载的应用时，核对应用名并点「打开」。若系统提示已损坏或无法验证开发者，请停止安装并核对下载来源。
3. 在快速入门中确认系统截图目录，然后去试一张截图。第一次附加时再连接当前浏览器；以后可在「设置 → 帮助」重看快速入门。[设置入口](README.md#设置入口)

| 想用的功能 | 设置方法 | 检查结果 |
| --- | --- | --- |
| 收录 macOS 截图 | 引导会显示 Mac 的截图保存位置。需要访问权限时选择同一个文件夹。若想核对系统设置，打开 macOS「截屏」App，在「选项」查看保存位置。 | 新截一张图片并存为文件，桌面边缘和截图历史中应出现这张图。仅复制到剪贴板的截图没有生成文件。 |
| 点截图附加到 ChatGPT | 在普通 Google Chrome 或 Microsoft Edge 中将要用的 ChatGPT 草稿置于前台。在快速入门或「设置 → 附加」按当前浏览器的提示授权。在该浏览器菜单栏中开启「允许 Apple 事件中的 JavaScript」，然后回到原草稿，在托盘上向上滑动并点选刚才的截图。Chrome 的开关位于「显示 → 开发者」。 | 在该浏览器前台准备一个可编辑的 ChatGPT 草稿，点一次缩略图。图片应出现在当前草稿的附件区。 |
| 用 Riftlet 自带的截图按钮 | 在「设置 → 截图」开启桌面截图入口。首次使用时，根据 macOS 提示授予「屏幕录制」或「屏幕与系统音频录制」权限。系统要求重启时，退出再打开 Riftlet。 | 从桌面截图入口截取一个窗口、区域或全屏，在「截图仓库」中查看。用 macOS 自带的「截屏」保存文件时无需向 Riftlet 授予录屏权限。 |
| 登录时启动 | 在设置中开启「登录时启动 Riftlet」。若显示待批准，打开系统设置的「通用 → 登录项」或「登录项与扩展」确认。 | 在设置中查看登录项是否已启用。 |

**曾拒绝权限时。** 截图文件夹可从引导或「设置 → 截图」重新选择。若 macOS 拒绝了浏览器自动化请求，可前往「系统设置 → 隐私与安全性 → 自动化」，在 Riftlet 下开启所用浏览器，再回「设置 → 附加」检查连接。该 JavaScript 开关对所有获准控制该浏览器的应用生效，可随时关闭。本地截图收录和历史仍然可用。正式签名版本替换早期个人开发版本时，macOS 可能会再次请求权限。

**English.** Open the disk image from the official website and drag Riftlet into Applications. You can also use the Applications folder in your home directory. For a manual upgrade, quit Riftlet, back up your library and replace the copy in its original location. Quick Start shows your Mac’s screenshot folder. If access is needed, select that folder, then try a screenshot. To attach it to ChatGPT in Google Chrome or Microsoft Edge, follow the prompt for that browser and enable **Allow JavaScript from Apple Events** in its Developer menu. Screen Recording is needed only for Riftlet’s built-in capture. [English quick start](QUICK-START.en.md)

[Apple 文件与文件夹权限](https://support.apple.com/en-au/guide/mac-help/mchld5a35146/mac) · [Apple 屏幕录制权限](https://support.apple.com/en-kw/guide/mac-help/mchld6aa7d23/mac) · [Chromium AppleScript 说明](https://www.chromium.org/developers/applescript/)

隐私请求可发至 [privacy@riftlet.com](mailto:privacy@riftlet.com)。[隐私政策 / Privacy policy](PRIVACY.md)
