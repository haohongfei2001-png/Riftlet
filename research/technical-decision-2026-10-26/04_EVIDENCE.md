# 本轮实际证据：Oracle 离线反例

## 1. 证据范围

**VERIFIED — OFFLINE FIXTURE ONLY。**

本轮在 Linux / Node v24.22.1 实际执行了随包脚本。没有打开浏览器或 macOS，没有网络上传，没有真实聊天、截图、凭据或第三方账号。

使用 steipete/oracle 固定提交 fde96271db1611c0287fcfde3053c19325280d10：

- 原 attachmentEvidence、attachmentProgress、composerRoot 表达式生成函数；
- attachments.ts 中原 buildAttachmentNamePattern 与完整 waitForAttachmentCompletion；
- 上游原 tests/browser/domFixture.ts；
- 原 INPUT_SELECTORS 与 SEND_BUTTON_SELECTORS。

加载过程只进行 TypeScript 转译、去除 import/export 包装及注入依赖。判断分支保持原样；虚拟 Runtime.evaluate 将表达式交给原 FakeDOM，假时钟让等待确定地前进。没有通过修改被测函数制造输出。

原始文件准确字节与固定 Git blob SHA 已逐项核对；source-index.json 同时记录 SHA-256。源码最初保存时多出的一个末尾换行已经移除，包内七文件均 exactPinnedBytesVerified=true。

## 2. 复现

从本资料包根目录执行：

~~~sh
node evidence/oracle/offline-adversarial.mjs
~~~

无需 npm install。需要提供 node:module.stripTypeScriptTypes 的 Node；本次用 v24.22.1。该内置 API 可能打印 experimental warning，不影响本次结果。

输出：

- 标准输出 JSON；
- evidence/oracle/offline-adversarial-results.json。

结果中的 elapsedSimulatedMs 是假时钟累计值，**不是实际上传延迟或真实性能测量**。重新运行只改写这份本地结果 JSON。

## 3. 四个反例

| Case ID | 构造 | 原函数观测结果 | 可以证明什么 |
| --- | --- | --- | --- |
| unique_unrelated_card_claimed_for_requested_asset | begin(wanted.png)，随后只加 unrelated-user-added.png 的 removal control，再 confirm | confirmed=true；wantedReportedPresent=true；requestedAssetWasInserted=false | 附件证据 claim 不核对新增 control 与期望文件身份；这是 PRESENT 身份反例，不是整条 READY 流程 |
| file_input_only_no_card_no_send_button | input.files 中有 wanted.png；无卡片；无 send button | completion 返回；模拟 1750 ms，8 次观察 | 原完成函数有仅凭 input 名称与按钮缺失继续的路径 |
| explicit_error_card_send_enabled | 有 wanted 卡片，合成 data-state=error；send 可用 | completion 返回；模拟 2000 ms，5 次观察 | 进度／完成函数没有识别该合成错误标记 |
| card_exists_send_button_absent_no_ready_signal | 有 wanted 卡片；无 send button；无额外正向状态 | completion 返回；模拟 0 ms，1 次观察 | 卡片存在且按钮缺失会直接完成 |

第三项的 Case ID 沿用实验命名；它不是已从真实 ChatGPT 采集到的 error markup。所有 fixture 都是假设输入，用于检验源码逻辑强度。

## 4. 对应源码位置

- attachmentEvidence.ts 69–82：新增 removal control 数量为一时认领；没有校验它是否为期望文件。
- attachmentProgress.ts：主要检查 loading／uploading／pending、aria-busy、进度元素；没有可直接继承的正向 READY 语义。
- attachments.ts 1764–1765：卡片有证据但 send 状态 missing 时直接 return。
- attachments.ts 1798–1817：input-only 且 send missing 的稳定等待分支。
- attachments.ts 1457–1827：被提取执行的整个完成函数。

固定链接可从 source-index.json 中直接打开；上游 MIT LICENSE 随源码保留。

## 5. 允许与不允许的结论

允许：

> 这些源码条件不足以直接承担 Riftlet 对特定图片、原草稿和正向 READY 的严格成功契约。原实现可以作为机制参考，但必须重新定义身份认领与成功判据。

不允许：

- “当前 ChatGPT 有四个已验证上传 bug。”
- “Oracle 完整上传管线一定误判。”
- “所有 input.files 方法不能上传。”
- “浏览器扩展已经通过真实验证。”
- “Mac 客户端因为缺少 GUI 工具所以无法实现。”

## 6. 其它证据分类

| 事项 | 当前状态 |
| --- | --- |
| 已读九份 Riftlet 正式基线材料，固定 main，交付前再次核对 | SOURCE-VERIFIED |
| Chromium 指定 tab 的 isolated-world AppleScript 执行 | SOURCE-VERIFIED |
| Native Messaging 限额、activeTab 手势、documentId 与 worker 生命周期 | 官方文档证据；本轮没有运行扩展 |
| Oracle 拒绝 Work、DataTransfer 输入、completion 分支 | SOURCE-VERIFIED |
| OpenAI Codex prepare／PUT／finalize 代码 | SOURCE-VERIFIED；未运行其 mock tests 或真实接口 |
| 官方 MCP send:false 与 entrypoint target 语义 | SOURCE-VERIFIED＋官方文档；本轮没有初始化真实插件 view |
| 本包推荐架构、UUID 输入身份、共享网页 adapter、透明画布 | INFERRED；等待具体真机验证 |
| 当前 ChatGPT Web 的 INPUT／IDENTITY／READY | NOT_TESTED |
| 新版／Classic Mac 的 INPUT／IDENTITY／READY | NOT_TESTED；本轮真实 Mac GUI 环境 BLOCKED |
| 自身截图排除、首次点击焦点、全屏穿透、多屏与资源消耗 | NOT_TESTED；Apple DTS 的平台案例仅作为官方工程师报告引用 |

没有把之前 Codex 文档里的“最小 Swift 已编译”升级成当前目标附件已成功；之前的测试工具限制也未被升级成产品不可行结论。
