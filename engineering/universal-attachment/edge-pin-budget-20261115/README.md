# Edge 合并文档绑定后的真实失败检查点

**两张均收到完整产品点击回执，但仍在最终原目标复核时以 `-1712` 拒绝。商业输入、上传开始和完成均为零。** 本记录保留真实失败，不把源码优化或性能模型记为验收通过。

运行包确切来源为 G `57d8f0dcb9cd17967ab012642378a24b9caff4d8`；准入 H 为 `a2c54950a410b0d34d49ba522b2d8cb69155690b`。两者仅准入 JSON 不同，1,813 个 native/test/build 文件逐个一致；不声称 G 包内包含后来的准入 JSON。[一致性原件](admitted-head-equivalence.json)。普通 App PID 70136 的可执行文件 SHA-256 已重新核算为 `2c66bc1ebc64e86c8ddc7276de4dd95433df684a2f87a736b0d0cef813e46972`，与[签名构建回执](signed-package-receipt.json)和发送配置一致。构建回执中的 GUI/normalLaunch NOT_RUN 是当时状态，随后正常入口运行由原始 App trace 单独记录。

这版已把执行环境准备和文档绑定合为一次原生 evaluation；150 ms 总预算、50 ms 最小剩余门槛、最终完整身份复核未放宽。两次都进入 `originalSelectionRecheck`。按该源码顺序，这意味着合并绑定返回 `bound`，但属于源码推断，不是独立的页面成功回执。

| 目标 | 输入窗口 / 事件 / tag | 原生复核阶段 | 终局原回执 |
| --- | --- | --- | --- |
| fresh-04 | 3509 / 26407 / 113105189241672 | `originalSelectionRecheck`，101.245167 ms，trace 13 | trace 22：`resolveSelection / nativeEventFailed(-1712)` |
| fresh-05 | 3512 / 2000 / 65429667202533 | `originalSelectionRecheck`，116.096167 ms，trace 28 | trace 37：`resolveSelection / nativeEventFailed(-1712)` |

每张只执行一个新测试点击，各有 2 条 App、7 条原生边界和 1 条选择回执，严格匹配资产、输入窗、事件编号和 tag，并取得明确输入前拒绝。它们沿用[上一检查点已明确输入前拒绝的两张不同系统截图](../edge-native-receipts-20261115/acceptance.json)；两张旧 UNKNOWN 没有被点击，fresh-03 也没有点击。[首图回执](pinbudget-01-1-receipt.json) · [第二图回执](pinbudget-01-2-receipt.json) · [最终完整 trace](pinbudget-01-2-trace-01.jsonl)

换包后普通 App 显示队列第一页，测试通过产品既有 AX 分页一次显示目标 4/5，再各点击一次微图。测试没有选择浏览器目标、使用文件选择器替代输入、发送消息或触发自动重传。两次的前后四份 AX 快照均为中性正文完全匹配、14 字符选区、1 张基线附件；两次前后数据库均为 5 资产、0 操作、0 上传开始。这只证明拒绝期间内容未变，不证明成功上传后的保留。[逐步原始观察](pinbudget-01-2-observation.json) · [最后草稿读回](pinbudget-01-2-draft-after.json) · [完整摘要](acceptance.json)

H 的最终 CI 独立报告尚待记录，不能继承上一个 H `d23267f` 的绿色结果。后续正在减少最终复核中的重复原生读取；新包尚未按本目录验收，不等待该优化才归档本次失败。所有商业上传、快速连击、切换标签和异常上传验收仍未通过。PR #69 保持 Draft，不合并或发行。

[manifest.json](manifest.json)列出 19 份原件与公开副本的独立 SHA-256。只有本机 home、临时构建和 App 路径被替换；其他原始字段保留，原件在本地归档。没有重复复制上轮工具源码或大 CI 日志，也没有公开图片、数据库、Profile、账号信息或草稿原文。本证据工作仅读取已有记录及可执行文件，没有 GUI、事件投递、Apple Events 或产品写入。
