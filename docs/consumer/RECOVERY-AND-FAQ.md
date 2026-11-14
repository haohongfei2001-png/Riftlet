# 找回图片、排除故障与更新

**非管理员账户如何安装？** 在 Finder 中打开个人主文件夹，把磁盘映像中的 Riftlet.app 拖入自己的 `Applications` 文件夹。从这个位置打开 App 并完成引导。同一台 Mac 上的每个账户各自授权截图文件夹与 Chrome。[安装与权限](INSTALL-AND-PERMISSIONS.md)

**没看到新微图。** 单击菜单栏 Riftlet 图标，查看是否「暂停收录」或「隐藏桌面截图」。前者停止收录，后者只改变桌面显示。打开「截图历史」看是否已经归档，再到「设置 → 截图 → 在 Finder 中打开」确认系统截图已写入文件夹。剪贴板截图、仍在浮动预览中的截图，以及首次打开之前的旧文件都可能不会进入队列。若目录不可读，在「截图」页允许访问当前系统截图文件夹，然后在同页点「重新检查」。恢复收录时，暂停期间保存并仍在目录里的合格截图可能被补收。[安装与权限](INSTALL-AND-PERMISSIONS.md)

**找回原图或已归档的微图。** 从菜单栏打开「截图历史」，在当前页按时间或记录编号搜索；更早的记录可翻页。列表和图像网格显示同一段历史。选中记录后，「查看原图」或「在 Finder 中显示」可查看 Riftlet 保存的本地副本；macOS 保存的原文件在「设置 → 截图 → 在 Finder 中打开」。可恢复的已归档或已移出图片会显示可用的「恢复到桌面」，恢复微图本身不会上传。闲置后自动归档仅影响可见队列，默认 2 分钟，可设 1–10 分钟或关闭。

**点过图片，草稿里没有。** 先查看刚才那个聊天的附件区，再看「截图历史」。若提示未附加，请按提示检查权限并打开可编辑的草稿。缩略图收起表示网页已开始接收，上传进度请看草稿。若显示「结果待核实」，Riftlet 会保留记录。请先确认原聊天中是否已有这张图，以免重复添加。若发现错图、重复或文字变化，可私下反馈发生时间及现象。[反馈说明](FEEDBACK-TEMPLATE.md)

**设置显示保存失败。** 暂停收录、隐藏桌面截图、关闭内置截图入口可以先停止当前行为，再保存。使用出错项目旁的重试维持该次选择，能否在重启后保留应看该项的保存结果。

**存储不足或本地副本不可读。** 在设置中点「检查用量」可查看本地库占用的空间。数据目录可从设置中的 Finder 按钮打开。[各版本的入口](README.md#设置入口)

归档、移出和收起微图不删除原图或私有副本。保留记录，先在其他安全位置腾出空间；不要拆开数据库、媒体和收录日志。若应用打开失败，保留当前完整目录与准确提示，并按[反馈说明](FEEDBACK-TEMPLATE.md)联系维护者。

## 更新、回退与卸载

1. **Riftlet 1.0.1 起支持应用内检查更新。** 在 App 菜单栏或设置中选择「检查更新…」，按照确认提示安装后续正式版。**从 1.0.0 或更早版本升级到 1.0.1，仍需先手动覆盖安装一次。** 采用手动更新时，保留现有 App 和经验证的旧安装包，从 [Riftlet 版本页面](https://github.com/haohongfei2001-png/Riftlet/releases)取得新版本，再从菜单栏右键选「退出 Riftlet」。在 Finder「前往文件夹」输入 `~/Library/Application Support/Riftlet/`，退出后备份整个文件夹，其中包括队列数据库及其附属文件、图片、副本、收录记录、配置及反馈。单独保留系统截图原件；维护者还需核对应用偏好、钥匙串与系统权限，这些不会被普通文件夹完整备份。
2. 核对新 DMG 的版本、来源和校验值，再仅替换原安装位置的 Riftlet.app。启动后检查已有历史、设置、目录访问以及一张新截图。旧版关闭了自动归档或使用 1–10 分钟时限时，升级会保留该选择；其他旧正时限回到 2 分钟。
3. 如果更新失败，正常退出，保存**最新**的完整数据、旧包和新包。请维护者先验证旧 App 确实兼容当前数据，再作 App 回退。部分早期版本无法读取现在的截图库，遇到这种情况应使用与当前截图库兼容的新版恢复。不得用升级前的数据库覆盖新历史。
4. 要卸载，可先在设置中关闭「登录时启动 Riftlet」，正常退出，再把 App 移到废纸篓。原始截图、本地数据目录、偏好、反馈凭证和备份保留。已发送反馈如需撤回，先在反馈窗口申请删除并查看结果；卸载本身不会撤回反馈。

**English.** Check History before retrying an uncertain attachment. Riftlet 1.0.1 supports Check for Updates in the app for subsequent stable releases. Upgrading from 1.0.0 to 1.0.1 still requires one manual App replacement: quit Riftlet, keep the old app and a verified backup of the complete current library, check the new package and replace only the app in its existing location. For recovery, keep the **latest** library intact. Some older releases cannot read the current library format. Uninstalling the app leaves the library, preferences, originals, backups and feedback credentials in place.
