## Feedback cloud continuation — 2026-10-29

The Feedback-only successor starts from the latest unified PR #15 source `c15fd4b4a27659946ef49280131e875f4d5ab9d1`, preserving all existing product history and screenshot admission. It adds bounded delivery fairness, D1 maintenance indexes, source-bound Beta capability metadata and actual receiver acceptance evidence. The dedicated HTTPS receiver and D1 are live; the Delivery Worker/private Issue path remains incomplete after the browser connection disconnected. Host remains nil. [Current cloud checkpoint](../engineering/evidence/2026-10-29-feedback-cloud/README.md) records exact observations, resources, test cleanup and remaining conditions. A new reviewed source and unchanged full workflows are required before the successor is admitted. Physical Mac work is prepared for Codex, without a scheduled executor or MAC PASS claim. Earlier checkpoints below retain their original scope.

## 2026-10-29 Feedback 可靠性与正式继承

源码 `7ef6cd4b` 已完成反馈可靠性修复、标准 macOS15 运行器迁移及非作者审查，完整 Native/Feedback CI 已通过，真实统一 Beta 安装包已下载核验。正式工程文档后继的最终 SHA、新正式分支 CI 和下载固定在 [PR #1](https://github.com/haohongfei2001-png/Riftlet/pull/1)，细节见 [Feedback 交接](FEEDBACK_V01_HANDOFF.md)。当前截图实现与准入、真实 Mac 工作树、原有历史与数据均保留，main 未合并。私有反馈仓库已建立；Cloudflare 登录和离线 Mac 仍阻塞真实原生到云端验收，endpoint 继续为空。以下原交接记录保留为历史。

---
> **2026-10-29「薄界」原生实施独立候选**：`codex/riftlet-real-mac-acceptance-thin-edge-20261029` 按最终设计继承预测入口与磁力基础，完成共享原生视觉、稳定裂缝/编号/分页/预览、入口空间统一和四相可中断动效。真实2x窗口截图、原生合成动效录像及CGEvent路由已取证；不重测上传、不改变生产或重试准入，不覆盖正式Pro分支。准确源码、macOS CI、非作者审查、未验项与可运行App说明集中在[独立交接](../engineering/evidence/2026-10-29-thin-edge-native/README.md)。所有新精确视觉参数仍为实施候选；本轮不要求创始人体验。以下保留历史与正式检查点，不把独立候选当作已经正式整合。

# 当前正式交接：Beta 体验修复与可运行版本更新 · 2026-10-28

从正式 `b4bcfa41e8e237723b975d2a9a0059e955fa0c1f` 在独立 worktree 合入 `8e1a1688e75db8c18965e073ae357010e7397a3a`，后者包含 Codex `fa74f3c68f05ab4eaccfc24e2f39c0177289ddb3` 体验修复与八份原始脱敏证据。Main 两处冲突逐块保留 owner/revision、精确错误提示、prepared/cancelled 展示和全部原 Feedback 接线。固定来源审计准确更新获准文件和 Main，不跳过、不豁免任意 UI/App 修改。

[当前安装和创始人体验入口](INTERNAL_BETA.md) / [本轮来源与审查](../engineering/evidence/2026-10-28-beta-ux-integration/README.md)。最终正式 HEAD、组合 Native/Feedback CI、非作者审查及下载包摘要固定在 [PR #1 最新交接](https://github.com/haohongfei2001-png/Riftlet/pull/1)。本地 Codex 直接继承该 HEAD，不重复合 fa74/8e1、Feedback 或 H。旧 UNKNOWN、媒体、历史与审计保留；普通生产与安全失败/重试关闭，Feedback endpoint=nil，不部署云端，不合并 main。

证据严格区分：人工 helper 来自 e421，Feedback 窗口软件检查来自 b4bc，独立修复 CI40693945938 来自 fa74；均不冒充最终组合 App 的新真机验收。交付后优先创始人体验，遇到实际问题再定位，不扩常规验证。

## 历史交接：首份统一内部 Beta

当前交接见 [统一内部 Beta：安装、启动和体验检查点](INTERNAL_BETA.md)。H 真实快吞噬 `c177174` 为 e421 的直接证据子提交，仅新增七份脱敏文件，限定软件 CGEvent PASS；人工物理鼠标 NOT_RUN、无 ACK 冷首击未解。Feedback v0.1 `f195beb` 按真实祖先合入，截图以 e421 为权威，Main 仅最小反馈接线；完整 App 附明确内部候选启动入口。反馈 endpoint 为空，本机待发送不能显示云端成功。原反馈分支不写入，main 不合并，PR #1 保持 Draft。

旧 UNKNOWN 不重传、不清除、不解锁；普通生产、安全失败和安全重试关闭。最终精确正式 SHA、完整 Native/Feedback macOS CI、非作者审查与实际 App artifact 由 [PR #1 最新正式交接](https://github.com/haohongfei2001-png/Riftlet/pull/1) 固定。下方各阶段的“待真机、反馈未合入”等表述仅属于对应历史检查点，不覆盖本段。

---

## 历史交接：第一、二阶段正式集成（871d825）

以下为该检查点原文；其中“修复后新输入未运行、三准入关闭”的旧状态已由上面的 F 真实证据与独立受限准入决定更新。其权限/兼容修复、审计、祖先和历史证据继续保留。


## 当前继承入口

正式分支仍为 `codex/engineering-foundation-20261027`，Draft PR #1；本轮由当前唯一正式集成负责人从 `4b7228a07a23381d3de467a44dd8490d73e26e7e` 在独立 integration worktree 完成。实际 Git 历史是：

`4b7228a → a5db972 → 3f4e18a → 5d2994c → 867d93f → 48574df → f2ae645 → 本文所在的交接提交`

第一阶段已是第二阶段祖先，采用快进继承；没有重复 cherry-pick、压平历史或另造合流。最终准确正式 HEAD、实际完整 macOS CI 与审查结果由 [PR #1 最新正式交接](https://github.com/haohongfei2001-png/Riftlet/pull/1) 固定；本目录的 [永久集成证据](../engineering/evidence/2026-10-28-integration-sc-stages1-2/README.md) 保留源码检查点、对象和非作者审查。该交接提交只更新文档/证据，产品源码、测试和构建输入与 `f2ae645451044649fbe73326952efbe084353869` / `48574df19f34e5681ee98815750e279540e9eb9b` 相同。

### 已进入组合的代码

- 第一阶段 `a5db972b7c4da20d30266ec8d1411fff9f434c13`：在取消原选择、清除 armed/frozen 状态并推进 epoch 后消费权限丢失的 idle wake；只恢复新的目标观察，保留单一在途、旧 epoch ACK 拒绝及严格原事件前 ACK。三项回归随完整原生 CI 执行。
- 第二阶段 `867d93f797952fd0402d50525f384f2f416c1b93`：v13 的严格同 root owner 白名单加入完整 v9，继续兼容 v10/v12；不替换 descriptor、不停止原监视器、不修复旧 proof、不让旧操作重新输入。无 armedTarget 时的诊断布尔值修正为 false，不赋予授权。
- 第二阶段 `48574df19f34e5681ee98815750e279540e9eb9b`：移除 `willReadFrequently`，保留显式 sRGB。完成仍要求精确文件字节或相同尺寸及全部 RGBA 的精确 SHA-256，且绑定原节点、source、最终 load 与完整原身份；没有像素容差。
- 原 Core、Capture、UI、SQLite v3、首次使用、被动权限恢复、原点击/AcceptedSelection、UNKNOWN、补偿与首观察审计保留；两阶段原始脱敏证据字节不改。

### 真实证据和准入必须分开

| 项目 | 当前准确状态 |
| --- | --- |
| SC-INPUT | **限定 PASS**：继承实际系统 PNG、CGEvent 单次点击、原事件前完整 ACK、原身份和 inputCount=1 的记录 |
| SC-START | **限定 PASS**：第二阶段原操作的同一进度节点递增中间值及持久候选 start；不保证快速小图或所有环境 |
| SC-COMPLETE | **旧运行源码 FAIL；修复后新系统截图输入 NOT_RUN**。只读颜色对照和 macOS CI 不补签真实完成 |
| 候选开始／完成／安全失败准入 | **三份映射继续为空**；本轮不会因为继承 START 证据自动开放 |
| 普通生产／safe-retry | **关闭**；PR #1 Draft，不合 main、不公开发行 |

第二阶段保留性证据只覆盖其普通线程样本的 48 字符、非空选区 8..11、未聚焦 editor，旧附件基线为 0、附件总数 0→1；非空旧附件矩阵、人工物理鼠标、无 ACK 冷首击、业务 ABA、MID、自包含和完整 T0/T1/T2 均不能由本轮 CI 升级。

### 本地 Codex 直接继承

从 PR #1 交接固定的最终 SHA 建立新的独立 worktree，保留旧工作树、系统原件、私有媒体、同一候选 SQLite v3 数据根、UNKNOWN、补偿和审计。已有第一、二阶段无需再次合入或重复验收。沿用：

```bash
bash scripts/build-macos.sh
./build/Riftlet.app/Contents/MacOS/Riftlet --system-screenshot-candidate --acceptance-trace
```

唯一待续的完成路径是：在原规则允许的独立业务草稿，使用**另一张新的真实系统 PNG**执行一次用户点击，记录修复后的精确 proof、原附件 attached journal 与正文/选区/旧附件保留；不重输旧 A/D，不回填旧 proof，不补造 uploadStarted，不新建数据根或清锁/重建数据库。仍使用 `Riftlet REAL TEST` 与原候选数据根。没有获准开始证据时不假吞噬；即使页面已上传，当前未准入的本地 UNKNOWN/可见不代表输入失败。

### 后续持续集成归属

当前负责人是正式工程唯一写入者。本地 Codex 真实 Mac 修复和反馈 Pro 的**正式交接**均由该负责人先刷新远端、核对祖先、独立审查并验证组合后纳入 PR #1；不重新合并已经是祖先的提交。更新正式 ref 使用预期旧 SHA 和非强制快进，若远端发生未知变动先停在独立集成分支核对。

反馈 `codex/feedback-v01-20261028` / Draft PR #7 继续独立开发；本次没有引入其 `RiftletMain.swift` / Package 接线，也没有写其分支。后续正式交接时以实际共同祖先整合两个 App 改动，不用整文件覆盖。

---

## 以下为已保留的阶段交接与历史记录

下文的“未修改正式 PR”“下一轮首验”“NOT_RUN”仅表示对应历史检查点；当前状态以上文及 PR #1 最新精确 SHA/CI 为准，原失败和证据不改写。

# 正式工程交接：第八、九轮与真实系统截图候选合流 · 2026-10-28

## 修复版真实系统截图完成复测 · 2026-10-28

本轮独立分支 `codex/riftlet-real-mac-acceptance-sc-complete-20261028`，运行源码 **48574df19f34e5681ee98815750e279540e9eb9b**，无生产源码新增修改。新系统PNG（6,796,322B，1746×1164）经一次实际微图CGEvent点击，**SC-INPUT/SC-START/SC-COMPLETE限定PASS**。原页面严格sRGB proof与候选attached journal一致；独立RGBA 8,129,376通道零差异。48字符、editor内8..11选区、未聚焦状态及一张稳定旧附件完整保留。

同一源码[CI40656871851](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40656871851)已核实success，非作者原始证据及脱敏审查PASS；不冒充新CI。候选本地仍unknown/visible，三准入关闭，旧A/D和历史全保留，不重输。正式Pro可依据[本例完整证据](../engineering/evidence/2026-10-28-system-screenshot-complete/README.md)分别审查受限开始/完成准入；物理鼠标、无ACK冷首击、旧v7/v8页面兼容及安全重试仍不在PASS范围。本轮已停止输入并结束现场工作。


## 系统截图第二阶段限定交接 · 2026-10-28

独立分支 `codex/riftlet-real-mac-acceptance-sc-stage2-20261028`；源码 `867d93f`（v9兼容+实际输入）、`48574df`（普通sRGB严格像素比较修复）。[macOS CI40656871851](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40656871851) PASS。一张1.56MiB真实系统PNG一次CGEvent点击，SC-INPUT/SC-START PASS；正文48字符、非空选区8..11、编辑器未聚焦保留。完整SC-COMPLETE仍FAIL：旧运行代码的willReadFrequently导致1级颜色舍入不匹配；同原图/原预览的显式sRGB单变量对照严格相等，源码最小修复已构建，但未新输入复测，旧D继续UNKNOWN。

只需集成后用另一张新系统截图独立复测最终proof/attached；禁止重输D或回填它的完成。开始、完成和安全失败准入仍分别关闭。非空旧附件、物理鼠标和无ACK冷首击不在本次PASS范围。完整身份、原媒体、数据库、日志只保存在私有目录；[脱敏结果、源码范围和数据保留](../engineering/evidence/2026-10-28-system-screenshot-stage2/README.md)。正式Pro工作树、PR#1及main未修改。


> **独立Mac真实系统截图交接（2026-10-28）**：`codex/system-screenshot-real-20261028`，修复源码 `a5db972b7c4da20d30266ec8d1411fff9f434c13`，CI树 `3f4e18a15d8cc77a367beca30ade338906df9d8d` / CI40647857737 PASS。可直接审查最小App wake修复与3项回归。真实系统PNG已有唯一输入、原附件attached候选；SC-START未取得，保留性矩阵未验，三项准入不得开启。[准确证据、协议偏差和剩余项](../engineering/evidence/2026-10-28-system-screenshot-real/README.md)。本段是独立分支提案，未修改正式PR #1或扩大Beta准入。

本节为当前入口；下方旧交接仅作历史。基线 `d6a083dec660990bd65124e7acd78f2d900b5013` 与固定第九轮 `b30bb80d5af5cc12b0640c3609f70292709738a1` 保留双亲历史；共同祖先 b839230，第八轮 8914c702 已是第九轮祖先，不再 cherry-pick。最终正式 SHA、组合 CI 与审查结果以 PR #1 的本轮交接记录为准，来源 CI 40555899978 不替代组合 CI。

## 本轮组合范围

- 第八轮：原视觉/AX 窗口忽略鼠标，图片与编号为独立非激活输入窗口；外部 CLEAR padding 可由 WindowServer 路由给底层窗口，无事件转发。原按下身份、隐藏、吞噬及补位生命周期保留。AX 提示注册移到当前捕获尝试之后，不产生 ACK 或权限。
- 第九轮：v13 只借用同 root、明确匹配的完整 v10/v12 原监视器；保留原 accessor、旧 operation/proof 和 v6–v12 只读恢复。新旧 generation 权限分离，不重建缺失证明。沿用已声明的 MAIN-world registry 完整性假设；不是对恶意闭包替换的认证。
- 真实截图候选的精确程序版本同步为 v13，仍要求自己的 origin/profile/journal；加入旧 sourceID 拒绝回归，不能放宽为任意程序。Core、SQLite v3、preflight、accepted+30 截止修复、独立数据根、首观察审计及三份空准入映射保留。
- 第九轮 helper 在原系统双击时间界内等待真实窗口几何再投递第二对软件事件；它验证既有补位防误选，不替代物理鼠标双击分类。

## 直接交给本地 Codex：先取得真实截图原始证据

无需重新研究架构，也无需先实现失败安全重试。从本轮最终正式 SHA 新建独立 worktree；保留所有现有工作树、数据库、原图、私有媒体、UNKNOWN、补偿及旧观察器。只用新截图，不重传旧未决。

```bash
bash scripts/build-macos.sh
./build/Riftlet.app/Contents/MacOS/Riftlet --system-screenshot-candidate --acceptance-trace
```

也可从普通 App 菜单选择“打开真实截图内部候选…”。核对 `Riftlet REAL TEST` 与独立 `Riftlet-System-Screenshot-Candidate` 数据根。普通实例仍只收录；测试时避免两个实例的裂缝叠放。首次授权、Chrome JavaScript 开关沿用已有原生引导，不安装扩展，不强制聚焦编辑器。

第一轮顺序与判断：

1. **SC-INPUT**：新系统 PNG 的来源、原字节/私有副本/hash、大小/像素、原点击、先行完整 ACK、完整 target、asset/operation/attempt 和目标文件 `inputCount=1`。不得自动发送消息。
2. **SC-START**：同一原操作/附件的正向进度观察及原文件身份；保存现有 candidate checkpoint，排除 files/change/占位和错目标/错图。不要因当前仍可见而重复点击。
3. **SC-COMPLETE**：同一原附件实际完成与精确内容证明；原正文、选区及已有附件不变。分别记录页面事实、候选观察和本地可见性/UNKNOWN，不把这三个层次混在一起。

**三份候选 start/completion/safe-failure 映射仍为空。** 即使真实页面已正确收到附件，本地仍 UNKNOWN、仍可见，是当前未准入策略的预期结果，不是输入失败；同草稿锁不能被清除来演示连续上传。取得原始 SC-START/SC-COMPLETE 并独立审查后，可以分别准入受限内部候选，复用现成快吞噬；普通生产和 safe-retry 不随之开启。证据公开前移除真实截图内容、私有正文、浏览器认证与完整目标秘密。

## 继承的范围，不扩大为 Beta 通过

第八轮 CLEAR/GAP/IMAGE/NUMBER 与按住补位是限定 CGEvent 软件路由 PASS；不是物理鼠标或图片 alpha/圆角逐像素透传。第九轮保留真实 Chrome v10/v12 只读识别恢复，以及第二击确实到 B、B 零选择的软件双击结果。没有本轮新真实截图/上传/GUI 证据。

无先行完整 ACK 的冷首击仍安全拒绝；第九轮该样本 ACK 晚约209ms，禁止晚到 ACK 补造原授权。业务 ABA/同 URL 无可观察切换、MID、真实安全失败、物理 GUI/显示器矩阵、系统截图自包含与 T0/T1/T2 继续开放，不阻止先取 SC-INPUT/START/COMPLETE。浏览器扩展实验只原样归档，不进入 App/bundle 或正常使用前提。

---

## 前一候选工程交接（历史原文）

# 正式工程集成交接 · 真实系统截图内部候选 · 2026-10-28

## 当前正式组合：系统截图候选接线已实现，生产准入仍关闭

正式基线 **b83923068064f6d82f2d253a3c177661fdabc294**；独立分支 `codex/system-capture-candidate-20261028`。实现 **3da1288f8b16fbf46082ebf78eab92a1e2089d22**，已测边界修复 **4d352c28dcb70e8f6dc42ef93d9df46042a9215d**；审查后以快进方式接入PR #1，全部既有历史保留。最终文档/证据HEAD以PR #1本轮交接评论为准；它与此已测源码的构建/测试输入必须相同。

候选把真实系统截图收录与现有Web v12输入接通，保持原Capture/私有副本、SQLite v3、单一Coordinator、AcceptedSelection/FIFO/权限、MAIN和后台原操作观察。新增本地图片preflight（prepare之前）、独立origin/profile、原SQLite六类首观察journal、共用App组合与原生菜单入口；没有新建Web系统或修改页面/Chrome源。截止判断修复与App原 `acceptedUptime + 30` 一致，不放宽ACK/到期/取消门。

当前候选允许受限真实PNG输入，但**开始/完成/安全失败三份映射均空**，没有生成图准入可借。候选start/attached会保存在私有checkpoint，队列仍UNKNOWN且可见，不自动吞噬、不记成功、不释放同草稿未决锁供盲重传。普通capture继续UnavailableAdapter；这份候选是下一步真实取证入口，不宣称普通产品已可用。[确切接口、格式矩阵与SC证据门](SYSTEM_SCREENSHOT_WEB_CANDIDATE.md)。

[候选macOS CI40551804340](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40551804340)已通过433原生、72当前页面/54legacy、迁移/UNKNOWN/补偿/权限/调度、Release/签名和五自检，100个详细复跑已含433。正式PR组合CI为[40553084871](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40553084871)，于2026-10-28 01:54:27北京时间completed/success，17步骤/433原生/五自检再次通过。合成/真实范围、首次失败、源码与完整日志非作者审查记录在[永久证据](../engineering/evidence/2026-10-28-system-screenshot-candidate/README.md)。不能用候选push或旧第七轮CI替代正式组合结果。

## 下一次真实Mac直接入口

本地Codex继续独占第八轮冷首击/CLEAR/身份工作。本包未读取、合并或写入第八轮分支/工作树，未操作其Mac。待现有工作适当完成并正式交接后，由root统一合流；本地执行者从PR #1最新正式SHA新建worktree，保留原工作树与所有数据，不用旧595142d重新起步。

运行现有构建脚本，或者从本轮CI取得开发App。原生菜单「打开真实截图内部候选…」提供不需终端的显式入口；工程验收可直接执行：

```bash
bash scripts/build-macos.sh
./build/Riftlet.app/Contents/MacOS/Riftlet --system-screenshot-candidate --acceptance-trace
```

确认 `Riftlet REAL TEST` 和 `Application Support/Riftlet-System-Screenshot-Candidate`；不要使用生成图队列或给截图改origin。普通实例继续收录，NSWorkspace启动回调不当作候选ready；确认候选正常后可按需退出普通实例避免两组裂缝。完成实际来源/Chrome权限设置后，只使用新的受支持系统PNG及原点击，保留原图/私有图/hash/完整target/原operation/attempt/inputCount与正向开始/完成观察。候选菜单/TCC/真实文件/物理点击当前NOT_RUN，不能用自检替代。

取证先走现有闭准入路径；要验证真实快吞噬，必须先交付同一真实截图的SC-START证据并独立审查，再受限登记候选start profile，继续原Core/UI，不把completion或retry同时打开。SC-COMPLETE、原正文/附件/选区、SC-ANOMALY和SC-FAILURE分别取得原证据；缺证据时UNKNOWN只读，不清库或重传旧未决。快吞噬的真实时延需在最终组合二进制上重新测，不能复制第五/六/七轮生成图数字。

继续保留无ACK冷首击、业务ABA/同URL、真实多进程权限、MID、CLEAR物理透传、按住补位/屏幕切换、系统截图自包含及系统延迟的原开放结果。第七轮双图仅为A最终合法完成之后B输入一次；不扩大为start后并行。PR #1保持Draft，不合main、不发布、不改网站品牌，不自动Send。

---

## 上一正式组合：第七轮已集成并验证（历史）

正式基础e3175f3；双亲merge **`2aaaadb1c3461f93f268f1f93b0b08854745aa5f`** 保留固定交接3b089b2与双方历史，最终已测源码 **`595142d0345adc0d06f54371f50406879310610d`** 补齐权限接收进程保护。只整合第七轮两项源码增量及原15文件，没有重复挑选第五、六轮。确切最终文档HEAD见PR #1本轮交接评论；后续文档提交保持本源码/测试/构建输入不变。

原AcceptedSelection、App同步次序和单一Coordinator已实现有界等待；A未最终终结时B不输入、不假吞噬，原UNKNOWN/跨profile锁不豁免。精确取消/expiry/lost-wake/新点击/restart接口见[已集成契约](ADAPTER_CONTRACT.md#第七轮已集成的原选择等待)。首轮预绑定尝试先结束，再观察启动时原ID快照；不是保证每次先有成功ACK。CLEAR防误选已合入，底层穿透仍FAIL。

负责人实际修复了accepted再点击旧UNKNOWN绕过权限校验，以及当前进程授权被借给另一个旧进程观察的两条路径。现在先核对adapter/application/session，再新鲜被动检查，拒绝时旧事实不变、零观察/输入。后台generic预检接口未改，实际多进程权限矩阵仍需现场验证；不用这项修复假称真实TCC通过。

[完整组合CI40543025253](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40543025253) / job122326159138于2026-10-28 **00:41:17北京时间** completed/success：410原生（Core134/Adapters121/Capture63/UI53/App39）、72页面/54legacy、原回放/故障/probe/helper/包装、实际迁移与UNKNOWN/补偿、Release/签名及四自检全部通过。十组详细77项全部passed/0skip，包含在410中。源码/修复/原证据和完整209,434字符日志均由非作者独立审查。[永久证据](../engineering/evidence/2026-10-28-integration-round7/README.md)。来源9de6a85的408项CI单独保留，不能替代组合CI。

## 精确真机范围

- f6417c6无overlay普通线程中，一组软件AX生成图片A/B通过：原B在A inputTriggered时prepared，A持久succeeded后B才begin，两项各input1/attempt1及独立start/final。非空文字、非折叠选区、三个旧附件在同样本保留，editor未聚焦。不是start后并行或任意草稿矩阵通过。
- 时延A点击→AppKit close2816.959ms，B12212.578ms（含等待和较慢页面start），动画配置0.24s；不作为本轮修复后二进制新测量或像素完成时间。
- 冷边界native完整验证晚26.323250ms、AppACK晚26.742000ms；安全拒绝且不重放，产品仍FAIL。不存在把较晚ACK补造为原授权的修复。
- 9de6a85的CLEAR软件误选修复通过，但底层0次仍FAIL；GAP/IMAGE/NUMBER仅限定CGEvent批次PASS_SOFTWARE_ROUTING，初批GAP未投递仍NOT_RUN。物理输入、跨应用持续焦点、按住补位/双击、多屏/Spaces未通过。
- 所有公开证据保留原hash/提交；审查没有重新访问私有DB/media/raw日志。旧UNKNOWN/补偿/开始审计及原媒体由本地执行器继续保留，绝不为演示清库或重传。

## 第七轮真实Mac入口（历史，保留生成图片模式）

从本轮PR #1最终交接SHA新建独立worktree，保留原round7和所有旧数据；无需重做顺序调度。可使用[当前开发App/helper/日志制品](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40543025253/artifacts/12751661331)（ARM64/ad-hoc，到期2026-11-11 00:41:12北京时间），或现有 `scripts/build-macos.sh`。普通App首启仍显示首次使用；Web现场沿用明确隔离的入口：

```bash
./Riftlet.app/Contents/MacOS/Riftlet --web-acceptance --acceptance-trace
```

原 `Riftlet-Web-Acceptance` 数据根保留，不复用真实截图数据根。只对新生成图片接受新的明确点击，旧未决只能观察。GUI helper保留explicit单批software事件入口，不能把软件结果写成物理通过。四自检和首用权限恢复入口继续可用，不增加用户日常操作。

下一轮增量优先：无ACK冷首击的原时刻身份连续性；CLEAR真正向底层应用穿透与物理按住补位/双击/多屏；真实业务ABA/同URL；修复后二进制权限撤销恢复和多Chrome接收进程；MID真实字节请求识别/中断；真实安全终止后可点击重生；截图自包含及T0/T1/T2。已有双图样本不需为展示重复上传，新增证据按确切源码和操作身份交接。uploadStarted schema和v12/旧只读观察协议未变；不得放宽成功、UNKNOWN、重试或生产准入。

PR #1继续Draft；main、网站/品牌/设计不动，没有发布或Send。本地Codex拥有真实Mac执行/修复/验收；正式ref及共享代码仍由root在正式交接后统一审查集成。

---

## 第七轮独立真机原交接（历史来源，已按上文合流）

分支 `codex/riftlet-real-mac-round7-20261027`，核心实现 `f6417c6faaf8aa21ac587b07f25ea2a159af021f`，最终源码 `9de6a85b0161713833dc25e3b3eb1e1a2f81a558`。完整 [macOS CI 40525056642](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40525056642) 与范围限定非作者审查通过。正式 `81b6a61` 已合第五、六轮，集成本轮两个增量即可，不重复 cherry-pick 历史成果。

真实普通线程已验证：B 原点击冻结同目标，A 尚 inputTriggered 时 B 保持 prepared，A succeeded 后才执行 B 唯一输入；两张分别取得开始与最终成功，非空文字、选区和旧附件保留。实现有界 runtime-only AcceptedSelection、原事件 FIFO、exact-token 撤销及 final intent 原子核对；旧 UNKNOWN 不解锁，等待图不假吞噬。预绑定先于旧操作远程恢复，真实 Chrome 进程权限检查不缓存授权。

冷首击完整 ACK 仍晚于原事件 26.323 ms，安全拒绝正确但产品体验 FAIL。CLEAR 软件实击误选已修复，底层透传仍 FAIL；GAP/IMAGE/NUMBER 为软件路由 PASS，人工物理仍 NOT_RUN。真实 Web 样本绑定 f6417c6，最终源码另补诊断和 GUI guard，不混写已测 SHA。生产截图、生产开始 profile 与安全重试仍关闭。

完整原始时序、性能拆分、CI、保留核验及剩余项见 [第七轮 README](../engineering/evidence/2026-10-27-real-mac-round7/README.md)。本分支含用户授权的最小 Core/App/UI 补丁，需 Pro 正式审查合流；没有直接修改正式分支、main 或 PR #1。


---

## 第六轮正式检查点（历史来源）

## 当前正式组合

已测源码 **`81b6a61b4e648a1b8d6ccf4b569fd6d727a0cc76`**。双亲为正式1246c4a与第六轮交接65f7d54，共同祖先3bb13999；保留7878de3/c000cc1/65f7d54三个独有提交，未重复合入第五轮。后续仅文档/证据检查点保持源码、测试、构建输入不变，精确正式HEAD见 [PR #1](https://github.com/haohongfei2001-png/Riftlet/pull/1) 最终交接评论。

v12最多256KiB传输与严格Chrome身份读取已与现有App合流；原64KiB通用默认、逐块ACK、两遍文件hash、唯一input、完整目标与v6–v11只读恢复保留。首次使用/权限预检/PassivePermissionResume/Core/UI/SQLite v3没有回退或新增第二套Coordinator。普通收录不上传；Web只准入隔离生成图片开始/完成，生产和安全重试保持关闭。

[组合CI40523594732](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40523594732) 于 **22:44:24北京时间**完成成功：380原生、72页面/54legacy、七详细组13/3/15/4/5/8/5全部passed、0skip，原回放/故障/probe/helper/包装、Release/签名和四自检通过。非作者源码/权限/原证据/实际完整日志审查PASS。[永久证据](../engineering/evidence/2026-10-27-integration-round6/README.md)保存原13文件hash、来源CI325与组合CI380的区别、实际checkout输入核对。

## 第七轮直接继承的边界

1. 本地Codex保持第七轮独立实现与真机工作，不要求中断当前包；本会话没有读取或合入进行中源码。正式交接后由root整合共享Core/App改动，不用旧e89 App覆盖首用和权限。
2. 既有 `AttachmentAdapter` / `TransferReceipt` / `UploadStartEvidence` 不变。新增排队按[顺序调度共享边界v1](ADAPTER_CONTRACT.md#第七轮顺序调度共享边界-v1实现待正式交接)映射接口：App同步接受时、权限await前固定顺序；只保留原完整token/lease；唯一drain、被动非capture preflight、所有序号结束、有界实际期限、不丢解除锁唤醒。
3. 原 `markDispatchIntent` 事务仍是最后门。start不解锁同草稿/UNKNOWN/跨profile；无intent取消不等于真实上传失败，新的实际点击可再次选择；intent后只有原操作核对，不重放。纯Python模型仅提案，不是已实现队列或真实双图通过。
4. [开发App/helper/日志](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40523594732/artifacts/12743890195)可直接运行 `Riftlet.app/Contents/MacOS/Riftlet --web-acceptance --acceptance-trace`。沿用原隔离数据根和旧UNKNOWN/审计/media，只有新的生成图片可用于新选择，不重输旧未决。
5. 实测关联原事件→permissionRequestID→原ACK/完整target→active_identity route→一次input→start→持久观察→AppKit→最终proof。正式新增权限前置没有在原性能样本中运行，需要实际测量；权限授权与目标身份不能相互替代。
6. 7878de3+overlay的5.51→3.67秒仅单次旧对照，非页面上传加速、像素测量或分位数；c000cc1仅三次只读capture/六次fast read，无新输入，fallback尚未真机覆盖。无ACK冷首击仍FAIL安全拒绝，第二图targetBusy仍FAIL，不能用读取改善关闭它们。
7. 新业务ABA/同URL、正文/附件/选区完整矩阵、MID、安全失败、物理穿透/多屏/全屏、自包含和新权限恢复/时延继续独立验收。公开保存记录不是本环境独立重算私有DB/media；本地继续保留私有基准和比较产物，无需公开私有内容。

PR #1保持Draft，main/网站/品牌/设计不改、不发布。以下全部是原检查点的历史记录，当前状态以上方第六轮为准。

---

## 第五轮正式集成交接（历史来源）

## 当前检查点：第五轮独立合流已完成

已测源码 **`caa6a65b69c6038154a2fff65f2fb1157125bb7e`**，双亲为正式首用 `e655b1e04241990ec35acbb79b5b6bc8ee95b960` 与第五轮交接 `3bb13999b0f444c7748804eef1976e179a52a85e`。本页后续文档检查点保持相同源码/测试/构建输入；精确正式HEAD见 [PR #1](https://github.com/haohongfei2001-png/Riftlet/pull/1) 最终交接评论。

v11/schema2真实开始、严格正常化、早返回、v6–v10旧操作只读兼容和原27份证据已完整进入正式工程。两个允许overlay仅用于生成图片开始准入、AppKit观察及synthetic AX标识；失败CUA窗口排序没有应用。运行时和打包自检共用 `WebAcceptanceConfiguration.receiptPolicy`，普通捕获仍UnavailableAdapter，生产及所有真实安全重试关闭。Core/SQLite v3、Capture、历史、首次使用与权限保护保留。

新增被动权限恢复修复初次Chrome不可用后没有自动重启观察的问题；仅Chrome激活/唤醒触发，不轮询、不缓存grant、不补发点击。新 `permission_check` 诊断给出purpose、permissionRequestID、起止uptime，选择关联asset、arm关联capture request/attempt/epoch。权限返回不是ACK，不能更换原完整冻结lease。`startAttachmentObservationIfPermitted` 在恢复/查询await后检查取消与终止，再单次安装。

[macOS CI40515643640](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40515643640) / job122228775354于 **21:53:30北京时间**记录成功：369原生，68页面/45legacy，helper9/4/2、包装12、既有回放/故障/probe、Release/签名/四自检；六个详细suite13/3/15/4/5/8均passed/0skip。独立源码/原证据/完整日志复核通过；[第五轮合流证据](../engineering/evidence/2026-10-27-integration-round5/README.md)包含原文件hash、输入对象和具体范围。

### 本地 Codex 第六轮成果的接入边界

- 第六轮正在独立推进，本次未读取/合并其未交接源码，不要求中断当前真机小包。提供正式分支/已测SHA/交接后由root合流。
- Web接口沿用 [uploadStarted v1](UPLOAD_STARTED_CONTRACT_V1.md#8-第五轮正式合流受限开始准入与下一真机入口)；原UI和Core不用重写。保留本包policy隔离、权限恢复和首用，不用旧e89版App覆盖共享文件。
- 运行本次 [开发App/helper](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40515643640/artifacts/12739217183)，显式 `--web-acceptance --acceptance-trace`，保留现有v3/私有media/旧UNKNOWN/补偿；只用新的生成图片与明确选择，原未决只能observe。
- 测原事件→permission check→原ACK/target→input→start→持久状态观察→AppKit调用/close→最终proof。第五轮基于e89+overlay，预绑定24.42秒、聚焦空草稿、软件AX一图；其5.51秒点击→close、59–322ms start→UI、26.869秒Core成功首次观察均不能当作新合流二进制性能。
- Chrome未运行后启动、系统外部授权后返回Chrome、仍拒绝、停止/重启期间迟到返回、普通capture零Chrome探测，按 [首用验收](FIRST_USE_ACCEPTANCE.md) 测真实TCC与事件接线。当前仅软件回归通过，真机仍NOT_RUN。多Chrome实例的权限检查对象范围仍待证据，输入/观察完整目标校验未放宽。
- 冷首击、真实业务ABA/同URL、正文/附件/选区、MID、物理点击/穿透/多屏及截图自包含继续原任务；软件AX不能替代物理鼠标，observer异常不能替代网络失败或重试终止证据。

PR #1保持Draft；main、网站、品牌未修改。以下保留此前首用与第四轮来源，当前状态以上方第五轮增量为准。

---

## 首次使用与本地可靠性检查点（历史来源）

正式起点 `e89d49f763036781c90618422da256e03cbca2ac`；实现 `4e080aa`，已测源码 **`2449d40a88225acba9d413cc6a4cb5d84fcae6a1`**。本页所在的后续文档检查点保留同一源码/测试/构建输入；确切正式 HEAD、可运行制品及交接评论见 [Draft PR #1](https://github.com/haohongfei2001-png/Riftlet/pull/1)。本轮是实际 App/Capture/UI/打包开发，没有重订计划或访问本地 Codex 的 Mac。

**实际完成：** 原生「开始使用与运行状态」首次显示/菜单重开，真实来源和权限诊断，独立隐藏/暂停/无图/UNKNOWN/能力状态；原生文件夹授权只接受系统实际截图位置；Chrome 按需授权/拒绝恢复；来源重检与暂停互斥；写入失败的持久提示；原字节/颜色/方向保护及新复制空间预检；可重复开发 App 打包与校验。基础设置不需终端或配置文件，正常成功没有通知。详情与可运行入口见 [FIRST_USE_ACCEPTANCE](FIRST_USE_ACCEPTANCE.md)。

[macOS CI 40508109228](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40508109228) / job122202566296 于 **21:00:40 北京时间**记录成功：344 原生（Core117 / Adapters102 / Capture63 / UI48 / App14），生命周期13/首用窗口3/Capture15详细复跑全部 passed/0skip，Python包装12、页面48/legacy14、原回放/故障/probe、Release/签名/四个自检通过。38项新增测试已包含在344内。首轮编译失败、两处 `try` 修复、非作者源码审查与实际日志复核见 [永久证据](../engineering/evidence/2026-10-27-release-ux/README.md)。

### 本地 Codex 合流时必须保留的最小边界

1. **Web/Chrome、Core/SQLite v3、页面测试、第四轮原证据及 `UPLOAD_STARTED_CONTRACT_V1.md` 与起点逐字一致。** 继续按原契约实现真实开始、严格归一化与早返回。本轮没有新 profile、生产开关或真实浏览器证据。
2. App 的 `AutomationPermissionChecking` 只在 Web 验收模式使用；普通收录/模拟完全不调用。arm、明确点击、后台只读观察前用 PID+launchDate 复核权限；只有明确设置动作请求权限，不自动启动 Chrome、换目标或重放拒绝点击。保持原鼠标事件冻结的完整 lease，不能为通过新权限检查而重新捕获活动草稿。
3. 原操作本地恢复与已完成记录查询成功后才安装一次 armer/watch；无权限仍保留/恢复本地事务，获得权限后再只读核对。不要清 UNKNOWN、替换 profile、降级 v3 或绕过旧锁。
4. 新被动权限检查属于 App 路径，**需要重新计入原事件→输入/开始延迟**；此前 3.40 ms callback 不能代表新路径。Web 验收启动不自动弹首用窗口；需要时菜单明确打开，关闭后再做物理点击验收。
5. 新 Capture 诊断/存储余量不改上传资产原尺寸/hash，已有 journal 恢复不被新复制空间预检阻止。目录重检、暂停、书签和隐藏均由 App 控制，不在 Web provider 增加重复设置逻辑。

[Development App/helper/日志](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40508109228/artifacts/12735493443) 可直接运行首次窗口并从菜单打开隔离合成演示；这是 ad-hoc ARM64 工程制品。真实 TCC/目录授权/书签重启、Finder 首装、物理辅助功能、HDR/EXIF 命中及新权限路径时延均 NOT_RUN，直接使用 [真机表](FIRST_USE_ACCEPTANCE.md#真实-mac-专项全部保留-not_run) 留证。

本地 Codex 正在进行的真实开始、冷首击、业务 ABA、原正文/附件/选区、MID、物理 GUI、自包含和系统截图两操作闭环继续原任务；无需停止设备执行来重复本包。取得其分支后由唯一集成负责人解决 App 交叉差异。生产输入/开始/安全重试继续关闭；不合 main、不发布、不自动发消息。

---

## 第四轮 Web 与新版生命周期合流（历史来源，保留）

> **第六轮独立真机增量（2026-10-27）**：Web v12 分块优化真实点击至 AppKit 关闭 5.51→3.67 秒（单次对照），无 ACK 冷首击已真实复现安全拒绝；同草稿第二图明确在 Core targetBusy 被取消、未输入。Core/UI/App 不改，Pro 安装专项不混入。源码/CI/保留核验/顺序调度提案见 [第六轮交接](../engineering/evidence/2026-10-27-real-mac-round6/README.md)。生产截图与安全重试仍关闭；首击与连续点击不标整体验收通过。


正式分支仍为 `codex/engineering-foundation-20261027` / [Draft PR #1](https://github.com/haohongfei2001-png/Riftlet/pull/1)。合流父基线为 `b84892071d7711177bb856051251a337f2c2c4f5` 与 `03a67cc41e542a7db6dc128b27da8f108efc9896`，保留 `35e9851` / `c9c68a6` 原源码及全部11份第四轮证据。main、网站、设计、旧数据库/媒体均不改动；本会话没有操作本地 Mac。

## 当前合流实现与下一步

**完整合流 macOS CI 与独立复核已通过：** 已测源码 [`c85020b`](https://github.com/haohongfei2001-png/Riftlet/commit/c85020b0ae250eaa37f7ed812c3c43587dca5a91)，[run40484855920](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40484855920) / job122123985228，于2026-10-27 **17:59:57北京时间**记录完成成功。**306项原生**（Core117 / Adapters102 / Capture48 / UI39），48页面VM、14旧观察器VM、8故障离线组、12只读probe组、55文件/19用例/89轨迹前缀/2明确模拟迟到错误回放全部通过。生命周期详细13 passed /0 skipped，包含7项软件面板测试，未重复计入306。Release、ad-hoc签名、三个App/helper自检通过，CHROME_NOT_RUN/GUI_NOT_RUN保留。

[验证与11份原证据清单](../engineering/evidence/2026-10-27-integration-round4/verification.json) · [非作者审查及首轮编译修复](../engineering/evidence/2026-10-27-integration-round4/review.json) · [实际日志摘录](../engineering/evidence/2026-10-27-integration-round4/ci-excerpt.txt) · [development App/helper/日志](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40484855920/artifacts/12724099125)。本页所在的最终文档检查点与c85020b的12组源码/测试/构建/回放输入对象相同，确切正式HEAD以PR #1最终交接记录为准；不能把c9c68a6或b848920的旧运行冒充本次验证。

- SQLite v3、快速视觉退出/后台最终事实、隐藏/归档/移除/历史保持既有实现；没有回退到第四轮旧schema2 App。
- Core 只增加精确 persisted UUID profile 格式识别；完整目标相等、旧UNKNOWN、跨profile/nil/未知身份和补偿锁保持原规则。真实SQLite重开回归保留原始target JSON，不回填身份。
- App/adapter 增加原生request→adapter→实际publication→原事件的host-only诊断。普通协议不变、同次单一capture、重复lease保留旧有效ACK。没有mailbox、ACK回填、冷点击等待或回放。
- v8页面可用composer/焦点区别与v6/v7原操作只读兼容已合流；现有Web仍只生成最终或未决回执，**尚未返回uploadStarted，真实快吞噬未验收**。
- root及非作者已完成完整源码、实际macOS CI和证据复核；新增7项持久身份/锁与5项诊断回归实际执行。首轮新测试括号语法错误及仅补1字符的修复保留在记录中，没有放宽断言或策略。

本地 Codex 下一次直接从本页所在 PR #1 最新正式 HEAD 建worktree，按 [UPLOAD_STARTED_CONTRACT_V1 §7](UPLOAD_STARTED_CONTRACT_V1.md#7-第四轮合流后的直接接入要求) 实现真实开始观察、严格版本解码/归一化、append早返回，在明确生成图验收模式中记录开始→持久隐藏→最终ATTACHED/UNKNOWN。不要争写Core/UI/App或准入注册表；将拟用start profile及真实证据作为交接，由root审查组合。安全重试保持关闭，原started/POST100日志不能替代新证据。

第四轮限定PASS为一次**已预绑定、普通持久会话、editor未聚焦、空正文/零原附件**的用户物理点击。不是冷首击、非空正文/附件/选区保留、真实业务ABA或快吞噬通过。无可观察ABA反例仍FAIL；MID未命中；物理GUI矩阵与系统截图自包含/完整延迟继续开放。详细范围见[原交接](../engineering/evidence/2026-10-27-real-mac-round4/README.md)。

升级数据必须保留原SQLite/WAL/媒体/补偿；v3数据不能交给旧schema2二进制。继续只读旧操作，不清UNKNOWN、不重建registry或以新profile绕过旧锁。普通capture仍UnavailableAdapter；所有生产开始/完成/安全重试准入均空，PR #1保持Draft，不合main、不发布、不发送聊天消息。

---

## 前一检查点：新版交互生命周期（历史保留）

继续使用 `codex/engineering-foundation-20261027` / [Draft PR #1](https://github.com/haohongfei2001-png/Riftlet/pull/1)。root 是唯一集成写入负责人；本地 Codex 独占第四轮 Web/Chrome 真实执行。本轮没有访问其 Mac、没有改 Web/Chrome/Capture/M1/helper 源码，保留原设计、网站和真实证据。

## 前一生命周期检查点的续做入口（历史）

**本轮完整 macOS CI 与非作者审查通过：** 已测输入 [`d834a3a4a76cacedd0cb763044085c9c2093680c`](https://github.com/haohongfei2001-png/Riftlet/commit/d834a3a4a76cacedd0cb763044085c9c2093680c)，[run 40479556833](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40479556833) / job 122106130530。**287 项原生**（Core 110 / Capture 48 / UI 39 / Adapters 90）、38 项页面 VM、8 组故障工具、12 组只读 probe、历史回放 55 文件 / 19 用例 / 89 trace 前缀 / 2 明确模拟迟到错误全部通过。Release、ad-hoc 签名和三个 App/helper 自检通过。新增逐项输出确认 **13/13 生命周期测试 passed，0 skipped**，其中 7 项实际 AppKit 面板软件测试；重复报告这 13 项没有增加测试总数。

[永久验证](../engineering/evidence/2026-10-27-interaction-lifecycle/verification.json)、[非作者审查](../engineering/evidence/2026-10-27-interaction-lifecycle/review.json)、[日志摘录](../engineering/evidence/2026-10-27-interaction-lifecycle/ci-excerpt.txt)、[可运行 development App/helper/日志](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40479556833/artifacts/12721893223)。Swift 5.10 / macOS 14.8.9 / ARM64；artifact SHA-256 `cea0daab14fcbbc3b18509e1ec902ec913d776bc07acf19621983b71a37d0122`，保存期限至 `2026-11-10T09:18:09Z`。临时 PR checkout `e0b2688cf99ed83ae949af700dedee58094fa2d1` 与 main `eba1a4fc77648a665e1d5c1f2609df1314c3b079` 的合流只用于 CI；**没有合并 main**。后续文档检查点保持本次已测 Sources/Tests/构建输入不变。

正式集成顺序：`a441c70` → `de56627`（保留 PR #4 `90a0488` 第二父历史并实现交互）→ `15ca4a8`（旧失败 fixture 对齐）→ `a09de4d`（选择 owner 生命周期修复）→ `d834a3a`（软件面板执行结果明确报告）。本页所在的文档检查点不改已测代码；本地 Codex 从 PR #1 当前正式 HEAD 建独立 worktree，记录实际 SHA，不从旧验收分支覆盖正式 Core/UI/App。

## 已落地行为

- `AssetRecord.visibility` / `visibilityReason` / revision / idle anchor 与 QueueStatus、OperationPhase 分开。只有准入的开始回执写入 `upload_starts` 并触发快速视觉退出；最终 READY 在后台写成功，UNKNOWN 保持隐藏且只读观察。
- 真正安全失败按原顺序恢复普通可点击图；unsafe compensation保留内部审计、不复活。移除/归档意图优先于迟到回执；原 attempt/目标/附件身份保持严格。
- 无图无裂缝；默认吞噬120ms可调、轻按压恢复、无成功Toast。持久 Hide/Show 与 Pause/Resume 分开；单张/批量移除不删除任何原图或远端附件。
- 归档在 hover/按住/选择/动画期间延后，SQLite事务/fence/revision保护跨await竞态；每批最多3张，启动/唤醒/时钟跳变有30秒安静期。24小时仅可调工程默认，可在菜单/JSON关闭。
- 原生历史每页200条、当前页搜索、分类待核实/已吞噬/归档/真正失败/移除；恢复先由Core复核，不能把UNKNOWN、成功或已吞噬图变成重传入口。
- `--simulate` 显式隔离的三态 App 已构建/自检；旧 GUI helper继续用于其既有N1辅助范围，不把旧 helper 的legacy完成动画当新版真实开始验收。

## 本地 Codex 最小合流契约

实现 [UPLOAD_STARTED_CONTRACT_V1.md](UPLOAD_STARTED_CONTRACT_V1.md) 的 `ReceiptOutcome.uploadStarted` + 可选 `UploadStartEvidence(version:1, profileID, signal, evidenceID, inputCount:1)`。复用完整原 receipt identity，必须有唯一原 attachment ID、原草稿成员、实际 uploading，不能是 ready/error/safeToRetry。start profile在原完成profile之外独立准入；页面本身不能指定信任策略。

`append` 获得真实正向开始后早返回，后续仅 `reconcile` 原操作；Core已持久保存第一份start。不得为了视觉快而把 input.files/change/占位图改名成 start。当前Web只有synthetic完成准入，start与安全失败均未打开。生产所有registries仍空；M1客户端profiles继续独立。

Web/Chrome作者在自己的分支提交真实页面程序、normalizer/严格版本解码、早返回及去隐私证据；不得并行改Core/UI/App。旧absence-only失败没有retired attachment identity，即使给profile也被新Core拒绝为retry；需单独交付同原附件安全终止证据，不是降低hasError/identity条件。root审查、测试并统一集成，不需要重做收录、SQLite或裂缝。

## 真实 Mac 下一步，保留原工作不重复

1. 真实start的唯一输入/图片/目标身份链，start早于最终ATTACHED，未开始反例、UNKNOWN和强失败终止矩阵；按场景明确PASS/NOT_EXERCISED。
2. UX-01冷首击/目标ACK与有效但未聚焦composer；正常使用不增加等待操作或第二次点击。
3. UX-02真实A→B→A、同URL草稿和v6/v7原操作观察兼容；真实MID识别/中断，不能用离线fixture补齐。
4. 实际鼠标穿透、按住补位、全屏/多屏/屏幕切换；隐藏后新图/唤醒/重启不自行显示。
5. 系统截图自包含与实际延迟；持久隐藏作为当前可运行退路，新版本capture/Web/观察/历史下资源需实测。

旧普通线程、后台观察及POST100 XHR中断仍仅在原证据范围通过。本轮没有新真实网络或物理N1结果。升级保留SQLite/私有媒体/UNKNOWN/clipboard journal，v3不得降级交给旧schema二进制；不清库、不盲重传、不自动发消息、不合main、不发布。

---

## 第三轮及以前交接（历史保留）

# 正式工程集成交接 · 第三轮 · 2026-10-27

北京时间。正式分支 `codex/engineering-foundation-20261027` / [Draft PR #1](https://github.com/haohongfei2001-png/Riftlet/pull/1)。root 负责统一集成；本地 Codex 负责真实 Mac 修复与验收。第三轮代码/证据已接入；日常一次点击和生产准入仍未达标，第四轮直接在现有实现上推进。

## 确切来源与本轮修复

| 来源 | SHA / 处理 |
| --- | --- |
| 前一正式基线 | `7d6bca6010fdd9098aef879d9734497a79403a03` |
| 第三轮源码 | helper `11aec0407dbef7e5fcec4be4f7ae03eecbf2749d`；最终源码 `159b3ef3e6c87ea468ba334dff64ad8db640d80c` |
| 第三轮证据 | `d26c6daafa7073102f5c8848b95fbbd425cdad9c`；最终澄清 `6344eb08c96180d1e675595083333ec860fd62a2`；[原12文件](../engineering/evidence/2026-10-27-real-mac-round3/README.md)逐字节保留 |
| 正式合流验证输入 | [`aa4fd2b9ed64efb83d9b7c8b29102cbd91d03e2b`](https://github.com/haohongfei2001-png/Riftlet/commit/aa4fd2b9ed64efb83d9b7c8b29102cbd91d03e2b)；保留完整祖先，新增下述 AX 缓存修复 |

非作者 native 审查发现 ChromeActivityObserver 只凭 PID 复用旧 observer：进程退出后 PID 被新实例复用时，事件唤醒可能仍留在旧实例。root 改为同时核对 PID 与 launchDate；启动身份缺失拒绝绑定，stop 同时清理缓存。AX 只是调度提示，不是目标授权，因此该问题影响唤醒可靠性；实际输入的 PID/launch/window/tab 检查未变。修正经非作者复核和完整原生构建/既有回归；**真实 OS PID 复用未执行**，不增造镜像测试或宣称现场复现。

除此文件外产品源码/Tests/构建输入与159b3ef一致。Core、Capture、M1五个后端源码与7d6bca6零差异。原分支、证据、网站/设计和 main 保留；没有写私有数据库、清 UNKNOWN、发布或发送聊天消息。

<!-- ROUND3_INTEGRATION_STATUS -->
**第三轮完整工程 CI 通过：** 已测正式输入 [`aa4fd2b9ed64efb83d9b7c8b29102cbd91d03e2b`](https://github.com/haohongfei2001-png/Riftlet/commit/aa4fd2b9ed64efb83d9b7c8b29102cbd91d03e2b)，[run 40471069966](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40471069966) / job 122078052804，于 **2026-10-27 16:06:16 北京时间**成功。**228/228 原生**（Capture 48 / Core 73 / UI 17 / Adapters 90）、**38/38 页面 VM**、**8/8 故障工具离线组**、**12/12 只读网络 probe 离线组**、历史回放 55 文件 / 19 用例 / 89 trace 前缀 / 2 明确模拟迟到错误、Release、ad-hoc 签名及三个自检全部通过。实际日志已核对 SQLite v1→v2 迁移/回滚、UNKNOWN、迟到失败补偿、逻辑草稿、预绑定、MAIN 回执和 M1 恢复。

[永久验证记录](../engineering/evidence/2026-10-27-integration-round3/verification.json)、[非作者审查](../engineering/evidence/2026-10-27-integration-round3/review.json)、[实际日志摘录](../engineering/evidence/2026-10-27-integration-round3/ci-excerpt.txt)、[工程制品 12718636844](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40471069966/artifacts/12718636844)。制品 SHA-256 由 GitHub 元数据提供：`fe204a7566b4dc0fb6c0d94d7e7cb4d73d786d36c038278b40985cd624de0d1e`。CI 临时 PR 合并为 `f202d50cad83b9ea132fe3f4d478a08956255752`，检查与当时 main `eba1a4fc77648a665e1d5c1f2609df1314c3b079` 的兼容性；没有合并 main。最终交接只更新文档/记录，未改变已测构建输入。自检明确 `CHROME_NOT_RUN` / `GUI_NOT_RUN`；CI 不扩大真实 Mac 验收范围。
<!-- END_ROUND3_INTEGRATION_STATUS -->

## 真实证据的准确状态

| 项目 | 继承结论与限制 |
| --- | --- |
| AX/预绑定探索 | 318次arm、92次armed，零selection boundary、零input command。来自最终版本前未提交探索工作树，native诊断/helper字段有差异；页面hash相同，不冒充最终二进制首击通过 |
| v7 root monitor | 三组474/847/79次普通commit检查及显式stop恢复有记录；单次最高7/11.6/3.6ms。证明运行/恢复，未证明真实业务ABA。另slot9读取失败，不宣称遍历了浏览器全部目标 |
| 系统截图自包含 | **FAIL**：只运行实际capture App、无helper的系统CLI区域截图仍有Riftlet微图，已排除helper来源；`sharingType.none`没有解决该次问题 |
| 资源 | **PASS_MEASUREMENT_ONLY**：实际capture-only App，约600秒/61内核样本，含一次CLI截图收录，没有上传。启动后RSS32.61–55.00MiB、末45.875MiB，footprint18.83–25.00MiB；interrupt wakeups增299。CPU0.73秒来自归档ps累计摘要，约单核0.12%，不是峰值或Web/monitor负载认证 |
| 收录与延迟 | 一次系统CLI区域截图收录5→6 pending，零生产操作；不是用户快捷键闭环。mtime→import约234ms、firstSeen→import约162ms，仅局部指标；完整T0/T1/T2未取得 |
| GUI探索 | 未冻结完整源码的早期helper有局部非激活/重复点击观察；CUA GAP仅事件4单点到底层、零选择。CLEAR坐标未命中；不能把窗口预测当实际穿透PASS/FAIL |
| 完整首击 / 业务转换 / MID / 物理N1 | **未完成**。本轮没有新真实上传、没有真实运行MID probe、没有abort；38页面/12probe离线不能替代这些验收 |
| 数据保留 | 原15份私有媒体字节、资产、operation identity/attempt/target/phase与3份补偿审计保留；恢复改变了部分updated_at/reason/receipt_json，不能称全部operation行逐字不变 |

[原始README](../engineering/evidence/2026-10-27-real-mac-round3/README.md)、[资源摘要](../engineering/evidence/2026-10-27-real-mac-round3/capture-resources.json)、[GUI来源](../engineering/evidence/2026-10-27-real-mac-round3/gui-review.md)、[数据保留](../engineering/evidence/2026-10-27-real-mac-round3/preservation.json)保留精确范围。本会话只审查归档与CI，没有操作本地Mac。第二轮普通线程成功、后台DOM补偿及真实POST100中断仍是原v6源码的历史局部事实，不扩大为当前v7新验收。

## 现行约束与产品缺陷

- 新 Chrome AX observer 只使用已有授权，不弹提示；只读 focused-window handle，不读标题/正文。对应用/window对象请求设置50ms messaging timeout，但设置返回值未检查，未验证硬截止；总启动耗时需另测。hover/AX只唤醒现有single-flight；不授予身份，不追认被拒点击。App与transport两个logger**各自**上限2048，transportSucceeded不等于已发布ACK。
- v7 root.current monitor 会改变真实页面属性的反射语义；只覆盖普通setter赋值，不能覆盖原地props ABA、defineProperty绕过再恢复或安装前历史。每form每commit检查，最多4个root；Home不安装。显式stop只恢复自身仍拥有的descriptor和最新value，失效墓碑不能rearm。性能峰值与真实业务转换仍需验收，不能直接生产启用。
- **跨版本恢复缺口OPEN**：v7不读取旧v6 registry，旧操作部分持续观察能力丧失；不自动搬迁或重放。原数据库/媒体/私有备份保留，供原版本审计；保留数据不等于恢复能力完成。下一步仅研究/实现原操作版本路由的只读观察，不能因此回填目标或恢复输入权。
- **透明区域风险OPEN**：原whole-row mouseDown/mouseUp接受路径与前版完全一致；预测CLEAR命中row不是实击证据。先做准确CLEAR与GAP自动化控制试验；若证实误选，按真实图/数字命中区最小修复。拒绝选择也不自动证明穿透；不拿hitTest(nil)、事件转发或推测多窗口重写代替验收。
- 普通capture仍UnavailableAdapter；Web仅synthetic验收，生产截图上传/吞噬、安全重试和Mac客户端profiles继续关闭。原UNKNOWN、补偿、legacy nil全tab锁、一次输入和完整receipt身份不放宽。原附件退役/无残留重试契约及开发容量上限继续保留。

## 第四轮直接动作

保持旧三个验收分支及私有数据，基于PR #1最新正式HEAD建立工作树并记录SHA：

```bash
git fetch origin codex/engineering-foundation-20261027
git worktree add -b codex/riftlet-real-mac-round4-20261027 ../Riftlet-real-mac-round4 FETCH_HEAD
git -C ../Riftlet-real-mac-round4 rev-parse HEAD
```

1. 恢复可可靠控制的精确测试标签后，用现有trace完成一组真实冷首击及真实同tab业务A→B→A/同URL切换。保存event→ACK→冻结→唯一输入证据，不用普通commit计数或重复成功图累加替代。没有发言框焦点不应成为正常使用的额外前置操作；不得放松原目标连续性。
2. 处理v6→v7只读恢复兼容性及monitor停止后的生命周期；只观察原操作。对实际PID重启/重绑补局部验收，不为此要求人为制造PID复用作为全工程前提。
3. 首先实际运行已有只读MID probe，绑定大图byte transport/body/hash；确认链路后再独立做真实中段中断/恢复。两同名JSON不算retry，没有命中仍NOT_EXERCISED。
4. 展示底层helper并核对实时坐标/接收窗口，执行一个准确CLEAR与GAP控制点，再测按住补位和替换行双击、跨应用键盘焦点、全屏/屏幕变化。代理事件标自动化，物理来源未证实则不称物理PASS；不新增日常用户步骤或把验收安排成用户审批。
5. 自包含已确认FAIL，沿现有系统截图入口核实可支持的原生排除方案与边界，再增量修复；不能把sharingType.none或未经实测的提前隐藏当保证。补齐capture-done T0、完整文件T1和可点T2；已有capture-only资源基线保留，Web+monitor负载单独测。

沿用现有构建、自检和[MAC_ACCEPTANCE](MAC_ACCEPTANCE.md)，每项留精确源码/输入来源/范围。root统一集成，本地Codex真机执行；没有新增发布或品牌依赖。

## 第二轮及以前交接（历史保留）

<details>
<summary>7d6bca6及此前检查点；现行状态以上文为准</summary>

# 正式工程集成交接 · 第二轮 · 2026-10-27

北京时间。唯一正式工程分支为 `codex/engineering-foundation-20261027` / [Draft PR #1](https://github.com/haohongfei2001-png/Riftlet/pull/1)。root 完成正式集成、CI 与非作者审查；本地 Codex 继续负责真实 Mac 执行、修复与验收。第三轮从此正式分支最新检查点直接续做，不重做基础模块或总体规划。

## 当前不可变来源与合流

| 来源 | 确切 SHA | 处理 |
| --- | --- | --- |
| 前一正式工程基线 | `c1456534fa2f9652f770321f179ff88737edc281` | 保留第一轮真机、M1 与此前全部祖先 |
| 第二轮已测源码 | `fff0e8c090f125211b35a56e7a16abef61109fb1` | 普通线程、逻辑草稿、MAIN 单次桥接、后台观察、单飞预绑定及原生选择诊断 |
| 第二轮交接 | `8d7007e069d077d5991904e72ebd8fcda3a00806` | [原始 11 文件](../engineering/evidence/2026-10-27-real-mac-round2/README.md)完整、逐字节保留 |
| 正式完整工程验证输入 | [`39046d16823401c50ce3527ec1204e7517e1078a`](https://github.com/haohongfei2001-png/Riftlet/commit/39046d16823401c50ce3527ec1204e7517e1078a) | 保留上述祖先；只增加 CI 中已有 8 组故障夹具的离线执行与日志归档，`round*` 支持第三轮沿用 |

第二轮直接继承 c1456534，采用保留祖先的快进整合，没有 squash、强推或冲突覆盖。产品源码、Tests、Package.swift、Resources、scripts、ThirdPartyNotices 与 fff0e8c 完全一致；M1 五个源码文件与 c1456534 完全一致。审查没有发现需要修改产品源码的新增合流阻断问题。main 的独立网站更新未混入工程改动，未改 main、设计/品牌、既有私有数据或原证据。最终检查点仅在已测工程上补充本交接与验证记录；精确 HEAD 由 PR #1 和提交记录给出。

<!-- ROUND2_INTEGRATION_STATUS -->
**第二轮完整工程 CI 与非作者审查通过：** 已测正式输入 [`39046d16823401c50ce3527ec1204e7517e1078a`](https://github.com/haohongfei2001-png/Riftlet/commit/39046d16823401c50ce3527ec1204e7517e1078a)，[run40462287936](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40462287936) / job122049461297，于2026-10-27 **14:39:36北京时间**成功。**227/227原生**（Capture48/Core73/UI17/Adapters89）、**31/31页面VM**、**8/8故障工具离线组**、历史回放55文件/19用例/89前缀/2明确模拟迟到错误、Release/签名及三个自检全部通过。SQLite v1→v2迁移/回滚、UNKNOWN/补偿、logical11、scheduler8、MAIN7和M1恢复均在实际日志核对。

[永久验证](../engineering/evidence/2026-10-27-integration-round2/verification.json)、[非作者审查](../engineering/evidence/2026-10-27-integration-round2/review.json)、[实际日志摘录](../engineering/evidence/2026-10-27-integration-round2/ci-excerpt.txt)、[工程制品12714722940](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40462287936/artifacts/12714722940)。源码/测试与fff0e8c一致，最终文档提交不修改已测输入。临时PR测试合并17dc667不是main合并；PR #1保持Draft，不发布。CI自检明确CHROME_NOT_RUN/GUI_NOT_RUN；不冒充本地真实验收。
<!-- END_ROUND2_INTEGRATION_STATUS -->

## 已审查的真实结果及边界

以下是本地 Codex 第二轮的真实执行记录，经独立审查继承；本集成会话没有再次操作真实 Mac 或浏览器。CI 与故障夹具的合成结果不扩大这些结论。

| 场景 | 当前结论 | 不包含的结论 |
| --- | --- | --- |
| 普通已有中文 Chat 对话 | **有范围 PASS**：`7607529F…`、`01FC359F…` 两个不同生成图片，各一次输入和独立逐图内容证明；旧正文、附件节点/源和编辑器焦点保留 | 首次自动化在 AX 动作后出现结果变量错误，下一次选了另一图片；不是无歧义的一次物理首击试验，不代表全部线程/模式 |
| UNKNOWN 恢复 | **有范围 PASS**：`01FC359F…` 仅观察原操作后转成功，inputCount 仍为 1 | 不授予重传权；不解决冷首击 |
| 后台观察与迟到补偿 | **有范围 PASS**：原成功证明跨隐藏/重启保持；原附件 DOM 错误标记导致持久补偿且 safeToRetry=false | 这是 DOM 故障，不是真实网络失败或真实消费后网络失败 |
| POST100 真实网络路径中断 | **故障命中与安全保留有范围 PASS**：`FF0FFE74…` 的 input hash→唯一 creation URL→实际 XHR Blob hash→自身 UI100→一次 native abort→abort event/status0；之后 UNKNOWN 跨重启保留 | loaded=total=3137 是 abort 后到达的进度事件；不证明服务器成功/拒收、消费后补偿、无缓存重试或安全重传 |
| 故障工具恢复 | **有范围 PASS**：60 秒窗口内 STOPPED、originalsRestored、pending=0，仍一次输入及一个匹配 creation | 不排除缓存请求或观察窗口外重试；最终 uniqueCreationURL=false 是停止时清空临时 URL，命中证据在事件 6/7 |
| MID | **NOT_EXERCISED**：生成大 PNG 成功上传，但未绑定其字节请求、未 abort | 两条含上传名的 JSON 请求不能证明重试、压缩或替代 transport |
| UX-01 / UX-02 | **仍 OPEN**：预绑定调度和 Core 逻辑身份契约已实现/回归；真实首击、ACK 和完整草稿转换矩阵未完成 | 无可观察事件、复用 DOM 的业务 A→B→A 仍有准入缺口 |
| 物理 N1 / 真实截图两操作闭环 | **NOT_RUN / 未完整验收**；本轮 helper AX 边界记录不是物理鼠标证据 | 不将静止横/竖屏截图尺寸当屏幕切换验收，不把生成图片开发吞噬当生产闭环 |

来源：[第二轮真实交接](../engineering/evidence/2026-10-27-real-mac-round2/README.md)、[POST100](../engineering/evidence/2026-10-27-real-mac-round2/post100-network-receipt.json)、[MID](../engineering/evidence/2026-10-27-real-mac-round2/mid-network-receipt.json)、[原操作](../engineering/evidence/2026-10-27-real-mac-round2/durable-operations.json)、[保留检查](../engineering/evidence/2026-10-27-real-mac-round2/preservation.json)。公开材料保留脱敏事实和匹配结果，不包含私有截图、聊天正文、signed URL 或原始网络抓包；没有把审阅归档写成新的独立真机实验。

## 当前接口与准入保持

- MAIN 桥使用精确 PID/启动会话、窗口、标签提交一次 percent-encoded `javascript:void(...)`；随机 nonce DOM 回执丢失后只读，不重发命令。一秒读循环不是总硬超时，每个 Apple Event 仍有五秒上限。真实测试观察到该 MAIN 命令本身没有触发 Navigation 事件，这不是所有 Chrome 版本的保证。
- `LogicalDraftIdentity` 只由已观察 profile 的当前已提交 React ancestry 提供，512 层有界，含 alternate 的实际 membership 和 HostRoot.current 检查；不使用 URL、pending props 或猜测节点作为身份。两个识别出的不同 ID 才缩小同 tab 冲突；nil/未知 profile 继续全 tab wildcard。原 target JSON 不回填，完整回执等值包含 logical identity 和原输入代际。
- blur/focus/visibility 撤销新输入权，但仍绑定原业务草稿/节点的已提交操作可后台观察；业务、route、Navigation、原节点/附件丢失仍撤销。一次输入墓碑、先持久 intent、UNKNOWN 只观察和补偿审计不变。
- 普通 capture 仍用 `UnavailableAdapter`；Web 仅显式生成图片开发验收，生产截图上传、自动吞噬与 safe-retry 注册表保持关闭。Mac provider/profile 不借用 Web 证据，M1 后端保留默认禁用。
- 补偿后重试仍须解决原非空 attachment ID 的退役关联与无残留/无自动完成证据；不把 nil 当通配符。页面 32 generation、每代 32 operation、64 成功 watch、M1 256 墓碑是当前开发上限，不能清未决历史规避。

## 第三轮直接执行交接

保留两个既有验收分支、SQLite v2、媒体、UNKNOWN/补偿与 clipboard journal；不 reset 到旧构建、不回填旧草稿 identity。使用 PR #1 最新正式 HEAD 建新 worktree，记录实际输出 SHA：

```bash
git fetch origin codex/engineering-foundation-20261027
git worktree add -b codex/riftlet-real-mac-round3-20261027 ../Riftlet-real-mac-round3 FETCH_HEAD
git -C ../Riftlet-real-mac-round3 rev-parse HEAD
```

然后沿用 [MAC_ACCEPTANCE](MAC_ACCEPTANCE.md)、`scripts/build-macos.sh`、三个自检及已有 helper。正式分支只由 root 集成；本地 Codex 在第三轮分支修复和实测，不争写 PR #1。以下是既有实现上的增量动作，不新增日常用户步骤：

| 开放项 | 下一条实际动作 | 通过所需事实 |
| --- | --- | --- |
| **UX-01 冷首击 / ACK 竞态** | 用已有边界 trace 关联原 event uptime、ACK、目标 epoch；覆盖新页面、即时截图、延迟 Apple Events、多窗口和激活变化；增量修正现有单飞调度 | 正常支持场景一次微图点击，无等待/第二击/确认。若自动续做，必须有跨原点击的同草稿连续性证据；没有证据不改投后来目标、不重放被拒点击 |
| **UX-02 稳定逻辑草稿** | 在 MAIN 实测可靠业务转换 epoch；跑真实 A→B→A、同 URL 替换、返回旧草稿、移窗、重启；沿用现有 identity / observer 分离 | 同草稿失焦/rearm不能解锁；证明不同草稿才独立输入；旧操作只 observe。无事件 ABA 未解决前继续拒绝相应准入，legacy nil 不回填/清锁 |
| **MID 请求关联** | 先只读确认大图真实 byte 请求的 transport/body 类型与尺寸，再绑定 operation/name/hash/request 后中断；沿用有界恢复工具 | 原请求身份链、实际中段 native abort 及事件、旧正文/附件保留、UNKNOWN/重启、hooks 恢复；没命中仍 NOT_EXERCISED，不由 JSON 数量推断 retry |
| **物理 N1 / 资源** | 真实鼠标首击、透明/间隙穿透、按住时补位/双击、Spaces/全屏、屏幕切换/热插拔/旋转和十分钟资源测量 | 记录实际输入来源、原 asset、下层点击/焦点、屏幕前后状态和实际 CPU/内存/唤醒；工具受限只隔离对应项 |
| **截图自包含 / 延迟** | 分别只运行实际 App 或 helper 隔离自包含窗口来源；覆盖既有截图快捷方式。分别记录触发、系统 capture-done T0、完整文件 T1、首次可点 T2 | `sharingType.none` 不作排除保证。两图已收录但截图包含 Riftlet 样式元素；约 61.5 秒是 shortcut 返回→mtime，不能归因 watcher。已知 mtime→import 0.280/0.293 秒、firstSeen→import 0.208/0.234 秒，完整预算仍需测 |

第三轮记录确切源码与 PASS/FAIL/NOT_RUN；不发送 ChatGPT 消息，不为演示清除 UNKNOWN 或放宽成功/重试准入。系统截图自包含与延迟是实际产品问题，不由品牌/发行工作阻塞修复。日常工程决定由双方自主完成。

## 前轮集成与第二轮候选记录（历史保留）

<details>
<summary>c1456534 交接及 8d7007e 中继承的候选说明；现行状态以上文为准</summary>

# 正式工程集成交接 · 2026-10-27

北京时间。唯一正式工程分支仍为 `codex/engineering-foundation-20261027` / [Draft PR #1](https://github.com/haohongfei2001-png/Riftlet/pull/1)。本文件记录本轮合流、真实缺陷和下一条执行动作；不替代既有开发计划。本地 Codex 继续独占真实 Mac 的 W2/N1 验收，root 负责正式集成、共享契约和准入。

## 来源与集成范围

| 来源 | 不可变提交 | 处理 |
| --- | --- | --- |
| PR #1 原检查点 | `485fa87a31140f9d2e428db69ec5e0599b1f96ae` | 保留祖先和所有既有模块 |
| 本地 Codex 四个源码提交 | `268e70b3a20ec141fd5f7f079a56585f29b06adf`、`0100f4654b079cc05f0bca141a9bf2134d6d6d3e`、`f58b22762d1dc42368a6e13fe2ef3a8e2d156106`、`1909771d45ad00290dffe245b9a42e6e9f55203c` | 独立 Web/Core 审查后按原顺序保留 |
| 本地真机证据检查点 | `f075b8fe97eddf04d868e9e5fe589c51c9d12ad5` | 保留全部六份[原始交接证据](../engineering/evidence/2026-10-27-real-mac/README.md)；源码与1909771相同 |
| M1 / PR #3 | `88f9e362d7e1610929eeb42e77b3d7652477bd1f`，已测源码`7dfa8ecbd221095f6c99d289aba794b51ce37e95` | 保留M0接口、原生后端、34项既有M1测试及原始审查/CI证据 |

采用合流提交保留两侧完整祖先，不 squash 或覆盖贡献分支。源码/构建没有文本冲突；`EXECUTION_BOARD.md`、`VERIFICATION.md` 两处共享文档文件的冲突按两侧证据合并，旧状态标为历史。main、网站、设计和品牌资产没有加入本轮变更。

<!-- INTEGRATION_STATUS -->
**正式集成已验证：** 已测合流源码 [`76a8385be063bf225248c057262eb8d57e4be43f`](https://github.com/haohongfei2001-png/Riftlet/commit/76a8385be063bf225248c057262eb8d57e4be43f)。[macOS CI40453748396](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40453748396) / job122022173576于2026-10-27 13:11:09北京时间全部成功：**201/201原生测试、20/20页面VM、release/签名、三个自检**。v1→v2迁移/迁移回滚/补偿回滚/UNKNOWN恢复及三项新增M1回归均在完整执行日志中核对。root与非作者分别读取了run、job、完整日志和制品。

[永久验证](../engineering/evidence/2026-10-27-integration/verification.json)、[非作者审查](../engineering/evidence/2026-10-27-integration/review.json)、[实际CI摘录](../engineering/evidence/2026-10-27-integration/ci-excerpt.txt)及[工程App/helper/日志制品12711707097](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40453748396/artifacts/12711707097)。当前检查点在76a8385之上只保存这些文档/证据，源码、测试和构建输入未变；不要把它当作另一次真机验收。
<!-- END_INTEGRATION_STATUS -->

## 实际接口修复

新 Core 的 `observeCompleted` 允许成功后发现匹配原附件的迟到错误。原 M1 拒绝 `.succeeded`；仅放宽 phase 又会使已完成操作重新取得全局剪贴板所有权，并在 UNKNOWN 时不释放。

本轮负责人补充 `MacClipboardCoordinator.verifyConsumedObservation`：仅接受成功/补偿操作，短暂持锁读取完整身份相同的 `resolved + consumed` 墓碑，在任何 AX await 前释放。不设置输入所有者、不改 journal、不恢复剪贴板。已有所有者时拒绝观察且保留其锁。Adapter 的这两个状态直接返回原目标观察，绕过 clipboard settlement；Native executor 的 Paste 仍只允许 `dispatchIntent`。

三个定向回归分别覆盖：实际 SQLite 成功→UNKNOWN观察→迟到错误补偿→新连接恢复、原审计与journal字节保持；同/跨实例及子进程锁、错误/取消身份拒绝；原生 executor 的完成后观察零 Paste/剪贴板读取。真实客户端 provider/profile 和 App Mac 接线仍未启用，测试使用合成观察。

## 保留的准入事实

- 真机原交接支持五次受控中文 Home 生成 PNG 成功、三张系统窗口截图收录、原活跃草稿内 DOM 错误补偿/重启及具体标签撤销/锁用例。它没有证明新合流二进制已在真实 Mac 运行。
- POST100 网络故障尝试没有截获上传请求、没有实际 abort；迟到错误来自原卡片的受控 DOM 注入。**真实网络异常、普通线程、完整N1及真实截图两次操作闭环仍未通过。**
- 普通模式仍 `UnavailableAdapter`；Web只有显式生成图片验收；Mac默认禁用、内置profiles为空。生产成功与safe-retry注册表均为空，无Send、自动重传或配置绕过。
- v1→v2仅升级本地SQLite操作/补偿记录；不删除或重建既有队列、媒体、UNKNOWN或clipboard journal。旧页面程序无法恢复的原操作只保留/观察，不向新程序重放。

## 已确认的产品体验缺陷与自主修复决策

### UX-01：首次点击依赖预先收到的目标ACK — OPEN

现状：新打开或尚未预绑定的草稿，首次点击可能安全拒绝。当前自动预绑定不保证刚到达页面的首击成功，不能要求用户“先等一下再点”或重点击作为产品解决办法。

采用现有目标接口上的增量：前台应用变化、新截图到达和**有真实证据的**窗口/标签/composer变化自动触发预绑定，保留单个有界后备任务；截图和用户点击不增加新步骤。点击仍冻结原目标。若需将冷首击自动续做，必须由持续观察器证明同一原草稿身份跨越原点击时刻；只可保留该asset/原选择意图并在这份证据成立后继续一次。无跨点击证据时不捕获“后来当前的草稿”、不偷换目标。

验收由本地Codex在真实Mac执行：刚打开页面、截图先/后于页面、立即首击、延迟native事件、A→B→A、多窗口/同URL草稿替换、输入中切换。正常支持场景均为一次微图点击；证明缺失或发生目标变化时零输入且资产保留。先取得事件/身份证据再改原子输入边界；当前ACK早于原事件的保护保留。

### UX-02：一个UNKNOWN阻塞同标签的新草稿 — OPEN

现状：当前 `serializationKey` 整标签锁堵住了“rearm换代绕过未知操作”的漏洞，也阻塞同标签内真正不同的后续草稿。用户不得通过换标签、清库、确认或点击重试承担这项缺陷。

采用**稳定逻辑草稿身份**与**短时输入焦点代际**分离：持续观察仍绑定原operation/asset/attachment；输入epoch失效只撤销输入权。取得真实且可区分业务草稿的证据后，未决锁以该逻辑草稿为范围，同草稿恢复/换焦点不能解锁；已证明不同的新草稿可独立处理新图片。未证明时保留现有整标签回退锁，不能仅凭URL、DOM新节点、超时或rearm生成token缩小锁。

验收必须覆盖同草稿失焦再返回、新线程、同URL业务草稿替换、返回旧草稿、窗口移动及重启：旧操作只有observe、无第二次输入；不同且被证明的草稿不被旧UNKNOWN阻塞。不迁移旧UNKNOWN为无证据的新draft identity。

### 相关准入依赖（不以本轮CI关闭）

- 当前页面焦点epoch同时限制观察；失焦会撤销证明并结束对应成功watch。后台、切出再返回后的迟到失败须随UX-02分离观察生命周期后真机验证，不能由活跃卡片DOM故障推出。
- 补偿后安全重试尚有契约缺口：Core要求关联原非空attachment ID；normalizer的无残留失败要求attachmentAbsent且ID为空。准入前必须表达并验证“原附件已退役且不会自动完成”的关联证据，禁止把nil当通配符。当前空retry注册表保持不变。
- 页面32个generation、每代32个operation、64个成功watch及M1 journal256条墓碑均是开发上限；持续日常使用尚未验收，不能通过清除未决记录规避上限。

## 本地Codex下一轮直接续做

以PR #1最新正式检查点建新的真机worktree，保留原验收分支和队列；不要把正式分支 reset 到旧1909771或f075b8f：

```bash
git fetch origin codex/engineering-foundation-20261027
git worktree add -b codex/riftlet-real-mac-round2-20261027 ../Riftlet-real-mac-round2 FETCH_HEAD
```

核对本页及验证记录的已测源码SHA后，执行现有 `scripts/build-macos.sh`、三个已有自检和[MAC_ACCEPTANCE](MAC_ACCEPTANCE.md)。沿用既有SQLite及私有媒体，升级时保留UNKNOWN/补偿审计；不要降级v2数据库给旧v1构建。

下一轮只做实际闭环剩余项：真实请求执行环境中的网络中断/100%后异常、普通线程Chat识别、UX-01/02身份事实及物理N1。M1只接取得真实版本/AX结构证据的provider/profile，独立于Web。每项保留确切源码、一次输入、原目标、原附件、无Send及PASS/FAIL/NOT_RUN，不扩大本轮已取得证据。日常工程决定由负责人和本地Codex自行完成；正式分支统一由root整合，main和发行继续不动。

## 第二轮本地 Mac 候选交接（2026-10-27）

独立分支 `codex/riftlet-real-mac-round2-20261027` 基于本文件正式检查点 c1456534；源码 `fff0e8c090f125211b35a56e7a16abef61109fb1` 已通过完整 CI 227 原生/31 页面测试和真实普通线程、POST100 XHR 中断、原操作后台观察/补偿的局部验收。详见[第二轮报告](../engineering/evidence/2026-10-27-real-mac-round2/README.md)。这是待 Pro 技术集成的候选，不是本文件上方正式分支已经合入的声明。生产与重试仍关闭；尤其无事件的业务身份 A→B→A、UX-01 全场景和物理 N1 未准入。原分支/数据库/媒体/补偿审计保留，不能清理 UNKNOWN 来继续演示。

</details>

</details>


## 第四轮本地 Mac 候选：待 Pro 合流

正式起点 `a441c70f3c4071069bd594513ecf16600bbb0ab8`；独立分支 `codex/riftlet-real-mac-round4-20261027`，源码提交 `35e98517ce2808a35a45a26a08d18e4b386b8bf7` 与 `c9c68a66c4b6ff55ffe8048cff6f1cf781600519`。不得把本段当作正式分支已合入声明。

实际突破：发言框未聚焦的普通已保存对话，人工首击新合成图一次，原目标冻结、单次输入、完整完成证据和 used 已通过一次局部实测。点击前已有 ACK，因此冷首击尚未关闭。新增裸 UUID 业务身份读取、composer 可用性与焦点分离、v6/v7 原操作只读兼容和 native ACK 诊断。未改 Core/UI/App 产品源；235 native / 48 page / 14 legacy 及打包 CI PASS。

PR #4 的 `90a04883160032fc6354fb4f3d3f7d56fede2947` 是本轮产品依据：实际 uploadStarted 后快速视觉吞噬，最终 READY 与安全重传独立。旧版 used/READY 动画不是新版视觉契约 PASS。详见[第四轮证据与限制](../engineering/evidence/2026-10-27-real-mac-round4/README.md)、[Core persisted profile 最小补丁请求](../engineering/evidence/2026-10-27-real-mac-round4/core-persisted-identity-request.md)和[App ACK 发布接口](../engineering/evidence/2026-10-27-real-mac-round4/app-integration-request.md)。

保留原 SQLite v2、16 个原媒体文件、16 个原操作和 3 个补偿审计；新加 1 图/1 成功操作。原 UNKNOWN 未重放。App 已正常退出，原页面 v8 observer 特意保留以支持可能的原操作迟到失败只读观察；不应 stop/清 registry 来制造新 bind。生产来源、安全重传仍关闭。


## 第五轮本地 Mac 候选：真实新版链路已验证，未合入正式分支

独立分支 `codex/riftlet-real-mac-round5-20261027`；最终已测源码 `53ebcc4da4b0df508edc11f6ead9ea4d8a843dad`，正式基线 `e89d49f763036781c90618422da256e03cbca2ac`。完整 CI [40497953468](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40497953468) PASS：314 native / 68 page / 45 legacy / 13 lifecycle detailed。Web v11/schema2 保留 v6–v10 原操作只读；修复真实初始无数值进度误拒绝，以及真实 MutationRecord NodeList 没有 `.some()` 导致 start 早返回后观察中断。

实际生成图片的 **一次 helper AX → 真实递增上传开始 → AppKit 快吞噬 → 后台独立最终成功 PASS（限定）**。原 input=1、完整 target/attachment、首份 start 审计、较晚 final proof 和 persisted succeeded 对齐；开始后约59–322ms调用动画，动画段约253ms，窗口关闭早于最终证明约4.89–5.16s。不是物理鼠标或无ACK冷首击；原保留配置swallowDuration=.24，不是点击到关闭仅253ms。

Core/UI/App正式源码未改；两份最小临时overlay供Pro接入synthetic start策略及诊断/AX元数据。生产、safe retry仍关闭。原11 Web资产/17操作/3补偿及所有原私有媒体哈希保留，新增5图各input1，其中2图未决保持原样；未发送消息。详见[第五轮完整交接](../engineering/evidence/2026-10-27-real-mac-round5/README.md)。本段替代此前“等待人工点第2张”的准备检查点；无需再请求该动作。下一项为Pro集成限定synthetic补丁，其后继续冷首击、业务转换、同草稿多图与物理N1，MID及安全终止分别准入。


---

## 第八轮独立交接（历史原文）

# 第八轮独立真机交接 · 2026-10-28

分支 `codex/riftlet-real-mac-round8-20261028`，最终源码 `ee1d960adf67432be627e86e7aa9350e5d85d9c0`。已继承正式 `595142d` 与第七轮祖先；本分支不写正式 PR #1。完整结果、准确已测 SHA、CI 和保留报告见[第八轮 README](../engineering/evidence/2026-10-28-real-mac-round8/README.md)。

功能源 `85250a8` 的完整 macOS CI [40544274635](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40544274635) PASS。最终 `ee1d960` 的 [40546396233](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40546396233) 因托管 macOS ARM64 容量不足未分配 runner，0 步骤，验证状态 NOT_RUN；本地完整构建及最终闭集诊断真机确认 PASS。待容量恢复只补跑该 CI，不重复上传，也不循环重试或改付费方案。

**已修复：CLEAR 真正底层透传（软件实击）。** 视觉 row 忽略鼠标，图片与编号独立非激活输入窗；最终默认竖屏 IMAGE/NUMBER/CLEAR/GAP 全通过，按住期间保留原位置、释放后选原图再补位通过。CGEvent 与人工物理分列，compact/全屏/Spaces/1×/跨应用物理焦点仍未闭合。没有事件转发或窗口排序绕过。

**仍未解决：真正无 ACK 冷首击。** AX hints 注册移到首次 capture 之后，但两次原 AX 点击仍无先行 ACK、零新输入。保留的 v10 root monitor 阻止 v12 接管，现有封闭拒绝码缺失已补；最终 App 实测返回 `unobservedRootDescriptor`。独立新文档完整 ACK 晚于点击约 1.938 秒，未回填或重放。最小隔离 MV3/native 通道真实跑通，但不证明业务草稿/前台事件连续性，不能据此启用发行扩展或生产输入。

SQLite v3、25 Web 媒体、27 操作、6 未决相位、补偿与开始回执、14 其他私有文件均保留。生产截图上传、生产开始 profile、安全重试仍关闭。Pro 集成此分支的最小 App/UI/adapter 增量；不重复挑选五至七轮，不清监视器或 UNKNOWN 制造成功。


## 薄界统一候选独立打磨 · 2026-10-29

正式 `0e7ea8be` 与原生 `443d21d` 按祖先双亲合流，独立候选分支 `codex/riftlet-real-mac-acceptance-internal-beta-thin-edge-20261029` / Draft PR #15；正式 PR #1 保持 Draft，main不合并。预测入口与磁力已在祖先，不重复cherry-pick。保留最新Feedback可靠性修复、原候选准入及所有旧证据。

统一设置、原生预览、分页、历史、Feedback布局与关闭、入口/辅助窗协调等实质打磨正在准确组合CI与非作者视觉/工程审查。已有成功CI中发现并主动驳回了漏NSPanel的多窗取证，不能以构建成功代表产品视觉合格。全部尝试、已审源与最终交付状态统一记录于[本轮质量交接](../engineering/evidence/2026-10-29-unified-candidate/README.md)，该记录是本轮最新结论入口；下方历史阶段陈述不代表当前准入。

真机离线，旧H不复测，不触碰UNKNOWN/原图/数据库。普通生产上传、安全失败与重试仍关闭，Feedback云端未部署；不要求创始人立即安装体验。
