# 截图以后，回到刚才那句话

**产品基线为 Riftlet 0.3.5（20）Public Beta。** 用户已经知道如何在 Mac 上截图。Riftlet 接手的是更短、也更容易打断思路的一段：把刚截下的那一处，带到正在写的 ChatGPT 草稿里。范围是 Google Chrome 网页版中可编辑、可附加图片的草稿。[公开发行说明](https://github.com/haohongfei2001-png/Riftlet/releases/tag/v0.3.5-beta.1)

## 谁会想用

| 当下在做什么 | 原来的动作 | Riftlet 改变了哪一步 |
| --- | --- | --- |
| 设计师在草稿里描述两处字距差异 | 从桌面上一排相近的文件名里认出刚截的细节，再拖进草稿 | 截完可先继续看设计。回到目标草稿，凭缩略图选中需要的那一处。 |
| 开发者向 ChatGPT 描述一次布局异常 | 为附一张报错或局部界面，从正在写的草稿切去找文件 | 把所需草稿放到 Chrome 前台，从屏幕边缘选图，已有文字可接着编辑。 |
| 读论文时想具体问图中一段曲线 | 给两个局部截图起名、找图，或靠剪贴板记住最后一张 | 两个局部可以先分开截。需要哪一张就选哪一张，稍后还可以从本地历史找回合格的归档项。 |

这些是适合复现的场景。Riftlet 负责把图交到草稿；读图、分析、回答以及发送时机属于使用者和 ChatGPT。

## Capture → Riftlet → Click → Attach

1. **Capture。** 用 ⇧⌘4 框选，松开，等 macOS 把图片保存为文件。Riftlet 读取实际截图保存位置，识别系统截图标记，校验单帧图像后存入本地副本及队列。第一次使用需允许访问该目录。按住 Control 只复制到剪贴板时没有相应新文件。内置窗口、区域和全屏截图另需屏幕录制权限。[截图校验](https://github.com/haohongfei2001-png/Riftlet/blob/v0.3.5-beta.1/Sources/RiftletCapture/FileValidation.swift) · [快速开始](../../../docs/consumer/QUICK-START.zh-CN.md)
2. **Riftlet。** 图出现在桌面边缘。截图托盘、风铃、微缝是同一队列的三种原生外观。闲置默认 2 分钟后归档，可调 1–10 分钟或关闭；历史提供列表和图像网格。「恢复到桌面」让仍可恢复的图片回到队列。系统原件和应用内副本继续保留。[桌面形态](https://github.com/haohongfei2001-png/Riftlet/blob/v0.3.5-beta.1/Sources/RiftletUI/RiftConfiguration.swift) · [归档设置](https://github.com/haohongfei2001-png/Riftlet/blob/v0.3.5-beta.1/Sources/RiftletCapture/QueueArchivePolicy.swift) · [故障与恢复](../../../docs/consumer/RECOVERY-AND-FAQ.md)
3. **Click。** 将目标 ChatGPT 草稿放在 Chrome 前台，单击需要的那张微图。App 在按下时读取 Chrome 窗口、标签和路线，再绑定网页编辑区。首次连接分两步：允许 Riftlet 控制 Chrome，在 Chrome 中开启「显示 → 开发者 → 允许 Apple 事件中的 JavaScript」。本地收录与历史可以单独使用。[点击时的目标](https://github.com/haohongfei2001-png/Riftlet/blob/v0.3.5-beta.1/Sources/RiftletAdapters/ChromeAppleEventsExecutor.swift#L37-L62) · [首次连接](../../../docs/consumer/INSTALL-AND-PERMISSIONS.md)
4. **Attach。** 网页程序用本次选中的图片操作原草稿的附件入口。它核对新增的附件表现与本图的对应关系；证据成立时记录 `START`，微图收起。请在草稿中看实际图片与上传结果。每张图各由一次明确选择发起，后续消息由用户发送。[网页附件接收判断](https://github.com/haohongfei2001-png/Riftlet/blob/v0.3.5-beta.1/Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js#L695-L741) · [桌面收起条件](https://github.com/haohongfei2001-png/Riftlet/blob/v0.3.5-beta.1/Sources/RiftletCore/QueueStore.swift#L596-L626)

## 最值得给第一次看的人看的三个细节

- **原来的截图动作可以留下来。** 在公众熟悉的普通 Mac 工作页面上截取一个可辨认的细节。用户一眼能认出下一镜微图里的同一块内容。
- **把决定权留在最后这一点。** 点哪张就交哪张，目的地是前台草稿。Riftlet 没有替用户提问的步骤。若没有可核实的真实网页镜头，影片应在本地动作处收住，用单独的文字交代发行能力及其证据。
- **眼前与稍后都照顾到。** 桌面只留手上正在用的图，历史能找回可恢复的归档图。拍两张图进入同一队列能讲清这个特点；拍到它们进入草稿则需要独立的网页证据。

## 失败时用户会看见什么

没有合用草稿或权限、且应用能确认尚未输入时，产品可给出明确原因，微图不会因这次点击而演出成功收起。输入可能已经发生、证据却不足时，保留原操作和「结果待核实」。此时检查原草稿及历史。Riftlet 没有自动重传；只凭本地历史标签也还不能判断是否发生过 `START`。有了接收证据后，最终上传结果以 ChatGPT 的附件区为准。[恢复指南](../../../docs/consumer/RECOVERY-AND-FAQ.md) · [原操作的处理](https://github.com/haohongfei2001-png/Riftlet/blob/v0.3.5-beta.1/Sources/RiftletCore/TransferCoordinator.swift#L531-L562)

## 公开范围

可向用户介绍 Mac 上的截图收录、桌面三种外观、共享历史、面向 Chrome 网页版 ChatGPT 的单击附加、用户自行发送和不确定时不自动重传。可说截图副本和历史在本机；点击附加会把所选图交给 ChatGPT，主动发送反馈也会联网。浏览器范围、首次权限和 Beta 身份应当放在下载决定之前。[支持矩阵](../../../docs/consumer/SUPPORT-MATRIX.md) · [隐私与数据](../../../docs/consumer/PRIVACY.md)

发行资料没有覆盖 Safari、Edge、ChatGPT 桌面 App、其他 AI 软件、只读聊天、剪贴板收录、自动问答、自动发送、云端图床或每次网络失败均可自动恢复。系统截图收录接受经校验的单帧 PNG、JPEG、HEIC、HEIF、TIFF；格式列表属于收录能力，不能据此承诺所有原始格式都在所有网页直接传输成功。面向用户的核心差异是省掉在桌面、Finder 和草稿之间找回刚才截图的往返。截图编辑、分类整理和长期图库不是这次传播的主角。[核验表](feature-verification.md)
