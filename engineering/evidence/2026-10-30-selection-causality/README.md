# 双截图成果交接与选区折叠定向诊断

2026-10-30。**证据正式交接 PASS；真实选区因果对照 BLOCKED，生产修复未实施。** 不重复上一轮两张成功附件，不将诊断用例称为真实产品验收。

## 已完成交接

重新读取 PR #1 `edbdc7aae45c35878694e9fa376757dac7b630a8` 与 PR #15 `bf3b97a432f65451c1b4232035e25c9d42b21523`，均未变化。原证据提交 `7d4d87223c135cbea23d6e0da06a91d2210bf1b1`、持久私有档案的45份摘要，以及两张系统原图/私有媒体hash全部复核一致。

仅将原五份脱敏证据以 `cherry-pick -x` 接到原自然首击分支：`74f25bd1ac1d161cec7948c5904775427891ada5`，父节点 `fcfd86780d1fe3e993caa23ad02d2fceeadf8954`。Git HTTPS在有界等待内失败；通过可用的GitHub Git Data API逐blob/tree/commit核对与本地Git对象完全一致，`force:false`快进原分支，读回精确SHA与父节点。未改PR #1/#15/main。见 [handoff-verification.json](handoff-verification.json)。

注意：自然首击分支保留其历史源码；以上是证据接续，**不代表该旧源码已经成为最新统一App**。实际双截图执行源仍为edbdc7aa的正式CI包。本轮没有运行旧分支App，也没有重复CI或上传图片。

## 选区问题当前结论

上一轮trial3的非折叠8..15最终变成0..0，正文、旧附件和完成状态保留。这是已观察的交互FAIL，但其原事件记录不足以区分：原生点击、文件setter/change、React节点替换、后续用户或窗口交互。

源码审查显示原生面板不激活、不能成为key/main，输入view拒绝first responder；页面commit调用files setter及change，没有focus或选区恢复。**没有直接证据支持某一层为根因，也没有证据证明ChatGPT自身不可避免。** 不添加强制focus、延迟恢复Range、正文重写或跨草稿恢复。

需要注意原试验的选区是DOM Range准备的，不等同于真实键盘/鼠标改变后编辑器内部选区状态已同步；这只是待检验的可能性，不是已证实根因。

## 本轮现场的准确停止位置

- 原成功试验标签已不存在。仅创建自己的新测试标签，未占用或重载其他任务标签。
- CUA创建/绑定两次分别在30秒/20秒超时；原生AE仍能读取新测试标签，不能把CUA超时称为Chrome完全断连。
- 通过固定接收进程、window/tab ID及只读检查确认：原测试配置中的新标签是空的普通已有聊天，但持续报告hidden，且目标窗口不是当前可见窗口。原生选择tab/窗口前移后仍未取得可见前台页面，未放宽visibility或目标条件。
- 有界建立一个独立窗口作替代，原测试聊天导航重定向到Home。第一次发现已有非空草稿，未改写；稍后只读取样变为空草稿，但仍是Home、不是受支持的持久聊天。状态改变原因未定，不归因于其他任务。本轮没有输入正文或附件，没有发送消息，没有接受新权限、修改配置或登录账户。
- 未在上述不合格环境安装页面观察器或运行候选App。**本轮新增真实上传0，原生手动附加对照0；五段实时因果链均NOT_RUN。** 未重输旧图片或UNKNOWN，原双截图成功证据不变。

恢复条件是：一个明确独占、可见前台、已授权且独立的普通持久测试草稿。不能仅因Home可输入就扩张候选准入，也不能覆盖其中既有正文来制造空测试环境。

## 最小可执行诊断工具

[selection-causality.js](../../diagnostics/selection-causality.js) 仅用于测试观察，**不属于App资源或生产页面程序**。在已核对的原测试页面执行一次，随后可以调用只读的`snapshot(阶段名)`与`read()`，结束调用`dispose()`。实例拒绝重复安装，120秒后停止，最多512条，明确报告capped/droppedSnapshots；附件最多40项，报告总数和截断。

记录仅包含单调页面时间、序号、临时WeakMap节点ID、节点类型/归属/连接状态、选区偏移/折叠、焦点、附件节点计数/加载尺寸及用户事件代际。不读取正文、HTML、选中文字、URL、图片src或文件名；不写files、focus、Range、正文或传输状态。

监听selectionchange、focus/blur、可信pointer/key/composition、input/change的capture/bubble以及DOM结构变化。原生mouseDown/up时间必须从原驱动取证；通过AE进行的事后snapshot另记请求开始/返回界限，不能冒充事件瞬间。change-capture在setter后；其中microtask**不保证**在React handler之后，应按真实序号、bubble/task/mutation判断。uploadStarted/完成仍由原操作journal与App trace关联，观察器本身不授予上传开始或完成。

下一次必要对照应使用不同的新图片，并分别记录原生附件按钮、picker进入/返回、change与React变化。原生picker会影响焦点，不能仅依据两条路径最终都折叠就宣称行为不可避免。先记录原生选区准备与DOM Range准备的差异，定位第一处转换，再判断是否存在可安全修复的注入副作用。

## 验证与审查

- `node --check` PASS。
- [便携headless定向测试](../../diagnostics/selection-causality.test.cjs)：作者及非作者各一次，11项断言PASS；新context、网络阻断、无用户profile、无可见Chrome。覆盖阶段记录、节点替换、隐私哨兵、容量/附件上限和dispose。结果见 [diagnostic-test.json](diagnostic-test.json)、[independent-test.json](independent-test.json)。这是测试工具验证，不是ChatGPT真机结果。
- 运行：安装环境已有Playwright可解析时，`node engineering/diagnostics/selection-causality.test.cjs`；可传第二参数保存JSON。没有新增项目依赖、workflow或产品测试数量要求。
- 非作者`selection_causality_audit`审查同一源码hash：`22732efdea969f9e712d024c3fc4bced1cd58e1067df8081463d5ce4b3bd1d96`，同意作为隔离诊断交付，未批准产品修复或普通开放。

无ACK冷首击、人工物理鼠标、未决A/B并发仍独立NOT_RUN。普通上传、Web continuation、safe-retry和所有UNKNOWN保护不变。原有正式CI是edbdc7aa的历史成功检查；本轮没有生产源码修改，不将其称作本次新CI。
