# Beta 体验修复与 Feedback 接线：非作者审查

审查角色：`/root/beta_ux_feedback_review`。日期：2026-10-28（北京时间）。

## 结论

**源码组合 PASS，无阻断项。** 本审查没有修改产品源码、远端引用或真实 Mac 数据；没有运行截图上传。批准范围是已交付 `fa74f3c68f05ab4eaccfc24e2f39c0177289ddb3` 的展示修复与既有 Feedback v0.1 的最小接线组合，不授予新的上传、重试或云端能力。正式交付仍须由负责人取得本次组合 Native/Feedback CI 和实际制品核验；本报告不把旧 CI 作为新组合测试。

审查基线：正式 `b4bcfa41e8e237723b975d2a9a0059e955fa0c1f`、体验源码 `fa74f3c68f05ab4eaccfc24e2f39c0177289ddb3`、证据后继 `8e1a1688e75db8c18965e073ae357010e7397a3a`、原反馈 `f195bebbc22ed1a162b5866ca1fe6c7ccb9835b9`。审查工作树 `/workspace/scratch/16d4559e9aa8/Riftlet-beta-ux` 的已暂存合流 Main blob 为 **`05fe28ec734ba0d8c040810c737b26715a33d5de`**。

## 两处共享冲突

1. **Selection catch：PASS。** `feedback(...)` 是 Codex 的 MainActor 展示闭包，先验证当前 `selectionUIOwners[id]` 与原 `selectionOwner` 相同，再验证当前 `selectionRevision` 与原可见性修订号相同；失配时不覆盖新选择的提示。catch 保留 `ProductStatus.clickFeedback(error)?.text`、既有权限/格式 fallback，随后明确调用成员 `self.feedback.diagnostics.record(.selectionRejected)`，避免局部闭包同名遮蔽 FeedbackHost。原取消/结束选择、首击授权与刷新顺序保留。诊断事件不会创建 ACK、原选择 token、目标或上传输入。
2. **Refresh render 后：PASS。** `render(snapshot)` 后先执行 Codex 的 prepared/cancelled 展示：只匹配当前 active operation 与 visible asset，prepared 文案保持中性，不从旧快照声称持续未输入；旧 preparing 提示仅在文本仍匹配时清除。随后完整保留 `feedback.assets(snapshot)`、`feedback.operations(successful + unresolved)` 以及 `interactionFence.snapshot().blocked` 对应的 `.uiProjectionDeferred`。这三项是原反馈的本地采样计数，不修改截图 store、队列、目标绑定或观察任务。

## 精确差异核验

独立读取 Git index 的 mode/type/object ID 与固定来源对象进行比较，结果保存在 `feedback-object-review.json`（本地原始报告 `/tmp/riftlet-beta-ux-feedback-object-review.json`）：

- 29 个 Feedback 模块、UI、Demo、Host、测试、服务、Package 和既有反馈脚本文件与 `f195beb` 精确一致，无新增差异。
- 96 个受保护 Core、Capture、Adapters、CSQLite、Resources 及相应原测试/Web 文件与正式 `b4bcfa4` 精确一致。
- 本次 8 个 Codex 交付源码/测试文件中，除 Main 的另外 7 个文件与 `fa74f3c` 精确一致。
- 以 `fa74f3c` 为基线的合流 Main 所有新增/删除行，与原 `e421e668 → b4bcfa41` Feedback Main patch 的新增/删除行按顺序完全一致：**20 行新增、1 行替换**。没有整文件覆盖或额外反馈重写。
- `git diff --cached --check` 通过，两个已知 Main 冲突均已解决。

## 既有 Feedback 与安全边界

- `import RiftletFeedback`、lazy host、启动初始化、菜单“反馈与建议…”及 `showFeedback()` 均保留。退出仍经 `applicationShouldTerminate` 等待反馈草稿可靠保存，再回复退出；原 screenshot `applicationWillTerminate` 不被替换。
- FeedbackHost 和窗口控制器未改。关闭每次调用 `saveBeforeClosing()`，重开同一个窗口不会因旧 allow-close 标记跳过保存；加载中、busy 或 IME marked text 阻止关闭；退出成功保存后编辑仍锁定至最终退出回复。取消、删除和 outbox/凭据账本保持原交付实现。
- Feedback 使用独立 `Feedback-v01` SQLite、actor/连接、Keychain namespace；没有截图表写入或截图媒体删除。
- 诊断仍为 64 项有界内存白名单事件，只采样枚举与计数；不读取原图、私聊正文、URL、目标描述或 trace 文本。勾选时冻结快照，预览可选；未经用户主动提交不外送。
- `FeedbackHost.endpoint == nil`、`DisabledFeedbackTransport` 不变。`pump()` 在 configured 检查处返回，尚未配置服务时不会开始 HTTP attempt，也不会写 received/delivered 成功状态。用户提交只能本地保存为待发送。
- 所有原 Feedback 在 selection/permission/capture/render 的诊断调用均为同步内存记录；无磁盘、网络、actor mailbox 或新 Task。不会在本次冲突处理中引入原点击授权、FIFO、吞噬、后台观察的因果变化。
- Codex 的 `hasOutstandingSubmission` 是只读展示查询；`clearFeedback`、可访问性 label/help 和用户可读错误映射不授予输入或安全重试。旧 UNKNOWN、原图、SQLite v3 和审计保持原合同。

## 限定与交付要求

本审查为源码与对象级非作者审查。macOS 原生执行、完整服务测试、关闭/重开软件 AppKit 回归及新包签名/可执行自检由本次组合 CI 提供；物理鼠标、无 ACK 冷首击、真实 Keychain/IME 全矩阵不因此变为 PASS。普通生产上传、安全失败/重试及云端部署继续关闭。完成必要组合 CI 和 App 核验后应交付创始人体验，不追加与本次改动无关的常规测试。
