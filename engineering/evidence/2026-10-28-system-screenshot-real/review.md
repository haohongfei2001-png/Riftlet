# 非作者审查

## 生产修复

独立执行者 `web_safety` 只读审查现有调度器与App失效分支，并在纯Swift重现现场链：idle request返回true被忽略后pending=true/inFlight=nil，100次后续request均合并且不唤醒。消费原wake后恢复；已有capture时request返回false，原completion拒绝旧epoch ACK并唤醒replacement。审查结论：最小App修复顺序正确，不并发捕获、不回填ACK、不回放点击、不改变输入保护。

该执行者编写3项调度契约回归，但不是生产补丁作者；测试明确不声称执行AppKit wiring。所有新增回归随完整macOS CI40647857737通过。

## 页面判据与候选journal

独立执行者 `late_failure` 对4b7228 v13/journal只读审查：input槽不能独立代替传输事实；start要求原附件单次输入后两个有限递增且小于100的进度；attached要求严格最终proof。preview允许PNG字节等同或同尺寸sRGB RGBA等同，不能扩展为服务端原文件/ICC/HDR保真。正文/选区/旧附件不由journal判据覆盖。其后真实证据复核任务因模型容量不可用，未把该失败任务算作完成审查。

## 实际证据与公开交接

独立执行者 `native_gui` 读取冻结的before/after SQLite与日志，并逐字段核对：

- 修复前6次mouse全部noPublishedTarget；before-fix快照0 operations。
- 修复后begin/chunk/commit各1次；A的asset/op/attempt/hash/full target与持久记录逐字段一致。
- input/attached为同一attachment；ACK提前7801.743ms，commit区间为点击后434.360–542.616ms。
- 无start槽，upload_starts=0；历史attached后来invalidated，不能据旧快照宣称当前仍已附加或允许重传。
- 赞同完整SC-COMPLETE标FAIL，仅历史attached候选观察子项PASS；公开README/results/validation/data-preservation边界相符。

没有审查者操作UI、浏览器输入、候选运行进程或数据库写入；现场输入所有权保持单一。SC-START未通过和保留性NOT_RUN是未满足的准入条件，并非通过审查即补齐的证据。

最终复核结论：无阻断发现。B仅prepared等待后activation取消，没有第二组输入；修复进程486次captureTarget执行区间无重叠，仍保持单在途与旧epoch拒绝。此计数用于核对非并发，不作为产品成绩。公开脱敏与私有证据hash一致。
