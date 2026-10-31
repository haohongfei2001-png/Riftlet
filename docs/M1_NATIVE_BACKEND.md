# M1：原生 Mac 后端交接

2026-10-27（北京时间）。这是已有 M0 的实现增量与接口说明，不重建总体计划。W2、N1 和真实 Mac Web 两次操作闭环由用户的本地 Codex 独立负责；本轮未访问该设备。

## 独立分支原交付边界（历史来源）

- 独立 worktree/分支：`codex/m1-native-backend-20261027`，起点 `485fa87a31140f9d2e428db69ec5e0599b1f96ae`。
- [Draft PR #3](https://github.com/haohongfei2001-png/Riftlet/pull/3) 以 PR #1 的 `codex/engineering-foundation-20261027` 为目标，供唯一正式工程集成负责人后续整合；没有直接写入 PR #1、main 或合并。
- 已测源码提交：`7dfa8ecbd221095f6c99d289aba794b51ce37e95`（原实现 `7cb9656`，后续只修正命名剪贴板测试夹具）。[macOS CI 40446467852](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40446467852) 全部通过：173 项原生测试、9 项页面 VM、release/签名及三个既有自检。[永久证据](../engineering/evidence/2026-10-27/m1-native-verification.json)与[非作者审查](../engineering/evidence/2026-10-27/m1-native-review.json)保留精确范围。
- 生产模式仍禁用，内置 Mac 客户端 profile 列表为空；未修改 Core、Web、Capture、UI、App、Package、CI 工作流或品牌资产。
- **没有真实 ChatGPT Mac 接入通过结论。** 已实现原生系统调用和安全协调；特定客户端结构、实际 Paste/选区保留、正向逐图完成与异常准入待真实证据。

## 正式集成接口增量

M1与本地真机分支的新Core共同进入PR #1，原来源和173项分支测试保留在下方；合流验证以[正式集成交接](INTEGRATION_HANDOFF.md)为准。生产能力及App Mac入口仍未启用。

新增 `MacClipboardCoordinator.verifyConsumedObservation` 只在短暂锁内核对完整身份相同的`resolved + consumed`墓碑；任何已有所有者均保持不变。成功/补偿阶段通过adapter只读inspect/observe/normalizer，不进入clipboard settlement，不设置activeID、不写journal、不恢复剪贴板。Native Paste仍只接受dispatchIntent。原未决操作“适配器resolved先于Core提交”的恢复路径保持独立。三个针对性回归覆盖Core补偿/重开、journal不变/新Copy保持和多实例所有权；真实AX观察仍需要真实provider证据。

## 现有接口上的实际代码

| 实现 | 已落地内容 | 原有边界 |
| --- | --- | --- |
| [NativePasteboardDriver](../Sources/RiftletAdapters/NativePasteboardDriver.swift) | 实际 NSPasteboard 多 item/type 物化读取、有界快照、守护写入/恢复及同步 owner 查询 | 实现 M0 的 `ClipboardTransactionDriver`，显式传入 pasteboard，没有默认 `.general` |
| [NativeMacAXDriver](../Sources/RiftletAdapters/NativeMacAXDriver.swift) | 实际 ApplicationServices 标准属性/对象/动作、逐对象消息超时和不弹窗的权限查询 | 不识别 ChatGPT AX 节点、不搜索菜单标题、不激活/设焦点/发按键 |
| [NativeMacAttachmentExecutor](../Sources/RiftletAdapters/NativeMacAttachmentExecutor.swift) | PID/launch/bundle/version/build/原窗口/composer/draft、私有文件与 owner 的输入前检查；持久意图后至多一次 AXPress；原操作 observe | 实现 M0 `MacAttachmentExecutor`；默认禁用、synthetic-only；AXPress 成功不代表已附加 |
| [MacClipboardCoordinator](../Sources/RiftletAdapters/MacClipboardCoordinator.swift) | 稳定 flock、原子 journal、跨实例/真实进程排斥、持久输入墓碑、恢复与分开准入 | 不写 QueueStore，不持久化剪贴板内容，不自动恢复/重试 |
| [MacAttachmentAdapter](../Sources/RiftletAdapters/MacAttachmentAdapter.swift) | 接入协调器、跨 await 重入保护、恢复原操作及协调失败降为 UNKNOWN | 保留原 M0 注入接口、normalizer 和 Core receipt/queue 权威 |

没有增加第三方 runtime package。Maccy 的固定版本剪贴板实现仅用作机制参考；它的类型过滤/合并、定时读取、全局 Cmd-V 和可选激活机制没有复制。本轮为独立 Swift/AppKit/ApplicationServices/Foundation/Darwin 实现，不新增第三方版权来源；原有许可证文件保持不变。

## 后续客户端代码只需提供的边界

`MacAXClientProfile` 绑定确切 bundle ID、version、build、surface、adapter ID 和公开安全的 evidence ID。当前 `supportedProfiles` 为空。`UnavailableMacAXBindingProvider` 是默认 provider，不选择任何真实目标。

真实证据到达后，在适配器专属文件实现 `MacAXBindingProvider` 的四项同步只读方法：

1. `capture`：返回证据实际识别的原应用、窗口、composer 和 Paste 菜单对象，以及 `MacTargetSession`。
2. `resolve`：只解析传入的原 `TargetLease`，不取当前任意窗口替代它。
3. `isOriginalDraft`：依据真实客户端能力证明同一聊天/草稿代际；PID 或同一窗口不足以证明。
4. `observation`：只返回原操作的逐图事实；需要真实身份关联和正向完成证据，不能回显请求 hash 或通用文件名充当证明。

驱动检查的通用 `AXMenuItem`/`AXPress` 只是执行前条件，**不能用来发现 Paste 节点**。Paste 身份、composer 结构、Chat/Work/Classic 区别必须来自实际客户端；不增加 guessed selector、按键 fallback 或自动发送。

后续显式开发组合需要把**同一个** `MacClipboardCoordinator` 对象交给 native executor 和 `MacAttachmentAdapter`，否则 adapter 在任何剪贴板读取前拒绝。所有使用同一系统 pasteboard 的 Riftlet 实例必须使用同一私有协调目录，不能按模拟/验收队列各建目录。当前没有 App 组合入口，避免把这个实现误当已启用能力。

native executor 默认 `mode: .disabled`、`profile: nil`。有证据的开发组合仍只接 synthetic 图片；生产成功与 safe-retry 继续分别走原有 ReceiptPolicy 准入，没有增加运行时绕过开关。

## 所有权、输入与恢复

从持久 reservation 开始，flock 跨 snapshot、写入、AX 输入、观察和结算持有；锁文件保持同一 inode，不删除。原剪贴板快照仅留进程内。journal 保存有界操作/asset/attempt/hash/target、阶段、marker/changeCount 和结算类型，不保存剪贴板字节、截图路径或 AX 文本。

| 持久阶段 | 重启处理 | 是否可以重新输入同一操作 |
| --- | --- | --- |
| `reserved` | 证明尚未提交 clipboard write intent；保存取消墓碑，允许不同操作继续 | 不可以 |
| `clipboardWriteIntent` / `clipboardOwned` | 剪贴板副作用保守保留；没有 input intent，不向远端观察借用附件完成证明；原图 UNKNOWN | 不可以 |
| `inputIntent` | 只观察原操作；没有旧快照就不尝试恢复；新输入仍被锁住 | 不可以 |
| `resolved` | 可回查同一完成事实，修复“适配器结算后、Core 回执事务前”中断；仅接受同一结算语义 | 不可以 |
| `cancelled` | 保存原墓碑，可继续不同操作；不把取消解释成生产 safe-retry | 不可以 |

inputIntent 在最终同步目标/owner/文件复核与一次 AXPress 之前落盘。输入报错、`cannotComplete` 或观察丢失保持 UNKNOWN，没有第二次 action、自动 fallback 或按计时器恢复剪贴板。

成功恢复旧剪贴板仍需要原 M0 的独立完成准入、完整身份、marker 和 changeCount，native writer 在最终片段再核对。后续用户 Copy 使所有权不匹配时不恢复。明确可重试失败必须有单独准入，只解除未来显式重试的锁，不恢复剪贴板、不自动粘贴。

协调 journal 身份/阶段/持久化/结算失败会把回执降为 UNKNOWN，Core 不消费、不重试；单纯的剪贴板恢复失败不会取消已经独立证明且持久结算的附件完成。

## 独立分支定向验证与非作者审查（历史7dfa8ec）

原34项新增测试聚焦以下边界；本轮另有上方三项集成回归，合流结果见集成交接：

- [NativePasteboardDriverTests](../Tests/RiftletAdaptersTests/NativePasteboardDriverTests.swift)：8 项，实际唯一命名 NSPasteboard 的多类型/空板/后续复制/拒绝/恢复；不使用 `.general`。
- [NativeMacAXDriverTests](../Tests/RiftletAdaptersTests/NativeMacAXDriverTests.swift)：10 项，原生对象/GetPid 等不查询客户端的原语，以及注入式目标/文件替换/owner/timeout/一次输入/observe 测试。
- [MacClipboardCoordinatorTests](../Tests/RiftletAdaptersTests/MacClipboardCoordinatorTests.swift)：10 项，实际文件、两个实例和 Python 子进程 flock、重开日志、重复/错身份/容量/IO 故障/损坏/symlink/FIFO。
- [MacCoordinatedAdapterTests](../Tests/RiftletAdaptersTests/MacCoordinatedAdapterTests.swift)：6 项，实际 SQLite 与协调日志、M0 编排的重启/未提交回执/结算 IO 错误以及无重传/无失快照恢复。

root 亲自实现协调器、M0 接线及协调/恢复测试；AX 和 pasteboard 作者实际并行；独立 reviewer 阅读全部 9 文件，作者再交叉审查。审查修复了三处问题：不可读 nil 误当空；resolved 早于 Core 提交的恢复断点；协调失败仍把成功交给 Core。后两项有故障/重开的定向回归；nil-server-error 的分类依据 Apple 明确的错误契约与源码复核，没有声称在 CI 注入了真实 pasteboard 服务失联。最终 CI、源码 SHA 和审查指纹保存在本轮 evidence 记录。

## 仍需真实客户端证据的验收

不争用本地 Codex 的 Web/N1 环境。将来 M1 对应执行者在已授权客户端获取 composer-only baseline/刚加入/上传中/完成/真实错误证据后，只接入上述 provider/profile，并按已有 M00–M06 验证。原草稿、选区、既有附件、准确目标、一次输入、逐图身份/完成、失败/UNKNOWN、跨进程恢复和实际通用剪贴板隐私行为仍需真实验收。任何未通过 surface 保持禁用。

当前实现的明确限制：

- NSPasteboard 不提供原子 compare-and-swap，flock 只约束配合的 Riftlet，不能锁住其他应用的 Copy；连续同步检查不是 OS 原子事务。
- `data(forType:)` 可能在返回前物化/分配或等待 provider；字节上限限制保留快照，不能预先限制系统调用的分配和延迟。item 顺序和类型/数据集合得到保留，原始类型声明顺序不保留。
- AX 默认 0.25 秒消息超时逐对象/调用生效，不是整个片段硬截止时间。最多 16 MiB 文件 hash 与最终 AX 检查当前在 MainActor 同步进行，真实响应延迟未测。
- journal 最多 256 条永久墓碑，满后拒绝；没有自动淘汰或生产长期保留策略。写入不明但未到 inputIntent 的状态保守占有，尚未提供完整产品恢复体验；不得删除 journal 绕过。
- 原子 rename + fsync 测试不等于真实断电认证；恢复测试通过销毁实例/重开与明确故障注入执行，不冒充 OS 崩溃测试。

## 使用的原始 API 依据

- [NSPasteboard.pasteboardItems](https://developer.apple.com/documentation/appkit/nspasteboard/pasteboarditems)、[changeCount](https://developer.apple.com/documentation/appkit/nspasteboard/changecount)、[writeObjects](https://developer.apple.com/documentation/appkit/nspasteboard/writeobjects(_:))。
- [AXUIElementPerformAction](https://developer.apple.com/documentation/applicationservices/1462091-axuielementperformaction)、[AXUIElementSetMessagingTimeout](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout)。
- [flock](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/flock.2.html)、[fsync](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/fsync.2.html)、[rename](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/rename.2.html)。
