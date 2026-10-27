# v10 范围性证据：start 已持久，AppKit 退出路径已执行，最终结果仍未决

日期：2026-10-27。配套：[v10-fast-swallow-evidence.json](v10-fast-swallow-evidence.json)。运行源为 `0659e1cc603b1963367a2ba3a032414eeb5ad2ed`，实际 executable SHA256 为 `51c999a20bbbd70c955058fb1162a4b18a5f8dd421d1a03517a7dfe5cec75998`。此临时构建叠加 synthetic AX 元数据 overlay 和 synthetic start/诊断 overlay；不是 Pro 正式 App 源码改动或生产截图准入。

**本轮证明了原操作正向 start 的持久化及一次 AppKit 吞噬代码路径；没有 final proof，不能标为上传 SUCCESS 或整体验收通过。**

## 原操作与证据关联

- assetID：`A484A063-19CD-4294-9EB0-0ED8F1A8A790`
- operationID：`3DBE58C7-B04D-4566-A252-BED937799A95`；attempt=1；页面 inputCount=1。
- 生成图片 SHA256：`494d7d015dc1a91073b356e1d6d64a546497aab37f8c47c4f82c630d7033f5bb`。
- targetDigest：`b688315f0ac079978d72ea2490b5462bab2720c10846d6f955df8d800ec6a975`。完整 target 仅本地保留；只读读取的 start receipt 规范 JSON 摘要与原选择 digest 相同。

helper 一次 AXPress 返回成功，前后台 PID 未变；App selection source=accessibility，已有 ACK 早于原边界、freeze accepted。这是**软件 AX 输入，不是物理鼠标或真人证据**。helper 自身没有证明上传成功；真实业务证据来自原页面操作、Core store 与 AppKit 日志。

页面从同一原节点的初始缺值等待到数值基线，随后观察 4.5378966329499795→8.622003602604961，记录 correlatedProgress start，evidenceID=`c852b572-8689-47a4-bbeb-d28d0937f5bc`，inputCount=1。start 相对页面 inputObserved 时钟约 2531.3 ms；此页面时钟不与 native uptime 混减。

## 已提交状态与可见退出时序

store 先后观察 pending/visible、prepared/visible、dispatchIntent/visible；收到 start 后为 transferring/swallowed、reason=uploadStarted、visibilityRevision=1、operation phase=inputTriggered。

额外只读查询 `upload_starts` 确认该 operation 的第一份 uploadStarted 审计仍存在：asset/attempt/hash/完整原目标一致，evidenceID 与页面 start 一致，positiveReady=false、isUploading=true、无 error，采用候选 synthetic start profile。后续 operations 的最新 receipt 变成 inputTriggered，不会覆盖这份独立 start 审计。当前只读 phase 仍为 inputTriggered；没有把开始事实升级成最终成功。

下表所有 native 间隔均以 helper 本次 AXAction 采样为零点：

| 边界 | 相对时间 | 解释 |
| --- | --- | --- |
| App refresh 读到已提交 swallowed snapshot | 5561.007 ms | commit 时间的观察上界，不是精确 COMMIT |
| swallowScheduled | 5561.274 ms | 已通过原 UI deferral gate |
| swallowActualStart | 5561.311 ms | 开始代码边界，随后写诊断日志并调用动画 |
| swallowClose | 5814.456 ms | 实际 row close 返回后的代码采样 |

scheduled→close 约 **253.181 ms**；actualStart→close 约 **253.144 ms**。本次传给动画的 actualDuration 为 0.24 秒。这个约 253 ms 是吞噬动画代码段，**不是点击到上传开始，也不是点击后 253 ms 就消失**；点击到 close 实际观测约 5.814 秒。

三条事件的 asset/op/revision/generation 完全一致，说明原行窗口的代码退出路径已走完。pixelPresentationMeasured=false；无法据此声称屏幕像素消失时刻或无日志情况下的性能。同步 JSON/stderr 诊断有开销，snapshot 读取也不是原子多表事务采样。

## 为什么不能宣告最终成功

fast-first 与 fast-final 的原 operation 都是 hasProof=false；start 对象保留，但后期 startDisqualified=true、progress 已移除、uploading=false。Core 后续仍 transferring / inputTriggered，保持 swallowed。页面最终 textPreserved、oldCardsPreserved，输入 selectionPreserved，但这些不替代 final attachment proof。

`fast.jsonl` 中 App 自有 acceptance 事件数量恰达到 2048 上限。三条早期 presentation 边界完整可见，但尾部缺少 READY 日志**不能单独证明**没有最终成功；本报告的未决结论依据页面 final 与 store/只读 phase，不依赖日志缺失。其他历史操作的 ready_persistence_observed 不属于本次 operation，不能混入本轮成功数。

## 最终 proof 缺失：已确认的 NodeList API 缺陷

只读 native NodeList 记录表明：nodeListInstance=true、isArray=false、iteratorType=function，而 someType 与 prototypeSomeType 都为 undefined。

对应运行源 `Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js:494` 使用 `(record.removedNodes || []).some(...)`。MutationRecord.removedNodes 是 truthy NodeList，即使为空也不会进入 `[]` fallback，且没有 Array.some；执行该分支会产生类型错误，可能使本批处理在第 507 行的 `sampleAll('mutation')` 前中断。相比之下，第 501 行已通过展开转换为数组再调用 some，说明需要修的是原生集合兼容性，而非放松业务判断。

本批独立只读 probe 清楚区分：

| probe 事件 | batch | 页面时间差 |
| --- | --- | --- |
| 原节点 progress=100 | 14 | 基准 |
| 原 progress 节点移除 | 15 | +2619.5 ms |
| 原图片 load，完整 1024×1024、data-png | 无 mutation batch | 移除后约 28.9 ms |

因此“100 与移除在同一 mutation batch 合并，导致未采到 100”的假设被**本批**证据否定。不能继续用该假设解释这次 final proof 缺失，也不能据此证明所有场景不会合批。

NodeList.some 的源码/API 不匹配已成立，足以破坏 mutation 采样；但本组记录没有实际异常栈，也没有修复后同条件对照，不能把它写成已经证明的唯一原因或已修复验收。后续修复应保留完整节点成员、旧值、身份与顺序检查，并用真实 NodeList 的回归覆盖，再单独验证最终 proof。不得重放本次已输入操作、增加 attempt 或把 start 审计当 retry 权限。

本次只新增本报告及脱敏 JSON。原始 trace、私有 store 和完整 target 留本地；公开内容没有页面地址、标签标识、聊天文本或本机路径。未操作 UI、未追加输入，物理 N1、生产截图与完整最终成功闭环均保持独立未完成状态。
