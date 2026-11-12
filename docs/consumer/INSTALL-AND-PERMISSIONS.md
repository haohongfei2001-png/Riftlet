# 安装与权限

适用于 Riftlet 0.3.5 (19)，macOS 13 及以上的 Apple 芯片和 Intel Mac。正式候选为 `Riftlet-0.3.5-19-universal.dmg`，SHA-256 为 `e9c725a09413ccdde4c30c1d27e26a7921be5d83dbb4a83638bb95790e16fe8e`。App 和 DMG 均已通过 Apple 公证及 Gatekeeper；Developer ID Team 为 `ZB9D4T66QB`。

如果手中是 build 18，请保留原有个人安装。该版本在共享「应用程序」目录中只允许安装者读取和执行，其他非特权账户可能打不开。遇到此情况，请保留现状并联系发放方取得经验证的修复包；无需更改系统授权、App 文件权限或截图库。

1. 打开 DMG，将 **Riftlet.app** 拖入 **Applications（应用程序）**。已有 Riftlet 时先按[更新说明](RECOVERY-AND-FAQ.md)保留数据和上一版，替换原安装位置的 App。
2. 推出磁盘映像，从安装位置打开 Riftlet。首次出现 macOS 下载应用确认时核对应用名，选择「打开」。如果系统提示已损坏或无法验证开发者，停止安装，通过发放渠道核对文件。
3. 跟随「开始使用 Riftlet」三步引导。之后可单击菜单栏 Riftlet 图标打开控制中心，或在「设置 → 权限与帮助 → 查看引导…」重新查看。

## 按实际使用的功能授权

| 想用的功能 | 去哪里操作 | 怎样确认 |
| --- | --- | --- |
| 收录 macOS 截图 | 按 ⇧⌘5，在「选项」核对保存文件夹。在 Riftlet「设置 → 截图」查看「截图保存位置」。若被拒绝，点「允许访问此位置…」，选中同一文件夹。也可在系统设置「隐私与安全性 → 文件与文件夹」检查 Riftlet。 | 新截一张保存为文件的图，看看桌面微图或「截图历史」中是否出现。原图仍在系统截图目录。「权限与帮助 → 重新检查」可更新状态。 |
| 点微图附加到 ChatGPT | 把目标 Google Chrome 草稿带到前台。在「设置 → 权限与帮助」中的 Chrome 权限项点「查看」，再点「检查 Chrome 权限…」，在系统提示中允许 Riftlet 控制 Google Chrome。已拒绝时，在「隐私与安全性 → 自动化 → Riftlet」开启 Google Chrome。在 Chrome 菜单栏「显示 → 开发者」勾选「允许 Apple 事件中的 JavaScript」（Allow JavaScript from Apple Events）。 | 回到可编辑的目标草稿；以其中实际出现本张图片为准。Chrome 未运行或在后台时，「暂不可用」本身不能判定先前的授权已丢失。 |
| 使用 Riftlet 内置截图 | 在「设置 → 截图」开启「显示截图入口」。首次使用窗口、区域或全屏截图时，按系统提示为 Riftlet 允许「屏幕录制」或「屏幕与系统音频录制」。若系统要求，正常退出后重新打开。 | 从桌面入口截一张，再到历史查看。只使用 macOS 截图并让 Riftlet 收录文件时，无需授予这项录屏权限。 |
| 登录时启动 | 在「设置 → 使用与历史」开启「登录时启动 Riftlet」。若提示「待批准」，点「打开登录项设置…」，在系统设置的「通用 → 登录项」或「登录项与扩展」内确认。 | 重新查看登录项状态；日常也可从应用程序手动打开。 |

日常使用以上功能无需授予「完全磁盘访问权限」或「辅助功能」。从历史 ad-hoc 个人版首次切换为 Developer ID 版本时，macOS 可能再次请求目录或自动化授权。按上表逐项验证实际功能，保留原有截图和历史。私测采用手动更新。

macOS 设置名称随系统版本变化。系统权限可参考 [Apple 文件与文件夹说明](https://support.apple.com/en-au/guide/mac-help/mchld5a35146/mac) 和 [Apple 录屏权限说明](https://support.apple.com/en-kw/guide/mac-help/mchld6aa7d23/mac)。Chrome 的开关位置可参考 [Chromium 的 AppleScript 说明](https://www.chromium.org/developers/applescript/)。

**English.** Build 19 is the planned private candidate. Once issued, verify its DMG against the included `SHA256SUMS.txt` and the maintainer’s separately supplied digest. Build 18 has a shared-install file-permission defect. Existing personal users can keep their copy. Open the verified DMG, drag Riftlet.app into Applications, eject the image and launch the installed copy. Grant access to the actual macOS screenshot folder. Google Chrome attachment also uses Automation and Chrome’s **Allow JavaScript from Apple Events** setting. Screen Recording is for Riftlet’s own capture tools. [English quick start](QUICK-START.en.md)
