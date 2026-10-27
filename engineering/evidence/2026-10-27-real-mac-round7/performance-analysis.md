# 第七轮：分阶段延迟，保留等待与页面差异

源码与二进制来源见 [队列分析](queue-analysis.md)。本批无 overlay；[性能 JSON](performance-evidence.json) 保留原 permission/bridge 事件、request IDs、逐阶段边界与原文件 SHA256。软件 AX，不是物理输入延迟或像素呈现测量。

## 主结果

| 指标 | A：3,147,775 bytes | B：1,770,843 bytes |
| --- | ---: | ---: |
| AX → submission 开始 | 0.611 ms | 0.445 ms |
| AX → 首个 transferring 快照 | 18.649 ms | 18.521 ms |
| AX → begin 排队 | 81.262 ms | **6467.855 ms** |
| begin 排队 → commit 返回 | 529.456 ms | 368.531 ms |
| 首 chunk 排队 → 末 chunk 返回 | 436.396 ms | 274.833 ms |
| begin / chunk / commit 数 | 1 / 13 / 1 | 1 / 7 / 1 |
| 页面原 input → 正向 start | **1750.600 ms** | **5127.200 ms** |
| AX → swallowed 提交观察 | 2573.558 ms | 11959.083 ms |
| AX → AppKit close | **2816.959 ms** | **12212.578 ms** |
| AppKit actualStart → close | 242.973 ms | 252.751 ms |
| 页面 start → 最终 proof | 5151.000 ms | 2944.600 ms |
| AX → 首个 persisted READY 观察 | 9531.961 ms | 22387.762 ms |

A 的“约 2.82 秒”是点击到 close，不能说成动画本身。B 约 12.21 秒包含原点击排队与页面上传过程：DB 直接观察其在 A inputTriggered 时 prepared，A persisted succeeded 之后才开始 B。B 的页面 input→start 为 5.127 秒，即使 B 字节数较少，也不能把它写成更快的上传体验。现有证据不确定该页面间隔由网络、站点排队还是其他内部因素造成。

动画使用保留配置请求时长 0.24 秒，未测正式默认 0.120 秒。close 是 AppKit 代码边界，不是屏幕最后一帧。持久快照 uptime 是 COMMIT 上界，不能据此宣称精确 SQLite 提交耗时。

## permission 与 bridge 工作量

A 的 acceptedSelectionValidation 被动权限检查共 3 次，时长合计 **46.390 ms**；B 共 11 次，合计 **187.171 ms**，包括其等待中和发出前的重新核对。每次原 session 绑定、askedUser=false、result=granted。原检查区间及 requestID 均在 JSON，不以旧 granted 缓存替代这些检查。

A 输入组 begin/chunk/commit 的 executionMS 合计 **502.218 ms**、queueMS 合计 **0.658 ms**；B 为 **318.175 ms** 和 **38.960 ms**。B 首个 chunk 的 queueMS 约 38.819 ms。以上是 transport 代码记录的分项工作量，与首尾墙时区间不相等，也可能与其他任务交叠；不要简单相加当作独占延迟预算。

原生 bridge 事件没有 operationID；本报告按两个不交叠的 begin→commit 组及已确认的 FIFO/page 原操作对应。A 13 块、B 7 块是实际调用次数；文件字节分布可由 v12 256 KiB cap 推导，但日志未记录每块实际长度，不把推导改成实测。capture/observe/permission 的整个 runtime 总数另存，不混作用户输入数。

原生时间使用同一 host systemUptime；页面 input/start/proof 差值使用同一页面 performance 时钟。pageFinal 只有 host 返回后采样，没有该次 bridge 开始界，因此**未制造精确 page→host 映射**，也不将跨时钟差值拼成看似完整的网络时间线。所有原始来源名称和字节 SHA256 在 JSON；没有 URL、完整 target 或真实文字。

## 首次未进入操作的 pre-run

较早 A helper AXAction 在 467247.402959333 返回成功，但 467282.423950 的 DB 查询结果为空，后取页面 fileEvents=0、operations=0；B 标 `NoSwallowCloseInBound`，未执行。AX 成功只代表 action 返回，不能算图片输入或上传开始。原 App cap 已耗尽，缺少有效 selection trace，因此不把原因猜成 cold ACK、权限或队列问题。

该 pre-run 单独保留在 JSON，不能用后来 fresh runtime 成功覆盖。fresh runtime 有两次可核对的 accepted selection、原 target、持久状态和页面 input=1 各一次，才支持本次 scoped 成功结论。没有生产截图准入、自动重试、同草稿 start 后解锁、物理鼠标或完整冷首击结论。
