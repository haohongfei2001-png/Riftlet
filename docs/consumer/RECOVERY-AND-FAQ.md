# 找回图片、更新与卸载 / Recovery and FAQ

## 微图不见了，图片去哪里了？

从菜单栏点「截图历史」，或进入「设置 → 使用与历史 → 打开历史…」。可以按时间或记录编号搜索当前页，切换列表与图像网格。两者使用同一历史；开关视图不会重新附加图片。

| 看到的情况 | 含义与下一步 |
| --- | --- |
| 微图已收起 / Swallowed | 草稿曾开始接收，或存在其他明确记录；不要据此断言最终上传完成。到原 ChatGPT 草稿看实际附件 |
| Needs review / 结果待核实 | Riftlet 没有足够结果证明。保留记录和原图，先检查原聊天；不会自动再次附加 |
| Not attached / 本次未附加 | 有明确未输入或取消的记录；按原因修正目标、权限等，再进行新的点击 |
| Archived / Removed from rift | 离开边缘显示，仍在本地历史。若「恢复到桌面」可用，可恢复为正常微图；恢复本身不上传 |
| Private copy unavailable / 本地副本不可用 | 记录尚在，但文件暂不可读。查看系统原图或已验证备份；不要删除数据库来消掉提示 |

「明确失败」筛选只显示已确认的上传失败，不包含全部取消、未输入和不确定结果；找不到时用「全部截图」或「待核实」。恢复资格由记录状态决定：**UNKNOWN 或已经交给网页的图片不能通过恢复按钮获得自动重传资格。** 查看原图不会重试。

## 草稿开始接收之后失败了怎么办？

普通路径在 START 后停止跟踪该次上传，不保证发现随后所有网络错误，也不承诺因此自动把图片弹回。先查看原聊天的附件错误或完成状态；本地历史和原系统截图仍可找回。报告[问题线索](FEEDBACK-TEMPLATE.md)时写清“微图收起前/后”和“ChatGPT 中看到了什么”，不要把看不到进度直接当成失败。结果不确定时，不用重新导入、重启或清库强制再次附加。

## 为什么没有新微图？

依次查看：截图是否已保存为文件；是否仍在系统浮动预览中；「暂停收录」是否开启；「隐藏桌面截图」是否开启；设置显示的截图目录是否可读；磁盘是否不足。仅剪贴板截图和初次安装前的旧文件不会自动补进来。修正权限后使用「重新检查」。不要为了重新导入而批量改名、移动原图或重置历史。

## 隐藏、暂停和清空会释放空间吗？

不会。暂停期间停止收录。恢复后，仍在截图目录中的合格文件可能被补收，包括暂停期间保存的文件。因此，暂停不能用来永久排除某张截图。隐藏只隐藏边缘；清空可见队列把相应图片移出微图显示。它们不删除截图文件。历史里的用量是按需计算的本地逻辑大小，可能不包含系统原图、外部备份及所有系统元数据，也不等于 APFS 能立即释放的空间。磁盘不足时保留现有数据并停止新增；不要删除数据库、媒体或观察记录来解锁附加。

## 保存失败了，开关为什么已经改变？

停止收录、隐藏和关闭内置入口可先停止当前行为，再保存；保存失败时当前行为和下次启动会读取的值可能不同。请使用该项旁的同方向重试，直到结果确认。别的设置保存成功不会代表这项也成功。布局或归档草稿保存失败则保留草稿；关闭窗口时可以继续编辑。

## 如何更新、备份和回退？

当前采用维护者提供的**手动更新**，没有已启用的自动更新器。

1. 保存设置/反馈草稿，正常退出 Riftlet。关闭窗口不等于退出菜单栏 App。
2. 保留当前 App；由维护者按[离线备份与恢复流程](../STORAGE_RECOVERY.md)复制完整 App 数据目录并验证完成标记，包括数据库及其 sidecar、媒体、观察记录、配置和反馈。仅复制一个 SQLite 文件不够。系统偏好与钥匙串不在普通目录备份的完整范围内，应另行保留相应恢复条件。
3. 核验新包的来源、散列、签名、公证和架构，再在不覆盖数据目录的前提下替换 App。不要混用同时运行的旧新版本。
4. 打开后检查历史、配置和几张无隐私的测试截图。若失败，保留旧包、新包、备份和准确提示，停止重复尝试并联系维护者。

回退 App 只在旧版本确实兼容当前数据时进行；不能用版本号或“数据库格式一样”推断安全。旧包不兼容时应修正新版，不能把旧数据库覆盖回去丢掉新记录。恢复工具只写新的隔离目录，不会自动接管或重置生产目录。所有备份都可能含私人图片和反馈，应私密保管，不随反馈上传。

新版首次打开截图库后，Personal Beta 3（0.3.0）无法继续使用这份历史。如果换回 Beta 3 后收录停止，请正常退出它，保留最新的完整数据目录，再打开支持这份历史的新版或修复版。升级前的备份仅包含备份时已有的截图和操作。

After the new App first opens your screenshot library, Personal Beta 3 (0.3.0) can no longer use it. If collection stops after switching back, quit Beta 3, keep the complete current data folder, and reopen it with the compatible App. A backup made before the upgrade contains only the history that existed at that time.

## 如何停止使用或卸载？

如果曾开启登录启动，先在「设置 → 使用与历史」关闭「登录时启动 Riftlet」并核对系统状态，再从菜单栏右键菜单选择「退出 Riftlet」。移除 App 即停止它后续的运行；截图来源文件、私有数据目录、偏好、钥匙串反馈凭证和自行保留的备份可能仍在。当前没有一键永久抹除截图数据功能，本指南也不新增清理脚本。

想处理已提交的反馈，应先在反馈窗口取消尚未发送的记录，或申请删除并等到服务确认；移除 App 不会代做。若要进一步处理本地隐私数据，先确认需要保留的原图、历史及恢复能力，并通过维护者的明确方案逐项处理，不要运行网络上的整目录清除命令。

## English safety path

Open History and search by time or record ID. Both display styles show the same records. `Needs review` means uncertain, not failed; inspect the original chat and keep the record. `Swallowed` means the thumbnail left the edge, not that the upload completed. The ordinary path stops observing after START. A file remains available locally unless it becomes unavailable outside this workflow. Restore is offered only for eligible archived/removed records and does not upload by itself.

For an update, save drafts, quit the App, keep the old App, obtain a verified offline backup of the entire data root, and verify the new package before replacing only the App. Do not overwrite the database with an old copy or force UNKNOWN to resend. A rollback requires proven data compatibility. Uninstalling does not automatically delete screenshots, history, preferences, credentials, backups or previously received feedback.
