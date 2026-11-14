# Riftlet 当前工程队列

2026-11-14启动全产品质量重整。唯一当前队列：[质量台账](quality/ISSUE_REGISTER.md)；机器可读轮次与状态：[ITERATION_STATUS.json](quality/ITERATION_STATUS.json)；工程实施入口：[CODEX_HANDOFF.md](quality/CODEX_HANDOFF.md)。

Codex认领已有Issue并完成可独立验收的增量，先处理R1目标准确性、启动/中断恢复与主线程活性。共用RiftletMain与Core接口由一位集成负责人串行修改。分支和PR必须从真实main开始，不能继续旧PR #41或旧Beta候选。

阶段状态随实际修复与独立验收更新。GitHub文档/Issue创建不是启动Codex执行器；未执行的真实Mac/ChatGPT格保持NOT_RUN/BLOCKED。当前没有承诺24小时后台编程。

旧任务板完整保留在[历史快照](quality/history/docs_EXECUTION_BOARD.before-20261114.md)，不再是待执行任务。
