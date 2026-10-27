# Riftlet 自主并行执行队列

>
> **Pro research handoff received (2026-10-27):** [read-only technical findings and minimal acceptance tasks](PRO_FEASIBILITY_REVIEW_FINDINGS_2026-10-27.md). Web no-editor-focus one-click is conditionally feasible but cold first click not yet accepted; Mac separate. System Screenshot.app cannot currently be promised universal exclusion; implement robust persistent user hide, isolate source in real N1 before any optional automatic-hide experiments. Prioritize ACK/main-thread/NSEvent timing, authorisation gap, empty-generation retirement, usable-composer gate and UI archive-protection. **No source code, source acceptance or production adapter changed by this document.**

> **NEW RELEASE UX REQUIREMENTS P29–P33 (2026-10-27):** [RELEASE_UX_REQUIREMENTS](RELEASE_UX_REQUIREMENTS_2026-10-27.md) confirms focusless composer single-click, subtle invalid-click feedback, interaction-safe archive, and the lean public-release baseline. Screenshot self-inclusion is a **technical feasibility study**, not a guarantee; see [Pro focused research brief](PRO_FEASIBILITY_REVIEW_BRIEF_2026-10-27.md). **Do not disrupt existing W2/N1/M1 implementation or mark release requirements PASS from current synthetic/partial tests.**



> **2026-10-27 NEW USER PRODUCT DECISION:** [INTERACTION_CONTRACT_2026-10-27.md](INTERACTION_CONTRACT_2026-10-27.md) now governs the final screenshot/rift lifecycle: current target at click; **positive upload start → very fast swallow**, not READY-only; only explicit/extremely high-confidence failure → rebirth; swallowed UNKNOWN stays locally hidden; idle archive, single/bulk removal, and **no slit at zero visible items**. Current source, acceptance and success/failed gates have **not** been revised merely by this note. The integration lead should create/claim a separate implementation+real-acceptance packet without discarding already passing W2/N1/M1 evidence. No unreviewed merge or production enablement. **Additional user rulings P23–P28:** no success Toast; no composer means no swallow; failure-qualified rebirth must be a normal clickable screenshot with ordinary archive/removal; queue clearing never removes ChatGPT attachments; optimize consecutive clicks only when safe. Hold-and-drag remains unapproved. Update product UI/state-machine acceptance accordingly; do not treat these product decisions as already implemented.

2026-10-27（北京时间）。本文件是可续做的工程队列；总体范围见 [ENGINEERING_PLAN.md](ENGINEERING_PLAN.md)。用户不承担日常任务分派、实现取舍或逐项审批。负责人完成一包后自动领取可做的下一包。

**M1 独立执行记录（历史，合流前）**：用户已将真实 Mac 的 W2/N1 与 Web 两次操作闭环交给本地 Codex；本会话不访问或争用其设备。以下 PR #1 表格及 W2 结果是继承到 `485fa87` 的检查点，不冒充另一会话的新结果。M1 在独立分支 `codex/m1-native-backend-20261027` / [Draft PR #3](https://github.com/haohongfei2001-png/Riftlet/pull/3) 完成原生后端，已测 `7dfa8ec`、173/173 原生测试与非作者审查通过；实际客户端准入仍等待真实证据。唯一正式工程集成负责人保持 root，后续按分支成果整合，不直接争写 PR #1。

## 1. 当前检查点

### 新版交互代码增量 · 代码、完整 CI 与非作者审查通过

- 正式起点 `a441c70f3c4071069bd594513ecf16600bbb0ab8`；继承 PR #4 `90a04883160032fc6354fb4f3d3f7d56fede2947` 批准文档及历史，不覆盖网站/设计。
- root 亲自完成 Core/SQLite v3/Coordinator/App；三个独立执行者实际并行完成 UI、历史、Core 回归与交叉非作者审查。共享源码由负责人单写入。本会话没有操作本地 Codex 的真实 Mac。
- 已实现：正向开始独立持久化并快速退出、隐藏 UNKNOWN、独立安全失败才重生、零图零裂缝、持久隐藏、单张/批量移除、受交互保护的可调归档、原生分页历史、隔离三态模拟。本轮独立 CI 已验证新增源码/测试；结果如下，未借用旧 228 项运行。
- [共享契约与可运行演示](UPLOAD_STARTED_CONTRACT_V1.md) 已写入；协调要求已发至 PR #1。Web/Chrome 本轮保持未改，当前真实适配器尚未产出新的开始回执。开始/成功/安全重试三项准入独立且生产默认空。
- 本地 Codex 下一包：在自己的 Web 分支接入真实开始、早返回/只读 reconcile、独立失败终止证据；继续第四轮冷首击/逻辑草稿/MID/物理 N1 与自包含/延迟。root 在取得真实源码与证据后统一集成，不重做已有模块。

**本轮完整 macOS CI 与非作者审查通过：** 已测输入 [`d834a3a4a76cacedd0cb763044085c9c2093680c`](https://github.com/haohongfei2001-png/Riftlet/commit/d834a3a4a76cacedd0cb763044085c9c2093680c)，[run 40479556833](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40479556833) / job 122106130530。**287 项原生**（Core 110 / Capture 48 / UI 39 / Adapters 90）、38 项页面 VM、8 组故障工具、12 组只读 probe、历史回放 55 文件 / 19 用例 / 89 trace 前缀 / 2 明确模拟迟到错误全部通过。Release、ad-hoc 签名和三个 App/helper 自检通过。新增逐项输出确认 **13/13 生命周期测试 passed，0 skipped**，其中 7 项实际 AppKit 面板软件测试；重复报告这 13 项没有增加测试总数。

[永久验证](../engineering/evidence/2026-10-27-interaction-lifecycle/verification.json)、[非作者审查](../engineering/evidence/2026-10-27-interaction-lifecycle/review.json)、[日志摘录](../engineering/evidence/2026-10-27-interaction-lifecycle/ci-excerpt.txt)、[可运行 development App/helper/日志](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40479556833/artifacts/12721893223)。Swift 5.10 / macOS 14.8.9 / ARM64；artifact SHA-256 `cea0daab14fcbbc3b18509e1ec902ec913d776bc07acf19621983b71a37d0122`，保存期限至 `2026-11-10T09:18:09Z`。临时 PR checkout `e0b2688cf99ed83ae949af700dedee58094fa2d1` 与 main `eba1a4fc77648a665e1d5c1f2609df1314c3b079` 的合流只用于 CI；**没有合并 main**。后续文档检查点保持本次已测 Sources/Tests/构建输入不变。

以下第三轮事实及 PR #4 的原交接说明作为来源保留；最新实现/验证以本节、[VERIFICATION](VERIFICATION.md) 和 [uploadStarted v1](UPLOAD_STARTED_CONTRACT_V1.md) 为准。

<!-- ROUND3_INTEGRATION_STATUS -->
**第三轮正式集成：** 7d6bca6 → 11aec04/159b3ef → d26c6da/6344eb0 → [aa4fd2b9ed64efb83d9b7c8b29102cbd91d03e2b](https://github.com/haohongfei2001-png/Riftlet/commit/aa4fd2b9ed64efb83d9b7c8b29102cbd91d03e2b)。全部原12文件保留；root修复ChromeActivityObserver仅PID缓存为PID+launchDate，非作者已复核。[完整 macOS CI 40471069966](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40471069966) 于 16:06:16 北京时间通过：228 原生 / 38 页面 / 8 故障 / 12 probe 离线组，历史回放、Release/签名及三个自检全部通过；[永久验证与范围](../engineering/evidence/2026-10-27-integration-round3/verification.json)。
<!-- END_ROUND3_INTEGRATION_STATUS -->

**第四轮最高目标仍是实际日常首击闭环。** 第三轮增加AX/hover调度、ACK返回复核、v7 root commit monitor与helper实际几何/焦点诊断；本轮没有新真实上传/MID故障。自包含已在仅实际App运行时明确FAIL；十分钟capture-only资源为有范围测量PASS。冷首击、真实业务ABA/同URL、MID、物理N1与完整延迟仍未完成，不能靠增加测试数量关闭。

当前新增开放边界：v7不能完整观察旧v6 registry；monitor停止墓碑不可rearm；CLEAR全row接受是旧风险，需准确实击区分误选与穿透。数据/旧操作不清理，生产输入/吞噬/安全重试继续禁用。[正式交接及第四轮动作](INTEGRATION_HANDOFF.md#第四轮直接动作)已写明；既有模块不重做，真实执行仍由本地Codex负责。

前次7d6bca6的227native/31page/8fault及第二轮普通线程、后台DOM补偿、POST100中断是[历史来源](../engineering/evidence/2026-10-27-real-mac-round2/README.md)。当前[第三轮来源](../engineering/evidence/2026-10-27-real-mac-round3/README.md)明确区分探索工作树、最终源码、自动化GUI和真实资源测量。

### 前一正式集成检查点（历史，保留来源）

| 项目 | 已核实状态 |
| --- | --- |
| 集成分支 | `codex/engineering-foundation-20261027` |
| 评审入口 | [Draft PR #1](https://github.com/haohongfei2001-png/Riftlet/pull/1)；尚未合入main |
| 本轮执行起点 | `b5958d144287b1e31ea6e6b6709173d0939bbc05`；此前完成的C1/C2/U1/U2/Q1/W0/W1/M0/D1不重做 |
| 最近已测原生代码 | `97f10b0bf03fbd9421083a15eefec0eb22ead606`；[macOS CI](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40437937532) **139/139** + 页面VM **9/9**，release/app签名、迁移App后的Web资源自检和原两个合成self-check通过；后续检查点仅更新文档/证据 |
| 最新读取到的main | `3f5248d6b1c0d32ad80141cbdee4ee16945e6f7b`；前轮从6dfba79推进的7文件均为网站/图标相关，没有原生源码/工程文档；本轮保留其改动，不同步覆盖网站 |
| 新增实现 | 取得6f415698真实Web交接并原样导入；捆绑页面程序、一次输入/有界观察、逐图证明、显式原生Web生成图片验收模式；公共策略/资源打包由root实现 |
| 生产上传 | 普通模式仍UnavailableAdapter；成功和safe-retry表为空。显式Web验收只使用独立目录中的生成图片，开发消费profile不能用于真实截图或重试 |
| 实际执行能力 | root亲自App/Core/构建接线；w2_implementation与w2_evidence_review真实并行实现/非作者审查；n1_native_acceptance核实设备后转App/Core非作者审查。GitHub macOS CI成功；已登记交互Mac离线，未运行本轮真实GUI或ChatGPT |
| 后台执行 | 没有新建常驻编码服务或定时开发任务；会话内连续执行，跨会话按本检查点续做 |

获取后续任务前，读取最新远端main与分支head并检查工作区；不覆盖其他会话改动。若main只改无关路径，不为同步而修改网站或重跑无关研究。共享文件发生变化时，由负责人先解决实际冲突。

## 2. 状态与领取规则

- **READY**：已有实现前提，可以立即领取；并不表示已开工。
- **ACTIVE**：已填写实际执行者、起点commit和独占写入范围，正在实现。
- **REVIEW**：代码与所需检查已提交，等待非作者技术审查；负责人负责解决意见，不等待用户。
- **DONE**：本任务定义的交付、检查及独立审查已完成，有证据链接；只代表注明的范围。
- **WAITING_DEPENDENCY**：只缺表内明确的前置任务；前置完成后自动变为READY。
- **WAITING_ENVIRONMENT / WAITING_EVIDENCE**：实现之外缺环境或外部事实；明确解锁条件，其他任务继续。
- **DEFERRED_RELEASE**：只在最终品牌/发行/清理阶段处理，不阻塞当前工程。

流程为 `READY → ACTIVE → REVIEW → DONE`；检查失败回ACTIVE修复。无法执行的场景保持WAITING，不用模拟结果填PASS。每次结束一个包或发现局部阻塞后，立即选下一个依赖满足的READY项；没有有效工作时保存事实状态，不循环空提交。

**当前续做入口：** 第三轮已正式合入PR #1；本地Codex继续第四轮首击/业务转换、版本观察兼容、MID及真实GUI/自包含修复，root负责统一合流。详见现行交接；M1真实客户端provider/profile保持独立，完整W2/N1/生产闭环未完成。

## 3. 并行所有权

当前预算为 **1名集成负责人 + 最多3个实现/审查角色**。角色是工程职责，不是假定额外机器或无限并发。可按任务完成情况重新分配。

| 角色 | 独占实现范围 | 共享变更处理 |
| --- | --- | --- |
| 集成负责人 I | `Sources/RiftletCore/**`、`Sources/RiftletApp/**`、`Package.swift`、CI/构建入口、集成分支与远端ref、工程文档 | 亲自落地公共契约/App接线、解决冲突、整体验收；不把所有代码转交他人 |
| 收录线 C | `Sources/RiftletCapture/**`，`Tests/RiftletCaptureTests/**` | 不自行改Core/App；提交小接口建议，由I落地；C1/C2同线串行 |
| 原生界面线 U | `Sources/RiftletUI/**`，`Tests/RiftletUITests/**`，独立的合成GUI验收辅助源码 | 新target由I接入Package；U1/U2同线串行；不会同时改App组合 |
| 适配线 A | 新建的适配器专属源码/fixture/测试路径；开始前在任务记录明确 | W0/W1/M0按优先级领取；Core模型/ReceiptPolicy由I修改，不复制第二套状态机 |

作者完成后由另一角色做只读审查，允许流水式审查，不要求所有并行包一起完成才集成。共享工作区必须使用不相交写入范围；需要修改同一范围时改用独立worktree并由负责人顺序集成。领取到commit的记录保持小而完整，避免长期大分支。

## 4. 可执行任务包

### 4.1 原生与质量线

| ID / 状态 / 角色 | 前置条件 | 最小交付与下一条动作 | 验收条件 |
| --- | --- | --- | --- |
| **C1 · DONE（下述实现范围） · C** | 已有CaptureService；不等上传 | 提取可注入的截图保存位置来源/变更入口，补自动重新绑定，I负责App接线；先写来源变更的可控用例再选择最小原生事件机制 | 不需菜单刷新/唤醒才能换路径；重复通知不重复导入；旧watcher释放；旧generation事件不污染新目录；切换交界的新截图不漏收；真实系统设置通知由N1验收，未验不声称通过 |
| **C2 · DONE（下述实现范围） · C（C1后优先）** | 已有Importer；与C1写入范围互斥 | 在staging/journal/media/DB各持久化边界加入受控故障用例；必要的小型故障注入口不进入正常热路径 | 各中断点重启后至多一条完整记录；部分文件不入队；原件不删；used不复活；空间不足和写入失败可重试恢复且不提前标seen |
| **U1 · DONE（下述实现范围） · U** | 已有RiftPanel；只需合成数据 | 新建最小原生验收辅助程序/场景，记录焦点、下层点击计数、触发assetID；先接2/3/12图固定场景，I加入构建入口 | 工具在Mac CI编译；无真实截图/ChatGPT连接；能观察N04/N05/N07；实际焦点/穿透结果仍留N1，不把“工具编译”当GUI通过 |
| **U2 · DONE（下述实现范围） · U（U1后优先）** | 已有纯布局/指针模型 | 针对配置更新、长队列可见区、屏幕消失回退、按下期间重排补确定性边界用例，修复发现的具体缺陷 | 比例/连续编号/asset身份不回归；最新图可达；无自动丢弃；reduced-motion和尺寸参数仍可调；物理显示器结果留N1 |
| **Q1 · DONE（下述实现范围） · I** | 已有QueueStore/Coordinator | 扩充崩溃intent边界、晚到回执与原target锁的交叉用例；只补真实未覆盖风险，不重写现有数据库 | 恢复只查询原操作；旧attempt/wrong lease不能消费；unknown不盲重传；used与操作回执原子持久；有失败就先修该Core改动 |
| **I1 · DONE（本轮合流/CI/审查）；持续职责 · I** | 任一代码增量到达 | 审查跨模块契约，集成小变更，触发对应macOS CI，维护SHA/日志/制品/剩余验收 | 相关测试、release构建、app签名/self-check通过；非作者审查有结论；未测GUI/上传状态准确；无需用户逐次确认 |
| **D1 · DONE（下述实现范围） · 空闲C/I** | 已有私有目录布局 | 增加按需磁盘用量与空间不足诊断，路径/内容不写公开日志；先做可测试的计量边界 | 无空闲轮询、无全量缩略图解码、无自动删除；存储失败不损原件/已用记录；性能测量留N1 |

C2/U2是同一角色的后续包，不能因为表内READY就同时写相同文件。若C1只剩真实设置通知证据，已完成的代码按验证范围提交，C线转C2；若U1只剩交互Mac，U线转U2。

### 4.2 适配器线

| ID / 状态 / 角色 | 前置条件 | 最小交付与下一条动作 | 验收条件 |
| --- | --- | --- | --- |
| **W0 · DONE（下述实现范围） · A** | 现有TargetLease/ReceiptPolicy | 建立最小版本化观察fixture与回放，直接喂现有receipt/store；先加入身份不匹配、迟到、上传中、导航、模糊失败用例 | 不发起网络/真实输入；非准入ATTACHED不消费；错误不能凭safeToRetry一个bool变成可重传；每个fixture注明synthetic/真实去隐私来源 |
| **W1 · DONE（下述实现范围） · A（W0后优先；可拆给空闲角色）** | 现有AttachmentAdapter；已有用户报告的Apple Events INPUT事实；不等完整异常包 | 实现默认禁用的Apple Events候选桥接与fake transport测试；以现有契约接线，具体页面注入/身份观察只取已取得源码/DOM证据，不凭空猜选择器 | 无Send；dispatchIntent先于外部输入；同目标片段复核；超时/断链保留unknown；reconcile只观察；正式App仍禁用；真实结果在W2验证 |
| **M0 · DONE（下述实现范围） · A（Web小包后补位）** | 现有接口/系统pasteboard类型 | 实现独立Mac adapter基础：fileURL/PNG表示、PID+window/composer身份接口、剪贴板所有权/恢复状态机与fake pasteboard测试；实际AX选择器待证据 | 后续用户复制后绝不恢复覆盖；不以固定延迟证明消耗；不宣称已验证Chat/Work/Classic；无额外真实权限申请或真实粘贴 |
| **W2 · WAITING_EVIDENCE（第三轮局部实测；第四轮续做） · A/I** | 159b3ef/6344eb0与AX启动身份修复已集成 | AX/hover唤醒、ACK复核、v7 commit monitor完成开发增量；下一步真实首击/业务ABA、旧版本只读恢复与MID | 没有新真实上传/中段abort；保留v6历史结果，生产和safe-retry不启用 |
| **M1 · 原生后端DONE；客户端WAITING_EVIDENCE · I/A** | 已完成M0；原生后端不等客户端结构 | PR #3已合入工程分支且本轮五个后端文件未改；原生AX/NSPasteboard、全局协调及完成后只读观察随本轮完整原生CI复验；接下来只按真实版本/surface证据补MacAXBindingProvider/profile | 后端范围见[M1交接](M1_NATIVE_BACKEND.md)；实际M00–M06、选区/旧附件/逐图完成仍未验。默认禁用、内置profile空，不借用Web结论 |

W0不是通用证据平台，只是现有协议的可回归小fixture集合。W1的transport外壳可以和W0并行；若当前三角色已满则顺序补位，不能通过重复实现Core或同时堆两套Web transport制造并行度。

### 4.3 验收和发行线

| ID / 状态 | 当前已有/可先做 | 精确解锁条件与届时动作 |
| --- | --- | --- |
| **N1 · WAITING_EVIDENCE；自包含FAIL** | 第三轮capture-only十分钟资源/单次CLI收录有范围通过；helper自动化GAP仅单点。实际App无helper仍进入截图 | 准确CLEAR/GAP、held reorder/替换行双击、键盘焦点/屏幕变化；解决自包含并补完整T0/T1/T2。探索未冻结源码与预测命中不作物理PASS |
| **R0 · DONE（正式合流构建，见上方CI）** | aa4fd2b完整原生/page/归档/8fault/12probe、release/签名和三个自检；历史CI保留来源 | 实际MacPID复用未跑，不虚报；Intel/其他OS/物理GUI保持各自验收范围 |
| **R1 · DEFERRED_RELEASE** | 保持工程制品、安装/权限说明草稿；不等证书或Logo才构建 | 必需功能的W2/N1及发行检查满足，且签名/公证凭据可用时推进对应发布工作；不为发行等待暂停开发 |
| **V1 · DEFERRED_RELEASE** | R2 01所有几何/动画参数可调；品牌Logo独立进行 | 有后续明确视觉结论时替换参数/资源并验收，不重建原生模块；候选不标Approved |
| **D2 · DEFERRED_RELEASE** | 原件/used私有媒体保留，D1先做空间诊断 | 收尾时制定并测试安全清理语义；本任务未实现前不得悄悄删除图片，不要求用户现在决策 |

## 5. 持续集成与质量关口

每个可集成包至少留下：任务ID、实际执行者/非作者审查角色、分支及起点/结果SHA、变更路径、完成的检查、证据链接、未测范围和下一步。用同一记录更新PR，避免重复维护大型报告。

```text
Task ID / state:
Owner / reviewer:
Branch / base SHA / result SHA:
Exclusive paths / shared-interface proposal:
Deliverable / actual check commands and results:
Evidence / exact environment / untested scope:
Blocked capability / missing prerequisite / resume trigger:
Next READY task or next concrete action:
```

集成顺序：检查路径和契约 → 对改动有意义的测试 → 非作者审查 → 负责人修复/集成 → 对应macOS构建与smoke → 记录完成范围。已有CI并行测试和同分支旧运行取消机制；纯文档不主动额外触发长测。当前`pull_request.paths`按PR整体差异匹配，PR #1仍含原生代码，因此文档更新也可能自动触发原生CI；如实记录自动运行，不手动跳过检查，也不宣称已实现逐commit的智能跳过。代码检查失败、数据/身份/隐私/许可问题必须在受影响增量修复，不能用“赶进度”把失败标为已完成。

可在Draft PR保留尚在修复的可审查commit，但要明确其未通过状态；只有通过适用检查与审查的增量才计为集成完成。生产启用是另一关：对真实成功/失败profile必须有实际异常证据；缺证据就继续禁用，不加可绕过的生产配置。

历史v2修订只改文档与PR模板，原40项测试证据仍保留在验证记录。随后本轮实际源码增量分别完成63、98、127、134项Mac测试；没有将旧结果重标为新测试。当前检查点另检查相对链接、状态/证据一致性及`git diff --check`。

## 6. 本次执行记录

- **P2 · DONE（计划修订范围）**：总计划v2、AGENTS自主执行授权、此队列、适配器依赖拆分、未决项作用域、PR交付模板。没有修改产品源码或把真实适配器启用。
- **独立复核**：执行计划审查角色指出W1/M1前置条件过粗，现已拆开；复用审查角色核对两项实际适配、Tendedero独立实现、Oracle/Maccy参考状态与app许可打包，修正Oracle归档“6源码/fixture + LICENSE”的数量表述。
- **以上为历史计划修订记录**；下面是随后实际执行的代码交付。


### 持续实现交付 — b5958d1历史检查点

| 包 / 实际作者 / 非作者审查 | 实际代码和验证范围 | 未完成范围的归属 |
| --- | --- | --- |
| C1 / capture_c1 + root接线 / root、ui_u1 | 系统偏好可注入/自动绑定、epoch、旧目录未完图和持久departure交接；15项测试。修复await期间新增旧源图漏收、陈旧start越过stop、单文件暂时不可读终扫遗漏 | Screenshot.app实际传播、TCC、真实睡眠→N1 |
| C2 / capture_c1 + root / ui_u1；capture_c1复核root增补 | journal rename即移交所有权、stage目录同步、IO与损坏数据区分、已有journal先恢复；10项测试遍历7个提交边界，含真实SQLite写锁、权限失败和碰撞 | 进程内注入/重开不冒充SIGKILL或断电；IO可保守停止整次恢复 |
| Q1 / root / ui_u1、adapter_w0 | mode初始化事务、持久receipt读取、missing状态保护；新增7个恢复边界+2个协调器用例，含真实SQLite trigger回滚 | 新的真实profile仍需W2/M1 |
| U1/U2 / ui_u1 / root | 独立合成GUI辅助程序并实际打包；7项布局/配置/断屏策略回归；修复大inset把微图移出窄屏 | 编译与纯布局不证明焦点/穿透/物理多屏→N1 |
| W0/W1 / adapter_w0 / root、ui_u1 | 严格观察schema、代码侧映射、14项契约+9项传输测试；真实NSAppleScript执行器在串行utility队列；分块、双hash、ACK、单次commit、observe-only恢复 | 页面function未取得；实际Chrome调用与click-time tab证据→W2；App仍UnavailableAdapter |
| M0 / adapter_w0 / root、ui_u1 | PID/launch/window/composer绑定、fileURL/PNG、完整snapshot、guarded write/restore、独立失败准入解除lease；19项合成流程测试 | 尚无native AX/NSPasteboard driver；跨实例/重启clipboard协调及真实输入→M1 |
| D1 / ui_u1 + root接线 / root、ui_u1交叉审查 | 9项有界元数据计量测试；菜单按需utility任务；used媒体计量进入打包self-check；无删除/内容读取/空闲轮询 | 物理占用、资源测量→N1；清理→D2 |
| 收录可靠性追加 / root / ui_u1 | 5处regular-file打开加O_NONBLOCK后立即fstat拒绝特殊文件；2项真实FIFO测试覆盖3个reader和collector start/stop，有界失败救援 | 不宣称这些测试替代真实系统截图验收 |

四个实际代码提交：

1. `94df78c74e75cf79b7832e62a228c6fd37913cf9` — Q1/U1/W0，63 tests。
2. `3e7b8eac6c3bd235f4e376172d6085ab0d5b4426` — C1初包/U2/W1/D1，98 tests。
3. `1afd849a9b2d2cfada0d01cd47b5f1ee31f83d37` — C2/M0，127 tests。
4. `e76e7985c05197c487dd4e7f585dc028ed64b1af` — C1审查修复/FIFO，134 tests。

全部run、job、制品hash、测试分布与审查记录见[VERIFICATION](VERIFICATION.md)和[机器证据](../engineering/evidence/2026-10-27/continuous-verification.json)。峰值为root加3个实际独立执行者，共用一个工作区，使用互斥路径；后续按包完成切换到编码或非作者审查，不声称每一时刻都有3个作者编码。

**以下为b5958d1时的历史续做入口，已由本页顶部和下方W2检查点更新：**

1. 读取最新main、功能分支head和本检查点；确认工作区/他人改动，不重建已完成架构，不覆盖网站或设计。
2. 如果真实Web源码/完整证据到达，直接领取W2：归档去隐私来源和范围→补W0 fixture→实现注入页面program→分别审查完成/安全重试→真实合成草稿闭环。点击时目标与同Chrome标签切换必须覆盖。无需改Capture/SQLite/UI。
3. 若可用交互Mac先到达，直接执行N1辅助程序和系统用例；缺一项显示器只保留该项。Mac客户端证据到达则推进M1真实driver及全局clipboard恢复边界。
4. 若只有这些缺失前提而没有新READY工作，保留此检查点；不编造GUI/上传结果，不开启生产profile，不空提交循环，不要求用户逐项审批。

历史搜索状态（b5958d1时）：原始Library交接ZIP存在，最新Codex实际页面源码与完整异常证据当时未取得。E06保留“用户报告本轮范围通过”的事实，不将“资料未取得”改写成“实测未通过”。该缺源码状态现已被E07和下方W2增量取代。

### W2产品闭环集成 — 继承检查点（截至485fa87）

- **代码提交**：`97f10b0bf03fbd9421083a15eefec0eb22ead606`；实际源于b5958d1，完整导入的Web交接固定为6f415698，不合并其余main/网站路径。
- **交付**：捆绑真实输入原语派生页面程序；完整identity、唯一输入、逐图进度/最终内容证明；超时后只observe；显式`--web-acceptance`原生App生成图片队列与受来源约束的开发吞噬。普通模式仍保留真实截图，不输入ChatGPT。
- **测试/审查**：[run40437937532](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40437937532)成功，139native+9页面VM、release/app签名、迁移资源自检和原GUI helper通过。root与两个Web执行者交叉审查，N1执行者审查rootApp/Core；修复依据和证据见[VERIFICATION](VERIFICATION.md)。没有把离线测试记为真实浏览器或GUI。
- **真实环境**：初始设备核实及长时间工具中断后的复核均为离线。没有启动实际Mac命令、系统截图、真实页面输入或GUI；N1/W2实际验收保留等待。中断后先核对远端仍b5958d1，再完成本代码提交，未重推或覆盖他人提交。
- **下一条动作**：在线Mac可用时按[现成入口](MAC_ACCEPTANCE.md#w2-integrated-web-acceptance-entry)运行生成图片Home Chat路径，并同期执行N1首击/焦点/穿透/系统收录；实际发现即修复。随后扩展当前聊天线程和点击标签切换证据、UNKNOWN恢复与迟到失败处理，满足对应准入后才能让真实截图进入两次操作闭环。
- **范围控制**：M1保持独立；品牌和发行没有加入关键路径。本轮没有新增无关模块、重做基础工程、修改main/视觉资产、发布或发送聊天消息。没有后台持续编码进程；下次从此检查点续做。


### M1 独立原生后端 — 历史88f9e36检查点

- **代码与分支**：起点485fa87；实现7cb9656；已测修订`7dfa8ecbd221095f6c99d289aba794b51ce37e95`。分支`codex/m1-native-backend-20261027`，Draft PR #3目标为PR #1工程分支。没有合并或覆盖PR #1、本地Codex的Web/Core、main、品牌或发行文件。
- **实际实现**：复用M0协议；ApplicationServices/NSPasteboard后端、精确原目标/私有文件/owner检查、稳定跨进程锁、metadata-only日志和一次输入意图；UNKNOWN只观察；丢失快照不恢复；协调失败不给Core成功/重试回执。
- **实际并行/审查**：root亲自协调器/M0接线/恢复测试；m1_ax与m1_pasteboard并行实现；m1_review非作者读全部源码，作者再交叉审查。修复nil读取分类、resolved早于Core提交断点和协调失败回执漏洞。
- **CI**：[run40446467852](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40446467852) / job121998836427，macOS14.8.9 arm64 Swift5.10，**173/173**（Capture48/Core30/UI17/Adapters78）+9页面VM，release/app签名及三个自检全部成功。此前首次运行的两处原生命名剪贴板fixture假设失败已修正，原生驱动未放宽。
- **证据/范围**：[M1接口与恢复说明](M1_NATIVE_BACKEND.md)、[验证记录](../engineering/evidence/2026-10-27/m1-native-verification.json)、[非作者审查](../engineering/evidence/2026-10-27/m1-native-review.json)。命名板是真实系统API，AX目标/动作主要为注入测试；未查询/操作真实客户端或通用剪贴板。
- **当时下一条动作（历史）**：保留独立成果供负责人整合；已有客户端AX/版本/模式证据到达后，仅实现对应provider并在授权环境完成M00–M06，再单独准入。W2/N1由本地Codex继续，root后续负责统一集成其真机成果。本M1分支没有遗留ACTIVE实现任务；不重复规划、不生成额外后台任务、不把本次CI写成真实Mac客户端通过。

## 第三轮本地候选交付（历史，现已正式合流）

源码 `159b3ef3e6c87ea468ba334dff64ad8db640d80c` 在独立 `codex/riftlet-real-mac-round3-20261027`。CI 228 Swift / 38 page / 12 新 probe groups 与打包自检 PASS；AX 唤醒及真实 root commit 监视局部有证据。UX-01 全场景、真实业务 ABA、物理 GUI 与 MID 仍未准入；系统截图自包含仍 FAIL。生产真实截图上传和 retry 保持关闭。详见[第三轮交接](../engineering/evidence/2026-10-27-real-mac-round3/README.md)。本段不覆盖上方正式版本状态。
