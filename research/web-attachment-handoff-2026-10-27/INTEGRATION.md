# 给开发 Pro / 工程负责人的复用说明

## 仓库基线与合并方式

本交接分支来自 main `3f5248d6b1c0d32ad80141cbdee4ee16945e6f7b`。准备时核对 Draft PR #1 的 head 为 `0849731799f8c2b24a1f58f14941ef00da4b189e`、分支 `codex/engineering-foundation-20261027`。随后再次核对，PR #1 已推进到 `94df78c74e75cf79b7832e62a228c6fd37913cf9`，新增观察模型/normalizer、GUI 验收工具和 Core 恢复测试。已逐项核对该增量，与本交接目录无路径重叠。

本分支只增加 `research/web-attachment-handoff-2026-10-27/`，不会同步/覆盖 PR #1 的源代码。负责人可在其工程分支 cherry-pick 交接提交（提交 SHA 见本 Draft PR），或只 checkout 这个目录。不要把 main 的网站变更、旧研究结论或实验运行目录顺带复制到工程分支。

PR #1 最新契约已记录用户报告的异常通过，但仍写明实际源码/证据未取得；这部分现在可由本包补充。这不代表修改或启用了该 PR 的 `ReceiptPolicy`。已阅读该 head 的 `docs/ADAPTER_CONTRACT.md`、`Models.swift`、`ReceiptPolicy.swift`，并复核新 head 的 `AttachmentObservation.swift`、`ObservationNormalizer.swift` 与更新后的策略/契约。以下映射兼容这次增量。

## 代码复用顺序

1. 离线运行根目录 `replay.py`，确认去敏后仍得到原来的结论；将这些 JSON 作为适配器 normalizer 的回归 fixture。
2. 从 `src/input/shared-adapter.js` 取实测的同步 guard → File/DataTransfer → 原生 `files` setter → bubbling change 操作；从 `web-evaluate.applescript` 取精确 window/tab 定位和 URL 拒绝逻辑。该路径不写 composer 文本、不删除既有卡片、不发送聊天。
3. 从 `src/observers/exception-observer.template.js` 取逐文件记录、独立 card/image 节点及实际 File 哈希逻辑，结合 normal-bound 模板的监听探测和 ARMED 回执。不要沿用 normal-bound 模板的“文字必须为空”或固定 `download.png` 基线作为通用产品要求。
4. 用 `attached_exception_audit.py` 的实测逐附件生命周期和内容要求替代单纯按钮/动画判断。保留历史 v1 中的完整目标/操作元组、预览完成顺序等拒绝条件。**两份都是实验判定器，不存在已经实现并真机通过的合并版生产 normalizer。**
5. 在现有 `AttachmentAdapter`/`TransferCoordinator` 边界内对接；本轮未写 Swift 适配器、队列/动画变更或生产 profile。负责人按工程已有审查与启用流程接入，不需重开研究或追逐内部 READY 字段。

## 与工程字段的对应

| 工程字段/责任 | 证据与可复用实现 | 不得省略的边界 |
|---|---|---|
| `operationID`, `assetID`, `attempt`, `assetSHA256` | 本地持久化意图、每次独立 UUID、实际 File SHA-256、唯一上传名 | 相同像素的两次截图仍是不同 asset；attempt 由正式队列提供，实验未覆盖多次重试 |
| `applicationID` | Chrome Apple Events 明确目标应用 | 运行前须验证实际 bundle/process；实验脚本使用 `Google Chrome` 应用名 |
| `sessionID` / Chrome profile | 实验用本地 session UUID；监听挑战和同一存储分区往返 | 本地 session 不是账户/浏览器 profile 标识。通用多 profile 自动解析未通过，不能仅凭这个 UUID 宣称已解决 |
| `windowID`, `tabID` | AppleScript 按精确数字 ID 定位 | 发布证据用不可执行的稳定别名；产品必须在用户点击时捕获原目标，不能找第一个 ChatGPT 标签页 |
| `documentID` | 文档注入时生成 nonce，并在同一执行中校验 | 不是浏览器原生 documentId；刷新/重载后不可复用 |
| `composerID` | WeakMap 分配的 editor/form 节点 ID、isConnected、唯一编辑器检查 | 节点必须属于原表单，不能仅凭选择器同名 |
| `draftGeneration` | 原 route、文档 nonce、绑定 lease、目标失效事件 | 本地 lease 不等于服务器草稿 epoch；同 URL 同 DOM 的隐式换草稿仍未验证。正常打字不能增代 |
| `attachmentID` | 唯一文件名 + 实际内容哈希 + 连续观察到的自有 card/image 节点 | 不可只用本地 operation UUID 或唯一新增按钮充当附件身份；节点 ID 只在当前文档有效 |
| `attachedCandidate` | 文件进入/卡片出现，但正向生命周期不全 | 不消费、不重复分派 |
| `verifiedReady` | 经过负责人审查后，可映射本包定义的产品级 ATTACHED | 不是严格内部 READY；必须有完整目标/操作关联、内容证明及版本化 profile，不自动修改生产 registry |
| `definitiveFailure`, `safeToRetry` | 本包没有授予重试安全 profile | 即使实验确认 abort，也不能推定服务器没有残留附件；UI 移除只保守 UNKNOWN |
| `reconcile` | `recovery-query.js`、原操作日志/观察器只读查询 | 不可重新注入文件、粘贴、切换备用上传通道；失去文档回执保持 UNKNOWN |

`positiveReady` 是工程的产品完成语义，只有经审查的 ATTACHED profile 才可设置；`belongsToOriginalDraft` 不能仅因 URL 一致而设 true。`safeToRetry` 默认 false，成功 profile 与重试安全 profile 独立。本包不会为它们发明生产 ID 或注册成功权限。

## 复用 PR #1 最新观察模型

`94df78c` 已提供 `AttachmentObservationEnvelope`（schemaVersion 1）、`ObservationNormalizer` 和 `ObservationProfile`，不要另外创建第二套 Core 收据协议。

- 真实去敏样本的 provenance 可标记 `sanitizedReal`，evidenceID 取本包的短案例标签；这只是来源标记，不是启用权限。合成反例仍标 `syntheticFixture`。
- 本包原始 DOM 日志不是该 envelope 格式，也可能超过其 64 KiB 限额。先在可信 adapter/normalizer 中按本图归纳有界事实，不能把整份日志直接传给 `ObservationDecoder`。
- 只有验证文件内容、原目标及完整生命周期后才输出 `.attached`、`exactImageIdentity=true`、`belongsToOriginalDraft=true`，同时保留观察到的附件身份；未知/失效对应 `.unknown`/`.invalidated`。
- `ObservationProfile(completionSignal: .attached)` 是代码审查后的映射，不由页面或 JSON 自行选择。它仍需通过 `ReceiptPolicy` 的独立准入，当前交接不改生产表。
- 两个真实 abort 样本不足以置 `automaticRetryExcluded=true` 或授予 failureSignal；只保留 UNKNOWN/故障证据。不要用本包无误报结果绕开 retry-safe 保护。

## 产品级 ATTACHED 的实际判据

同一操作必须同时成立：

- 分派前持久化意图，实际进入原 input 的文件名/大小/SHA-256 与 immutable asset 一致，输入次数唯一。
- 原文档、原 composer/form、原草稿 lease 连续有效；新文字及其他文件不能伪造或补齐本图的证据。
- 恰好一个自有卡片，连续的 card/image 节点；观察它自己的上传进度 → 100% → 进度消失 → 最终 data 图片加载完成。
- 对最终预览进行精确内容核验：小图是相同文件字节；实测重编码大 PNG 是相同 sRGB canvas 解码 RGBA 哈希与尺寸。源字节哈希始终保留。未校准的缩放、有损转换、色彩处理差异不能用“看起来一样”放行。
- 无已观察的关联错误、图片错误、替换、移除、重新上传、事件截断/缺口；证明结束及消费前再次核验目标和同一预览源。

时间仅定义先后顺序，没有“等待 N 秒就完成”。按钮可用、动画消失、卡片出现、100% 单独都不够。大图内容证明详见 `evidence/exceptions/main/pixel-proof.json`，小图见 `concurrent-preview-proof.json`。

## 归档实现的精确成熟度

- **输入代码**是真实运行过的 JavaScript/AppleScript/Python 实验代码；公开版没有改动核心插入路径。启动依赖当时的隔离目录/config/运行日志，当前目录不是一键实机启动包。
- **v1** 在正常可信手动轨迹上判 ATTACHED，包含完整绑定/顺序校验；对并发和文本变化过于保守、要求最终字节不变。保留它是为了历史追溯及反例测试，不是当前产品策略。
- **异常审计器**处理不同附件并行、文字变化和实测 PNG 重编码。它消费可信实验采集结果；预览 proof 本身没有携带完整目标/操作元组和哈希完成时刻，也没有完整生产级不可伪造关联。不可直接对外部 JSON 调用它再消费截图。工程必须把 proof 和原 lease/operation/card/source、完成顺序一起绑定。
- **正常 observer**有固定空文字、固定既有合成图的实验前提；**异常 observer**依赖注入后的配置、仅跟踪登记的文件；两者都不是任意 ChatGPT 页面的通用适配器。
- **fault bridge**只用于故障证据；生产路径不需要网络拦截、MAIN-world JavaScript URL 注入或探测私有完成接口。v1 附带 fetch 关联过宽的问题在 v2 收紧；只以精确自有 XHR abort 作为实际故障证据。
- **身份保护**是持续绑定的本地证据，未验证所有 profile、多标签/重启、同 URL 草稿代际；遇到无法确认的情况守住 UNKNOWN，不选另一个目标继续。

## 直接交付给 Pro 的下一步

取本目录 → 跑一次离线回放 → 将输入原语和 normalizer 映射到现有契约 → 在工程已有流程中完成针对实现的 review/验收。沿用本包的明确 NOT_TESTED 项，不能因归档成功将它们改成 PASS。不要为了接入再写另一套扩展、重新做竞品/技术栈研究，或把 fault bridge 作为正式依赖。
