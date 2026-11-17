# G7 普通应用 615、616 双图实机核验

2026-11-17，主执行人在同一隔离 Edge 临时草稿的第六页分别点击新系统截图 615、616 各一次。应用记录到的两次 down 相隔 414.949 ms，两次选中回调相隔 407.857 ms。每图均有独立的发送前保留标记、10 项有序原生回执和一项持久操作。原窗口、标签、document、composer、draft generation 与既有 612/613 相符，两项新操作分别保存了新的点击绑定。

| 结果 | 615 | 616 |
| --- | --- | --- |
| 未修改的系统原 PNG | 1,405,721 字节 | 1,405,361 字节 |
| 普通 App 的实际点击后结果 | 观测到文件 setter、更改和 1 条持久 START | 分块时 `invalidTarget`，正式记录为 `fileInputCommandNotInvoked` |
| 新附件在原草稿内出现次数 | 1 | 0 |
| 队列显示 | 观测到吞没开始及收拢 | 失败后仍可见 |
| 本轮 QA 对首方服务处理终态的确认 | UNKNOWN | UNKNOWN；该操作在文件输入前结束 |

原始普通 App trace 共 102 行。序号 247 的 `edge_web_command` 记录 `chunk / process / invalidTarget`，紧随的 248 号 `web_command_refused` 通过操作 ID 摘要对应 616。251 号记录 `discard` 返回成功。253 号记录该操作失败并保持可见。第 5 块在原生目标检查时被拒绝，尚未交给页面。此前同一操作的 4 个分块均已获确认。旧日志把进程身份读取失败与原生 Apple Event 描述符不可用映射为同一错误，无法区分这次走了哪条分支。新诊断分别记录失败检查、操作摘要与分块索引。

只观察本次两份原件的 QA 收到了 615 的一次文件 change，匹配到的原处理请求数为 0。14 次状态采样和最后的独立读回均未捕获逐文件处理帧。截止后观察器报告已卸载，原 fetch 已恢复。615 的普通应用 START、实际吞没和附件行各自有证据。其服务器处理终态仍未知。616 的捕获、真实点击、应用拒绝均可独立核对。

前置快照有 18 项资产、9 项操作、3 条 START。运行后的独立只读 SQLite 和媒体投影有 20 项资产、11 项操作、4 条 START。原 18 项资产行、9 项操作、3 条 START 及 18 份媒体摘要逐项匹配。原草稿三张图片各保留一次，结束后共四张，正文 SHA、原 UTF-16 选区 [61,14] 均匹配。此前冻结的 73 份原件和回执总计 33,122,893 字节，复核全部匹配。

从含私有原始证据的工作区根目录执行以下只读校验。命令使用本地文件和冻结的 SQLite 投影。

```sh
python3 -B engineering/universal-attachment/edge-fresh-pair-20261117/followup-615-616/verify.py --build "$RIFTLET_PRIVATE_BUILD" --expect engineering/universal-attachment/edge-fresh-pair-20261117/followup-615-616/actual.json
```

环境变量 `RIFTLET_PRIVATE_BUILD` 指向已封存原材料的目录。报告可公开核验的部分包括 [102 条原始 App 事件](pair-trace.jsonl.gz)、[两次试验的原生分块对照](chunk-comparison.json) 和 [测试产物摘要](actual.json)。私有目录只用于逐字节复算截图、账本和服务观察原件。

稍后导出的 191 项原网络记录将 615 唯一对应到 1,386,385 字节的存储写入、HTTP 201 和 ETag。该文件处理请求返回 HTTP 200，记录 576 字节并伴有 `net::ERR_ABORTED`，没有可用响应正文。616 没有匹配的服务创建或处理请求。[逐文件服务证据](service.json)
