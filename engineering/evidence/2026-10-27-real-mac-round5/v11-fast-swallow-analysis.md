# v11：一次生成图软件 AX 的 start → 吞噬 → 最终 READY 闭环

日期：2026-10-27。配套：[v11-fast-swallow-evidence.json](v11-fast-swallow-evidence.json)。实测源 `53ebcc4da4b0df508edc11f6ead9ea4d8a843dad`；实际 executable SHA256 `30fa313bc0aee80176263dfcb8f09f7575c35018cac5a579c62543ab12d97268`。使用两份已知临时 overlay：synthetic AX identifier/enabled 元数据，以及 synthetic start registry/AppKit 诊断。App 已停止后收集最终日志。

**这一次范围内，原图只输入一次，start 审计持久、AppKit 行窗口退出，随后原操作取得页面 proof 并进入 Core used/succeeded。** 这不是生产准入、物理鼠标或冷首击结论。

## 原操作、目标与准入范围

- assetID：`A69D72AA-1616-4D12-BC70-8FA5A77B8AE0`。
- operationID：`D53F7E0E-871B-4118-84DB-FB00772E1FE7`；attempt=1；inputCount=1。
- 生成图 SHA256：`494d7d015dc1a91073b356e1d6d64a546497aab37f8c47c4f82c630d7033f5bb`。
- 原目标 digest：`af15d55ae0fd2a0eaab29660f3a2c19c2a103dfe23bfb8029512a1dfaf3c85b9`。

helper 输入为 source=helperAX、physical=false，AXPress 返回成功，前后台 PID 未变。App 原选择为 accessibility，freeze accepted，ACK 比原边界早约 24.420 秒。因此是**已有预绑定**的点击，不是尚无 ACK 的冷点击。页面 change 记录显示 editorFocused=true；协调方记录测试前为空文本、零旧附件。保留布尔均为 true，但这个空草稿基线不能提升为复杂文字、非空选区或已有多附件保存验收。

start receipt 和 final receipt 的 asset/op/attempt/hash 均与原页面操作匹配；两份完整 target 的规范 JSON 摘要均等于原 selection digest。公开文件只包含 digest，完整 target、页面地址、标签标识、聊天和本机路径未公开。

## 开始与不可变审计

页面初始原 progress 节点缺数值时保持等待，随后从 4.084106969654981 增长至 8.622003602604961，生成 correlatedProgress start。start 的 page performance 时间为 156323.7 ms，原 inputObserved 为 154145.8 ms，间隔约 2177.9 ms。start evidenceID 为 `e948f80c-8d5a-4176-aeee-a7be66d4d073`，唯一输入计数仍为 1。

store 从 prepared/visible、dispatchIntent/visible 变为 transferring/swallowed，reason=uploadStarted、revision=1、phase=inputTriggered。第一份开始回执与可见状态对应；最后 used/succeeded 仍为 swallowed/uploadStarted/revision=1，没有以 legacyCompletion 替代开始事实。

`upload_starts` 最终快照仍有 **2 行**：前一 v10 操作与本次 v11 操作的首份开始审计都保留。此次 final READY 没有覆盖或清掉首份 start evidence；该计数不是“两个本轮成功上传”。

## 三种时间不可混为一项

下列 native 时间以本次 helper AXAction 为零点；page 时刻经一次 bridge 前后界限映射，区间宽约 263.431 ms，不是假设两端时钟精确同步。

| 边界 | 点击后时间 | 证据语义 |
| --- | --- | --- |
| 页面正向 start | **4.935–5.199 s** | bridge 界限换算区间 |
| App 观察到持久 swallowed snapshot | **5.257130 s** | COMMIT 的观察上界 |
| swallowScheduled | **5.257462 s** | 已通过原 UI deferral gate |
| swallowActualStart | **5.257550 s** | 动画调用前的代码采样 |
| swallowClose | **5.510232 s** | 原 row close 返回后的代码采样 |
| 页面最终 proof | **10.403–10.667 s** | bridge 界限换算区间 |
| App 首次观察 Core succeeded | **26.868680 s** | 成功持久化的观察上界 |
| 外部 store 首次观察 used/succeeded | **26.893080 s** | 另一轮询观察上界 |

AppKit **actualStart→close 约 252.683 ms**，scheduled→close 约 252.771 ms，本次请求动画时长为 0.24 秒。不能将动画段写成“点击后 253 ms 消失”：点击到 close 约 **5.510 秒**。start 页证据到实际 AppKit start 的界限为 **58.8–322.2 ms**。

协调方另已核对，本次保留原 Web-Acceptance 配置：swallowDuration=0.24、shift=0.18、return=0.18、reducedMotion=0.1 秒，本轮未更改。正式默认 swallowDuration 为 **0.120 秒**；本次 252.683 ms 不是该默认参数的实测，也不是新的默认目标。

页面最终 proof 时间为 161791.5 ms，晚于页面 start 5467.8 ms。映射区间表明，proof 比 AppKit close 晚 **4.893–5.156 秒**，足以证明这一批 UI 退出先于最终 proof，而非等待 READY 才吞噬。只观察到一组 scheduled/start/close；后来 READY 没有重播该组事件。

约 **26.9 秒**的 Core 成功持久化观察是另一个必须保留的测量，不能省略、当成页面完成时刻或假称准确数据库提交耗时。原生日志有 32 次没有 operationID 的 observe/nativeEventFailed(-1728)，不能归到本次新图，更不能把全部观察延迟归因于它们。此记录未测得各后台调度阶段的精确耗时。

page→host 换算使用 `hostBefore + (eventPageMS - snapshotPageMS)/1000` 到相应 hostAfter 上界；依赖同一页面单调计时和本批 bridge 界限，未用墙钟 timeOrigin 算一个虚假的精确点。原始 bridge 范围、pageNow、事件 page 时间和推导区间均保留在脱敏 JSON。

## 最终成功与日志完整性

原页面 hasProof=true、committed=true、invalid=false、error=false、uploading=false；Core 原操作 final receipt 为 verifiedReady、positiveReady=true、belongsToOriginalDraft=true，最终 used/succeeded。后期 progress 节点移除令 startDisqualified=true，不会抹掉此前已成立的 start 审计，也不会将 final proof 改成失败。

该源已将 native removedNodes 先展开为 Array 再调用 some，保留 start 早返回后的 mutation 观察。本次后续取得 proof；它与 v10 的缺陷定位相符，但不把一次真实成功扩展到所有浏览器、页面变体或失败路径。

App 自有 acceptance 日志 **976 条，低于 2048 上限**；本操作三条 presentation 边界各一次。历史操作 READY 日志按 operationID 排除，重复后台观察不计为新输入或新成功。

## 保留的限制

这只是一个生成图、预绑定 ACK、编辑器已聚焦、空文本/零旧附件的 AX 软件样本。AppKit 日志证明代码路径，pixelPresentationMeasured=false；close 不是屏幕像素呈现完成时刻，同步诊断日志也有测量开销。未测试物理 N1、冷首击、未聚焦编辑器、真实系统截图生产上传、同草稿未决时连续输入、安全失败或重试准入；safeToRetry 仍为 false。

本次只新增本报告与配套 JSON，完整原始记录仍留本地；没有修改 source、其他报告或操作 UI。
