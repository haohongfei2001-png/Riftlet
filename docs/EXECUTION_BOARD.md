# Riftlet 自主并行执行队列

2026-10-27（北京时间）。本文件是可续做的工程队列；总体范围见 [ENGINEERING_PLAN.md](ENGINEERING_PLAN.md)。用户不承担日常任务分派、实现取舍或逐项审批。负责人完成一包后自动领取可做的下一包。

## 1. 当前检查点

| 项目 | 已核实状态 |
| --- | --- |
| 集成分支 | `codex/engineering-foundation-20261027` |
| 评审入口 | [Draft PR #1](https://github.com/haohongfei2001-png/Riftlet/pull/1)；尚未合入main |
| v2修订起点 | `d267336f2ffba4f8ff422c8b41ccfea76b1659da`；本次只调整工程文档与PR模板 |
| 最近已测原生代码 | `2f60f01657cc29e7a4cabe41792c6ccd558d6974`；[macOS CI](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40377481770) 40/40，release/app签名/合成self-check通过 |
| 此次读取到的main | `6dfba79f9ccef295cc0234580a3adc99f0757e09`；相对启动基线只新增网站恢复提交，无原生代码或工程文档变更；本轮不改网站 |
| 已有基础 | Capture、私有副本/manifest恢复、SQLite队列/操作事务、参数化AppKit面板、模拟适配器、Mac CI |
| 生产上传 | UnavailableAdapter；成功和safe-retry准入表均为空 |
| 执行能力 | 当前作者环境为Linux；已有GitHub macOS测试/构建。交互Mac GUI/真实ChatGPT执行器未在本会话验证可用 |
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

**当前下一步：** 集成负责人先确认远端head未变；同时领取C1、U1、W0，分配下表互斥路径；负责人处理必要的共享接口/Package/App组合。三包均为未开工READY，不把计划分工伪称为已有后台开发进程。

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
| **C1 · READY · C** | 已有CaptureService；不等上传 | 提取可注入的截图保存位置来源/变更入口，补自动重新绑定，I负责App接线；先写来源变更的可控用例再选择最小原生事件机制 | 不需菜单刷新/唤醒才能换路径；重复通知不重复导入；旧watcher释放；旧generation事件不污染新目录；切换交界的新截图不漏收；真实系统设置通知由N1验收，未验不声称通过 |
| **C2 · READY · C（C1后优先）** | 已有Importer；与C1写入范围互斥 | 在staging/journal/media/DB各持久化边界加入受控故障用例；必要的小型故障注入口不进入正常热路径 | 各中断点重启后至多一条完整记录；部分文件不入队；原件不删；used不复活；空间不足和写入失败可重试恢复且不提前标seen |
| **U1 · READY · U** | 已有RiftPanel；只需合成数据 | 新建最小原生验收辅助程序/场景，记录焦点、下层点击计数、触发assetID；先接2/3/12图固定场景，I加入构建入口 | 工具在Mac CI编译；无真实截图/ChatGPT连接；能观察N04/N05/N07；实际焦点/穿透结果仍留N1，不把“工具编译”当GUI通过 |
| **U2 · READY · U（U1后优先）** | 已有纯布局/指针模型 | 针对配置更新、长队列可见区、屏幕消失回退、按下期间重排补确定性边界用例，修复发现的具体缺陷 | 比例/连续编号/asset身份不回归；最新图可达；无自动丢弃；reduced-motion和尺寸参数仍可调；物理显示器结果留N1 |
| **Q1 · READY · I** | 已有QueueStore/Coordinator | 扩充崩溃intent边界、晚到回执与原target锁的交叉用例；只补真实未覆盖风险，不重写现有数据库 | 恢复只查询原操作；旧attempt/wrong lease不能消费；unknown不盲重传；used与操作回执原子持久；有失败就先修该Core改动 |
| **I1 · READY · I（持续职责）** | 任一代码增量到达 | 审查跨模块契约，集成小变更，触发对应macOS CI，维护SHA/日志/制品/剩余验收 | 相关测试、release构建、app签名/self-check通过；非作者审查有结论；未测GUI/上传状态准确；无需用户逐次确认 |
| **D1 · READY · 空闲C/I** | 已有私有目录布局 | 增加按需磁盘用量与空间不足诊断，路径/内容不写公开日志；先做可测试的计量边界 | 无空闲轮询、无全量缩略图解码、无自动删除；存储失败不损原件/已用记录；性能测量留N1 |

C2/U2是同一角色的后续包，不能因为表内READY就同时写相同文件。若C1只剩真实设置通知证据，已完成的代码按验证范围提交，C线转C2；若U1只剩交互Mac，U线转U2。

### 4.2 适配器线

| ID / 状态 / 角色 | 前置条件 | 最小交付与下一条动作 | 验收条件 |
| --- | --- | --- | --- |
| **W0 · READY · A** | 现有TargetLease/ReceiptPolicy | 建立最小版本化观察fixture与回放，直接喂现有receipt/store；先加入身份不匹配、迟到、上传中、导航、模糊失败用例 | 不发起网络/真实输入；非准入ATTACHED不消费；错误不能凭safeToRetry一个bool变成可重传；每个fixture注明synthetic/真实去隐私来源 |
| **W1 · READY · A（W0后优先；可拆给空闲角色）** | 现有AttachmentAdapter；已有用户报告的Apple Events INPUT事实；不等完整异常包 | 实现默认禁用的Apple Events候选桥接与fake transport测试；以现有契约接线，具体页面注入/身份观察只取已取得源码/DOM证据，不凭空猜选择器 | 无Send；dispatchIntent先于外部输入；同目标片段复核；超时/断链保留unknown；reconcile只观察；正式App仍禁用；真实结果在W2验证 |
| **M0 · READY · A（Web小包后补位）** | 现有接口/系统pasteboard类型 | 实现独立Mac adapter基础：fileURL/PNG表示、PID+window/composer身份接口、剪贴板所有权/恢复状态机与fake pasteboard测试；实际AX选择器待证据 | 后续用户复制后绝不恢复覆盖；不以固定延迟证明消耗；不宣称已验证Chat/Work/Classic；无额外真实权限申请或真实粘贴 |
| **W2 · WAITING_EVIDENCE + 实现依赖W1 · A/I** | W1 +（完整真实异常证据，或可用的已授权真实测试执行器产生该证据） | 把另一Codex的环境/用例/逐图证据导入W0；只改归一化/adapter/profile并做真实合成草稿全链路 | W00–W07适用用例有观察证据；正确原草稿/图像、原文/旧附件保留；失败/导航/并发不误判；成功和safe-retry分别独立审查；满足后按surface启用 |
| **M1 · WAITING_ENVIRONMENT + 实现依赖M0 · A/I** | M0 + 特定Mac客户端/版本/模式的实际执行环境和权限 | 观察AX，再做合成图片输入与逐图完成/异常验证；先单surface完成闭环 | M00–M06适用用例通过；目标/剪贴板/选择保留及逐图完成可证；单独profile准入；其他surface不借用通过结论 |

W0不是通用证据平台，只是现有协议的可回归小fixture集合。W1的transport外壳可以和W0并行；若当前三角色已满则顺序补位，不能通过重复实现Core或同时堆两套Web transport制造并行度。

### 4.3 验收和发行线

| ID / 状态 | 当前已有/可先做 | 精确解锁条件与届时动作 |
| --- | --- | --- |
| **N1 · WAITING_ENVIRONMENT** | [MAC_ACCEPTANCE.md](MAC_ACCEPTANCE.md)已列N01–N10；U1继续做辅助程序；系统/GUI证据还没有 | 有实际可控、已授权的交互Mac后执行；逐项记录系统截图、首击焦点、透明命中、物理多屏/唤醒、自包含、资源与延迟。缺某显示器只留该用例待验 |
| **R0 · DONE（当前基础版本范围）** | macOS14 ARM64构建、40 tests、ad-hoc app和合成self-check已通过 | 后续修改由I1持续验证；Intel/其他OS若未测只注明，不虚构全平台支持 |
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

本轮v2只修改文档与PR模板，因此保留先前40项测试的原SHA，不声称新跑了一遍。文档检查包括相对链接、任务依赖/状态一致性、与现有产品约束一致性和`git diff --check`；独立审查覆盖计划阻塞拆分、实际复用和许可范围。

## 6. 本次执行记录

- **P2 · DONE（计划修订范围）**：总计划v2、AGENTS自主执行授权、此队列、适配器依赖拆分、未决项作用域、PR交付模板。没有修改产品源码或把真实适配器启用。
- **独立复核**：执行计划审查角色指出W1/M1前置条件过粗，现已拆开；复用审查角色核对两项实际适配、Tendedero独立实现、Oracle/Maccy参考状态与app许可打包，修正Oracle归档“6源码/fixture + LICENSE”的数量表述。
- **当前可继续的首批**：C1 / U1 / W0。此记录提供可直接执行的交接，不要求用户确认下一批。
