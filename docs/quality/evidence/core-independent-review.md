# 独立复核：附件目标与崩溃前 prepared 恢复

审查者：`storage_audit`（非原 finding 作者 `attachment_audit`）。
基线：`44f745a15ecb3682a9da0bda17f17a5d9fc1f07e`。本次涉及的 JS、Main、Core、Panel 文件与 `v1.0.1` 无 diff。
结论：**两条 finding 均成立，可进入 Issues；证据范围和修复边界须按下述措辞保留。** 本文是缺陷复核，不是修复代码准入或新版本验收。

## QA-ATT-001：PASS finding，P0 合理

### 独立执行

执行命令（明确清除夹具可选源码覆盖，使用仓库原生产 JS）：

```bash
env -u RIFTLET_PAGE_PROGRAM_SOURCE node /workspace/scratch/6d7f70782eae/audit-work/attachment-foreign-picker-repro.cjs /workspace/scratch/6d7f70782eae/Riftlet
```

本次真实输出：`elapsedMS=3005`，`entryClicks=1`，`foreignSetters=1`，`foreignChanges=1`，`foreignReceivedCurrentFile=true`，`state=inputTriggered`；`openedContainers=0`，`setterEntered=true`，`changeReturned=true`。退出码 0 表示“已复现缺陷”的断言成立，不是产品通过。

### 夹具有效性

- 脚本导入仓库已有 `Tests/WebPageProgram/independent-input-fixture.cjs`，该夹具从 `Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js` 读取并执行完整当前生产程序；复现脚本没有修改或替换生产算法。
- 原 composer input 被移除，真实 Add files 按钮仍位于 composer 内，处理器只计数，确实不会调用/创建/引用那个外部 picker。
- foreign input 位于 body 下独立 section；没有 form、label、aria-controls、aria-owns 或其他到 composer 的关系。独立 timer 在 commit 前安排，10ms 后自行调用 foreign.click，故不是故意把它放进真实入口回调里冒充外部输入。
- `applicationAccept=false` 禁止夹具自动生成草稿附件卡，避免将 wrong setter 演绎成虚假的 ChatGPT START。最关键的证据是生产程序确实把当前文件放入外部 input 并派发 change。
- 夹具是受控 DOM、合成 1×1 PNG、无网络；它证明算法违反“明确绑定正确附件输入”的边界，**没有证明真实 ChatGPT 的某个现行头像/项目控件已经收到图片，更没有证明服务端泄露或误发消息**。

### 代码因果链

`discoverThroughEntry.capture:499–508` 对没有正面归属但也没有“其他归属标签”的 picker 仍记录 `tied=false`；`617–623` 在没有 tied 选项时把全部 live 候选作为 choices；`631` 使用 `tied.length || ended`，在3秒deadline到达后把唯一无归属候选提升为可执行对象。`execute:857–877` 只复核原 draft 和 input 可用性，不补 input-owner 关系，然后实际 setter/input/change。

“只剩一个”和“等待满3秒”不能证明该 input 属于用户点击时的草稿。用户定义 P0 包含错误附件/安全边界问题，因此 **P0（已复现的非预期 input 写入；真实平台影响待验证）** 合理。不要降成单纯性能或测试覆盖问题，也不要夸大成已发生跨账号数据泄露。

### 最小修复和回归约束

1. deadline 到达只能结束发现或给出“无法确认附件入口”的前输入失败，不能给无归属 input 授权。必须移除 `ended` 对 `tied=false` 的提升。
2. 保留正面归属链：真实 composer entry 的同步实际调用、entry 的 label/aria-controls/aria-owns 所指向的 input/portal、已确认 owned popup 的异步挂载、同一真实调用内替换的后继 input。不要退回“必须在同一个form里”“只能有一个input”“accept必须含PNG”等旧错误门槛。
3. 不要仅扩大头像/项目字符串黑名单。无名称的独立 picker 一样不能接收文件。
4. 现有测试 `independent page activity...` 往往在异步外部调用之后又产生真实调用，因此凭两个候选可判歧义；新用例填补的是“真实入口没有产生picker，外部只有一个调用”的空档。
5. 还有一个必须诚实处理的边界：**完全脱离DOM、在原生 await 后调用、没有可观察归属关系的 input**，与同样时序的外部 input 在当前探针中不可区分。不能承诺删一行就同时保留所有这种合成布局。应以当前真实 ChatGPT 可观察入口补足特定关联；不能证明归属的形态应前输入保留图片。不要为了让所有旧合成“成功”断言继续绿，而恢复这个不安全兜底。
6. 验收必须同时保留已有同步 detached、hidden、connected portal、owned asynchronous mount、rebuilt picker 的正例，以及单一foreign/多个foreign/真实+foreign/超时/导航/用户中断负例。foreign setter/change 均须0，原草稿文本/选区/旧附件不变，执行过 setter 后绝不换路径。最终还需原生 Chrome 实际附件验证。

## QA-ATT-002：PASS finding，P1 合理

### 确认的真实调用链

- `QueueStore.prepare:235–238` 在 SQLite 事务中写入 `phase=prepared`，资产 `status=transferring`。随后 `TransferCoordinator.select:284–301` 才设置内存 waiting、调用 onChange、settle、drain；存在持久化完成但尚未记录 dispatch intent 的真实中断窗口。
- 新进程的 `TransferCoordinator` 中 `waiting`、`operationSelections`、`currentFileInputs` 初始为空（91、103、112行），不会自动重建旧FIFO。
- `WebAttachmentAdapter` 实际实现 `IndependentFileInputAdapter`；`RiftletMain:558–564` 在该分支跳过 `store.recoverInterruptedOperations()`，直接把 originalRecoveryIDs 置nil。
- 正常鼠标入口 `RiftPanelController:1813–1816` 拒绝 `record.status == transferring`，所以旧图显示但无法直接再次附加。
- 即便绕过UI调用 Core，`TransferCoordinator.select:239–271` 遇到旧 prepared 时当作原 unresolved，只有 unknown/compensated 会 reconcile；prepared 既不重建 waiting，也不退役，随后返回。不是仅一层按钮禁用问题。
- `QueueStore.recoverInterruptedOperations:731–735` 已有正确的“prepared→failed、未发生外部输入”语义，但正式独立adapter启动没有调用该路径。

### 严重度与措辞

**P1 核心附件在崩溃/异常结束后无法正常继续**成立；源码可确定，当前Linux无法执行macOS原生重启复现，不能标为原生PASS。

有非常隐蔽的人工绕行：移出仍可见的prepared图会在 `QueueStore.removeVisible:128–131` 退役为failed；随后在历史恢复到桌面可再次点击。因此不要称“不可恢复故障”或“图片永久丢失”。这不影响P1：正常点击恢复路径确实坏了，不应让普通用户先移出再找回。

### 最小修复和验收

- 独立adapter启动、任何新selection可入队之前，只退役上一个进程遗留的 `.prepared`：事务条件检查原phase，保留UUID/attempt/target/图与可见性；状态改为已取消/可再次点击，原因明确“输入前中断”。已有missing状态仍保持missing。
- 不直接恢复旧waiting、不自动重发旧点击、不重新选当前Chrome目标。下一次必须来自用户新点击，并独立绑定新目标/新attempt。
- 不笼统复用会改写所有post-intent记录的全量恢复来解决这一个问题；原UNKNOWN/START、dispatchIntent后的不确定输入保留。需要可复用的窄“retire pre-input after restart”操作，不需要另造恢复框架。
- 在实际 App 初始化路径或同一组装helper上建立回归，而不是只测 `QueueStore.recoverInterruptedOperations` 这个未被产品调用的方法。
- 两个独立用例：①prepare落盘后、dispatchIntent前结束进程→重启→图正常可点，启动0输入，新点击只输入一次；②dispatchIntent后结束→重启保留不确定记录，启动和重复恢复0输入。另核对原有UNKNOWN完整行/receipt/媒体hash不变。
