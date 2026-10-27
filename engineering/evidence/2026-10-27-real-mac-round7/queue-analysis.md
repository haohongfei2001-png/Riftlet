# 第七轮：同草稿第二次原点击等待后发出

实测源码 `f6417c6faaf8aa21ac587b07f25ea2a159af021f`，executable SHA256 `07453578abcdf96256430380ce3bc5ac6120dc586fba9a880954992e2f8e0089`，无临时 overlay；来源由运行协调方提供。App 在两项均 succeeded 后停止。配套 [脱敏证据](queue-evidence.json) 与 [分阶段性能](performance-analysis.md)。这里只读已有记录与 SQLite `mode=ro`。

**本次两张不同生成图分别由一次 AX 软件点击发起，第二张保留原点击与原 lease 排队，在第一张持久 READY 后输入一次，最终两者 used/succeeded。** 这验证了当前等待方案，没有解除 start 阶段的同草稿锁，也不是物理鼠标、冷首击或生产准入。

## 原授权与身份

| 项目 | A | B |
| --- | --- | --- |
| assetID | E4CF6A7D-E1BB-496E-841B-E970EC1130B3 | 4D760E58-DB9A-4F6D-965E-A021B58B7E24 |
| operationID | 682B6E20-FC6F-46DA-BB6D-7B8ECA820908 | F765CD23-ADF3-4B21-856E-A97595E9A661 |
| selectionID | 99AC10E6-D5E2-4633-BD12-7547A5A2F86B | A6248B6F-AC26-491D-B264-50BF649C37EB |
| 原事件 uptime | 467409.989541667 | 467413.118712542 |
| accepted uptime | 467409.989578125 | 467413.118723083 |
| 共同有效 ACK uptime | 467409.926400167 | 467409.926400167 |
| ACK 领先原事件 | 63.1415 ms | 3192.3124 ms |
| FIFO ordinal | 0 | 1 |
| attempt / inputCount | 1 / 1 | 1 / 1 |

共同 hostEpoch 为 `BD70CE7F-2696-4517-AA10-92FD6F3FB977`；captureRequestID 为 `0DE82F74-E410-4BC3-831B-EB5E618DDC0D`，armAttemptID 为 `843EDD7D-5199-48CC-B4C3-A00F86AB9D40`。B 在等待中的 11 次 accepted-selection 验证保留同一 selectionID、原事件、原 ACK、target digest 和 30 秒期限；没有把后来 ACK 拼接成新点击依据。

私下核对 A/B 完整 target 相同、logical identity 相同，而 asset/hash 不同。公开 target digest 为 `f02a6a414d37bb301e90d6a64d614b17a49170444bbb9605b485c8e040d3e5fe`。图片原 hash、字节数、start audit、final receipt 与原操作逐项匹配。完整目标、URL、聊天正文、选区内容、机器路径不公开。

## 持久排队与实际输入时序

| host uptime | 观察 |
| --- | --- |
| 467412.806486042 | A AppKit close；先前 start 审计与 swallowed 已成立 |
| 467413.061391541 | 点击 B 前只读 A 为 inputTriggered |
| 467413.118697042 | B helper AXAction，source=helperAX，physical=false |
| 467413.226635916 | 同次 DB 快照：A=inputTriggered，B=prepared |
| 467419.521487417 | App 首次观察 A persisted succeeded，上界而非准确 COMMIT 时刻 |
| 467419.586552375 | B 唯一 begin 排队，比上述成功观察晚约 65.065 ms |
| 467419.588386666 | 同次 DB 快照：A=succeeded，原 B op=dispatchIntent |
| 467425.144809791 | B=inputTriggered，start audit 已对应 swallowed |
| 467435.586612208 | DB 快照两项 succeeded |

B prepared 快照直接记录了 phase，不是仅由 transferring UI 推测。B 后来沿用同一 operationID/attempt=1，未新建重试；A/B 页面各 inputCount=1，总计两次 file change。后台 captureTarget 调用属于预绑定活动，不是 B 重新捕获目标的证明；原 token/target 的连续一致才是此次不换目标证据。

最终只读 DB 显示两项各一行首份 start 审计，used/succeeded、swallowed/reason=uploadStarted/revision=1，final receipt=verifiedReady、positiveReady=true；safeToRetry 仍 false。页面两项 hasProof=true、committed=true、invalid=false、error=false、uploading=false。最终 progress 节点移除使 startDisqualified=true，不抹掉此前开始审计。

## 非空草稿保留与边界

本批 setup 记录 textNonempty=true、oldCards=3、selectionPresent=true、selectionNoncollapsed=true，pageFocused=true 而 editorFocused=false。两次 change 均记录 textPreserved/cardsPreserved/selectionPreserved=true；最终 textPreserved/oldCardsPreserved=true，编辑器仍未聚焦。没有发布原文字、旧附件身份或选区内容；这些是该探针的保留断言，不推广到任意富文本和页面变体。

整个 fresh runtime 的 App 自有 acceptance 事件为 1671，低于 2048 cap；两项 presentation 各 scheduled/start/close 一组，共 6 条。重复 READY 观察不是新增成功或新增输入。原生日志和 App 日志采用不同限额，不能用总 JSON 条数衡量 App cap。

同 asset A 较早在另一段 runtime 中曾 AX 返回成功但随后 DB 操作快照为空、页面 fileEvents/operations 为空，B 因 `NoSwallowCloseInBound` 未执行。该 pre-run 的 App 日志 cap 已耗尽，缺 selection 日志不能推断具体拒绝原因。此次是在确认未产生操作后，fresh runtime 收到新的实际点击；不把先前失败尝试抹掉，也不把它描述成 UNKNOWN 自动重输。
