# 冷首击可靠性：可恢复预绑定缺陷与零证明边界

独立技术分支 `codex/riftlet-cold-click-reliability-20261029`，基于正式 PR #15
`c15fd4b4a27659946ef49280131e875f4d5ab9d1`。本轮未修改正式分支、PR #15 或 main。
已审源码：`c308d46c1412a56e90d665972c0bc8f6ad1511a3`。独立审查、CI 与最终交接以同目录
`results.json` 的精确记录为准。

## 产品结果

- **已修复、受控真实浏览器 PASS**：一个从未输入图片的有效页面，在失焦／返回后不再永久耗尽
  32 个 input lease。旧版在相同真实 Chromium 回归中报 `LEASE_GENERATION_LIMIT`；新版 40 次往返
  保留一个空状态，每次仍生成新的完整目标，旧目标始终不能输入。
- **已修复、源码独立审查 PASS**：旧 host epoch／Chrome 接收者的异步权限结果不能撤销新 ACK，
  旧 grant 也不能批准过期选择。没有执行页面 capture 的过期检查不再被误当作页面捕获失败。
  每个调用者仍执行自己的真实权限检查；没有缓存 grant 或借用另一个调用者的 grant。
- **提前观察**：截图已持久收录时，先请求现有预绑定，再执行预览与多次异步刷新。
  这只是更早开始观察，没有创造点击资格，也没有保存点击等待将来的 ACK。
- **仍未解决**：原鼠标事件早于任何完整可信 ACK 时，仍安全拒绝。本轮没有把正常页面可见、
  浏览器前台、迟到 ACK 或事件处理器执行时间当作原点击时的完整目标证明。
- **新的真实附加闭环 NOT_RUN**：本机 CLI／Swift 可用，但现有 Chrome tab 控制超时，原生 Chrome
  接口返回 `-10005 timeoutReached`。本轮没有生成并点击新的系统截图、没有真实 ChatGPT 输入，
  没有要求创始人提前体验 Beta。人工物理鼠标同样 NOT_RUN。

## 既有失败的因果边界

以下均为保留的历史真实证据，**不是本轮的新测量**。

| 原样本 | 完整 native ACK 晚于原点击 | App 发布 ACK 晚于原点击 | 可支持的结论 |
|---|---:|---:|---|
| 第六轮 | 6.365 ms | 7.247 ms | 原事件没有完整 ACK |
| 第七轮 | 26.323 ms | 26.742 ms | native → App 约 0.419 ms，不能归因于主线程长时间阻塞 |
| 第九轮 | 208.687 ms | 209.412 ms | v13 兼容已工作，但该原事件仍早于完整证明 |

原始脱敏出处：
[第六轮](../2026-10-27-real-mac-round6/cold-click-analysis.md)、
[第七轮](../2026-10-27-real-mac-round7/cold-analysis.md)、
[第九轮](../2026-10-28-real-mac-round9/cold-and-monitor.json)。

本轮区分三类：

1. **A：正常可恢复观察**。32 代空 lease 和权限乱序撤销是实际可修复缺陷。
   受控 Chromium 的 iframe↔顶层真实 focus 事件证明页面实现；它不等同于 macOS 应用切换。
2. **B：native ACK 已完整、App 尚未发布**。当前 authority 仍采用真实 MainActor 发布时刻。
   历史样本这段仅约 0.4–0.9 ms。未发现足以用回填时间替代发布规则的证据，未改动该规则。
3. **C：原点击确实没有完整目标证明**。传输查询与系统事件异步，且点击可以先于首次查询完成。
   提前观察只能缩小窗口，不能为已经发生的无证明事件建立追溯身份。此类点击不等待、不重放。

## 最小实现与反例

页面 v13 保持同一版本及全部原 monitor 协议。仅当原 state 的 input lease 已撤销、operation
数量为零、业务连续性仍有效、composer 唯一可用、当前页面有焦点且 native context 完全一致时，
才在原空 state 中发出一个**新 target 对象**。新 document/draft input generation 不能改变原
logical draft 连续性，更不能解锁任何旧 UNKNOWN。任意 `begin`，即使尚未 commit，也排除该路径。
已经存在操作的 state 永不回收、清除或重写，仍按旧身份只读观察。

新的 lease 必须重新经过正常完整 native capture 和 App 发布。此前返回的 target 对象不被原地
修改，`validate`／`begin` 使用旧 target 均拒绝。没有 renewal 方法的旧 v13 闭包仍走原有保守
安装流程；已耗尽 32 个、含原操作或不可证明连续性的老页面不会被本轮代码强制修复。

原生 `AutomationPermissionPublication` 将每次实际检查绑定 host epoch、当时 foreground 和
明确 receiver。晚到失败不能清除新 ACK，晚到 grant 不能越过较新的 denial。两次同域、各自实际
返回 grant 的检查允许完成顺序不同，避免把正常并发检查误当成权限丢失。

`targetDisposition` 只有在没有进行页面 capture、原 epoch 和前台 session 不变、原 ACK 确实存在
时才保留该 ACK；不改其时间。真实页面 capture 失败、错接收者或无 ACK 仍拒绝。实际当前权限丢失
先按原机制清除 authority／撤销选择，不能被 retain 分支恢复。

确定性反例包括：旧目标／错 native context、modal、失去 root descriptor、多个 composer、业务
A→B→A、已 begin 未 commit、原 UNKNOWN、旧版闭包、较新 denial／旧 grant、foreground 改变、
Chrome 重启 session、终止、原事件早于 ACK、ACK 在按住期间到达及后来目标替换。

## 本轮验证范围

| 项目 | 结果与边界 |
|---|---|
| 页面 VM 回归 | PASS，97；原旧版本只读观察回归 PASS，61 |
| 真实 Chromium | PASS，Playwright 1.62.1 + 匹配 Chromium 151.0.7922.34，5 组；全部离线合成 fixture |
| 基线对照 | 同一 Chromium runner 加载 c15 原页面，准确复现空 lease 耗尽；零真实上传 |
| 原生编译 | 本地 `swift build --target RiftletApp` PASS；完整 release App 与 CI 均 PASS |
| AppKit 原事件 | 4 个构造 NSEvent 直接调用真实 input island 的回归；CI PASS，原日志可复核 |
| 权限乱序 | 11 个确定性 policy＋真实调用接口回归；CI PASS，原日志可复核，不是系统 TCC 撤权验收 |
| 真正冷首击／新系统截图／实际附加与快吞噬 | NOT_RUN；现有 UI 控制接口超时，零真实输入 |
| 人工鼠标、WindowServer 路由、Spaces／多屏 | NOT_RUN；不把构造 NSEvent、AX 或 headless 点击冒充人工 |

本地 macOS 27.0（26A428）、arm64、Swift 6.4、Command Line Tools；`xcrun --find xctest`
明确不可用。完整 XCTest 在 GitHub macOS runner 执行。专用 workflow 构建完整 App、运行原完整
Swift suite、原生冷边界明细、页面及旧观察回归、离线真实 Chromium，并执行四个原有打包 self-check。
原正式 workflow 和固定 source gate 均未改写；独立 gate 执行固定 Git blob，只允许本轮明确文件。
它只证明独立技术树一致，不授予 PR #15 集成或任何生产准入。

浏览器 fixture 保留非空正文、非折叠选区、旧附件原 DOM 对象，编辑器未聚焦；新合成 File 的
begin/chunk/commit/change 各一次，重复 commit 拒绝，提交消息零次。React ancestry 明确是 fixture，
没有验证现网 ChatGPT 的当前 React 形态，也没有伪造 uploadStarted／attached。

## 无扩展裁决

保留[第八轮独立扩展实验](../2026-10-28-real-mac-round8/extension-lab/README.md)，不安装扩展或
新增 Native Messaging host。该实验已明确 `inputAuthority: false`；本轮不重复建设另一条桥。
扩展的推送可能更早提供页面事实，但不能单靠 browser document ID 替代业务草稿身份，也不能
保证原点击早于首次 proof／晚到 invalidation 时的安全性。

官方机制依据：Chrome 的 [content scripts](https://developer.chrome.com/docs/extensions/develop/concepts/content-scripts)
在 document_start 可以先于 DOM 完整出现；[Native Messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging)
仍需要消息传递及本机 host 注册；[service worker 生命周期](https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle)
允许停止和重启。由此推断，仅换消息通道不能保证 C 类事件已有唯一完整目标证明。默认无扩展路线
保留；本轮不以持续调整计时器、扩大权限或延迟重放掩盖这个限制。

## 数据、审查与交接

本轮只读审计三个既有 SQLite v3 数据根，基线共有 32 个历史操作、7 个 upload_starts、
3 个补偿记录、50 个私有媒体文件。原图、媒体、原操作、UNKNOWN、锁、补偿和审计均保留；
私有快照仅留本机，公开不含路径、会话、截图、正文、目标完整身份或原始日志。
基线私有 manifest SHA-256：`e33565b7ad34ec7c29d705f263fe3c7f4758d3b1a0bfa7237caaeb9525be40ec`。
最终三个数据根的全部表计数及逐行规范化内容哈希、50 个媒体的字节哈希全部相等（PASS），见 results.json。
未启动旧 schema 二进制、未重传、未清库。

页面修改由 native/browser 方向非作者审查，权限修改由页面方向非作者审查；CI／范围 gate 的
审查建议已落实为固定 blob 执行、净化 Git 环境和有界下载。完整精确源码 review pin 与 CI
记录在 results.json。正式负责人应在其独立集成时重新审查 Main 差异及正式 composition pin，
不能直接将本技术分支 gate 当作正式集成批准。

下一项有价值的真实验证是：在 UI 控制恢复且只有一个输入所有者时，用**全新**系统截图与有效
独立草稿检查截图触发的预绑定／一次输入／真实开始／独立完成，并保留原 click 与 ACK 的因果
时序。不要重传任何历史操作；不要把本轮受控页面 PASS 宣称为真实 cold-first-click PASS。

## 完整 CI 与准确交接

[Cold click reliability 40881144683](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40881144683)
首次执行 SUCCESS。CI checkout 为 `3611a5f7545268893596ff43d046373d128c9f88`，相对受审源码
`c308d46c1412a56e90d665972c0bc8f6ad1511a3` 仅有三份明确元数据变更。

- macOS 15.7.9／arm64／Swift 6.1.2；完整 Swift suite 760 项编号执行通过，专项串行 63 项通过，
  其中原生权限 11 项及构造 NSEvent 时间边界 4 项均逐例 PASS。专项重复运行不累计为更多唯一用例。
- 页面 97、旧观察 61、真实离线 Chromium 5 组通过。完整 release App、原四个 synthetic self-check
  通过；没有把其中的生成图片“软件输入”写成真实系统截图或 ChatGPT 输入。
- source job `123472664044`：9 项独立来源检查、原正式隔离回归 24 项通过。
  native job `123472664424`：实际浏览器版本 151.0.7922.34，匹配固定 Playwright 1.62.1。
- 原制品 `12900233034` 已下载，外包 digest 匹配 GitHub 记录。内部原
  `Riftlet-Cold-Click-Technical.zip` 为 1,970,756 bytes，SHA-256
  `68f554e9612ce49a0739340ce4eae46da244f411b8ba6c8f424b783a8f047bee`。
  包内资源检查、严格签名校验及实际 arm64 Mach-O 均通过；未重打包、未安装到用户目录、未启动它操作旧数据。
  这是 development/ad-hoc 技术制品，未公证。本增量未重新执行 Intel 架构或整套视觉影片验收。

Pro 可直接以已审源码提交及本分支后继证据作集成输入。实际生产只修改三个文件：页面程序、Main 的
权限结果归属／更早观察接线，以及新权限发布策略。Core、UI、Capture、SQLite、原队列、来源准入、
上传开始／完成判据、安全失败和重试保护保持原对象。对应 native/page/browser 回归应一并保留。
独立 workflow／scope checker 不替代正式 PR #15 的来源门禁；正式负责人决定其集成方式并重新固定
正式 review pin。本轮最后的 evidence-only 提交不重跑相同 CI，也不冒称它有新的运行结果。

非作者已再次检查原 CI ZIP、14 个解包文件、包内新旧页面精确源码 hash、全部测试日志及
GitHub 实际 job/step 状态（PASS）。没有 skipped step；760 项编号执行完整覆盖，专项 63 项
逐例通过。审查期间没有启动 App 或接触用户页面／数据库。
