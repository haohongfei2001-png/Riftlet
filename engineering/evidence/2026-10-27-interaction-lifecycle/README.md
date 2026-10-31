# 新版交互生命周期 · 实现与执行证据

2026-10-27。正式 Draft PR #1；生产上传/开始吞噬/安全重试未启用。

- 正式起点：`a441c70f3c4071069bd594513ecf16600bbb0ab8`。
- 批准文档：PR #4 `90a04883160032fc6354fb4f3d3f7d56fede2947`，作为源码合流提交 `de56627d5292ca91e9e777d598b5923d6fe9b296` 的第二父提交保留。
- 完整已测输入：`d834a3a4a76cacedd0cb763044085c9c2093680c`；产品源码与 `a09de4d6053d519e3c9bb7723493fe48cee750c2` 一致，随后只增加明确 passed/skipped 的 CI 报告步骤。
- 完整结果：[verification.json](verification.json)、[review.json](review.json)、[实际日志摘录](ci-excerpt.txt)。
- [CI](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40479556833) / [App/helper/log artifact](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40479556833/artifacts/12721893223)，development ad-hoc 构建，未公证/发行。

## 实际交付

SQLite v3 将可见性、开始证据与终态分离；first-start 原子持久化；UNKNOWN 保留原操作且只读恢复；强关联安全失败才恢复可点击图片。用户 hide/remove/archive 意图不被迟到回执覆盖。AppKit 快速吞噬、零图零窗口、按压恢复、归档交互保护、独立隐藏/暂停、分页原生历史均接线。

`--simulate` 是观察新版交互的入口，依次演示开始后成功/安全失败/UNKNOWN，独立 synthetic 数据及目标，绝不访问 ChatGPT。具体运行步骤与本地 Codex 接口见 [uploadStarted v1](../../../docs/UPLOAD_STARTED_CONTRACT_V1.md)。

## 修复与证据边界

首个 CI 编译通过但有4个旧测试失败：无附件身份的 absence-only 回执不再授予安全重试。修订后的测试明确保持 UNKNOWN、原 attempt 和剪贴板租约；直接 policy fixture 使用明确 synthetic 原附件身份。第二次发现 fixture 后续观察默认返回成功，现显式指定失败以测试持续 absence-only。生产适配器没有为通过测试而放宽。

非作者审查另修复迟到按压回退逆转吞噬、混合历史快照误标成功、重复选择提前释放 UI 保护，以及原 drain 尚在处理别图时重生图的新点击被旧选择锁吞掉等问题。详情见 review.json；所有新增源代码和最后的具体修正已纳入上述实际 CI。

首个完整成功 run 40478942469 的并行索引不足以证明7项软件面板未 skip，因此新增详细报告步骤。当前 run 的逐项 passed/0 skipped 关闭这一日志缺口；它仍不是物理 N1、真实焦点、屏幕切换或 ChatGPT 上传证据。自检明确 CHROME_NOT_RUN / GUI_NOT_RUN。

本地 Linux 对原只读 probe 的并发离线运行曾在20ms固定等待后的 hash assertion 失败；同一未修改源码串行诊断通过，macOS CI亦通过。记录为测试时序敏感性，不删除失败记录、不以该诊断宣称真实 MID 已执行；原 probe 与故障归档源码保持不变。

既有普通对话上传、后台观察、真实 POST100 XHR 中断仅继承原有范围。新版真实 uploadStarted、旧操作安全终止、冷首击/ACK、实际 A→B→A/同 URL 草稿、MID、物理 N1、自包含/完整延迟与新版本资源测量继续由本地 Codex 在独立分支完成。
