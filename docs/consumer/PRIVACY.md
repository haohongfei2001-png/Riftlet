# 隐私与数据 / Privacy and data

Riftlet 的截图副本和历史保存在本机。**点击微图会把那张图片交给当前 ChatGPT 草稿；明确发送反馈则会把反馈内容发送到维护者的反馈服务。**

## 截图与页面访问

- 系统截图原文件留在 macOS 的保存位置。Riftlet 在自己的数据目录保存私有副本、缩略图/必要派生文件、历史和操作记录。内置截图及编辑结果也可能分别占用空间。
- 普通数据目录为 `~/Library/Application Support/Riftlet/`。设置还包括系统偏好中的来源授权、引导和历史视图偏好；反馈访问凭证存储在 macOS 钥匙串。App 数据目录不是整个系统偏好、钥匙串或权限的完整备份。
- 为确定目标并保留原稿，页面程序在当前 ChatGPT 页面内检查编辑器、相关控件、附件预览及选区，并可临时读取编辑器值来判断是否被改动。反馈诊断不会导出这些临时文本。本地数据库和原始诊断文件可能含有私人信息。
- Chrome 的「允许 Apple 事件中的 JavaScript」开关适用于已获准控制 Chrome 的应用。关闭它会停用 Riftlet 的一键附加，本地收录和历史仍可使用。
- 点击附加才把图片交给该网页。Riftlet 不自动发送聊天消息，不主动删除现有聊天附件，不上传整个截图目录。图片进入 ChatGPT 后由该服务处理，适用你自己的账号和服务设置。
- 当前产品没有 Riftlet 账号、截图云同步或后台使用率埋点。日常收录不会将截图发送给维护者。

## 反馈是什么时候联网的

打开反馈窗口、编辑或关闭并保存草稿不会新提交报告。点「发送反馈」后，已授权的待发送项可在后台、网络恢复或下次启动时继续投递；这不会每次重新弹出确认。反馈的查询、取消/删除申请也可能联网。

发送内容包括你填写的文字、问题/建议类别、随机报告编号、版本和提交时间。可选诊断只包含有限的事件类别和计数，不包含截图字节、图片路径/编号/散列、剪贴板、聊天正文、浏览器会话或原始工程日志。新草稿默认不附带诊断；重新打开已有草稿会保留你之前的选择，可在发送前预览或取消勾选。

反馈通过 HTTPS 发往 Riftlet 的 Cloudflare 接收服务，并可进入维护者的私有反馈中心；不是公开 GitHub 源码仓库的 Issue。正文是你输入的内容，**不会自动识别并删除其中的隐私**。服务和基础网络提供方可能处理连接元数据，不能承诺匿名或端到端加密。

“已保存在本机”不代表云端已收到；“已持久接收”也不等于维护者已经阅读。反馈窗口会区分这些状态。需要撤回时，使用对应记录的取消或删除动作；已经尝试发送的报告需要等待服务的删除确认，包括可能存在的私有维护副本。卸载 App 不会自动撤回此前反馈。

## 图片保留与卸载

在菜单栏打开「设置 → 使用与历史」，展开「存储与恢复」。点「检查用量」可查看私有图片、内置截图、收录暂存及记录、队列数据库的逻辑大小。系统截图目录、反馈、偏好和其他备份另计。统计不完整时会显示已查到的部分。点击同组的「在 Finder 中显示」可打开本机数据文件夹。也可在 Finder 的「前往文件夹」中输入上文的数据目录。目录中的图片、历史和反馈可能包含私人内容。

收起、归档、移出微图和清空可见队列只改变本地显示，不删除系统原图、Riftlet 私有副本或远端附件。结果待核实的记录保留，不自动重传。当前没有自动清理截图的保留期限或永久删除策略。

移除 App 不会自动清空这些数据、系统偏好、备份或反馈凭证。数据可能仍包含隐私，请按[恢复与卸载说明](RECOVERY-AND-FAQ.md)保管。不要把整个目录上传用于问题排查。

## English essentials

Screenshots and history are stored locally. A thumbnail click hands that image to the selected ChatGPT draft; ChatGPT then processes it under its own service/account settings. Riftlet inspects the current page’s editor, controls and attachment previews, and temporarily reads editor content/selection to preserve the draft. It does not export that text as feedback diagnostics.

Chrome’s **Allow JavaScript from Apple Events** setting lets apps with Chrome automation access execute page scripts. Turning it off stops one-click attachment. Local collection and history remain available.

Feedback is optional. Pressing Send authorizes the queued report to be retried later, including after restart. Its text, category, report ID, version, time and any explicitly selected diagnostic snapshot go to the private feedback service. New drafts have diagnostics off; saved drafts retain your choice. Diagnostics use a closed list of counts/events, but free text is **not automatically redacted**. Do not include images, chats, credentials or raw databases. Local storage, receipt, delivery and deletion are different states.

Archiving or retracting a thumbnail does not delete its file. Uninstalling the App does not erase local data or already received feedback. Riftlet has no screenshot cloud library, account system or usage telemetry.

Settings → `使用与历史` → `存储与恢复` → `在 Finder 中显示` reveals this copy of Riftlet’s data folder. The storage estimate covers image copies, built-in captures, import staging and journals, and the queue database; external originals, feedback, preferences and backups are separate. There is no per-image permanent delete control. Keep the complete data folder together for backup or recovery.

## 反馈保留和联系

接收服务对正文和可选诊断设有 90 天保留期，到期由定时任务清理。私有反馈中心中可能已有的副本单独处理，尚未确认的删除请求会继续保留。已完成删除或过期且从未投递的报告可留有不含正文的记录，服务按创建时间在一年后清理。可在 App 中对该条反馈申请删除，并查看服务确认。

如需查询或删除已提交的反馈，或有其他隐私问题，可发邮件至 [privacy@riftlet.com](mailto:privacy@riftlet.com)，也可使用应用内「反馈与建议…」。如有报告编号，可在私信中提供。请勿附上截图、聊天内容、数据库或凭据。生产备份的残余保留期限尚未确认。[反馈说明](FEEDBACK-TEMPLATE.md)

For a privacy question or to ask about a feedback report or its deletion, email [privacy@riftlet.com](mailto:privacy@riftlet.com) or use the private in-app feedback window. You can include the report ID if you have it. Keep screenshots, chat text, databases and credentials out of your email. The retention period for residual production backups is unconfirmed.
