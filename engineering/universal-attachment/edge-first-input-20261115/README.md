# Edge 实际首图输入：2026-11-15

**普通 Riftlet App 已执行一次真实 Edge × ChatGPT 文件输入；双图验收未完成，原选区保留失败。** 本目录归档已有实测，不表示重新点击、再次上传或 11 月 16 日恢复成功。第一图保留 UNKNOWN，第二图本轮未投递。PR #69 继续 Draft，不满足合并／发行条件。

构建源码 G `285389696de110f076ba60d2e8a1a6fbe98c6b3e`，准入 H `932f278f3412fd3158f01907a5a484ac9c235fa2`；两者仅准入文件不同。构建后 1,836 个 tracked 文件未变，H 的其余 1,835 文件与 G 相同。普通签名 App 1.0.2 (24) 的可执行 SHA-256 为 `39b9cd983441533a75a171fe56432de903a9c16e93cd4d367577cc4fd9aaa894`，保留的签名归档为 `55a8135dabe6d2ec7eb62d2006534da92f22a74b26502e02ebce74444d46b003`。依赖网络失败后的成功构建仅使用官方 SwiftPM `--skip-update` 和已核实的固定依赖；外部构建脚本差异、原／派生脚本哈希见 [构建来源](offline-build-provenance.json)。签名回执的 `normalAppLaunch/GUI: NOT_RUN` 属于 14:00:40Z 构建阶段；后续实际普通 App 入口由进程／可执行身份、原生点击及产品回执证明，未重写旧回执。[包身份](signed-package-receipt.json) · [源码等价](admitted-head-equivalence.json) · [构建后核验](post-build-source-verification.json)

## 逐图结果

| 项目 | 第一图 fresh-04 | 第二图 fresh-05 |
| --- | --- | --- |
| 真实系统截图 | 62,508 字节，SHA `fcd3e2c5748e888c8d47363b441d325361823a828f64452859eb0a13526971f8` | 62,346 字节，SHA `568de2784c37e0c6bfcc2de4b81a8eff4d022d72ded5be772ab80ef4d50c8991` |
| 普通微图输入 | 一次软件 CGEvent down/up，输入窗 3563，坐标 (33, 434.44876325088342)，事件 8651，tag 229607662175447；2 App + 7 原生边界 + 1 选择回执严格匹配 | 本源码未投递，NOT_RUN |
| 原目标绑定／文件输入 | pin 99.558958 ms；captureTarget、validate、begin、chunk、commit 各一次完成；setterEntered/changeReturned 为 true | NOT_RUN |
| 上传开始／完成 | 均未确认，0 START／0 完成，原操作 UNKNOWN | NOT_RUN |
| 正文、选区、原附件 | 正文及 1 张基线保留；选区由 14 变 0，FAIL | NOT_RUN |

[完整分阶段记录](acceptance.json) · [严格点击回执](selectioncheck-01-1-receipt.json) · [发送记录](selectioncheck-01-1-sent.json) · [原始产品 trace](selectioncheck-01-1-trace-36.jsonl) · [既有截图身份](../edge-native-receipts-20261115/asset-and-queue-snapshot.json)

该首图通过了此前失败的最终原目标复核预算，但不能因此宣称冷首击、快速双击、切标签或暂时无响应等所有场景通过。操作 `46A3293A-FD87-4533-B4CB-201AD3777D12` 属于原资产，attempt 1，`dispatch_exclusive=0`；释放文件输入排他权不授权重传。[持久状态读回](after-first-input-state.json)

## 观察、配额弹窗和保留失败

97 条产品 trace 中有 34 次原操作观察：全部原草稿仍有效、原正文不变、2 个基线 DOM 节点保留（对应 **1 张** 基线图片）。第 2 次图片已加载，早于第 5–7 次观测到的进度 100%；没有观测到 0–100% 中间值，ready 属性始终为 0。第 8 次开始进度和 blob 消失、选区比较为 false。图片、文件名匹配和 100% 进度均不能单独证明真实上传开始或最终完成；Edge 的 START／完成准入仍关闭。没有将已有 Chrome profile 套用到 Edge。[34 次观察原件](selectioncheck-01-1-trace-36.jsonl)

14:02:56Z AX 暂时找不到编辑器，因为服务显示“文件仅添加到聊天／剩余存储空间不足”的 Library 配额提示。该提示不能直接解释为上传失败或完成。14:13:59Z 诊断工具核实原文件名及唯一启用的关闭按钮后，只执行 AXPress 关闭该信息框，没有打开存储管理、改选区或改编辑器焦点。关闭后的独立 AX 读回确认原正文、1 张基线仍在，选区长度 **0**；原 14 字符选区未保留。选区丢失与模态框／异步节点变化之间的唯一因果尚未证明，不以“选区对象变了”掩盖语义读回失败。这次额外关闭操作不能算普通 App 无额外步骤验收。[点击前](selectioncheck-01-1-draft-before.json) · [模态时](selectioncheck-01-1-draft-after.json) · [服务提示](selectioncheck-01-first-service-dialog.json) · [唯一关闭动作](selectioncheck-01-first-dialog-close.json) · [关闭后](selectioncheck-01-first-after-dialog-close.json)

第二张没有发送记录或产品操作，不能宣称被第一张阻塞，也不能宣称成功。没有自动发消息、重传 UNKNOWN 或删除任何用户数据。下一步须在原操作仅观察的约束下修复选区保留，取得独立且真实的 START／完成证据，再完成第二图和异常场景；本目录不记录尚未执行的恢复工作。

## H2 必要 CI

独立复核确认 H2 五项必要 job 全部成功，实际测试 merge `49f7c280083d84a933b19bc9183b45c4d5524bb7` 的有序父为 main `b5a412f6`、H2 `932f278f`，tree 与 H2 相同。ARM64／Intel 各 1,444 项测试记录中，本增量 5 项和上增量 4 项均实际执行；已有条件跳过与各架构 2 项 appearance XCTest 跳过仍是跳过。托管商业测试另记首图 `-1744`、第二图 NOT_RUN、0 操作／START，不冒充本机上传成功。

[Native run 43721502023](https://github.com/haohongfei2001-png/Riftlet/actions/runs/43721502023) · [Feedback run 43721501954](https://github.com/haohongfei2001-png/Riftlet/actions/runs/43721501954) · [完整独立 CI 报告](ci-verification.json)

CI 报告原件 SHA-256 为 `6b4e4b37f1245ed5ea1fb81bb3d990edcee9e0d7fe885487ae21191af76334dc`。五个完整 job 日志的字节数／SHA 和官方 artifact ID／大小／digest 与 uploader 日志的交叉核验保留在报告中；未下载 ZIP，不声称本地重算 artifact 哈希。此处绿色仅覆盖精确 H2，不覆盖后续提交。

## 证据范围

[双哈希清单](raw-evidence-manifest.json) 记录每份私有原件和公开副本的字节数、SHA-256 及精确脱敏范围。保留一份完整最终 trace，不重复复制 36 份累计日志。公开副本只含中性状态、计数和身份摘要；不含图片、数据库、Profile、账号／会话秘密、草稿全文或签名包。历史目录不变；旧两张缺回执 UNKNOWN 与本轮已输入 UNKNOWN 是不同操作，均不得重发。
