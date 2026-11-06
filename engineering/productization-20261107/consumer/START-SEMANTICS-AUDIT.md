# START 与最终状态：当前普通路径

只读审计基线 `2e779f646ac4874344fac94f79103e8ddf9b02c8`；未修改附件代码或触发真实上传。当前真实服务复验为 **BLOCKED_TOOL_POLICY**。以下是代码事实及改进建议，不是新实现或已观察到的网络终态。

## 当前 START 实际证明什么

1. 页面内的文件 setter/change 已返回。`sample(op)` 需要 `changeReturned`，且仍是原草稿；仅发起调用、等待时间或找到一个 input 不够。
2. 出现与这次 File 的唯一文件名或其 object URL 相符的附件节点。相对输入前的预览基线，该节点出现新的图像来源或 progress 元素；已识别的错误节点不产生 START。
3. 页面保存 `signal: attachmentAccepted`、`inputCount: 1` 和该节点身份。该事实是“草稿开始接受这次图像”，**不是 HTTP 请求完成、服务器确认或消息发送**。后续页面重绘也不撤销过去已经发生的接收事实。

固定源码位置：[page sample/observe](https://github.com/haohongfei2001-png/Riftlet/blob/2e779f646ac4874344fac94f79103e8ddf9b02c8/Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js#L701)。仅有新预览是该已审实现的接收判据，不应把它描述成实际网络流量证明。

## START 后发生什么

- `WebAttachmentAdapter.swift` 在 START 回执出现时结束本次等待（约第 485 行）。页面释放基线/URL 集合，没有 load/progress/COMPLETE watcher。
- `QueueStore.swift` 610–624 行独立写入不可变首个 `upload_starts`，把 visible 改为 swallowed。它**不会仅因 START 设置 status=used / phase=succeeded**；只有另行认可的 verifiedReady 才做那件事。
- `TransferCoordinator.swift` 537–539 行在普通独立输入取得 START 后移除 `currentFileInputs`；576–585 行让已有 START 不再进入 reconcile；638 行让普通路径 `observeCompleted` 返回 false。启动恢复也不会把旧 UNKNOWN 当成新输入。
- 历史显示将未结束 operation 投影为 Checking attachment / Needs review，即使已有 START 事实。这不是持续监测最终状态的保证。旧完成/补偿能力和 policy 中的完成 profile 仍保留，不能据类型存在推断当前页面程序会产生终态。
- 普通 policy 没有开放一般上传安全重试。明确的 **pre-input rejection** 可以恢复可点击状态；已开始后网络失败是否可安全再传是另一项证明，当前普通路径不承诺自动发现或自动回归。

## 给集成负责人的最小建议

**可以立即做的准确表述：** 主路径说明用“草稿开始接收，最终状态请看 ChatGPT”；历史若已有不可变 START，可考虑纯呈现文字“草稿已接收 · 最终结果请看 ChatGPT”，避免看似永久后台检查。此处仅提建议，不改 queue、retry、observer 或 admission，也不把当前状态改成成功。

**本轮不能可靠宣布的新终态：** 目前未获得当前真实页面中与同一操作绑定、跨重绘稳定的最终成功/失败信号。进度消失、卡片存在、缩略图加载、按钮可点、超时、导航或连接中断都不能单独证明上传完成或安全失败。当前工具不能进入真实服务，不能用合成 DOM 替代缺失证明。

**后续研究的接受条件：** 在获准的自有空白聊天中，分别保留成功、真实失败、重绘、刷新/断线及多张接续的原始证据；终态必须唯一对应原 File/附件/原草稿，不能借其他图片的进度或请求。若能形成稳定的正证据，再独立审查一个有界、只读、可退出的后续观察；它不能阻挡新截图输入、改变点击目标、把 UNKNOWN 升级为可重传或自动发送。

**当前消费者恢复承诺：** 可以找回本地原图和记录；不能承诺在每个 START 后失败时自动弹回、恢复按钮总可用或可无风险再传。文案已按此区分。
