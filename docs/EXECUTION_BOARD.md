# Riftlet 自主并行执行队列

> **第九轮独立交接（2026-10-28）**：Web/真实 App 源码 fcb052b，最终 helper/完整构建源码 23becda；v10/v12 旧监视器兼容在真实页面恢复，原 descriptor/操作保留。原冷首击 ACK 仍晚约209ms，安全拒绝零输入；补位双击实测软件路由 PASS，人工物理 NOT_RUN。144页面/legacy、完整构建/四自检及非作者审查 PASS；本机 XCTest 缺失，CI40555899978 尚待执行，不能写全套 native PASS。系统截图候选4d352c2未在此分支集成，生产准入不变。[准确结果与交接](../engineering/evidence/2026-10-28-real-mac-round9/README.md)。

> **第八轮独立交接（2026-10-28）**：源码 `ee1d960`，已含正式 `595142d`。CLEAR 真正底层 down/up 与按住补位为软件实击 PASS；冷首击仍 FAIL（无 pre-event ACK、零输入），AX bind 顺序改进已实测，v10 root 冲突明确诊断。隔离扩展/native 通道可运行但不具输入授权。人工物理/compact完整矩阵/全屏等 NOT_RUN；功能 CI40544274635 PASS，最终诊断 CI40546396233 因 runner 容量不足 0 步骤 NOT_RUN。全部数据保留，生产准入不变；[准确来源和 CI](../engineering/evidence/2026-10-28-real-mac-round8/README.md)。

> **第七轮独立交接（2026-10-27）**：源码 `9de6a85b0161713833dc25e3b3eb1e1a2f81a558`；[macOS CI 40525056642](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40525056642) PASS。真实双图在原目标 FIFO 中 B prepared→A succeeded→B 唯一输入，两张最终成功；冷首击 ACK 晚于点击 26.742 ms 仍 FAIL。CLEAR 防误选修复已真实 CGEvent 复测，透传仍 FAIL；GAP/IMAGE/NUMBER 仅软件路由 PASS，人工物理 NOT_RUN。[第七轮证据与 Pro 交接](../engineering/evidence/2026-10-27-real-mac-round7/README.md)。保留 v3、旧媒体/UNKNOWN/审计，不启用生产输入/重传；正式集成由 Pro 负责。

> **第六轮独立真机增量（2026-10-27）**：Web v12 分块优化真实点击至 AppKit 关闭 5.51→3.67 秒（单次对照），无 ACK 冷首击已真实复现安全拒绝；同草稿第二图明确在 Core targetBusy 被取消、未输入。Core/UI/App 不改，Pro 安装专项不混入。源码/CI/保留核验/顺序调度提案见 [第六轮交接](../engineering/evidence/2026-10-27-real-mac-round6/README.md)。生产截图与安全重试仍关闭；首击与连续点击不标整体验收通过。


>
> **Pro research handoff received (2026-10-27):** [read-only technical findings and minimal acceptance tasks](PRO_FEASIBILITY_REVIEW_FINDINGS_2026-10-27.md). Web no-editor-focus one-click is conditionally feasible but cold first click not yet accepted; Mac separate. System Screenshot.app cannot currently be promised universal exclusion; implement robust persistent user hide, isolate source in real N1 before any optional automatic-hide experiments. Prioritize ACK/main-thread/NSEvent timing, authorisation gap, empty-generation retirement, usable-composer gate and UI archive-protection. **No source code, source acceptance or production adapter changed by this document.**

> **NEW RELEASE UX REQUIREMENTS P29–P33 (2026-10-27):** [RELEASE_UX_REQUIREMENTS](RELEASE_UX_REQUIREMENTS_2026-10-27.md) confirms focusless composer single-click, subtle invalid-click feedback, interaction-safe archive, and the lean public-release baseline. Screenshot self-inclusion is a **technical feasibility study**, not a guarantee; see [Pro focused research brief](PRO_FEASIBILITY_REVIEW_BRIEF_2026-10-27.md). **Do not disrupt existing W2/N1/M1 implementation or mark release requirements PASS from current synthetic/partial tests.**



> **2026-10-27 NEW USER PRODUCT DECISION:** [INTERACTION_CONTRACT_2026-10-27.md](INTERACTION_CONTRACT_2026-10-27.md) now governs the final screenshot/rift lifecycle: current target at click; **positive upload start → very fast swallow**, not READY-only; only explicit/extremely high-confidence failure → rebirth; swallowed UNKNOWN stays locally hidden; idle archive, single/bulk removal, and **no slit at zero visible items**. Current source, acceptance and success/failed gates have **not** been revised merely by this note. The integration lead should create/claim a separate implementation+real-acceptance packet without discarding already passing W2/N1/M1 evidence. No unreviewed merge or production enablement. **Additional user rulings P23–P28:** no success Toast; no composer means no swallow; failure-qualified rebirth must be a normal clickable screenshot with ordinary archive/removal; queue clearing never removes ChatGPT attachments; optimize consecutive clicks only when safe. Hold-and-drag remains unapproved. Update product UI/state-machine acceptance accordingly; do not treat these product decisions as already implemented.

2026-10-27（北京时间）。本文件是可续做的工程队列；总体范围见 [ENGINEERING_PLAN.md](ENGINEERING_PLAN.md)。用户不承担日常任务分派、实现取舍或逐项审批。负责人完成一包后自动领取可做的下一包。

**M1 独立执行记录（历史，合流前）**：用户已将真实 Mac 的 W2/N1 与 Web 两次操作闭环交给本地 Codex；本会话不访问或争用其设备。以下 PR #1 表格及 W2 结果是继承到 `485fa87` 的检查点，不冒充另一会话的新结果。M1 在独立分支 `codex/m1-native-backend-20261027` / [Draft PR #3](https://github.com/haohongfei2001-png/Riftlet/pull/3) 完成原生后端，已测 `7dfa8ec`、173/173 原生测试与非作者审查通过；实际客户端准入仍等待真实证据。唯一正式工程集成负责人保持 root，后续按分支成果整合，不直接争写 PR #1。

## 1. 当前检查点

### 第七轮成果正式合流 · DONE；下一轮直接基于本检查点真机增量

正式基础e3175f3，双亲合流2aaaadb保留第七轮3b089b2及其历史，追加权限接收进程修复后已测 **`595142d0345adc0d06f54371f50406879310610d`**。App同步ordinal、runtime AcceptedSelection、既有Coordinator有界prepared等待/取消/唤醒、原目标与权限重检、重启不恢复旧点击及CLEAR防误选已实际集成；v12/首用/PassivePermissionResume/v3/旧UNKNOWN和原证据保留，没有重复第五、六轮。

[完整组合CI40543025253](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40543025253)于2026-10-28 **00:41:17北京时间** completed/success：410原生（Core134/Adapters121/Capture63/UI53/App39）、72页面/54legacy、回放/故障/probe/helper/包装、Release/签名/四自检通过。10详细suite共77项passed、0skip，已包含410。三位非作者实际并行审查，权限旁路/跨进程接收对象两项发现已由root修复并复审；完整日志也独立复核。原来源408项CI不替代此组合运行。[永久证据](../engineering/evidence/2026-10-28-integration-round7/README.md)。

**下一次现场入口：** 从PR #1最终交接SHA建新worktree，沿用[现有接口](ADAPTER_CONTRACT.md#第七轮已集成的原选择等待)与[原生验收](INTEGRATION_HANDOFF.md#下一次真实mac直接入口)，不重新开发FIFO、不重传旧UNKNOWN。双图限定PASS为B等待A最终成功后再一次输入；不是start后并行。冷首击FAIL，CLEAR防误选PASS但透传FAIL，GAP仅software。继续真实冷边界、CLEAR/物理GUI、ABA/MID/安全失败、自包含及修复后TCC/多进程复测；生产与重试仍关闭，具体结果独立交接。第七轮分支未被写入，无法从远端断言其本地无未推送工作。

### 第六轮稳定成果正式合流（历史检查点）

已测组合 **`81b6a61b4e648a1b8d6ccf4b569fd6d727a0cc76`**，双亲1246c4a/65f7d54，共祖3bb13999。仅整合7878de3、c000cc1、65f7d54三个独有提交，保留13份原证据与双方历史；没有重复cherry-pick第五轮。v12最多256KiB、逐块ACK/双遍文件hash/唯一input、严格Chrome绝对descriptor及fallback、v6–v11只读恢复已合入。正式App/Core/UI/Capture/SQLite v3/首用/PassivePermissionResume均未改动，生产与Web安全重试仍关闭。

[完整macOS CI40523594732](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40523594732) completed/success于2026-10-27 **22:44:24北京时间**：380原生，72页面/54legacy，原回放/故障/probe/helper/包装、Release/签名/四自检全部通过；七个详细suite13/3/15/4/5/8/5均passed、0skip，包含在380内。源码、权限组合、原证据、共享契约和完整实际CI日志由非作者审查通过。[永久证据](../engineering/evidence/2026-10-27-integration-round6/README.md)记录对象/原hash/全部测试名。

**第七轮直接接入：** 本地Codex独占安全排队及真机实现，本会话未读取其进行中分支。按[最小共享边界](ADAPTER_CONTRACT.md#第七轮顺序调度共享边界-v1实现待正式交接)固定权限await前的原选择序号、无capture被动preflight、唯一drain/有界等待/不丢唤醒和原事务门。未实现或准入同草稿start后第二图输入，不另建Coordinator。冷首击产品FAIL、安全拒绝有效；同草稿第二张targetBusy产品FAIL。5.51→3.67秒是旧overlay二进制单次对照，不是当前权限前置组合的实测。确切最终文档HEAD见PR #1交接；以下保留历史。


### 第五轮真实开始 + 首次使用正式合流（历史检查点）

合流已测 **`caa6a65b69c6038154a2fff65f2fb1157125bb7e`**，双亲 `e655b1e` / `3bb13999`，保留第五轮53ebcc4的全部源代码与27份原证据。v11/schema2开始观察、严格归一化/早返回、v6–v10只读、两个允许的App/UI最小overlay已进入同一正式App；只有隔离生成图片Web模式的start profile获准，生产及安全重试保持关闭。失败CUA窗口排序只存档，不应用；原Core/SQLite v3/Capture/历史/首次使用保护保留。

实际修复初次Chrome不可用导致以后缺少自动恢复入口：仅Web模式由Chrome激活/唤醒触发被动重检，合并事件并拒绝旧代际；安装前保留取消/latch保护，原点击目标不换、不等较晚ACK、不回放。新permission_check时钟诊断仅在验收trace中记录，不缓存权限或代替开始证据。

[macOS CI40515643640](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40515643640) completed/success于 **21:53:30北京时间**：369原生（Core117/Adapters110/Capture63/UI52/App27），页面68/legacy45，第五轮helper9/4/2、包装12、原回放/故障/probe、Release/签名及四自检全部通过。原生命周期13/首用3/Capture15、新呈现4/Web组合5/权限恢复8详细复跑均passed/0skip，已含在369内。源码、原证据与实际完整日志非作者审查通过，见[第五轮合流证据](../engineering/evidence/2026-10-27-integration-round5/README.md)。

**直接续做边界：** 本地Codex第六轮继续其独立工作；本会话未读取/合并进行中成果。交接后由root整合，不重复v11或首用。第五轮真实一图只证明预绑定、聚焦、空草稿、软件AX的受限链路；该App不含新权限前置，5.51秒点击→close不能冒称新二进制时延。新权限/单击/时延、冷首击/业务ABA/草稿保留/MID/物理GUI/自包含继续真实验收。确切最终文档HEAD见PR #1最终交接；旧检查点作为历史保留。

### 首次使用与发行基础体验 · 代码、macOS CI 和非作者审查 DONE

正式起点 `e89d49f`；实现 `4e080aa`，已测修复 `2449d40a88225acba9d413cc6a4cb5d84fcae6a1`。root 与三个独立执行者实际并行完成原生首用/状态窗口、按需权限恢复、Capture 诊断/原字节保真/空间预检及 App 打包保护；没有改 Web/Chrome、Core、SQLite v3 或上传开始契约。普通用户基础设置不需终端或 JSON；普通收录模式不请求 Chrome 权限，生产能力未启用与权限问题明确区分。隐藏、暂停、空队列和待核实分开；没有成功 Toast。

[实际 macOS CI 40508109228](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40508109228) 完成成功：344 个原生测试（新增 38 已计入），详细生命周期 13 / 首用软件窗口 3 / Capture 15 全部 passed、0 skipped，Python 包装 12、页面 48 / legacy 14、原回放/故障/probe、Release、ad-hoc 签名及四个 App/helper 自检通过。首轮两处缺少 `try` 的真实编译失败、修复和非作者独立读日志复核均保留在 [本轮证据](../engineering/evidence/2026-10-27-release-ux/README.md)。

**直接续做：** 本地 Codex 继续既有真实 `uploadStarted`、一次点击、草稿身份和物理验收；不重复本包、不占用其设备。合流 App 时保留新增被动权限检查及原冻结目标，在新完整路径上测量点击时延。真实 TCC、书签/目录授权、Finder 首启、物理辅助功能等仅阻塞 [首用真机验收表](FIRST_USE_ACCEPTANCE.md#真实-mac-专项全部保留-not_run)，不能用本轮 CI 宣称通过。签名/公证/自动更新没有凭据时保持独立未发行项。确切正式 HEAD 以 PR #1 的本轮最终交接为准；以下历史增量保留。

### 第四轮 Web 合流 · DONE；真实开始接入 · 本地 Codex READY

正式起点 `b848920`；保留本地 Codex `35e9851` / `c9c68a6` / `03a67cc` 全部历史与11份原证据，合流到现有 SQLite v3 / Core / UI / App。root 实现最小 persisted-profile 识别及 host-only request→App publication 诊断，非作者已审查源码；完整合流已测 `c85020b` 的 [macOS CI40484855920](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40484855920) 通过：306原生、48页面、14legacy、13生命周期逐项passed/0skip、既有离线回放/故障/probe、Release/签名/三个自检；证据和首轮编译修复见 [VERIFICATION](VERIFICATION.md) 与正式交接。生产上传/开始/安全重试均未开放。

本地 Codex 下一项 READY 工作是 [uploadStarted v1 直接接入](UPLOAD_STARTED_CONTRACT_V1.md#7-第四轮合流后的直接接入要求)：实际开始证据、严格版本归一化、append 早返回及新版 v3 App 真机快吞噬。当前 Web 尚未返回开始回执，不把第四轮旧生命周期的一次预绑定成功当作新版体验通过。冷首击、业务 ABA、原非空正文/附件/选区、MID、物理 GUI、自包含仍保持原未通过范围。以下各历史检查点继续保留，当前工作不重订总体计划。

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

**当前续做入口：** 第七轮实现和固定证据已正式集成，详见上方当前检查点；本地Codex直接继承最新正式SHA推进冷首击、CLEAR实际穿透/物理GUI、真实业务转换、MID、安全失败和自包含，修复后权限/多进程时延分别实测。沿用已集成原选择FIFO，不再复制提案模型、不放开UNKNOWN/start锁。只有正式交接后的成果由root统一合流；生产仍未开放。

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


## 第四轮本地候选交付 · 已留检查点（非全部准入）

起点 a441c70f3c4071069bd594513ecf16600bbb0ab8，独立分支 codex/riftlet-real-mac-round4-20261027。Web/Chrome适配器、页面JS、对应测试及验收helper由本地Codex处理；Core/UI/App产品接线由Pro负责。按PR #4契约90a04883160032fc6354fb4f3d3f7d56fede2947执行：实际uploadStarted后快吞噬与最终READY分开，不能将旧READY动画当新版PASS。当前修复正文/侧栏非composer焦点、跨v6/v7原操作只读路由、原生ACK因果诊断；保留所有旧数据，不改变生产与安全重传准入。

源码 `c9c68a66c4b6ff55ffe8048cff6f1cf781600519`，CI 235 native / 48 page / 14 legacy PASS。真实普通已保存对话（裸 UUID）发言框未聚焦、已有预绑定 ACK 的一次人工物理点击：单次 input、完整 proof、used，局部 PASS。冷首击无 ACK、真实 ABA、非空原草稿/选区保留、完整 N1 和 MID 仍未通过；生产与重传保持关闭。新 persisted profile 在 Core 尚未识别，继续保守整 tab 锁，最小 Core 补丁交 Pro。见[第四轮完整交接](../engineering/evidence/2026-10-27-real-mac-round4/README.md)。下一项优先原始点击/ACK 发布边界与真实业务转换，不重复普通成功样本。


## 第五轮本地真实 uploadStarted · 候选完成，交 Pro 集成

独立分支 `codex/riftlet-real-mac-round5-20261027`；最终已测源码 `53ebcc4da4b0df508edc11f6ead9ea4d8a843dad`，正式基线 `e89d49f763036781c90618422da256e03cbca2ac`。完整 CI [40497953468](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40497953468) PASS：314 native / 68 page / 45 legacy / 13 lifecycle detailed。Web v11/schema2 保留 v6–v10 原操作只读；修复真实初始无数值进度误拒绝，以及真实 MutationRecord NodeList 没有 `.some()` 导致 start 早返回后观察中断。

实际生成图片的 **一次 helper AX → 真实递增上传开始 → AppKit 快吞噬 → 后台独立最终成功 PASS（限定）**。原 input=1、完整 target/attachment、首份 start 审计、较晚 final proof 和 persisted succeeded 对齐；开始后约59–322ms调用动画，动画段约253ms，窗口关闭早于最终证明约4.89–5.16s。不是物理鼠标或无ACK冷首击；原保留配置swallowDuration=.24，不是点击到关闭仅253ms。

Core/UI/App正式源码未改；两份最小临时overlay供Pro接入synthetic start策略及诊断/AX元数据。生产、safe retry仍关闭。原11 Web资产/17操作/3补偿及所有原私有媒体哈希保留，新增5图各input1，其中2图未决保持原样；未发送消息。详见[第五轮完整交接](../engineering/evidence/2026-10-27-real-mac-round5/README.md)。本段替代此前“等待人工点第2张”的准备检查点；无需再请求该动作。下一项为Pro集成限定synthetic补丁，其后继续冷首击、业务转换、同草稿多图与物理N1，MID及安全终止分别准入。
