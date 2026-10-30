# 独立审查：PASS_LIMITED

2026-10-30。非作者审查执行者 `natural_independent_review` 仅只读核对本轮报告、源码差异、私有文本日志/保存快照及 GitHub CI；未操作 UI、Chrome、业务数据库或正式 refs。隔离构建者与工作流作者为另外的执行者，现场输入由 root 单独执行。

## 已核对

- 隔离构建此前审查：258 个受控复制文件中仅声明的四文件 overlay 不同；binary/overlay/bundle/source provider/private root 对应，普通 capture 不启用 Web，Feedback endpoint=nil，自动 onboarding 抑制单列。没有把该包说成原样正式组合 App。
- a442 系统 PNG 的导入 asset → decoded/eligible 输入窗 → 同 token/window/asset 的唯一 CGEvent receipt → 唯一 selection submission → `noPublishedTarget` 日志链一致。210.388 ms 仅为首次观察到输入窗日志，不是精确 T2。
- 历史 AX 文本显示唯一行、同 asset 前缀、702×482、待附加、detail image 节点；关闭成功。图片实际像素可见/内容观察由 root 完成，本子审查没有再次打开图片。
- 重启前后 assets、metadata、operations、upload_starts、compensations、mediaHashes 六组保存快照精确相同：3 张、0 操作/start/compensation，hidden/paused 保留。恢复及 31 文件保留结果与 runtime receipt 一致；本子审查依据校验回执，不重新读取原业务数据库/媒体。
- 两张无法归因输入来源的内置输出被明确排除出模式 PASS，没有伪称物理事件或断定产品缺陷。
- 独立读取 CI `41008775790` / `07f2249ad189d7c5d318496bcfa18a3ddf65f4f1`：单次 completed/success。原日志 5 条 JSON 含重复打印的同一 summary；去重后 4 条逐字段等于公开记录。region PASS，window 和 fullScreen 分别在导入前/捕获前因 `FOREIGN_OVERLAP_VETO` 为 NOT_RUN，summary PARTIAL。没有将 job success 升级全模式通过。
- 14 路径集成差异仍对应临时 tree `97344dd7c4a464cc5630ca598dcb29e64c181c2c`，不改正式 refs。公开文件隐私扫描无真实路径/聊天链接等命中。

## 发现与修正

必要更正一项：`durableCommitUptime` 实际记录在数据库导入 await 返回后，并非精确的 SQLite commit 时刻。README 表格已改为准确措辞；未改原始日志或回填时间。

结论为 **PASS_LIMITED**：支持本轮限定的本地文件/原生观察/安全拒绝/恢复与交接结论。不是正式组合 App 生产准入，也不是人工物理、Chrome 附加、窗口/全屏完整验收或新源树全套测试批准。没有剩余本报告阻断性发现。
