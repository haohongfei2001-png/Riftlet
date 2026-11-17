# 无扩展附件引擎 · 首轮工程交接

## 612 与 613 的普通 App 实测

在已登录的隔离 Edge 临时草稿里，两张不同的 macOS 系统截图通过普通 App 微图各点击一次，实际间隔 398.130 毫秒。两次分别绑定到同一窗口、标签、文档和编辑器。预置图 614 与两个新附件各出现一次，原正文及原位置的 14 字符选区保留，编辑器在前后两次读回时均未聚焦。Riftlet 对两图分别持久记录 START，随后各自触发吞噬。[逐图实测与原始事件](../engineering/universal-attachment/edge-fresh-pair-20261117/README.md)

完整的 68 条 Edge 网络记录保存了两次独立的存储 HTTP 201 和 ETag。ChatGPT 的两个逐文件处理请求均返回 HTTP 200；导出缺少两个响应正文。两笔最终处理仍为 UNKNOWN，组合保留 INCOMPLETE。[逐文件回执](../engineering/universal-attachment/edge-fresh-pair-20261117/product-and-network.json) · [兼容性矩阵](../engineering/universal-attachment/live-matrix.json)

## 607 与 608 的较早快速双图实测

**2026-11-17 快速双图验收。** 普通 App 以 489.789 毫秒间隔收到了两个真实微图点击，各有 10 条回执。607 在原草稿产生首条产品 START 并吞噬，匹配的实际存储写入返回 HTTP 201。608 一次输入后未出现。原草稿显示文件附件数量限制，已有五图、正文和 14 字符选区保留。607 的最终处理和 608 的投递结果均为 UNKNOWN。[逐图实测](../engineering/universal-attachment/edge-native-pair-20261117/README.md)

**2026-11-17 实测更新。** 605 和 606 均经普通 App 的单次微图点击进入同一临时草稿。两笔存储写入都返回 HTTP 201，并独立关联原操作的文件名、服务文件身份与内容长度。606 的原服务响应明确记录 `file.processing.completed`。605 的最终处理响应正文缺失，终态仍为 UNKNOWN。被测包自身记录的 START 和完成均为 0。原正文、14 字符选区、已有三图和两张新增图片均保留，实际点击相隔 439.076 秒。[分项证据](../engineering/universal-attachment/edge-service-pair-20261116/README.md) · [矩阵](../engineering/universal-attachment/live-matrix.json)

## 602 与 603 的较早双图实测

2026-11-16，**普通 Riftlet App 的两次微图点击已把两张不同的系统截图输入同一个隔离 Edge × ChatGPT Temporary 草稿。** 每张截图各有 10 条匹配回执和一次文件输入。两次绑定的进程、窗口、标签、文档、编辑器及草稿均一致，间隔 85.677551 秒。03:39:34Z 的延迟 AX 读回确认原正文、14 字符选区、原附件、首图、第二图全部保留，三张对应图片各 1 个。此次运行使用 G `28538969` 的普通签名包，准入 H `932f278f`。[两图原件及独审](../engineering/universal-attachment/edge-temporary-pair-20261116/README.md)

每张图都出现了归属于原操作的中间进度，首图有 35 个样本覆盖 2%–95%，第二图有 24 个样本覆盖 2%–96%。产品记录中真实 START 为 0，两个操作最终仍为 UNKNOWN。快速连续场景仍待运行。前一天普通草稿配额弹窗后选区变为 0 的失败仍单独保留。PR #69 继续为 Draft。[上传观察和原操作](../engineering/universal-attachment/edge-temporary-pair-20261116/independent-audit.json) · [普通草稿失败](../engineering/universal-attachment/edge-first-input-20261115/README.md)

## 上一普通草稿首图检查点（历史）

2026-11-15 普通草稿检查点：**普通 Riftlet App 已向隔离的 Edge × ChatGPT 原草稿执行首图文件输入；双图验收仍未完成，原选区保留失败。** 运行源码 G `285389696de110f076ba60d2e8a1a6fbe98c6b3e` 与准入 H `932f278f3412fd3158f01907a5a484ac9c235fa2` 仅准入文件不同；实际可执行 SHA-256 为 `39b9cd983441533a75a171fe56432de903a9c16e93cd4d367577cc4fd9aaa894`。首图有 10 条严格匹配的原生／产品回执，99.558958 ms 内完成原目标 pin，captureTarget、validate、begin、chunk、commit 各一次完成。此后 34 次观察均为 inputTriggered，真实 START／完成各 0，原操作 UNKNOWN，不重传。第二张本源码尚未投递，严格 NOT_RUN。[实测、原件与双哈希清单](../engineering/universal-attachment/edge-first-input-20261115/README.md)

服务随后显示原文件的 Library 配额提示；该提示、缩略图及 100% 进度均不足以证明上传开始或完成。诊断工具只关闭归属明确的信息框后，14:13:59Z 独立 AX 读回原正文与 1 张基线仍在，但原 14 字符选区变为 0。**选区保留 FAIL**；额外 AX 关闭是测试诊断操作，不能算无额外步骤通过。丢失的唯一因果尚未确定，不能以当前首图结果宣称双图、冷首击、快速连续或异常场景均通过。旧缺回执和之前两张输入前拒绝的证据仍分别保留。

H 的五项必要 CI 已独立确认全部成功：ARM64／Intel 各 1,444 项，新增 5 项和前增量 4 项均实际执行；原有条件／appearance 跳过保留。托管 Edge 的 -1744／第二图 NOT_RUN 与本机首图实测分开。官方产物 digest 已核对，未下载 ZIP；绿色 CI 不是商业上传成功，也不覆盖后续源码。PR #69 保持 Draft，尚不满足合并或发行条件。[精确 H2 CI 报告](../engineering/universal-attachment/edge-first-input-20261115/ci-verification.json)

## 上一合并绑定预算检查点（历史）

此前检查点：**合并 Edge 文档绑定的 G57d8f0d 新包未完成附件输入。** 构建源码 G `57d8f0dcb9cd17967ab012642378a24b9caff4d8` 与准入 H `a2c54950a410b0d34d49ba522b2d8cb69155690b` 的 1,813 个 native/test/build 文件一致；实际普通 App 可执行文件 SHA-256 为 `2c66bc1ebc64e86c8ddc7276de4dd95433df684a2f87a736b0d0cef813e46972`。两张均有严格匹配的完整 10 条点击链和明确输入前拒绝：首图在最终 `originalSelectionRecheck` 阶段 101.245167 ms、第二图 116.096167 ms，均为 `nativeEventFailed(-1712)`。没有操作、文件输入、START 或完成。[本轮原始证据及检查点](../engineering/universal-attachment/edge-pin-budget-20261115/README.md)

该运行版已将 prepare 与 document pin 合为一次原生 evaluation，150 ms/50 ms 门槛及最终完整身份复核不变。进入最终复核说明前面的合并绑定返回 `bound`，这是源码顺序推断，不能替代完整草稿归属和上传证据。四份点击前后 AX 读回均保留中性正文、14 字符选区和 1 张基线附件；这只覆盖明确输入前拒绝。换包后使用一次产品既有分页显示目标 4/5；旧 UNKNOWN 与 fresh-03 未点，没有消息或自动重传。后续减少重复原生最终读取的优化尚未实测，模型不等于真实通过。新 H 的最终 CI 结果待独立报告，不能沿用旧 H 的绿色结果。

## 上一原生回执检查点（历史）

此前检查点：**普通 App 两张截图的产品级点击回执通过，Edge × ChatGPT 双图上传未通过。** 当前签名运行包来自 H `d23267fe825f9ad2384b35b03db9fe2692485741`，实际可执行文件 SHA-256 已重新核算为 `8f68a1dc1907371271e7a17b90866d1527cac4e48d03ed0a7757f87708b562f9`。fresh-04 与 fresh-05 各投递一次，各收到 2 条 App、7 条原生边界及 1 条选择回执，资产、输入窗口、tag 和事件编号均严格匹配。[完整真实回执、源码/包身份与原始证据](../engineering/universal-attachment/edge-native-receipts-20261115/README.md)

第一张在 `documentEditorPin` 阶段用时 108.945583 ms，随后明确拒绝 `resolveSelection / invalidReply`；第二张进入 `originalSelectionRecheck`，100.515 ms 后明确拒绝 `resolveSelection / nativeEventFailed(-1712)`。这两个原生预算边界不能合并，也不是网页拒绝编辑器的同一原因。两次都未创建持久化操作，当前商业输入、START、完成为零。两次前测中性正文、14 字符选区与一个原附件均在，但没有成功输入后的保留证明。两次间隔约 74 秒，快速连续点击尚未验收。旧两张 UNKNOWN 和未点击的 fresh-03 保留，未重发；旧 `315978e` 丢回执根因仍不追认。

后续源码修复已把 Edge 执行环境准备与文档绑定合成一次原生 evaluation，150 ms 总预算、50 ms 最小剩余门槛和最终完整身份复核不变；模型与新增 XCTest 不等于真实通过，新包尚未运行，不能套用 H 的验收结果。

H 的五项必要 CI 已由独立复核确认全部成功，新增 Edge XCTest 和两资产无标记 AppKit 测试在 ARM64/Intel 实际执行。原有跳过保留；托管 Edge 首图 `-1744`、第二图 NOT_RUN 与本机新两图结果分开记录。官方 artifact hash 已与上传日志交叉核对，本地 ZIP 哈希因下载受阻未重算。后续 Edge 预算修复还需自己的源码与 CI；H 的绿色结果不覆盖未来源码。[CI 原件与范围](../engineering/universal-attachment/edge-native-receipts-20261115/ci/README.md)

## 前一重启检查点（历史）

此前重启续验：**该检查点的 Edge × ChatGPT 双图未通过**。17:46（Asia/Shanghai）重启使原临时包、Profile 和进程身份失效；持久保存的原日志、数据库和图片身份仍在。已从 `c3278c0bea1c03dc8cfc445fd7678a3de3467ae1` 重建独立签名的普通测试 App，可执行文件 SHA-256 为 `d3b8e12c05d989f6b14fa72f1555eedc167ffe10fa77dd71afc0e72ea38ef38e`。新隔离 Profile 已登录；12:16:58Z 的原生读回确认唯一编辑器、中性文字、14 字符选区和一张由官方选择器准备的基线附件。这些仅是验收前置条件。[重启、包身份、逐次点击与保留证据](../engineering/universal-attachment/edge-double-image-20261115/resumption.json)

重启后的 `restart-01` 分别在 12:16:58Z、12:20:10Z 向两张不同资产各投递一对带独立标记的鼠标事件，两次均先确认原 Edge 窗口和各自 Riftlet 输入窗口。有界观察都未取得匹配的 App/window/input/onDown 回执，均为 `UNCONFIRMED_DO_NOT_REPOST`，没有重复投递。第二次投递前中性文字、14 字符选区和基线附件仍在；数据库为 2 资产、0 操作、0 上传开始。两个被动事件 tap 的精确标记匹配为空，不能据此断言事件未到达，标记可能被丢弃。该缺失不能归因于旧会话的 `-1744`：旧首图曾有完整产品链并明确在目标解析前拒绝，另一次无标记的 `browserNotFrontmost` 仍属于同一首图，是独立事件。两次原生回执验证失败；商业输入、上传开始和最终完成均未确认。

用户已明确批准隔离 Edge 的 JavaScript Apple Events 设置及签名测试 App 的 Automation 授权。保留日志中有实际 App 的 `OSStatus 0` 授权回执；它只证明原会话，不能替代新进程的目标绑定。12:00:28Z 的原生菜单读回确认隔离 Edge 的脚本设置已开启。此前的 `REQUESTED_PENDING` 与 `BLOCKED_LOGIN` 保留为历史状态，不是当前阻塞。[早期准备及隔离修复原件](../engineering/universal-attachment/edge-double-image-20261115/preparation.json)

本次新增的 Edge 只读诊断已通过独立源码审查：限定原声明容器，排除整页、历史与辅助区域，记录有界的文字/选区/节点比较和未校准进度属性。修复前四项回归失败；修复后页面及历史观察共 220 项通过、实际 JS→Swift 读取器 9 项通过、独立探针 4 项通过。本机 XCTest 未运行（CLT 缺少 XCTest）；当前 `c3278c0` 的五项既有 CI 成功不能替代新增源码的 CI，也不能证明商业上传。该增量尚未包含在上述运行包中，START/完成和 UNKNOWN 规则未开放。[诊断修复、原始受控日志及独立审查](../engineering/universal-attachment/edge-calibration-20261115/README.md)

续验另发现一个诊断盲点：运行中的旧包仅在正数探针标记存在时记录 App/行鼠标边界，标记缺失时无法区分“未投递”和“投递但失去标记”。新增源码在显式启用开发诊断后也记录无标记的实际事件，保留 `nil`，不伪造身份；发送端精确标记匹配不变。三文件增量独审无阻塞，六种无效标记仍被拒绝，临时构建目录中的整个 App 构建通过（27.09 秒）。已补两资产无标记 `sendEvent` 与显式启用测试，原生执行及最终 CI 尚待记录。这修复了观察能力，**尚未证明两次缺失回执的投递根因已修复**，也不允许重发。[独立增量边界、构建与审查](../engineering/universal-attachment/edge-calibration-20261115/mouse-diagnostic-visibility-followup.json)

最新基线更新至 main `b5a412f6`（已合入 PR #101／#102）。隔离组合包源码 `78309aaf` 的正常启动、严格验签与退出已验证；随后主线的官网／更新源变更未改变 App 构建输入。该包先前记录的商业 Edge 双图为 `BLOCKED_LOGIN / NOT_RUN`，没有 START 或完成；登录状态已由上方 11 月 15 日记录更新。详见 [精确包与入口回执](../engineering/universal-attachment/edge-double-image-20261114/merged-package-and-entry.json)。

> 2026-11-14 主线后续：PR #101 已合入实际 main `5b73c755`；PR #69 正常整合质量修复并保留 Edge 原目标绑定。当前验收范围及旧包边界以 [专项交接](PR69_EDGE_ACCEPTANCE_20261114.md) 为准，商业 Edge 双图仍未完成。


任务开始时的正式产品是 0.3.5 (20)，远端基线为 `280be2f8422ccf6c0864f53b8f83e80552b2ec32`。开发期间主线合入 1.0.0 首次使用与连接检查，本分支先同步了 `bc314340692b1db7246127e4b6fb9dd02a446568`，又同步了正式下载入口 `427c5325` 、官网语言选择 `8a648237` 与内置更新器 `5da42a221fb3e6496585c127e6cf11b8e836840f`。更新器退出期间的点击仍被拒绝。公开版和发行资源由各自的发行任务管理。在 build 18 上曾实测 Chrome 中的两张截图连续进入 ChatGPT 草稿，build 20 沿用那一版附件实现。本次修改了点击绑定，因此历史实测不能证明这个候选版本的首击、吞噬或速度。发布版本与候选版本都只需系统截图后点击微图，发送消息由用户决定。[已发布版本](https://github.com/haohongfei2001-png/Riftlet/releases/tag/v0.3.5-beta.1)

## PR #69 Edge 双图专项的当前范围

普通 App 已接入独立的 Edge Apple Events 执行器，复用原有 WebAttachmentAdapter、TransferCoordinator 和持久化输入意图。点击时保存宿主进程及内核启动时间；路由返回后再次核对最初应用和 session。Chrome/Edge 的同步原生查询和文档绑定共用 150 ms 截止时间，晚到结果被拒绝。独立审查发现的 PR #101 picker 归属修复已按局部差异移入；冻结的 v17 原操作观察资源不变。

此前空 Profile 的真实 ChatGPT 页面要求登录后上传，当次记为 **BLOCKED_LOGIN / NOT_RUN**。当前登录与两项正常授权的状态已由上方记录更新，但普通 App 商业双图仍未通过。Edge 的预览不能借用 Chrome 的 START/完成 profile，页面与原生归一化均拒绝未经校准的状态。新的输入路由、诊断事实或授权成功均不等于商业附件验收通过。

托管 Mac 在源码 `275012e547c2a3f0f6dd98626b47c67a72767011` 的普通 App 上记录了两条完整原资产鼠标链及拒绝回执。原测试整体仍失败：聚合器要求不同事件编号，而发送器使用了 CGEvent 默认编号；本机公开 API 分配实验确认两个默认编号均为零。云端当时没有导出实际编号值，旧 `315978e` 第二张缺失原因也不能追认。发送器随后为每张图显式指定独立编号，并加强接收端逐图匹配；旧失败保留，后续 `c3278c0` 的五项 CI 已成功。[专项报告](PR69_EDGE_ACCEPTANCE_20261114.md)

下文保留此前阶段的研究、原型和尝试历史；其中“Edge 未注册”和“一秒点击预算”描述的是此前源码，不代表本次实现。PR 继续为 Draft，无合并或公开发行。

## 一次点击由谁负责

1. **应用和窗口。** 三种呈放形态继续走同一个鼠标按下或辅助功能调用入口。`ConversationClickRouter` 只调用与前台应用匹配的唯一已接入适配器。Chrome 和 Edge 的 `ApplicationHostAdapter` 按各自的脚本字典解析原进程、内核启动时间、窗口、活动标签和地址。Chrome 保留原来的 `ChromeAppleEventsExecutor`、`ChromeCommandRouting` 和历史 session 编码。未登记的宿主在读取聊天内容或准备文件前就被拒绝。
2. **草稿。** 普通 Chrome 点击同步在原标签上绑定文档、导航、编辑器及其容器。随后初始化 MAIN 页面并检查同一次点击的绑定，原生端在提交前复核当前宿主。活动标签变更、相同 URL 的新文档、原编辑器被替换均不能成为新的接收者。动态重建文件输入仍走既有附件入口发现。延迟选择器回调在实际写入前复核文档仍然可见且处于活动状态，不要求光标位于编辑器。同步点击阶段的原生查询共用一秒截止时间。候选版本真实首击延迟尚未测量。其他服务各有路由和界面选择规则；只读探针复核原文本、选区、原附件节点与文档，只向宿主返回枚举和计数。未得到服务真实样本的特征仍待校准。Edge 的原生读路径可组合这些探针，读回值不授予写入权。
3. **传输。** 编译期的 `AttachmentTransport` 接口将一次文件交付和其返回值配对，供 AX/WK 原型使用。正式截图仍走 `TransferCoordinator → WebAttachmentAdapter → ChromeAppleEventsExecutor`，沿用既有持久化意图、`TargetLease`、文件来源验证和独立输入回执。`NativeMacVerifiedFile` 复用打开的目录与文件描述符、inode 与哈希核验。供 WebKit 使用的 URL 仍有从返回 URL 到接收方实际打开文件之间的竞争窗口，原型在自有临时目录和回环服务器上核实实际到达的字节。
4. **状态。** 输入或选中行只代表尝试。已有产品的 `attachmentAccepted` 表示当前文件在原 ChatGPT 草稿出现了应用归属的接收迹象；它不会记录服务器已经收到字节。普通产品在 START 后停止管理该上传。新增服务需要标定自己的 START、最终确认和明确失败，不能借用 Chrome 的 profile 或用占位图触发吞噬。回环实验用不同的观测记录第一个正文字节、完整文件以及原草稿收到确认。失去确认保留 UNKNOWN，下一张图片可独立发起；超时、窗口关闭和进程退出都不会触发自动重传。

## 真实商业服务兼容性

表中每个格子表示**本分支经 Riftlet 实际点击并附加至对应商业服务**的结果。N 表示 NOT_RUN，I 表示已运行且仍有关键验收项未确认。各格的前台宿主、窗口及草稿、附件入口、指定图片、文本选区及原附件、START、最终状态、失败及 UNKNOWN、连续附加、额外操作十项都有独立字段。[32 个组合的逐项记录](../engineering/universal-attachment/live-matrix.json)

| 本机宿主 | ChatGPT | Claude | Gemini | Perplexity | Poe | 本轮可核实的宿主证据 |
| --- | --- | --- | --- | --- | --- | --- |
| Google Chrome 157.0.8103.51 | N | N | N | N | N | 发现三个运行实例；既有真实草稿证据限于较早版本 |
| Safari 27.0 | N | N | N | N | N | 已安装，本机采样时未运行；字典声明当前标签和索引，无标签类稳定 ID |
| Microsoft Edge 156.0.4314.58 | I | N | N | N | N | Temporary 草稿两张截图各输入一次，正文、选区、原附件及两图保留。START／最终完成未确认。另有普通草稿选区丢失记录 |
| Firefox | N | N | N | N | N | LaunchServices、运行列表与常用目录均未找到 |
| Brave | N | N | N | N | N | 同上 |
| Arc | N | N | N | N | N | 同上 |

| 原生目标 | 本轮真实草稿 | 本机观测 |
| --- | --- | --- |
| ChatGPT for Mac | NOT_RUN | 未发现 `com.openai.chat`；名为 ChatGPT 的现装应用实际为 `com.openai.codex` 26.1106.51428 (26605)，AX 核实后台进程拥有一个窗口。没有读取草稿内容或操作该窗口。 |
| Claude Desktop | NOT_RUN | 未发现登记、运行或安装的 `com.anthropic.claudefordesktop`。 |

此前内置浏览器未能建立专用 ChatGPT 测试草稿，访问 Claude 和 Gemini 时报告 IAB 不可用，后者在导航前就已停止；其余组合没有被后续 Edge 准备工作追认为通过。没有向商业服务发送测试消息，也没有使用个人浏览器会话绕过访问限制。已安装、已登录、允许自动化和能够证明目标草稿是不同事实。某服务的未执行不表示该产品无法支持。[宿主清单与复现命令](../engineering/universal-attachment/hosts/README.md) · [ChatGPT 标识应用的 AX 记录](../engineering/universal-attachment/native/installed-chatgpt-host.json)

## 可复现的原型结果

| 场景 | 直接验证的结果 | 范围 |
| --- | --- | --- |
| Edge 独立无窗口实例 | 服务器核实四次请求的图像字节。两次 201、一次明确 422、一次服务端收图后丢失回执，重复请求为零。另一个操作可成功；保留原文、反向选区及原附件节点。 | 测试网页主动运行同一交付程序。本机未证明 Apple Events 已送达 Edge；更未证明 Edge × ChatGPT。 |
| macOS 原生 WebKit | 两次实际文件选择代理回调、两个不同 PNG 的完整字节、两次草稿确认。未聚焦编辑器的文字、选区及第三张原有 PNG 均保留。拒绝同内容 inode 替换和重复交付。 | 自有非持久 WKWebView 的公开代理接口，窗口未显示；外部 Safari/原生 App 的代理由对应应用拥有。 |
| 五个对话表面 | 在真实 WebKit 引擎上分别运行五种服务形态的受控 HTML，覆盖多文档、相同地址、导航离开再返回、编辑器重建、焦点、已有附件和歧义入口。 | 静态服务特征尚未在对应账号草稿上认证。 |
| 外部 AX 与系统文件面板 | 托管 Mac 探针分别测试受控 AppKit 文件列表和真正的 NSOpenPanel。只有相同进程/窗口、唯一原草稿与可核验选中 URL 同时成立，才允许最终操作。 | 首轮托管 Mac 的两个探针均因无法核实接收进程的前台身份而停止，零文件提交。后续改用 LaunchServices 启动独立签名的测试宿主，并核实实际前台进程、启动时间和关键窗口；在 macOS 15.8.2 上，第二轮成功找到原草稿并按下附件入口，自有文件列表仍未证明文件选择，系统面板查询返回 `-25204`，两种路径均未提交图像。第三轮已核实自有文件列表的目标行和干扰行，在提交前拒绝，现有日志无法区分是在按下目标行之前还是之后；系统面板仍无法证明属于原窗口，均未产生文件交付。随后的分阶段诊断证实，此测试文件行未向外部进程提供 `AXPress`，因此该次在选择之前拒绝。自有应用可以显式实现 AppKit 的辅助功能按钮动作；本机两个不激活窗口的独立进程已验证一次选择与一次确认，接收端按原操作标记和 69 字节中性 PNG 的哈希给出回执。跨应用可行性取决于目标应用公开的操作。在随后的一次托管 macOS 15.8.2 实测，外部 AX 进程在有干扰文件的自有文件列表选中指定 PNG，回环服务器确认首字节和完整文件，原草稿确认接收且保留文字、选区和原附件。系统 NSOpenPanel 仍无法证明属于原窗口，实测零次传输。[托管结果、源码与产物摘要](../engineering/universal-attachment/hosted-macos-results.json)XPC 面板或无法证明的行必须单独记为未验证。 |
| 系统剪贴板 | 继续使用独立命名板测试 NSPasteboard 的实际读写、完整多类型快照、所有者标记、changeCount 和外部复制后放弃恢复。 | 其他进程可能在检查与写入之间复制，AppKit 未提供跨进程原子比较与写入。一般剪贴板不作为普通点击备用路径。 |

运行真实 macOS 检查使用 `bash Tests/ConversationSurfaceHost/run.sh`、`python3 -B Tests/UniversalNativePickerHost/run.py`、`python3 -B engineering/universal-attachment/edge/verify.py --mode headless`。Chrome/Swift/XCTest 随正式 Native ARM64/Intel 工作流运行。Safari 和 Edge 的前台实验只在临时托管 Mac 上执行。托管 Mac 上，Safari 与 Edge 的 Apple Events 被动授权预检均返回 `-1744`（需要用户同意），因此没有向目标草稿执行脚本。macOS 15 的 WebKit 缺少该表面探针要求的 Navigation API，测试确认了拒绝；同机独立 WK 文件交付仍完成了两次接收。脚本使用中性生成图片、临时文件夹、独立 Profile 或非持久数据，浏览器只接触自有测试页。[Edge 实验](../engineering/universal-attachment/edge/README.md) · [WebKit 日志](../engineering/universal-attachment/surface/run.json) · [原生文件交付](../Tests/UniversalNativePickerHost/README.md)

## 权限及发行

- 官网 Developer ID 渠道沿用 Apple Events entitlement。本轮对隔离签名的 Riftlet Product Test 请求控制 Edge，并依用户明确批准启用隔离 Edge 的原生脚本设置；没有修改 TCC 数据库、当前公开安装包或签名更新源。每个接收方都要验证实际 Automation 授权和浏览器 JavaScript 开关，开发工具或旧进程的授权记录不能替代当前安装包/接收进程的检查。[Apple Event 权限](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events)
- AX 辅助功能授权用于读取或操作其他进程的界面。该授权本身无法证明选中的草稿、面板或文件；探针仅被动检查现有授权。普通系统截图文件收录使用既有目录访问与书签。内置屏幕捕获按原流程处理录屏权限。新适配器没有为识别窗口增加录屏权限。[辅助功能信任检查](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions) · [安全作用域书签](https://developer.apple.com/documentation/foundation/nsurl/bookmarkcreationoptions/withsecurityscope)
- Mac App Store 要求 App Sandbox。目标须提供适用的 scripting access group，否则发送 Apple Events 通常要逐目标申请临时例外并说明理由。现有 Developer ID entitlement 不能证明沙箱外部 AX、跨 App 文件访问或商店审核通过。后续应使用单独的沙箱测试包验证授权、重新启动后的书签解析和失权时的降级。[App Sandbox](https://developer.apple.com/documentation/security/app-sandbox) · [Apple Events 沙箱例外](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html)

## 早期原型与投递尝试（历史）

本节保留此前源码的阶段结果，包括当时尚未注册 Edge 的限制和旧 ARM64 失败；不能覆盖上方当前状态，也不能解释另一轮缺失回执。

在隔离的托管 macOS 上，普通 Riftlet 1.0.1 (23) 已确认前台 Edge 的进程启动时间、可执行文件及中性测试窗口。两张不同的系统截图都带有 macOS 截图标记，普通 App 的队列也按各自 SHA-256 收录了两条记录。外部辅助功能探针在 14 秒内未能唯一定位第一枚可按下的微图，实际点击为零。该次测试使用的版本没有向外部探针提供微图与输入窗口的对应关系。[分阶段实测及原始产物](../engineering/universal-attachment/acceptance-20261114.json)

本轮复核普通 App 的注册表后确认，Edge 目前只能检查草稿。即使准备好已登录的 Edge 会话，现有微图入口也无法向它交付图片。Chrome 是当前唯一注册的宿主，本轮隔离浏览器超时，未能建立已登录的专用草稿。两张图片的点击、START 和最终完成分别保留为未执行。[逐图验收记录](../engineering/universal-attachment/acceptance-20261114.json)

在后续五项 CI 通过的托管实测中，普通 App 已导出两枚微图映射，第一枚的输入窗口属主和区域通过预检，首次 AppKit 鼠标窗口查询返回零，外部探针因此记录零点击。同一隔离回环页随后报告原文字、选区和已有图片仍在，独立 Edge 候选的 Automation 预检返回 `-1744`，零文件提交。此轮外部 AppKit 文件列表经新的传输接口完成了选取、提交、接收首字节、完整文件和原草稿回执；系统文件面板仍缺少原窗口归属证明。

本机针对同一组自有窗口和同两个点的双进程对照，复现了未初始化 `NSApplication` 时全部返回零、初始化并保持禁止激活后正确返回输入窗。两个进程均未发送鼠标事件。随后托管探针在第一图返回 `eventDeliveryUnconfirmed`，记录零点击。这个旧枚举同时覆盖禁止激活初始化检查和首个接收者匹配后的窗口矩形重叠检查，日志无法区分。探针现将初始化失败单独报告，并保留系统首个实际鼠标接收窗口、精确属主和几何复核，删除透明窗口矩形造成的额外否决。新一轮托管检查已匹配第一枚微图的真实首个鼠标接收窗口，外部进程投递了一次软件鼠标按下/抬起。完整 App 选择与拒绝回执在观察期限内未确认，因此本轮明确失败，第二图和独立选择器未启动。该轮没有区分缺失条件。下一轮加入只读聚合后，确认有界日志中选择、目标请求、目标解析和拒绝事件均为零，App 和原 Edge 窗口仍存活，两条截图队列仍与导入时完全相同且为可见待处理状态。数据库操作、上传开始、页面文件变更和 POST 均为零。首图投递是否进入原选择回调仍未确认，第二图与候选选择器均未运行。ARM64 验收保留失败结果。

开发包现可用双开关记录已解码、可点击微图所属的原输入窗口及 2×2 点区域。托管 Mac 探针用两张不同截图逐次核对系统在该点选定的首个鼠标接收窗口，再给鼠标事件加独立标记，从 App 读回同一标记、窗口和资产的回执。受控 Edge 文件选择实验另行记录原生标签、AX 编辑器、原附件、选中 URL 和接收端事件。探针只对一次性回环草稿开放文件输入。

Edge 商业验收的下一步是在普通 App 接入已验证的单次文件交付，并取得隔离且已获授权的登录环境。然后用包含中性文字、选区和已有附件的专用 ChatGPT 草稿，从实际微图连续操作两张不同截图，分别观测真实上传开始和最终确认，保留未发送状态。Safari 需先验证两同址标签切换、标签移位及重建时仍能复核原文档。Claude、Gemini 依次从已绑定的精确草稿采集脱敏的真实状态，只在能排除错投、重放、伪 START、文字/选区丢失时注册对应路由。对未安装的客户端先取得独立安装环境和受支持公开接口，再运行同一组验收。当前没有公开发行或主线合并操作。

## 当前验收边界与续验

当前运行包构建源码为 G `57d8f0d`、对应准入 H `a2c5495`；已合并的原生绑定仍在两次最终原选择复核中以 `-1712` 拒绝，没有文件输入。新 H 的最终 CI 待独立记录；后续减少重复原生读取的源码不在此运行包验收内。早期源码 `18d6189`、准入头 `f26694d` 和执行对象 `04ceda0` 的九次托管尝试保存在[原失败档案](../engineering/universal-attachment/acceptance-20261114.json)，不会被新结果覆盖。

1. 保留 `restart-01` 的 UNKNOWN 原投递，不自动重发。历史 `calibration-01` 两图分别在文档绑定/最终复核拒绝；最新 `pinbudget-01` 两图均在最终复核拒绝。各自保留完整原回执，不从受控性能模型推断商业成功。
2. 对后续真实点击分别取得普通 App 接收、点击时原进程/窗口/标签/文档/草稿、一次输入、真实 START 和最终完成证据。基线附件、进度 100、ready 属性及加载完成图片都不能单独证明商业上传完成。
3. 连续双图、快速点击、点击后切换标签、Edge 无响应、明确拒绝、文字/选区/已有附件保留仍须分别实测。新诊断只提供观察事实，无法代替这些验收，也不解除 UNKNOWN 的禁止重传。
4. 新增源码形成最终 checkpoint 后执行必要 ARM64/Intel/Feedback CI，并核对精确签名运行包。PR #69 保持 Draft，未满足合并或发行条件。

不明投递只可在原操作上观察。早期已经结束的托管作业现场不可再次观察，旧记录不能补认成功；这不指当前本机隔离会话。后续独立的全新托管作业使用新的空数据目录和新生成图片。当前商业组合的验收通过数为零。
