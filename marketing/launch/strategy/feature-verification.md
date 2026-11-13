# 功能、实测与镜头用语

截至 2026-11-14（北京时间）。本表核对公开发行、源代码和既有验收。**本次成片实际拍到了什么，以逐镜记录为准。** 发行能力、历史运行和当日摄影分别留有出处。[版本与线上入口](../evidence/release.md) · [本轮取景记录](../video/capture-log.md)

| 项目 | 可以据实说明 | 直接依据与归属 |
| --- | --- | --- |
| 下载和平台 | Public Beta 0.3.5（20），macOS 13+，Apple 芯片与 Intel。网站下载按钮直连通用 DMG，更新手动安装。 | 当日检查 [Release](https://github.com/haohongfei2001-png/Riftlet/releases/tag/v0.3.5-beta.1)、[线上入口](../evidence/release.md) 和[安装说明](../../../docs/consumer/INSTALL-AND-PERMISSIONS.md)。新非管理员账户的首次完整图形体验仍待验证。 |
| 系统截图收录 | 已授权的实际保存目录、系统标记、单帧格式和安全尺寸检查；已有旧文件不作为首次启动后的新截图。收录后有本机副本。 | 标签里的 [CaptureService.scanOnce](https://github.com/haohongfei2001-png/Riftlet/blob/v0.3.5-beta.1/Sources/RiftletCapture/CaptureService.swift#L390-L479)、[FileValidation](https://github.com/haohongfei2001-png/Riftlet/blob/v0.3.5-beta.1/Sources/RiftletCapture/FileValidation.swift) 与 [PrivateAssetImporter](https://github.com/haohongfei2001-png/Riftlet/blob/v0.3.5-beta.1/Sources/RiftletCapture/PrivateAssetImporter.swift)；build 19 有独立管理员真实首张系统截图收录与找回记录。 |
| 桌面与历史 | 截图托盘、风铃、微缝共享队列，未使用图片可归档。历史两种视图可查看和找回符合条件的图片。 | [发行桌面外观实现](https://github.com/haohongfei2001-png/Riftlet/blob/v0.3.5-beta.1/Sources/RiftletUI/RiftConfiguration.swift#L4-L15)、[当前消费者说明](../../../docs/consumer/SUPPORT-MATRIX.md)、[较早原生托盘验收](../../../engineering/native-desktop-forms/FINAL-TRAY-ACCEPTANCE.md)。 |
| 草稿目标与动作 | Chrome 中，把可编辑、可接收附件的 ChatGPT 草稿置前，点击指定微图。按下时绑定窗口和标签，再复核编辑区。 | [原生点击绑定](https://github.com/haohongfei2001-png/Riftlet/blob/v0.3.5-beta.1/Sources/RiftletAdapters/ChromeAppleEventsExecutor.swift#L37-L62)、[网页路由和文件入口](https://github.com/haohongfei2001-png/Riftlet/blob/v0.3.5-beta.1/Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js#L20-L44)、[发布说明](https://github.com/haohongfei2001-png/Riftlet/releases/tag/v0.3.5-beta.1)。其他浏览器、原生 ChatGPT、只读页面均超出公开支持。 |
| 开始接收与收起 | 页面出现能与该图关联的新附件表现，且仍是原草稿时，应用可记录 `START` 并收起微图。最终附件状态应直接在 ChatGPT 核对，发送由用户决定。 | [本图的新附件证据](https://github.com/haohongfei2001-png/Riftlet/blob/v0.3.5-beta.1/Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js#L710-L741) 与 [QueueStore 状态处理](https://github.com/haohongfei2001-png/Riftlet/blob/v0.3.5-beta.1/Sources/RiftletCore/QueueStore.swift#L604-L626)。单纯鼠标点击、文件输入返回、通用进度条或桌面归档都不足以证明接收。 |
| 一张接一张 | 每一张另行点击，一次不确定的操作不因选择下一张而自动重放。build 18 曾在同一真实草稿内成功接收两张，保留正文和原附件，未发送。 | [build 18 实测描述](../../../docs/consumer/SUPPORT-MATRIX.md) 与 [PR #61 对版本的归属](https://github.com/haohongfei2001-png/Riftlet/pull/61)。发行变更沿用同一附件机制，片中两张入托盘只证明本地动作。 |
| 失败和恢复 | 可确认输入前拒绝时，可按原因恢复权限/打开目标草稿；若输入可能已发生，核对原草稿与历史，保留未知结果，不自动再传。 | [原始请求及回执](https://github.com/haohongfei2001-png/Riftlet/blob/v0.3.5-beta.1/Sources/RiftletCore/TransferCoordinator.swift#L531-L562)、[截止与恢复](../../../docs/consumer/RECOVERY-AND-FAQ.md)。公开材料不承诺所有失败都能识别或恢复。 |
| 权限与隐私 | 系统文件截图收录需要截图目录权限；内置截图另需屏幕录制。附加还需 macOS 自动化与 Chrome Apple 事件 JavaScript。图片点击后交给目标服务；反馈自愿，默认不带诊断。 | [隐私说明](../../../docs/consumer/PRIVACY.md) · [安装与权限](../../../docs/consumer/INSTALL-AND-PERMISSIONS.md)。 |

## 三个容易被混为一谈的记录

- 对较早的三形态候选，独立测试草稿未能建立，记录写明两次网页输入都未发出。它同时记录了能够核对的原生窗口和系统截图收录。[托盘验收](../../../engineering/native-desktop-forms/FINAL-TRAY-ACCEPTANCE.md) · [PR #58](https://github.com/haohongfei2001-png/Riftlet/pull/58)
- 后续消费者资料明确把同草稿连续双图、原正文与附件保留、逐图开始接收与收起、未发消息，归到已安装的 **build 18**。build 19 的管理员首开和文件权限是另一场实测。build 20 的发布材料沿用了前者的功能结论，不能把日期或构建号改写成当前拍摄定论。[支持矩阵](../../../docs/consumer/SUPPORT-MATRIX.md) · [PR #61](https://github.com/haohongfei2001-png/Riftlet/pull/61)
- 更早的个人 Beta 在空草稿中有软件鼠标点击的双图记录，也记录了另一提交的五图。该 PR 明确原截图、原始日志和测试聊天身份留在私有交付目录。公开仓库已有的动效影片分别是设计探索或旧原生窗口实验，未找到可用来展示 build 20 实际草稿接收的原片。[PR #41](https://github.com/haohongfei2001-png/Riftlet/pull/41) · [片源检索](../evidence/release.md)

在本次发行版上，只有能确认归属的独立 Chrome 草稿、两次分别选中新图、原图分别出现在同一草稿、每张对应收起以及未发送消息，才能填写本轮真实连续附加。由正式二进制运行的隔离界面可证明原生呈现和本地收录；它的独立数据根没有浏览器权限。[隔离运行模式](https://github.com/haohongfei2001-png/Riftlet/blob/v0.3.5-beta.1/Sources/RiftletApp/SettingsReviewEnvironment.swift#L4-L16)

**本轮实测。** 公开 build 20 的原生画面证实两张带 macOS 原生标记的独立截图按序进入托盘、相机键展开，以及第二张微图收到辅助功能按压。原图与收录副本的两组 SHA-256 均相等。真实草稿的两次接收仍为 NOT_RUN。[本轮拍摄记录](../video/capture-log.md) · [实际运行回执](../evidence/native-capture.json)
