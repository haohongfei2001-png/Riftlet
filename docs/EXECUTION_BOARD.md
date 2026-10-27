# Riftlet 自主并行执行队列

2026-10-27（北京时间）。本文件是可续做的工程队列；总体范围见 [ENGINEERING_PLAN.md](ENGINEERING_PLAN.md)。用户不承担日常任务分派、实现取舍或逐项审批。负责人完成一包后自动领取可做的下一包。

**M1 独立执行记录（历史，合流前）**：用户已将真实 Mac 的 W2/N1 与 Web 两次操作闭环交给本地 Codex；本会话不访问或争用其设备。以下 PR #1 表格及 W2 结果是继承到 `485fa87` 的检查点，不冒充另一会话的新结果。M1 在独立分支 `codex/m1-native-backend-20261027` / [Draft PR #3](https://github.com/haohongfei2001-png/Riftlet/pull/3) 完成原生后端，已测 `7dfa8ec`、173/173 原生测试与非作者审查通过；实际客户端准入仍等待真实证据。唯一正式工程集成负责人保持 root，后续按分支成果整合，不直接争写 PR #1。

## 1. 当前检查点

**第二轮本地真机候选（待 Pro 集成）：** 从 `c1456534fa2f9652f770321f179ff88737edc281` 建独立分支 `codex/riftlet-real-mac-round2-20261027`，已测源码 `fff0e8c090f125211b35a56e7a16abef61109fb1`，[CI 40458148137](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40458148137) 227 原生 + 31 页面测试通过。普通线程生成 PNG、后台原操作观察、真实目标 XHR 的 UI100 后中断和 UNKNOWN 重启保留已有局部 PASS；预绑定调度、逻辑身份冲突与 MAIN 单次回执传输已实现。UX-01 全场景、无可观察事件的业务 A→B→A、真实 MID 字节关联、物理 N1 与生产闭环仍未通过，不能升级为日常可用。两张新系统截图收录/原件私有哈希保留，截图源出现约 61.5 s 延迟待定位。确切证据、状态和续做点见[第二轮交接](../engineering/evidence/2026-10-27-real-mac-round2/README.md)。本段不改写下方正式集成历史，PR #1/main 未被本地会话修改。

<!-- INTEGRATION_STATUS -->
**正式集成已完成（代码/CI/非作者审查范围）：** 合流源码[`76a8385`](https://github.com/haohongfei2001-png/Riftlet/commit/76a8385be063bf225248c057262eb8d57e4be43f)保留本地真机`f075b8f`及M1`88f9e36`的完整祖先。[整合macOS CI40453748396](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40453748396) **201/201原生、20/20页面VM、release/签名和三个自检通过**；v1→v2迁移/回滚、补偿/UNKNOWN及M1恢复均重新执行。后续本检查点仅文档/证据，代码输入不变。PR #1仍Draft且main未合并；PR #3已由GitHub记为合入工程分支。root仍为唯一正式集成负责人，本地Codex继续真实Mac验收；本会话未访问设备。来源、确切证据、缺陷及直接续做命令见[正式集成交接](INTEGRATION_HANDOFF.md)。
<!-- END_INTEGRATION_STATUS -->

**实际产品缺陷：UX-01预绑定首击限制、UX-02整标签UNKNOWN阻塞均OPEN。** 工程已决定自动触发目标预绑定、在有证据时分离逻辑草稿身份与输入焦点代际，保持原操作只观察；方案与真机验收写入[交接](INTEGRATION_HANDOFF.md#已确认的产品体验缺陷与自主修复决策)。不增加用户确认、重点击或手工清锁，不凭空放宽当前锁。

**本地真机增量，2026-10-27：** 独立分支 `codex/riftlet-real-mac-acceptance-20261027`，正式 PR #1 / Pro 集成分支未被覆盖。源码 `1909771d45ad00290dffe245b9a42e6e9f55203c` 已通过 [macOS CI](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40449181125)。本机 macOS 27 / Apple M5 / Chrome 156 实际可用；此前 Mac 离线记录只属历史。

已完成：五次受控 Home 生成图片 verifiedReady；三张真实系统窗口截图自动收录和重启核对；迟到 DOM 错误的持久补偿/观察点击/重启；v3 真实 A→B→A 撤销；v4 同 tab 未决锁实际拒绝新输入；2/3/12 原生辅助场景。修复启动主 actor 阻塞、Chrome 多进程绑定、late failure、点击冻结、页面代际和重arm绕锁。完整 W2 验收 FAIL（未达标），N1 全套及真实截图两次操作闭环尚未完成；生产与 safe-retry 仍关闭。详细事实和集成指令见 [真机交接](../engineering/evidence/2026-10-27-real-mac/README.md)。

下一步：实际网络中断/100% 后请求异常的准确故障注入、已有对话的 Chat 模式证据和适配、延迟事件/窗口/业务草稿变更矩阵及物理 N1。未预绑定首击仍安全拒绝；不以开发吞噬替代生产准入。无需重新开发已完成模块，不再以本机离线为等待理由。

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

**当前续做入口：** 本地Codex继续拥有真实Mac的W2/N1验收；负责人将f075b8f与PR #3的88f9e36整合到PR #1。受控Home成功、DOM迟到错误补偿和截图收录证据保留；网络异常、普通线程、首击和物理GUI仍未完整验收。M1后端已完成，客户端provider/profile仍待真实证据。下一轮只从正式集成检查点续做，不重领已完成基础模块。

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
| **W2 · WAITING_EVIDENCE（本地部分实测，完整验收未达标） · A/I** | 1909771源码/CI/非作者审查及受控Home实测完成 | 基于实际页面完善普通对话Chat判别，完成真实网络中断/100%后失败、延迟点击/多窗口/业务草稿变更与恢复矩阵 | 保留已验证的生成图片成功、持久补偿和观察-only；生产成功与safe-retry仍需独立准入，不重做Core/截图/UI基础 |
| **M1 · 原生后端DONE；客户端WAITING_EVIDENCE · I/A** | 已完成M0；原生后端不等客户端结构 | PR #3已合入工程分支；原生AX/NSPasteboard、全局协调及完成后只读观察随201项整合CI通过；接下来只按真实版本/surface证据补MacAXBindingProvider/profile | 后端范围见[M1交接](M1_NATIVE_BACKEND.md)；实际M00–M06、选区/旧附件/逐图完成仍未验。默认禁用、内置profile空，不借用Web结论 |

W0不是通用证据平台，只是现有协议的可回归小fixture集合。W1的transport外壳可以和W0并行；若当前三角色已满则顺序补位，不能通过重复实现Core或同时堆两套Web transport制造并行度。

### 4.3 验收和发行线

| ID / 状态 | 当前已有/可先做 | 精确解锁条件与届时动作 |
| --- | --- | --- |
| **N1 · WAITING_EVIDENCE（本地部分实测）** | N01/N02系统窗口截图子集与2/3/12场景已实测；Mac及两块显示器可用，详见真机交接 | 完成物理N05/N07、热键、自包含、Spaces/全屏/热插拔/睡眠及资源/端到端延迟测量，不把子集当完整PASS |
| **R0 · DONE（当前合流工程构建）** | 76a8385通过201 native/20页面VM、release/app签名和三个自检；原分支CI仅保留历史 | 后续修改由I1持续验证；Intel/其他OS若未测只注明，不虚构全平台支持 |
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
