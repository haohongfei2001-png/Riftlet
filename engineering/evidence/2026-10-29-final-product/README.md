# Quiet Edge R2：最终原生取证修正与正式准入 — 2026-10-31

**最终源码、同源完整 CI 和两份 App 以 [PR #1 本轮最终交付](https://github.com/haohongfei2001-png/Riftlet/pull/1) 为准。** 唯一正式工程仍在现有 Draft PR #1；PR #23 已通过原始双亲历史合入正式分支，main 未改，没有新长期候选或公开发行。

## 为什么在绿色 CI 后继续修正

正式 `107898ee31c8e55d9f7eda150625231adb72e261` 的 [Native 41179937595](https://github.com/haohongfei2001-png/Riftlet/actions/runs/41179937595) 和 [Feedback 41179937661](https://github.com/haohongfei2001-png/Riftlet/actions/runs/41179937661) 均成功，实际 checkout `520f32f4ea313a5e500263aef91d6c0e9391fde6`。完整执行结果保留为历史，**不据此批准最终视觉交付**。

独立查看本轮 R2 原始 PNG 发现，首个左上场景的折叠相机窗处于可见状态、图标透明度为 1，却被验收 helper 的不透明背景盖住。真实原生窗口顺序是 row → backdrop → camera/input；屏幕变化后重建队列，只将背景放到首行后面，未保证它低于原相机。原 R2 `057a007` 同场景 PNG 与本轮逐字同 hash，确认不是实例可靠性合并引入的产品回归。旧图/日志及其准确验收范围均保留，没有选择性丢弃失败帧。

## 最小修复及精确源码

- 修复源码 S2：`1459ab26b88eec15fdc9102f05f4f540dff29f07`；tree `02d06aa465385a1580fe133b723e10f7985c6a12`；唯一父为 `107898ee…`。
- 仅四个既有验收文件：两个 GUI helper 文件、原 capture manifest 验证器、对应 Python 回归。App/Main、所有产品 UI、实例所有权、Core/Capture/Adapters/Feedback、所有 workflow 和准入实现均与上一正式头相同。
- helper 按本进程真实 AppKit 窗口顺序，把**背景窗本身**置于最靠后的可见产品窗之后；静态取证在既有等待前再正确排列背景。未提高产品层级、强制相机 alpha 或重排捕获数组。
- 原生捕获前检查完整真实选窗列表，合成背景必须在最后，否则失败；随原始 frame 固定背景身份，Python 验证器同样严格拒绝缺身份或遮挡。单一产品窗口分支不变。
- 两个针对性回归在旧验证器上产生 7 个预期反例失败，修复后 **20/20 PASS**；修正前后的完整日志 hash 及原始结果保留于 `results.json`。

两位非作者独审精确 S2 后，正式 gate 仍仅更新 `REVIEWED_SOURCE` 字面 pin，不修改已有三个 metadata 例外、四历史审计、父链/对象规则或固定 main 28 个网站对象。旧 pin 对 S2 实际为 24/25 PASS，仅拒绝四个被修改对象；路径集合、历史审计全部通过。这是加强取证真实性，不是放宽检查。

本检查点之后须用最终 H 的新完整 Native ARM/Intel、Feedback、来源审计、同源原生 PNG/MOV 和原始 App ZIP 完成收口；`107898ee` 的 App 不作为最新版交付。最终运行结果更新在 PR #1，不再追加没有对应 App/CI 的源码 HEAD。

## 准入及真机续做

**普通生产上传、内置截图上传、safe-retry、Web continuation 继续关闭。** 内部 U1 的限定成功、选区 FAIL、111 份私有原始证据未重新验证等边界不变。新 CI 图像仍是 synthetic native WindowServer 取证；真实系统截图 fixture 的 PASS/NOT_RUN 按最终日志分别记录。人工物理输入、多屏热插拔、VoiceOver 朗读、Spaces/全屏、最终默认 App 和原生 Feedback 到云端不从合成图或测试推定通过。

后续 Codex 使用本轮最终 HEAD、实际 checkout 和两份 ZIP 的精确 hash，执行下方既有六项最小清单即可。无需重做 R2 或重复历史研究；新权限/物理操作仅留下对应项目，其余工作直接推进。以下全部先前检查点和原审计原样保留。

---

# Quiet Edge R2：正式组合源码准入检查点 — 2026-10-31

**唯一正式工程继续使用 Draft PR #1；不修改 main、不公开发行。** R2 已按完整累计差异合入最新实例可靠性修复，保留两个真实父提交。没有另建候选分支，也没有重新设计 R2。

本文件记录源码准入时的事实。**最终正式 HEAD、同一 HEAD 的完整 Native ARM/Intel、Feedback、实际 PR checkout、独立视觉/实包结果及两份 ZIP，统一见 [PR #1 本轮最终交付](https://github.com/haohongfei2001-png/Riftlet/pull/1)。** 后续完成的 CI 不通过追加未测试源码提交记录；下面历史检查点各自保留原来源和范围。前一轮完整 PR 正文原样归档于本目录 `results.json` 的 `quietEdgeR2Integration.precedingFormalPRDelivery`，不因更新顶部而丢失审计。

## 来源、选择与独立审查

| 项目 | 精确身份与范围 |
|---|---|
| 前一正式 HEAD | `8b70cb0d63da1e3768ed9dfc3facdcca6efdab21` |
| R2 已审实现 | `057a0071791d654ecfe2b7840cf86904dd600df8`；累计包含四次实现与必要修复 |
| R2 原始交接 / 第二父 | `4c92f6e639538bc7f3b1e06cf71fb07086add278`，原 PR #23 |
| 独立批准的组合源码 S | `86a6646abbe05c4dbe186f022b08d779950de5ae` |
| S tree | `02b7b82ed8ceddbd14cd9d31159ad794c19c003c` |
| S 真实双亲 | 按顺序 `[8b70cb0d…, 4c92f6e…]` |
| 继续固定的 main | `fccd809e9d55e0b221e75e6dcd7c21f6d357ee74`；28 个已批准网站对象 |

相对前一正式树仅 **35 路径**：14 个 App/UI 产品文件、17 个必要测试/支持文件、两个既有 GUI helper、一个 35 行 R2 原生 capture 脚本、一个既有 Native workflow。33 个路径原样取 R2 blob；Main 是以 `2bddb61` 为公共基线的确定性三方合成；workflow 仅将原 R2 capture 步骤取消 PR23 分支限定，使两架构正式执行。原有完整 CI 测试步骤和失败退出语义保留，Feedback workflow 不变；旧几何耦合测试随 R2 累计实现替换为对应配置/相机回归。

R2 的 78 个设计/旧验收归档对象不复制进当前树；它们完整保留于第二父提交。原 [INTEGRATION.md](https://github.com/haohongfei2001-png/Riftlet/blob/4c92f6e639538bc7f3b1e06cf71fb07086add278/engineering/evidence/2026-10-31-quiet-edge-r2/INTEGRATION.md)、[VISUAL-REVIEW.md](https://github.com/haohongfei2001-png/Riftlet/blob/4c92f6e639538bc7f3b1e06cf71fb07086add278/engineering/evidence/2026-10-31-quiet-edge-r2/VISUAL-REVIEW.md) 和 18 场景原像素证据均可按原 SHA 追溯。新正式树新增 5 文件、无删除，971 个原正式对象不变；总文件 1006，门禁保护对象 1003。

`ownership_review` 独立审查所有产品/回归、组合 Main 和新调用链；`admission_review` 独立核对全部 tree、父链、35 路径映射、原历史门禁及网站对象；两者均批准精确 S。`acceptance_review` 复核原交接、原始日志、18 场景 67 文件 hash 及关键原图，给出限定范围 PASS。完整结构化报告及 hash 见 `results.json` 的本轮字段。这是实际非作者工程审查，不冒称 GitHub 人工 APPROVED review。

## 实例所有权与 R2 正确共存

Main 的组合 blob 为 `1be863f64a3d907dee84074f296b0125ecc6c950`。App 仍在菜单、首次使用状态、Feedback 和异步队列前取得主锁；失败实例不启动 sidecar；获准退出后锁保留至进程退出。ownership 源文件、五项锁回归和四份 U1 原始交接原样保留。

R2 接入持久配置、六位置/显示器 UUID、独立相机、分页/受保护补位、完整 hover 和校验原图 Fit/100%/200%。旧绝对布局保持到明确选择；显示容量不限制收录数量；新截图不强制翻页；点击 UUID/revision、唯一输入、uploadStarted 与最终完成仍独立。左侧只反射几何，不镜像原图。原图详情保护归档/补位，关闭时释放保护。

Core、Capture、Adapters、Feedback、服务、SQLite、Resources、Package.swift 和包装脚本均与原正式树一致。没有重放 UNKNOWN、清库、删锁或删除原图/媒体；没有新增生产准入。

## 准入门禁与正式验证

原 pin `3cc74fc` 实际检查 S 时，25 项中 23 项 PASS，仅精确路径/对象两项拒绝：5 新增、30 修改，缺失对象为空。四历史审计分别 42/17/17/13 项 PASS。独立审查后，gate **只将 REVIEWED_SOURCE 精确改为 S**；既有三个 metadata 例外、全树比较、四历史 blob/祖先、实际双亲和固定 main 28 对象均不变。

正式运行必须以最终 H 的真实 PR merge checkout 完成两个来源 job、Native ARM/Intel、Feedback、原有完整视觉/辅助功能与新增 R2 12 场景、两份原始 App ZIP 审查。旧 R2 workflow 的整体 FAIL 不改写为成功；旧执行 job 成功不代替新正式运行。

**原交接纠错：** R2 `final-verification.json` 的 `native.checkout` 和 `feedback.checkout` 把 API source HEAD `057a007` 写作 checkout。独立读取 ARM、Intel、Feedback 原日志后，实际 checkout 均为 **`50a362a995381f5f50d26d13068b5f87716dd4e5`**，与原 README/native manifest 一致。保留原文件，本轮准确区分来源 HEAD 和实际 checkout。

## 保留的真实验收与生产边界

此前 U1 是 `b0cc673` 的内部普通配置、已有预绑定、聚焦编辑器和已保存聊天：一张新系统 PNG、input=1、start=1，约 1.876638 秒开始吞噬，后来独立证实最终成功。不是最终默认生产包，不是 1.88 秒上传完成；**选区保持 FAIL** 保留。111 份私有原始证据未重新取得，不冒称再次验证。

R2 原 18 场景和本轮 CI 视觉均为隔离合成原生 WindowServer 证据，不是物理输入或真实上传。当前登记 Mac 离线，本轮真机普通启动、实际显示器/Spaces、真实默认 App 上传、原生 Feedback 到云端尚未执行。普通生产 input/start/completion、内置截图上传、safe-retry、Web continuation **继续关闭**，原受限候选范围不扩大。开发 App 为 ad-hoc，未 Developer ID 签名/公证，不冒称 Gatekeeper 通过。

## Codex 最小最终真机清单

以 PR #1 本轮精确 HEAD、相应架构原始 ZIP、manifest/checkout/二进制 hash 为起点，保留所有旧数据与原 operation。能够独立执行即直接完成；人工物理操作或新的系统权限仅留对应项目。

1. 最终普通 App 启动、Feedback 可用、第二实例拒绝、正常退出及隔离受控异常恢复；不删锁、不清库、不重放旧 UNKNOWN。
2. 用现有数据验证旧绝对布局不被自动迁移；另用隔离新配置检查默认左中、六位置、0/90% 遮挡、0/256pt 边距、1/10 显示容量、设置重启持久化和独立相机。收录超过显示容量后翻页，新图不得强制跳页。
3. 单击、双击、按住期间配置/入队、正向开始后吞噬与受保护补位；hover 完整预览与查看原图区分，Fit/100%/200%、缺失/更换原件保持真实失败且不替代上传。历史、设置、Feedback 草稿重开/重启及截图模式/取消不回归。
4. 在已有获准隔离内部普通配置中，用新截图/新操作补已有聊天与 Home/local、聚焦/失焦；记录唯一 input、真实 start、开始吞噬、后台独立完成和重启。无 ACK 的安全拒绝仅算安全通过，不算一次点击可用性通过；不开放默认生产入口。
5. 同一最终来源定位原选区 FAIL，保留真实草稿/非折叠选区，追踪首次 blur/collapse 并做原生附件对照；不得强制 focus、恢复陈旧 Range 或改正文制造 PASS。原生 Feedback→云端须先具备独立 D1/私有 Issue 验证与清理能力，再发一次合成样本并完成清理；缺访问仅暂停该项。
6. 真实多屏断连/重连与明确恢复、负坐标/混合 Retina、Spaces/全屏、VoiceOver 朗读、人工物理鼠标与新增系统权限集中最后执行。准确记录 NOT_RUN，不把模型几何或 CI PNG 改称真机 PASS。

无需重做 R2、历史研究或另建长期分支，不要求创始人提前体验 Beta。以下为此前完整历史记录。

---

# 最终实例可靠性补丁：正式源码准入检查点 — 2026-10-31

**唯一正式工程为 Draft PR #1。** 本次完整复用 `b0cc673` 的三个已审文件与 `3cc74fc` 的四份原始脱敏验收记录，沿原提交历史快进整合。代码与证据无二次改写，没有新产品分支或研究增量。

本文件是最终源码准入时的永久记录。**最终正式 HEAD、同一 HEAD 的 Native ARM/Intel、Feedback、来源审计、实际 checkout 与两份原始 App ZIP 的检查结果，统一以 [PR #1 顶部的本轮最终交付](https://github.com/haohongfei2001-png/Riftlet/pull/1) 为准。** 不为追加完成措辞制造一个没有经过相同 CI 的新源码 HEAD；下方旧 CI、旧包与历史 pending 均保留各自时间和来源。

## 精确来源与独立审查

| 项目 | 身份与范围 |
|---|---|
| 原正式 HEAD | `2bddb61a19114167b7485c392600c4b91dc62725` |
| 原始产品修复 | `b0cc67366fa78e6fc24d8e0c5cc468fd6a13cb76`；三个文件 |
| 原始验收交接及完整已审源码 S | `3cc74fc80750a47f437ab7361e31016a5de0b118` |
| S tree | `74d80ff1efc034a0ed4e848ee9757d32d955d30a` |
| 官网 main 固定来源 | `fccd809e9d55e0b221e75e6dcd7c21f6d357ee74`；28 个对象保持 |
| 增量 | 7 个路径：2 个新实现/测试文件、1 个 Main 修改、4 份新证据；6 新增、0 删除；994 个原对象逐 mode/type/blob 不变 |
| 审查 | ownership_review：三文件与启动/退出/Feedback 调用链 PASS；acceptance_review：公开交接和真实 CI 来源有范围 PASS；admission_review：完整 tree/历史审计/官网对象 PASS |

主锁在菜单、首次使用状态、Feedback sidecar 和队列启动之前同步取得。失败实例直接退出，退出路径不会反向触发 lazy Feedback。退出已获准后主锁保留到内核进程回收，避免旧 FeedbackStore 还活着时新实例提前取得主锁。五项原始 XCTest 与既有测试完整保留；不删除锁文件、媒体、历史或旧 UNKNOWN，不改变数据库 schema。

正式 gate **仅更新 REVIEWED_SOURCE 到上述 S**；既有三个 metadata 例外、四历史审计的原始 blob/祖先、28 个 main 网站对象、真实双亲与全对象比较均未放宽。两个正式 workflow 原样。原 gate 对 S 的两个精确差异拒绝已记录，不能将该旧 pin 的失败当成测试已全部通过。

## 继承的真实结果与未通过范围

[原始完整交接](../2026-10-31-unified-unattended/README.md)保持原文。内部普通验收构建在已有聊天中，对一张新系统快捷键 PNG 完成一次 CGEvent 点击、唯一 input、唯一正向 uploadStarted、约 **1.876638 秒开始吞噬**、约 **2.007499 秒原面板关闭回调**，并独立观察到最终 `succeeded / used / swallowed`。最终成功被观察的时间是约 25.591942 秒上界，不是 1.88 秒完成上传。

该样本事先已预绑定，编辑器有焦点；它不是默认生产 App、自然冷首击或物理鼠标验收。正文与旧附件保持，但**选区保持为 FAIL**：后来发生 blur/折叠，并检测到站点提示；完整因果尚未证明。没有强制 focus、恢复陈旧 Range 或重写正文来掩盖失败。

原始验收报告记录重启后原操作身份、两条旧内部 UNKNOWN、39 份旧媒体加新 U1 及 122 份既有证据保留。当前集成者读取的是公开脱敏交接与实际云端日志；111 份私人原始文件未取得，不冒称本轮重新验过原图和真实 SQLite。Feedback 仅本地 AX 草稿保存/重开/重启通过，原生窗口到云端未跑。内置截图仅入口、模式切换和取消部分通过，截取动作因外来窗口覆盖而安全拒绝。

当前已登记 Mac 离线；最终包真机操作只留给具备设备能力的后续 Codex。这不阻断本轮完整正式 CI 与双架构构建。

## 生产准入结论

**普通生产 input/start/completion、内置截图上传、safe-retry、Web continuation 均继续关闭。** 原受限候选范围不扩大。完整 CI 与实包通过只证明最终工程组合和构建，不代替最终默认 App 的真实端到端和独立准入。PR #1 保持 Draft，不修改 main，不公开发行；两架构是开发 ad-hoc 包，Developer ID、公证及 Gatekeeper 不冒称通过。

## 给 Codex 的最小最终真机清单

先从 PR #1 本轮交付取得最终源码 HEAD、实际 checkout、两架构包与 SHA256，核对 `build-info.json`、二进制及 14 组构建输入。使用对应架构；保留正在工作的目录和旧数据。

1. **最终包启动、所有权和恢复。** 正常启动并打开 Feedback；重复启动的失败实例不得创建 UI 或抢 Feedback 锁；正常退出和受控异常退出后重新获取所有权。检查原操作、媒体和旧 UNKNOWN 保留，不能重放旧输入、清库或删除锁文件绕过故障。
2. **默认 App 已有完整功能。** 新系统截图收录、微图、无/磁力、历史、设置、Feedback 本地草稿关闭重开及重启；确认默认生产上传仍关闭。安全完成内置区域/窗口/全屏截取与取消；内置上传保持关闭。
3. **内部普通配置的缺口。** 仅使用已有获准隔离编译配置及新系统截图、新 operation，补已有聊天与 Home/local、聚焦与失焦。记录唯一输入、真实 start、吞噬、独立原操作完成和重启保持；如无 ACK，准确记录是否安全拒绝，不预设成功或强制吞噬。这些结果仍标为内部配置。
4. **选区 FAIL。** 同一最终来源、受控非空草稿和非折叠选区，记录首次 collapse/blur/对话框时序并做原生附件对照；不得强制焦点、恢复陈旧 Range 或改写草稿制造 PASS。
5. **Feedback 原生到云端。** 先确认独立 D1/私有 Issue 验证和清理路径，再提交一次合成样本并验证真实接收/状态/删除；可自动执行的 IME/VoiceOver 等继续做。缺清理或账号能力只保留该项，不暂停其他工作。
6. **最后统一列人工项。** 物理鼠标、即时截图后的自然点击、Spaces/全屏实际交互及确实缺少的新系统权限。A/B 重叠和安全失败仅在各自独立证据充分后单独准入，不能借普通成功顺便开放。后续默认生产包须在正式准入后再次验收，内部包结果不替代它。

完成全部可独立操作后一次性交接精确结果。创始人无需提前体验 Beta；不再重做本轮修复、旧成功样本或另建正式集成分支。

---

<details>
<summary>此前普通入口正式集成与全部历史记录（原文保持）</summary>

# 普通入口正式集成：WAL 修正后的精确源码准入（2026-10-31，北京时间）

**已审完整源码：`a271929d35cdc0ee0e49d87ae02989cfaa133d2d`；tree `b1b46bc3f3aa84bae1ee9be0c37fc14a95458b9b`；唯一父提交为首轮正式 H1 `6f290c4ccd2d7fef75dd474fc0df412838cef6de`。** 本提交只更新准确来源 pin 和两份既有证据 metadata。S2 仅改 WAL 初始化及其回归测试，其他 993 个对象逐 mode/blob 保持；scope 与 release 非作者复核通过，WAL 作者另行披露。新的正式 Native ARM/Intel、Feedback、实际合流来源及原始 App 实包验证仍待执行。

## 首轮结果与最小修复

[Native 41123996316](https://github.com/haohongfei2001-png/Riftlet/actions/runs/41123996316) attempt 1 整体失败：ARM 与 source 成功，Intel 的新增 WAL 两阶段锁测试记录 `elapsed=4.096347656s`，未满足原 `<4s` 断言。801 是唯一测试方法枚举数；日志没有 WAL 内部逐调用时序，不能断言具体原因或称为已证明的偶发失败。[Feedback 41123996227](https://github.com/haohongfei2001-png/Riftlet/actions/runs/41123996227) attempt 1 成功。两个 source job 各 32/32 通过，四份历史审计保持。以上仅属于 H1；未盲重跑、未交付旧 H1 App，也不借用为新源码通过。

独立的隔离 SQLite 实验确认累计睡眠 timeout 的实际缺口：单调用受控暂停后约 4.076 秒，单调时钟截止处理器约 3.000 秒。修复仅在 WAL 初始化期间安装截止时间 busy handler，prepare、step 及立即 BUSY 重试共用三秒预算。回调不重入 SQLite；作用域退出时先恢复原 3000 ms timeout，再释放指针。分阶段真实锁测试直接计时实际生产 WAL helper，保留 `<4s`、连续两阶段锁、原行与构造器恢复，并核对失败连接的 timeout 恢复。迁移、事务、schema、上传重试均未改变。该预算不能保证被操作系统暂停的进程在暂停期间返回。

补丁 SHA256：`d6eb49a393a124e1e44c7e9c3a7c5e73039fa4840e4aebab50fdc7c9c73f3983`。三份 S2 精确复核、非作者 patch 批准、作者说明和独立实验原文及哈希均在 `results.json → ordinaryEntryIntegration.nonAuthorReviews`。

## 完整组合与来源

按完整依赖复用 `4f5285e`、`9e43ad3`、`10a8fe9`、`4e02c21`、`5010b4e`、`f306251`、`629624f`、`8ed2f90`。相对原正式 `edbdc7aa`，实现/必要测试/构建/门禁为 26 路径，另有两份既有 metadata；总计 28 路径、6 新增、0 删除，967 个其他对象保持，22 个产品变更对象直接等于专项最终 blob。S2 清单 SHA256：`581836f20df664802517d3357cf59c0221648f1ae1f8afbb7c6eb6957c4a745e`。

main 再核实为 `fccd809e9d55e0b221e75e6dcd7c21f6d357ee74`；精确 28 网站对象、四份历史审计、双亲/祖先/路径/mode/blob 规则保持。没有修改网站、main ref 或两份正式 workflow；不纳入新增研究工具、专项 workflow 增量、临时运行配置或 TEST-ONLY overlay。保留的隔离编译通道不属于默认统一 App 的内部验收 flag、身份或数据根。

## 准入与真实验收

最终普通 App 真实端到端仍 **NOT_RUN**：已授权 Mac 执行器离线，本会话没有连接的本地 Chrome 来源上下文；没有真实 App 启动、输入或个人数据修改。旧内部 Home 成功仅属于 `f306251` 的预绑定 CGEvent 范围，不能替代最终 App。普通生产 input/start/completion、内置截图来源附加、Web continuation 和 safe-retry 均保持关闭；原受限候选准入不扩大。

旧 UNKNOWN/历史/媒体、来源隔离、Home/local 精确身份、独立开始/完成、原子 B 条件、Feedback 固定云端、薄界、磁力、内置截图与资源完整保留。选区折叠沿用原生对照结论，没有 Range、focus 或正文恢复。PR #1 保持 Draft，不合并 main、不公开发行、不要求创始人体验 Beta。

---

<details>
<summary>首轮 S1/H1 源码准入及此前完整交接（历史原文）</summary>

# 普通入口正式集成：精确源码准入检查点（2026-10-31，北京时间）

完整组合源码 **`e0a81ea9ec1e95557e733face88658c16f44efe7`**、tree `d2bcc065258b43fac3af9363a54a329a3747c699` 已经三路非作者审查；唯一父提交是正式 `edbdc7aae45c35878694e9fa376757dac7b630a8`。本提交只写入该已审源码 pin 和两份既有证据 metadata。**正式 Native ARM/Intel、Feedback、实际合流来源及新 App 实包验证尚待本次 PR #1 工作流完成。**

## 实际范围与最小修复

按完整依赖复用 `4f5285e`、`9e43ad3`、`10a8fe9`、`4e02c21`、`5010b4e`、`f306251`、`629624f`、`8ed2f90` 的产品与必要测试/包装差异。26 个路径为14 Sources、7 Tests、4构建/门禁脚本及1个既有网络fixture；6新增、20修改、0删除，969个其他正式对象保持。22项直接等于专项最终blob；其余仅为下列已审组合修订。

- WAL初始化的prepare和每个step前刷新同一剩余三秒预算。真实SQLite分阶段锁复现旧约4.54s、新约3.00s；新增Swift真实锁回归仍须正式双架构CI执行。仅WAL初始化BUSY重试，不重试迁移/事务/上传，不改变schema。
- 支持说明限定“旧内部候选证据”，避免与内部Home/local范围混淆。
- 最新main `fccd809e9d55e0b221e75e6dcd7c21f6d357ee74` 的28个网站对象按精确blob/mode审核；保留四个历史审计、双亲、祖先、路径和模式检查。网站内容、main ref及工作流均未修改。旧pin准确拒绝本次26路径差异，未跳过或降低检查。

不纳入新增研究诊断工具、专项workflow增量、临时运行配置或TEST-ONLY overlay。保留受控隔离编译通道源码，但默认统一包不带内部验收flag、身份或数据根。Feedback、Capture、薄界、磁力、内置截图、资源及旧UNKNOWN/媒体/审计保持。

完整精确路径、来源、审查记录原文及SHA256见 `results.json → ordinaryEntryIntegration`。主源码清单SHA256：`d88546171a652ddd56797f5ccf65be3846fb8f54244803d5533cd8ad8039fcea`。WAL作者与交叉非作者审查角色明确分开。

## 真实证据与能力边界

[专项最终交接](https://github.com/haohongfei2001-png/Riftlet/tree/d8a84277fac3e90ff80056b82e64db41c59f2426/engineering/evidence/2026-10-31-product-closeout)中的Home一次输入/实际开始/吞噬/独立完成限定于 `f306251` 的隔离内部预绑定CGEvent运行。`8ed2f90` 后续仅做启动/恢复，没有新上传。专项CI41116412129的两个macOS job成功，但source job失败、整体失败；它不能替代本次正式组合CI。

本会话登记的已授权Mac执行器离线，且没有连接的本地Chrome来源上下文。**最终普通App真实端到端为NOT_RUN**；没有启动真实App、操作Chrome、修改个人数据或要求创始人体验Beta。历史Home记录及内部Test App不替代最终包验收。普通生产input/start/completion仍关闭；内置截图来源附加、Web continuation和safe-retry保持关闭。原受限候选的既有准入不扩大。

旧UNKNOWN和历史注册只读；新scope不补旧资格、不重输。系统截图与内置来源隔离；本地身份与持久身份不互相别名。开始、吞噬、最终完成独立判断；A开始不直接放行B。选区折叠保留原生附件/存储提示对照结论，没有添加无证据的Range、focus或正文恢复。

PR #1保持Draft，不合并main、不公开发行。正式CI与包完成后仅收口证据；真实验收阻塞只限制相应准入，不追加无目的工程打磨。

---

<details>
<summary>此前已完成生命周期与Feedback正式证据（原文完整保留）</summary>

# 冷首击与持续使用生命周期：正式集成完成 — 2026-10-30

**PR #1 的正式整合、非作者审查、Native ARM/Intel 与 Feedback 组合 CI，以及两份新统一 App 实包核验均已完成。两套正式工作流都是 attempt 1 成功，无重跑。**

**本 PR #15 分支只交付两份 metadata；产品与构建的唯一来源是 PR #1 `edbdc7aae45c35878694e9fa376757dac7b630a8`。PR #15 保留此前代码和旧 gate，不能将本交接分支 SHA 当作新 App 源码或构建来源。** PR #1/#15 保持 Draft，main 未合并，未公开发行，未要求创始人体验。

## 精确来源与最小范围

| 对象 | 精确身份 |
|---|---|
| 正式产品 HEAD | `edbdc7aae45c35878694e9fa376757dac7b630a8` |
| 非作者已审源码 pin | `b714dc44b27cccb76356fe15fb4854dba599a689` |
| 已审源码 tree | `f043c283eeb49e1f3f8b3c2640ea43c7bbeeabde` |
| 正式 H tree | `b0c34e307b3c7f804f6b80432b314a2ed232d097` |
| 实际正式 CI checkout | `9b6063677672f2af6d9c9f0adf4ce115fa238385` |
| 实际 checkout tree | `108d0222e41a28340b9978c94de5f7be477b031c` |
| 原正式基线 | `98e66a956d55b5fac71718bc627dd89705b2a506` |
| 保持不变的 main | `eba1a4fc77648a665e1d5c1f2609df1314c3b079` |

按顺序只取 `973a3e8c`、`9790cc3a`、`90dc466a`、`f7f8acdd` 的产品及测试差异：**18 路径，10 Sources + 8 Tests，5 新增、13 修改，971 个基线其他对象不变**。整树与专项已测源相比唯一差异是排除专项 workflow。没有合并技术分支、带入 `f02ddafb`、研究实验或 TEST-ONLY overlay。

三路非作者分别完成生命周期/身份安全、SQLite/原子槽位、全产品组合审查，均固定实际源码 b714、无确认阻断。H 只在已审源码之后更新来源 pin 和两份既有交接；另经非作者精确复审。四份历史 gate、原工作流、三个 metadata 例外及15个 main 网站对象保持原样，未降低门禁。

Feedback固定云端端点、薄界、磁力、截图设置、Resources、Package、服务及包装对象保留。原UNKNOWN、媒体、完整身份和审计保留。**真实Web continuation、普通真实上传、safe-retry仍关闭；A开始上传本身不能放行B。** 新B仍需要独立证据、原append返回、完整目标/nonce/运行期owner及原子SQLite事务。精确类型化未输入恢复不适用于commit已调用、回执丢失或旧UNKNOWN。

## 本轮实际正式 CI

| 正式工作流 | 结果与范围 |
|---|---|
| [Native 41024560197](https://github.com/haohongfei2001-png/Riftlet/actions/runs/41024560197) | **success / attempt1**；ARM `123959480040`、Intel `123959479659`、source `123959479843` 全部成功；2026-10-30 16:20:32 北京时间结束。 |
| [Feedback 41024560240](https://github.com/haohongfei2001-png/Riftlet/actions/runs/41024560240) | **success / attempt1**；Feedback `123959479892`、source `123959479708` 成功；2026-10-30 16:13:18 北京时间结束。 |

两份来源日志的实际checkout双亲为 main eba1a4fc 与正式 H，**各32/32检查通过，父提交986、合流后997个保护对象完全一致**。14组构建输入与正式 H 逐对象相同。没有把专项41017793874或旧H/H2运行当作本轮结果。

两架构完整、未筛选 `swift test --parallel` 均成功，每架构枚举779个唯一方法；这不是1558个不同用例，也不代表779次物理操作或零环境条件skip。页面106、legacy61均通过。13项dispatch生命周期、6项迁移及旧UNKNOWN/重启、两连接、持锁、原子槽位、列/索引回滚、安全拒绝均在完整执行中；严格磁力另9项详细用例通过，包含自然结束与停表不能伪造自然结束的反例。原包装12+13、release、bundle、严格ad-hoc codesign、4个App及GUI helper自检、统一Beta原验包均通过。

Feedback为**49个唯一原生/UI方法、24个服务用例、8套共117项隔离回归**通过；关闭测试2方法×3轮为重复，不追加唯一数。服务测试为受控HTTP/SQLite，不是再次部署或真实原生到云端验收。

原生视觉门禁：ARM原46场景119PNG/5MOV，Intel104PNG/5MOV；补充静态均6/6，系统可访问性变体分别18PNG/1MOV与14PNG/1MOV。owned capture保持**PARTIAL**：ARM window/region成功、fullScreen未运行；Intel region成功、window/fullScreen未运行，原因均为原 `FOREIGN_OVERLAP_VETO` 安全否决。原专项分支条件不适用步骤仍skipped，没有新增跳过；本轮不宣称物理GUI或新艺术验收。

## 新统一 App：本轮正式 Native 的原始包

| 架构 | 原始制品 | 内层统一包 bytes | 内层 SHA-256 |
|---|---|---:|---|
| ARM64 | [artifact12963810366](https://github.com/haohongfei2001-png/Riftlet/actions/runs/41024560197/artifacts/12963810366) | 2,038,878 | `3c1761e9e6632c59152530eab895536e3bd06e2da1be54b2c9300bfff7523d4f` |
| Intel x86_64 | [artifact12963282793](https://github.com/haohongfei2001-png/Riftlet/actions/runs/41024560197/artifacts/12963282793) | 2,148,795 | `594abfd488b1882efcf916e352f6f7015bfc8a4436427217034674c380585a7c` |

两者都来自外层 `build/Riftlet-Internal-Beta.zip`，内层原始字节不变。已分别独立核对API digest、完整ZIP/CRC、所有解包字节、原可执行权限、原仓库验包脚本、实际Mach-O架构、14组manifest输入、资源/许可证、固定Feedback端点与模式边界。

版本0.1.0/build1、最低声明macOS13，实际本轮CI为15.7.9；development ad-hoc，非Developer ID、未公证、真实Gatekeeper未运行。两包包含完整App、显式受限候选启动器、中文说明与build-info。普通App仍仅收录；旧H真实验收字段保持历史范围，不冒称本轮新真机结果。原日志和四份独审记录及摘要完整记录在 [results.json](results.json) 的 `coldClickLifecycleIntegration`。

## 剩余 P0 与本轮停止点

**无本轮已确认的源码、正式CI或实包阻断。产品真实验收仍未关闭：**

1. Chrome空闲后的真实冷首击、长期附加/移除及旧页面状态升级连续性。
2. A未完成时B不替换/取消A的独立真实附件证明；证明前真实Web continuation仍关闭。
3. 真实导航/失焦/刷新、迟到结果、丢回执和重启观察；不重传旧UNKNOWN、不清理原数据。
4. 普通模式真实上传和safe-retry的正式开放验收，按各自证据独立决定。
5. 保留已有真实Mac Feedback窗口至云端、IME/Keychain/VoiceOver/重启及截图隔离验收。

本轮不操作真实Chrome/用户Mac，不修改云端/官网，不安排后台执行器。**完成交接后停止追加工程打磨；下一轮只推进用户指定的真实附加、持续使用和产品开放验收。**

---

<details>
<summary>来源准入时的历史检查点及完整前序交接（其中pending只描述当时）</summary>

# 冷首击与持续使用生命周期正式集成 — 2026-10-30

**精确合流源码已完成非作者审查；此提交是来源准入检查点，正式组合 CI 与新 App 制品尚待实际运行。** 正式产品仍由 Draft PR #1 承载，PR #15 只用于必要交接。不合并 main、不公开发行、不要求创始人提前体验。

- 原正式产品：`98e66a956d55b5fac71718bc627dd89705b2a506`。
- 实际合流源码／本轮审查 pin：`b714dc44b27cccb76356fe15fb4854dba599a689`。
- 精确源码树：`f043c283eeb49e1f3f8b3c2640ea43c7bbeeabde`。
- 指定提交依次取用：`973a3e8c`、`9790cc3a`、`90dc466a`、`f7f8acdd`；18 个产品／测试文件，5 新增、13 修改，971 个基线其他对象保持原样。
- 整树与专项已测 `f7f8acdd` 的唯一差异是排除 `.github/workflows/transfer-lifecycle.yml`；没有纳入 `f02ddafb`、研究实验或 TEST-ONLY overlay。
- 专项依据：[最终交接 c99900c6](https://github.com/haohongfei2001-png/Riftlet/tree/c99900c6cc5c4a1f9f575576226d46252a1d6065/engineering/evidence/2026-10-30-transfer-lifecycle)。专项 CI `41017793874` 只作来源验证，不代替本轮正式组合 CI。

## 独立审查与固定来源

`lifecycle_safety_review`、`integration_scope_review`、`release_composition_review` 三位非作者分别完成 Web/Adapter/Core、SQLite/范围、完整产品组合终审，均固定上述实际合流 SHA，结论 `PASS_SOURCE_ONLY`，无确认阻断。18 路径 mode/blob 与已测来源逐一相同；完整 manifest 与审查范围写入 [results.json](results.json) 的 `coldClickLifecycleIntegration`。

正式 gate 仅更新 `REVIEWED_SOURCE`。四份历史审计的 revision/blob、三个 metadata 例外、固定 main `eba1a4fc` 及15个网站对象全部保持。独立审查曾先用旧 pin 执行新源码：只有5新增路径、13修改对象导致的两项预期拒绝，其余23项及四份历史审计通过；没有先放宽 gate 再审查。

本地离线页面106、legacy观察61、组合gate反例24均通过。完整 Native ARM/Intel、Feedback、严格磁力自然完成、原生视觉、签名和统一包验证将由原有正式工作流执行；本段不预报其结果。

## 产品与安全边界

48次与32→33相关回归覆盖旧身份保留、活跃载荷释放和迟到附件审计。类型化 pre-input rejection 仅在当前调用的完整身份/nonce/零输入/未commit证明满足时恢复；commit已调用、回执丢失、旧UNKNOWN和身份不明保持保守。新B须有独立 continuation 资格、原append返回和同一原子SQLite事务，不因A开始上传直接放行。

Feedback云端端点、薄界、磁力、截图设置、资源和原安全准入保留。**真实Web continuation仍关闭，普通模式真实上传和safe-retry仍关闭。** SQLite旧列、原目标、操作/回执与UNKNOWN均保留；v1/v2整体迁移和v3扩展失败回滚。并发v3扩展有定向回归，不能泛称旧v1/v2并发开启均成功；旧v13能力fixture也不等于真实历史页面升级验收。

## 本轮剩余 P0 与停止点

正式组合CI、新统一App及其独立核验尚待完成；最终实际run/head/package结果以PR #1和PR #15后继交接为准。随后停止扩展工程，转向Chrome空闲后的真实附加、持续使用、独立双附件证据、真实导航/失焦/刷新及丢回执/重启、普通模式与safe-retry开放验收，另保留既有真实Mac Feedback窗口到云端验收。此轮真实Chrome/物理Mac全部NOT_RUN。

---

## 保留的上一轮已完成正式交接

以下原文继承 PR #15 `623d3725`，完整保留其成功、失败、运行与制品原始来源；不把旧包或旧CI改称本轮结果。

# Formal PR #1 integration and completed CI handoff — 2026-10-29

**Feedback is in the actual formal engineering branch, both original formal workflows completed successfully, and the existing independently verified H2 unified App packages remain the delivery artifacts.** Root fast-forwarded PR #15 to approved evidence E `53ea3a1de76a30ab0d8cb221ff7e4e4fa2bce83f`, then PR #1 (`codex/engineering-foundation-20261027`) to H2 `98e66a956d55b5fac71718bc627dd89705b2a506`. PR #1 and PR #15 remain Open/Draft. PR #18 is Closed/Merged because its ancestor entered its target; main remains `eba1a4fc77648a665e1d5c1f2609df1314c3b079`. No main merge or public release occurred. This successor changes only the two existing metadata files, with no source, admission, workflow, screenshot, website or cloud changes.

## Actual formal checkout and source admission

The actual PR #1 test-merge checkout is `6537ab3a449f17d88caec8295d72f58e61f42535`, tree `248d3d8f75323d02c0d909e950582d557a822723`, with parents main `eba1a4fc77648a665e1d5c1f2609df1314c3b079` and H2. Independent reviewer `/root/deployment_review` fetched the complete995-file remote tree and verified exact H2 plus the original15 fixed main website objects (11 added paths and4 replacements). Every other object matches H2. The ephemeral test merge does not edit or deploy the website or main.

Root's actual Git ancestry checks also confirmed the original delivered Feedback `f195beb`, reviewed Feedback `969463d`, prior formal head `0e7ea8be` and prior unified head `c15fd4b` are all ancestors of H2. Their identities and histories remain preserved; this evidence is not a squash/cherry-pick reconstruction or a new admission gate.

Both formal source jobs passed the existing fixed-main-test-merge gate's **32 top-level checks**, including981 protected candidate-parent objects and992 protected merged-composition objects. Their parsed gate JSON hashes agree: `76398650973ebc2ef635a74c40f2f01cde03e5285d1ae84d865aa1f25ee72641`. These are the actual formal counts; H2/PR #18's25/981 history remains separate. The independent source/ref decision is SHA256 `7b5f3f45c8981d7110a11345ab05c08e9850d82c5988689d66da98296db08a74`. Stale PR API base-SHA fields are retained as raw observations, while actual Git refs and merge parents determine source identity. The decision and original fixed-overlay manifest are embedded in [results.json](results.json).

## Completed formal workflows and independent original-log review

| Workflow / job | Actual identity | Verified result |
|---|---|---|
| [Native foundation](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40912645579) | Run40912645579; head H2; attempt1; updated2026-10-29T16:49:58Z | Completed/success. Both architecture jobs completed the original full sequence with no formal rerun. |
| ARM native | Job123584425353 | Full Swift, all12 original round-three fixture groups,49 unique Feedback cases, unified App/bundle, strict ad-hoc codesign, original repository-aware package validation and required native visual gates PASS. |
| Intel native | Job123584425407 | The same original complete sequence PASS; its actual formal checkout is6537ab3, not the prior PR #18 checkout507259e. |
| Native source admission | Job123584424805 |32 checks PASS; parent981 and merged992 protected objects verified. |
| [Feedback v0.1](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40912645494) | Run40912645494; head H2; attempt1; Feedback job123584425203; source job123584425370; updated2026-10-29T16:40:05Z | Completed/success;49 unique Feedback cases and24 service cases, with the separate32-check source gate PASS. |

The49 Feedback cases are30 core and19 UI. In the dedicated workflow, two close cases repeated three times make55 executions, not55 unique tests; in each native architecture, two selected visual repeats make51 executions, not51 unique Feedback cases. All24 service cases passed with zero failure, cancellation or skip on actual Node22.23.2. Each native architecture's745 parallel entries are scheduling evidence, not a physical-Mac acceptance count. Original branch-specific inapplicable steps are explicitly listed in the reviews; required gates remain intact.

Both completed successful unfiltered Swift runs also retain source/log evidence for13 representative existing migration, recovery and isolation cases per architecture: SQLite v1/v2 migration and atomic rollback, future-version preservation, UNKNOWN restart locks, original-operation compensation/audit preservation, and screenshot/Feedback database isolation. The exact source hashes and scheduling lines are archived; individual detailed passed lines are claimed only where they were actually emitted. These13 samples are not added as a new test suite or relabeled as physical-Mac acceptance.

The actual full decoded logs are retained by their exact hashes: ARM `20d49ee0f5d4c39564167ef1b3360f4c2854eaf42ac74910484db983a12ce405`, Intel `203870b9a7d7d130c5aa72a402edd4bfbb7990b276acf2bb8227a096e7b3835d`, Feedback `40b984ab48272a251de0a7a339ff3f0c30dff16cec1bddec531c4b4a907e934b`. The complete independent runtime aggregate (SHA256 `3a36f3a0a29c93f7884c19e97e629104cab71876e800502be6761d33932e9a56`), original per-job reviews and exact provider run fields are embedded in `formalPR1Continuation`. This formal attempt1 success does not erase the earlier H2/PR #18 Intel failure, initial rejected403 request, or one unchanged successful rerun; those E records remain unchanged.

Root separately observed all four additional E workflows completed/success at attempt1: Native PR40912564543, Native push40912556511, Feedback PR40912564300 and Feedback push40912556577. The last Native push updated2026-10-29T16:53:25Z; existing jobs were allowed to finish before the evidence-only successor. This is a platform-status appendix, not another complete log review or an addition to the formal test counts.

## Original unified Beta packages remain the deliverables

The two delivery ZIPs retain Native run40907767281, source H2 and PR #18 checkout `507259e1c8d2ba7aace2994c1ca1956a14aa0205`. They are the previously independently downloaded and source-bound archives, not renamed artifacts from formal run40912645579. Formal CI's own package construction passed, but no new formal package bytes are claimed as independently downloaded or substituted.

| Architecture | Original verified artifact | Delivered ZIP | Bytes | SHA256 |
|---|---|---|---:|---|
| arm64 | [12912183820](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40907767281/artifacts/12912183820) | `Riftlet-Feedback-v0.1-98e66a9-arm64.zip` |1,970,151|`ed91633d35222ac97771403d73a1092aad666f8731969d9df755368c9e149d0c`|
| x86_64 | [12913941348](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40907767281/artifacts/12913941348) | `Riftlet-Feedback-v0.1-98e66a9-x86_64.zip` |2,072,285|`2b46a4bbf985d708be41ccbe0bd675289979b283a75c011499bf0d09c9296f29`|

These are two architecture-specific unified Apps with Feedback, existing screenshot functionality and permission resources. Their source, manifests and compiled binaries contain the exact HTTPS Receiver endpoint, and the original byte/source/resource/notices/signature reviews remain authoritative. The full-tree formal source review separately establishes that the15 fixed website objects do not change those H2 product inputs. Both packages use development ad-hoc signing; no Developer ID, notarization, Gatekeeper or physical installation claim is made.

## PR #7 closure, cloud evidence and acceptance boundary

Root's actual [PR #7](https://github.com/haohongfei2001-png/Riftlet/pull/7) readback at2026-10-29 16:39:12 UTC confirms Closed/Merged at `f195bebbc22ed1a162b5866ca1fe6c7ccb9835b9`, with8 of8 review threads resolved and0 unresolved. The older bot summary6462441687 still says Running and was last updated2026-10-28T09:30:56Z; it is not a fresh approval. The safe state/thread-ID summary is embedded without comment bodies. Engineering approval comes from the recorded independent reviewers; PR #7 was not reopened or merged again.

The [existing real cloud acceptance](../2026-10-29-feedback-cloud/README.md) remains54 HTTPS checks,3 unique private Issues and8 final deleted records, with the actual failures, diagnostic201 evidence limit and retention/backup limits preserved. No cloud test is repeated by this metadata successor. The configured source/package endpoint is `https://riftlet-feedback-receiver.haohongfei2001.workers.dev/v1/feedback`; static endpoint presence, CI and service-script acceptance do not prove an actual App-window submission.

**Real Mac and native-window-to-cloud E2E remain NOT_RUN.** The user left Mac connection to Codex; [the prepared handoff](../2026-10-29-feedback-cloud/CODEX_REAL_MAC_E2E.md) covers actual native diagnostics, IME/VoiceOver, close/quit/restart/network recovery, native SQLite/Keychain cleanup and screenshot isolation. No executor is scheduled. Native CI and owned synthetic WindowServer fixtures are not physical acceptance. The existing screenshot admission, Chrome target policy and all old UNKNOWN records are unchanged.

The top-level `currentRuntimeEvidenceField` now identifies **`formalPR1Continuation` as the authoritative current formal CI record**. The historically named `latestCompletedRuntime` is deliberately preserved unchanged as E's H2/PR #18 runtime and delivered-package provenance. Its `NOT_RUN_AT_THIS_EVIDENCE_CHECKPOINT` subfields and E's pre-promotion wording describe that earlier checkpoint only. All E content, H/8525 history and prior failures remain intact; no own successor SHA or later ref/result is predicted.

---

# Preserved E evidence checkpoint and all earlier history

The following E document is retained byte-for-byte. Its former formal-promotion/CI boundary has been superseded only by the actual new records above; its H2 package and execution identities are unchanged.

# H2 completed CI and enabled unified Beta evidence — 2026-10-29

**The admitted H2 source has completed the original Native ARM/Intel and Feedback workflows, and both unified App ZIPs have passed independent byte and source-binding review.** H2 is `98e66a956d55b5fac71718bc627dd89705b2a506` (tree `5ab168800db05f757f08c3eed9fe5cb97c23355d`), based on reviewed source C2 `4223a9dc80bd982e4b95305a1bd1e8f15ce7393c`. The actual PR #18 checkout `507259e1c8d2ba7aace2994c1ca1956a14aa0205` has parents c15 and H2 and exactly H2's tree. Complete C2 review, the narrow H2 admission successor and both actual source-admission jobs were independently reviewed. Runtime/package reviewer `/root/codex_handoff` completed the actual final aggregate at2026-10-29T16:28:02.956571Z (SHA256 `c846caa51241573328fefdf3209e917c243dac63bb83bee33b351e5ed96e6b1f`), embedded unchanged in `latestCompletedRuntime.originalVerificationRecord`. Only these two existing evidence files change in this successor; the source pin, composition policy, workflows and product bytes remain unchanged.

## Actual completed workflows

| Workflow / execution | Actual identity | Verified result |
|---|---|---|
| [Native foundation](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40907767281) | Run40907767281; actual attempt2; head H2; updated2026-10-29T16:23:39Z | Completed/success after the single unchanged full Intel rerun. Original failed attempt remains preserved. |
| ARM native | Original job123567118497; latest API representation123572107768 | Complete native job PASS, including the full Swift suite,49 unique dedicated Feedback cases, original synthetic native fixtures, unified App packaging and strict ad-hoc signature checks. The two job representations have byte-identical original logs and count as one ARM execution. |
| Intel native | Successful rerun job123572103993; original failed job123567118367 | Complete unchanged rerun PASS: all12 original round-three fixture groups, full Swift suite,49 unique dedicated Feedback cases, native fixtures, App/package build and strict ad-hoc signature checks. |
| Native source admission | Original independently reviewed job123567118411; latest API representation123572105676 | Original25 checks PASS with981 protected files; the current successful API representation is recorded without inferring an extra execution. |
| [Feedback v0.1](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40907767213) | Run40907767213; actual attempt1; Feedback job123567119165; source job123567119883; updated2026-10-29T16:07:51Z | Complete PASS:49 unique native Feedback cases,24 named service cases using actual Node22.23.2, and source admission. |

Each native architecture's745 parallel entries are test scheduling evidence, not a physical-Mac pass count. The Feedback workflow's two close cases repeated three times are additional executions of the same cases. The two visual cases repeated by another selected Native suite likewise do not increase the49 unique Feedback cases. Branch-specific steps that are intentionally inapplicable remain explicitly listed as skipped in the original records; no required gate was removed.

### Original Intel failure and bounded rerun

Intel attempt1 failed at the unchanged historical lab probe before native compilation: `bind()` observed `changeHashOK=false` after its fixed20ms timer. Native suites and package were not run in that attempt. The later always-run capture-output verifier correctly rejected the absent report; this was not an executed capture failure. The probe's asynchronous hashing finishing after the timer is consistent with the evidence, but the failed log does not uniquely establish its cause.

The first rerun request received actual403 because the workflow was still running; it executed no rerun. After independent review, one later request ran the entire failed Intel job unchanged. No delay, assertion, historical fixture, gate, workflow or environment policy was relaxed. That one full rerun passed; the original failure is retained. Its downloaded artifact12911139737 is10,195bytes, SHA256 `24e3e587fae789670a59042002ed6e8f703aca8fa86142c6b1c0d7a9ee2264d2`, and contains six diagnostic logs with no App or Beta. Exact failure analysis, original log hashes, both request responses and independent decisions are embedded under `h2RuntimeVerification` in [results.json](results.json).

## Two usable unified internal Beta packages

Both packages contain the same integrated Riftlet App, existing screenshot menus and permission/onboarding resources, and Feedback v0.1 with the real HTTPS endpoint. They are architecture-specific packages, not a universal binary or the separate offline Feedback Demo. Each linked GitHub artifact contains the original `build/Riftlet-Internal-Beta.zip`; the delivery filenames below are byte-identical copies of those inner archives.

| Architecture | Actual GitHub artifact | Delivered inner ZIP | Bytes | SHA256 |
|---|---|---|---:|---|
| Apple silicon arm64 | [12912183820](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40907767281/artifacts/12912183820) | `Riftlet-Feedback-v0.1-98e66a9-arm64.zip` |1,970,151|`ed91633d35222ac97771403d73a1092aad666f8731969d9df755368c9e149d0c`|
| Intel x86_64 | [12913941348](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40907767281/artifacts/12913941348) | `Riftlet-Feedback-v0.1-98e66a9-x86_64.zip` |2,072,285|`2b46a4bbf985d708be41ccbe0bd675289979b283a75c011499bf0d09c9296f29`|

The successful Intel artifact is the exact ID above; its same-named earlier failure artifact12911139737 is not a Beta. Independent review checked both outer/inner archive integrity, actual Mach-O architectures, bundle/resources/notices, the compiled full endpoint, all14 manifest input objects against H2 and the actual checkout, and the original repository-aware bundle/package validators. ARM's earlier missing-local-object limitation is resolved by its separately recorded successful source-bound follow-up. Common manifest fields and nonbinary file hashes agree between architectures. Actual macOS build/package steps performed strict codesign checks, and each binary's embedded ad-hoc flag was independently read. These are development ad-hoc packages; Developer ID, notarization, Gatekeeper and physical installation are not claimed.

## Cloud capability and remaining acceptance

The exact endpoint in committed source, build metadata and both compiled binaries is `https://riftlet-feedback-receiver.haohongfei2001.workers.dev/v1/feedback`. [Existing real cloud acceptance](../2026-10-29-feedback-cloud/README.md) records54 HTTPS checks,3 unique private Issues and8 final deleted rows, with all failures, retention limits and the diagnostic201 observation limit preserved. These existing records are reused without sending new cloud feedback for this metadata successor. Static endpoint presence and service-script acceptance do not prove an App-window submission.

**Physical Mac and native-window-to-cloud E2E remain NOT_RUN.** The user left Mac connection to Codex; [the prepared handoff](../2026-10-29-feedback-cloud/CODEX_REAL_MAC_E2E.md) still requires actual native business-event diagnostics, IME/VoiceOver, close/quit/restart/network recovery, native cancellation/SQLite/Keychain cleanup and screenshot isolation. No executor is scheduled. CI capture probes remain owned synthetic fixtures: region passed, window/fullScreen were not run under the foreign-overlap veto, and no real upload or pixel/color admission is granted. The original screenshot admission, Chrome target policy and every old UNKNOWN stay unchanged.

At this evidence checkpoint, root's fresh GitHub check still had PR #15 at c15 and PR #1 at0e7ea8be, both Open/Draft; main remainedeba1a4f. The formal promotion and subsequent PR #1 CI have not yet occurred. The H2 PR #18 runs above are not relabeled as that future work. A later evidence-only successor can record the actual new refs and CI after execution. This document predicts no self-SHA, future result, main merge or public release.

`latestCompletedRuntime` now identifies this actual H2 result. The exact earlier H object is retained as `historicalHRuntime`;8525 and all prior records are unchanged. The complete original admission-time README below is preserved as history, including its then-pending CI/package statements and its old meaning of `latestCompletedRuntime`.

---

# Preserved H2 admission-time checkpoint and older history

The following original text is historical. Its original `latestCompletedRuntime` H record is now preserved exactly under `historicalHRuntime`; its incomplete statuses are not current blockers and are superseded only by the actual observations above.

# Feedback cloud closeout and enabled-source checkpoint — 2026-10-29

Frozen source C2 is `4223a9dc80bd982e4b95305a1bd1e8f15ce7393c` (tree `a8eebcbfe47b4b3ad6f97412b4760def444910e3`), a direct child of previously admitted H `2f30885644c9dc597e47d8f1dc89b9e16828092a`. **Complete C2 non-author review passed with no blocking findings.** Reviewer `/root/deployment_review` matched all984 GitHub/local file objects and the complete89-file delta; a separate reviewer checked84 documentation/evidence files,182 links and12 anchors. The three new redirect tests were authored by deployment_review and reviewed by root as non-author. The exact decision (SHA256 `123d623b584685e032ac5274cafc23fda7c0f731233af5d2cac0f8d10626f780`) and89-file manifest are embedded in `results.json`. This is engineering review, not a claim of GitHub human approval.

C2 configures the single fixed public HTTPS Receiver endpoint in `FeedbackHost` and contains the reviewed two-site Cloudflare Workers `redirect: "error"` to `"manual"` repair. Three new service cases each cover HTTP301/302/307/308: the old source actually failed all three; the repaired source passed all24 named local cases. The endpoint change is one line; screenshot Main/Core/Capture, admission, old UNKNOWN and the independent source gates are preserved. These local results do not replace the new complete macOS workflows.

## Actual cloud service acceptance

[The cloud evidence entry](../2026-10-29-feedback-cloud/README.md) and [final archive manifest](../2026-10-29-feedback-cloud/final-acceptance/manifest.json) record54/54 real HTTPS contract checks, direct D1 identity/hash persistence, same-ID lost-client-receipt recovery, real503 and429/rollback, and exactly3 unique private GitHub Issues. Six exact-body checks are two complete observations of those same3 Issues. The64 unique primary events retain four response-discard attempts, including the original pre-write DNS failure; snapshots are not double-counted.

Owner permanent deletion of Issues1/2/3 was independently verified in the same authorized private repository by successful repository reads, a successful empty all-state Issue list and each exact Issue's explicit **410 Gone/deleted** response. The prepared404 expectation is retained as corrected history. Guarded D1 closure and direct final observation at15:39:00.373Z show8rows/8deleted/0active payload/0pending deletion/0temporary probe, with original Issue identities retained and limits100/20. The final three original-capability GETs returned their exact IDs, `deleted` and Boolean `durable=true`. Task-specific private temporary files were then removed under the recorded review:7 exact directories/18 files, all absent. No physical-media, native SQLite/Keychain or immediate provider-backup erasure is claimed; actual D1 Time Travel shows a past7days restore window.

Ordinary Receiver version `39f6277e-11f2-455b-be27-8f0b6a795685` and Delivery version `3c749b91-ace3-45d9-86e5-62e2dab06c35` are restored. Production bundle/readback and removal of the temporary fault variable are recorded. The diagnostic scenario directly establishes actual Issue creation → D1 uncertain/null identity → delete intent/body scrub → normal cron recognition of the original Issue. Its HTTP201 response bytes and conditional discard-branch execution were not directly captured. No native-window or native-business-event diagnostic acceptance is inferred.

## Current source, new CI and unified Beta

Committed C2 has `sourceEndpointConfigured=true` for `https://riftlet-feedback-receiver.haohongfei2001.workers.dev/v1/feedback`. Configuration is not a per-feedback receipt or Issue-delivery claim. **The C2 admission successor's complete Native ARM/Intel CI, Feedback CI and enabled unified Beta build/independent ZIP verification are NOT_RUN at this metadata checkpoint.** No successor SHA, CI run/job, artifact identity or outcome is predicted.

After that approval, this admission successor changes only the existing source-pin literal plus this README and `results.json`. The original gate first rejected only C2's74 new paths and15 changed objects while all four historical audits passed; that unmodified rejection is recorded in `results.json`. All audit policy, historical pins, workflows, metadata exceptions and screenshot admission remain unchanged. Completed new execution must identify the actual source/admission SHA, PR checkout, runs/jobs and downloaded ARM/Intel unified ZIP hashes in the formal PR handoff. An earlier nil-endpoint package cannot stand in for that result.

## Preserved completed H verification

Historical H `2f30885644c9dc597e47d8f1dc89b9e16828092a` used reviewed C `4d1fd5f1b6c7f75305d70ab5f1c04da2cdddb6bb` and actual PR checkout `1f145f08da6cec1043789dfe34d4d5144e7c3e25` (tree `c9c874bd35878e6784ef96a29e01b00c36c90a8c`, equal to H's tree). Non-author `/root/deployment_review` verified the complete successful runs and logs:

| Historical workflow | Run | Completed successful jobs |
|---|---|---|
| [Native foundation](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40891805452) |40891805452|ARM123510319038; Intel123510319389; source admission123510319390|
| [Feedback v0.1](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40891805617) |40891805617|Feedback123510319310; source admission123510318287|

Each historical Native architecture's detailed Feedback suite passed49 unique cases. The historical Feedback job passed49 unique cases plus two close cases repeated three times; its55 passed executions are not55 unique tests. The historical service result is21/21 with actual Node22.23.2. Native745 refers to parallel test scheduling entries, not physical-Mac acceptance. The exact original verification record, log hashes, job IDs and artifact metadata are embedded under `latestCompletedRuntime` in `results.json`; the older8525 record and all earlier history remain preserved. H packages were built and checked in CI as **local-outbox-only**, and their ZIP bytes were intentionally not independently downloaded. Those results apply to H only.

## Remaining real Mac acceptance and formal boundaries

The user explicitly leaves Mac connection to Codex. [The prepared real Mac handoff](../2026-10-29-feedback-cloud/CODEX_REAL_MAC_E2E.md) covers the actual unified native window → cloud chain, opt-in diagnostics from native business events, IME/VoiceOver, close/quit/restart and network recovery, local/remote deletion and screenshot isolation. Every such real Mac item remains **NOT_RUN**; no executor has been scheduled or promised. Service scripts, software AppKit tests and CI WindowServer fixtures do not replace that acceptance, so **true native-to-cloud end-to-end delivery is not declared complete**.

At this checkpoint the C2 continuation has not updated PR#1; it remains Draft. Main, screenshot admission and old UNKNOWN data are unchanged. No main merge, public release, paid upgrade, website/DNS change, Developer ID signing or notarization is claimed. The token expires2026-11-28 and requires maintainer rotation; no future automated operator is implied.

---

# Historical checkpoint records

The original sections below preserve the facts, review outcomes and incomplete work at their original checkpoints. Their statements about an uncreated Delivery, a disconnected browser, nil endpoint or pending cleanup are historical and are superseded by the current cloud entry above. They are not current blockers or new C2/H2 execution results.

# Feedback receiver continuation — 2026-10-29

The new independently reviewed source is `4d1fd5f1b6c7f75305d70ab5f1c04da2cdddb6bb` (tree `ffda55a2af47c17eb130d21700a210c698ac73e3`), a direct child of current unified PR #15 head `c15fd4b4a27659946ef49280131e875f4d5ab9d1`. Non-author reviewer `/root/deployment_review` compared the complete remote/local trees and all 46 changed files. There are no unresolved source blockers. The source pin successor changes only the existing reviewed-source literal and these two existing metadata files; no policy, workflow, metadata exception, screenshot admission or historical evidence is changed.

The increment fixes actual five-minute delivery starvation, adds three D1 maintenance indexes, binds Beta service capability metadata to committed Host source, and records real Receiver deployment/testing with all failures and cleanup limits. Independent local checks passed 21 service subtests, 13 packaging cases and four offline transport-boundary cases. The original source gate actually rejected C's 31 new paths and 15 changed prior objects before the new review pin; all four historical audits passed.

[Exact cloud checkpoint](../2026-10-29-feedback-cloud/README.md): the dedicated Receiver/D1 are deployed, 36 actual HTTP checks passed, two original D1 IDs/hashes were read directly, and the five synthetic IDs finally report deleted through authenticated HTTP. Final direct D1 cleanup proof, final active version, separate Delivery/cron/private Issue creation and permanent deletion remain incomplete after the authorized browser disconnected. The native Host remains nil. Real native-window acceptance is prepared for Codex as the user requested; no executor is scheduled. This is not a cloud-pipeline or native E2E completion claim.

The full independent decision and exact 46-file manifest are embedded in `results.json`. New full Native ARM/Intel and Feedback CI are pending at this metadata checkpoint; their completed exact head/checkout, run/job, archive/hash and independent verification results will be recorded in the associated Draft PR. Prior c15 successes remain prior-source evidence. No main merge, public release or Developer ID/notarization is performed.

---

# Unified product integration — 2026-10-29

## Status

Engineering continuation on the existing Draft PR #15 only. **Not a release or fully accepted product.**
The current reviewed source is product commit `683aefb46b7ed774674a3dd2e6199868952b7b46` (tree `2188e6839aadeaa052f81800f640edb077269148`), the direct child of formal `73251d034c8da8f486d09083b048a35cdee39bc0`. It integrates only PR #17's seven product/test files. The formal gate changes only its reviewed-source literal; both original workflows, every historical audit and all runtime requirements remain unchanged. New formal-head and actual PR-merge CI are pending at this source-review checkpoint; their completed results will be recorded in PR #15 with exact run, job, source and checkout identities. Earlier sections below retain the facts and limitations of their original checkpoints.

## PR #17 product integration and non-author source review

This continuation fast-forwards the existing formal line through the original product commit; it does not copy the technical branch's later CI/scope commits `6d9649c46a2f6655fd5b91afe6c306a075a2f5b2` and `fea4145cdc7eec91c36db34bec23a75a2e403a9a`. The product delta is exactly three production files and four test files, 562 additions and 28 deletions. All other 872 baseline file objects retain their original mode, type and OID. No new candidate branch, product design, screenshot integration or Feedback implementation is introduced.

Independent execution roles `/root/receipt_integration_review` and `/root/queue_integration_review` reviewed the complete changed implementations and their existing native/adapter/App/Core call sites. `/root/formal_source_review` independently compared the full Git trees, original workflow objects and audit policy. All three report PASS with no unresolved blocker. This is non-author engineering review, not a claim of a GitHub human approval. The exact seven reviewed blobs are recorded in results.json.

- MAIN submission remains single-shot. Recovery only rereads the same captured PID/window/tab/nonce after an empty receipt or exact `errAETimeout (-1712)`. Invalid identity/schema, page rejection and every other error fail immediately. The original one-second absolute receipt budget is not renewed; actual send, receipt and decode enforce it. Receipt-only event timeout is at most 250ms and no send occurs with less than 50ms left. Submission/identity events retain five seconds, and the original ten-second nonce cleanup remains. Independent execution of the actual JS templates reproduced the old lost-return failure and verified one MAIN execution with recoverable identical reads. OS scheduling is not claimed hard real-time.
- App queue entries retain the original absolute deadline. Timer startup recomputes the remaining interval; drain checks expiry before executing an entry. The original selected token, FIFO, capacity, maximum wait and cancel-once lifecycle remain. Core already rejects expired authority, so this fixes App queue lifecycle rather than claiming the old version could upload an expired selection.
- Four added home/thread and body/sidebar fixtures preserve body, noncollapsed selection, focus and existing attachments, assert one input and no Send. The original 86 cases remain; independent local execution passed 90/90 with zero skips. These fixtures do not execute real ChatGPT React handlers.

The original final isolation suite passed 24/24 locally. Before the source literal changed, the original gate rejected P's new path and six changed objects while all four inherited audits passed. After independent source review, the updated gate must still verify 25 checks and all 876 protected objects. No directory exception, test skip or workflow change is added.

### Preserved completed baselines and failure

Formal `73251d0` completed Native [push 40852759638](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40852759638) / [PR 40852766774](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40852766774) and Feedback [push 40852759654](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40852759654) / [PR 40852766770](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40852766770), all SUCCESS with no rerun. Its prior full visual acceptance remains scoped to that source and its actual recordings.

PR #17's four workflows also completed successfully at its technical HEAD; they are source evidence, not substitutes for this formal combination. In its Native push [40861759911](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40861759911), original Intel job `123406495677` failed at unchanged `network-fault.test.cjs:23:484` (`undefined !== 1`) before Swift. The unchanged test checks `x.sent` after its original 15ms wait while the template awaits Blob/WebCrypto work. The original log lacks that asynchronous event trace, so a sole scheduling cause remains unproven. One unchanged full Intel job rerun, `123409797586`, passed; both outcomes and artifacts `12891138473` / `12891849858` are retained. Failed log SHA256: `6d7a29b63209dfeec364592e8c69f2ffa2ce8638a2b2c9621a6f595b91c21411`; rerun log SHA256: `b51f839f0c4a2bfb02716fd32b66dbd8f3efea633231206f509e78250c1289ba`. A recurrence in the new formal CI requires original-log diagnosis, not unbounded reruns or removed assertions.

### Unchanged real-world boundaries

The authorized Mac is still Offline in this continuation's read-only device check. New physical input, actual system screenshot-to-ChatGPT input/start/completion/recovery, real Chrome AE fault recovery, cold first-click without a pre-event ACK and cloud Feedback are NOT_RUN. Historical cold rejection remains product FAIL / safe refusal PASS; this receipt fix does not authorize that refused click. Old H/F uploads and UNKNOWN records are not repeated or modified.

Ordinary upload, applicationScreenshot upload and safe-failure/retry remain closed. Core/SQLite v3, v13 page code, original target freezing and ACK publication, uploadStarted/completion/UNKNOWN rules, all source permissions, thin-edge/magnet UI, screenshot implementation and Feedback retain the formal baseline objects. New macOS CI will separately report the owned Apple-engine capture component; it cannot replace true system-screenshot or ChatGPT acceptance. PR #15 stays Draft; main, PR #1, release state and founder Beta participation remain unchanged. After this integration passes, the next product objective is the real cold-first-click and screenshot attachment loop, not more routine visual polishing.

## Exact inputs

- Thin-edge source: `2c8cd0371de5e07fd7794f76335381a40403030d` (descends from formal `0e7ea8be148e1124b387e799fd886a7830e96559`).
- Complete built-in screenshot handoff: `6b60f67f6d35272eecff901c507bd75a77874ed6`.
- Common ancestor: `443d21da1a55c0061eafced823b5406879b96024`.
- Experience supplement: `69600ab3c7fa9e373582613bd55d22075234b65a`, read as specification, not merged as a product tree.

The integration uses both real parents; no repeated arrival/entry cherry-picks. The disposable source-object/diagnostic workflow is removed in the product tree. User worktrees, databases, media, main and PR #1 are untouched.

## Magnet failure, evidence and bounded fix

Original run `40770139026`, artifact `12852063171`, source `2c8cd037`, checkout `fb5f18ef`: the delegate starts, the 100 ms-grace cleanup fires first, and removal then produces `finished=false`. Failure remains recorded. No missing image is relabeled a success.

Isolated run `40819965387` tests two independently pinned local diagnostic commits. Direct-main-delegate `1b54745ca7a7cef9275b8736de5c154cc124ff5e` and cleanup-grace `3944b6aa20d9ea3024b966ce3b0803b08d81dec2` each passed unchanged magnet+interrupt evidence checks. These are diagnostic variants, not this combined product.

Repeat run `40820327845`: unchanged original and direct-main variant each passed 5/5 native magnet observations. Original readiness-to-completion observations: 656.047, 636.012, 628.309, 638.978, 655.991 ms. Direct-main: 645.989, 636.001, 642.605, 636.011, 640.110 ms. These are small, capture-loaded samples, not latency p50/p95. The original is timing-sensitive rather than deterministically broken; these results do not isolate the extra dispatch as its sole cause.

The product delta avoids an extra queue turn when `animationDidStop` already arrives on the main thread and allows 500 ms of bounded completion-delivery grace. **The 560 ms trajectory, asset-ready origin, one-sprite limit and immediately live input islands do not change.** Watchdog termination remains `timedOut`, never `finished`. The previous software test accepting either result is replaced by a strict natural-finish assertion, with a separate stopped-render-clock timeout test. The actual pixel/MOV driver still requires a genuine `finished=true` delegate. Exact combined-tree verification is recorded only after it runs.

## Semantic conflict decisions

Preserve PR #15 integrated RiftSettingsForm, five sections, Return/save behavior, source preference observation and latest Feedback backend. Preserve PR #14 strict canonical/legacy preference migration, complete disable lifecycle, safe hidden-directory/ordinary-leaf capture, fd/identity checks, exclusive publication and explicit built-in application import.

Disabling remains effective in the running session even when persistence fails. The integrated settings snapshot therefore carries actual effective state plus a save-failure fact; it cannot roll the switch back on or display “saved”. Enabling still requires a successful durable save. Collection rechecks do not disable this independent local stop control. Default-mode changes preserve fixed slots until the next session.

Both original unit-test bodies are retained apart from explicit API adaptation to the unified settings form. Additional regression coverage checks failed-save disable/enable presentation. No import origin is inferred from system xattrs. Built-in originals and edited derivatives remain `applicationScreenshot`; current upload admission remains closed for that origin.

## Experience disposition at this checkpoint

Q01: capability-specific first-use titles and explanations are consistent. Q02: optional one-page redesign is not adopted; the existing three-page flow remains. Q03: confirmed request and next mode are independently presented, with the original countdown, fixed slots, moving X, exposure exclusion and session cancellation. Q04: the same pointer-free peek panel presents owner/revision-bound reasons; repeated projections do not renew timers, and settlement refreshes an initially deferred prepared state without replaying input. Q05: already-readable source access no longer prompts redundant authorization; existing separate capture/Automation guards remain. Q06: complete history previews use a separate single-flight bounded decoder, checked file identity and SHA256, stale-result rejection and correct Retina small-image sizing. Q07/Q08: persistent service capability, safe destructive defaults, guarded save-close, explicit retry and body-only copy are implemented. Q09: existing five-section settings/window behavior is retained with app-scoped Cmd-, and standard editing actions. Q10: actual CI accessibility variants remain required; physical environment coverage is separately blocked by the offline authorized Mac. All new native behavior remains runtime-pending until the exact combined CI executes.

## Verification and boundaries

The final-source gate pins the non-author-reviewed source above. A software build/test result never substitutes for that review. Native/Feedback workflows run exact combined objects on their normal checks; inherited acceptance scripts are not rewritten to accept this delta. Two architectures, production capture component probes, original-pixel visual/MOV checks and actual runner accessibility variants are retained.

Physical mouse, real Mac permissions, Retina/mixed screens/Spaces, new built-in ChatGPT attachment, Gatekeeper/notarization, and Feedback HTTPS-to-private-Issue acceptance remain NOT_RUN/BLOCKED. Feedback endpoint stays nil. No old H upload is repeated, no UNKNOWN or original media is cleared, and no cloud/private data is collected by this integration.

## Continuation: actual blockers and bounded repairs

The latest branch was refreshed rather than assuming the prior diagnostic-workflow failure persisted. `b3cec64f0ecbf869aff3b17b88d55323d1765393` already includes PR #14 with both parents and removes the disposable workflow. Native [40821969722](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40821969722) failed because three retained integration-test references used the old `isEnabled` property. Commit `d7080499ef4d50ab612c456246da4e1b7688a095` adapts those names to `builtInScreenshotEnabled`, retaining every assertion and expected value. Its non-author review passed.

Native [40830335742](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40830335742), ARM job `123302828056`, compiled and exposed the next genuine failure: AppKit changed the settings scroll style from overlay to legacy during replay; clip width changed 476→461pt and preview width 444→429pt. The genuine size change correctly cancelled the preview. `autohidesScrollers=false` alone did not prevent this style change. The settings document now reserves the public native legacy-scroller width in both styles, without forcing the user's style. The original width/animation assertions are unchanged. Apple API basis: [preferredScrollerStyle](https://developer.apple.com/documentation/appkit/nsscroller/preferredscrollerstyle), [scrollerWidth(for:scrollerStyle:)](https://developer.apple.com/documentation/appkit/nsscroller/scrollerwidth(for:scrollerstyle:)). This remains a proposed runtime fix until the exact combined tests pass.

The same reviewed source finishes the remaining Q01 title/capability projection; hides already-satisfied folder authorization; wires app-scoped Cmd-, and standard nil-target editing actions; keeps Feedback service capability visible across edits; binds destructive sheet defaults to Keep; and adds explicit safe-close reasons, retry-save and body-only copy. Screenshot admission, Core/Adapters, capture/import, Feedback engine/service and all historical evidence are unchanged from `d708049`.

Non-author review was split by authorship: the Feedback author reviewed Setup/Main and the unchanged protected composition; a different reviewer examined all Feedback UI/tests and the scroller fix. Both reviewed exact `a3d18b5`, with no unresolved findings. Prior `b3cec64` full-composition review also found no new integration safety defect and ran all 24 final-isolation regressions. These are source reviews, not GUI or cloud acceptance. Q06 preview work is still separate uncommitted work at this checkpoint; Q03/Q04 and remaining Q05 are not claimed implemented.

## Reviewed combined experience source

The next source checkpoint is `c81f24b388c0a4d54c3c470a23df60f0cc31b6a3` (tree `2f21eea44cebde6de3111607ccc2dcc2eb88d474`), a descendant of the same Draft PR #15 and both original integration inputs. No independent product branch is introduced. Native run [40831099906](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40831099906) passed source admission but stopped at the new sheet test's missing Swift argument label; this checkpoint changes only that call to `performKeyEquivalent(with:)`, preserving the original Return/Escape, queue-state and send-count assertions. No runtime pass is inferred from the compiler repair.

Non-author review is bound to exact Git blobs: the integration reviewer checks the unchanged security composition, helper, workflow and Main wiring; the experience reviewer checks Q04 and the independently authored Q06; the lead checks the independently authored Q03; the magnetic reviewer checks the Feedback test API correction. The Q04 review found a deferred prepared-state projection and required a read-only refresh after the exact selection is released. The Q06 review found an unverified thumbnail fallback and required an initially empty full-preview shell plus a valid-PNG replacement regression. Both findings are repaired; no self-review substitutes for these independent module reviews.

The original native driver is byte-for-byte unchanged: all 46 scenes and five real WindowServer MOVs remain required. Six additional static captures follow that full suite: history portrait/light, wide/dark, missing file at 360×280, Feedback actual fixture SQLite save failure at 560×500, queue explanation and confirmed-countdown/next-mode presentation. The supplemental verifier reuses the original source/hash/pixel/owned-window checks and keeps the one-titled-window requirement. Its local self-check rejects 34 unsafe observations; original 18 visual-manifest and 24 final-isolation regressions pass. These are Linux checks of scripts, not Swift/macOS execution.

Supplemental files are synthetic and helper-owned. The SQLite fault is a fresh private journal-path collision using the real save path and DisabledFeedbackTransport; it neither injects a production bypass nor accesses user data. Capture state and queue explanations are explicitly synthetic presentation fixtures, not real capture, rejection or upload evidence. Endpoint configuration, cloud deployment, private-Issue delivery and real ChatGPT acceptance remain unchanged and unverified.

## Native runtime findings and next reviewed repair

Exact HEAD `f744aa703bf4421efd929463b0005930fba267e2` passed all four source-admission jobs. Native [40833279966](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40833279966) compiled on ARM and Intel, then the full 723-case test invocation stopped on three failure groups: the Feedback sheet lost its Keep default and Return did not dismiss; AppKit advertised the expected plain-text compatibility type in addition to `.string`; and the history replacement regression remained in loading state. No original 46-case/5-MOV or supplemental visual result exists for this failed run. The two prior settings-width assertions did not recur, but no successful detailed suite was inferred from a failed full invocation.

Feedback [40833286409](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40833286409) compiled and ran 49 native cases; five assertion failures belonged to three cases. Its 117 isolation and 20 Node service tests passed. Repeated-close tests and demo packaging did not run after failure. Native PR ARM job `123312149222` additionally observed the unchanged deadline regression still prepared after its fixed 150ms wait; both push architectures executed it without failure. Core and that original test are unchanged, and the next complete run must still pass it.

The reviewed repair `ee538eb7e3aedc459cbccffbeb0337918fa13b6b` (tree `dcfeb2d5cfc1148a3910c4e177ae7255c77c2c89`) changes only five files. Sheet key equivalents are configured before presentation, then Keep receives defaultButtonCell and first responder synchronously after beginSheetModal. All original Return/Escape/default/queued/zero-attempt assertions remain, with a further post-layout stability assertion. Clipboard checks allow only the two observed plain-text representations and require each to equal the original body.

History uses a bitmap-independent image-view intrinsic size and a bounded footer, ensuring an empty preview has a positive viewport before decode. This removes the source path where a zero viewport returned silently without starting verification. A new actual AppKit empty-shell→verified-image→minimum-window regression checks usable dimensions and original-byte preservation. The rejected valid-PNG replacement still has its original two-second failure requirement; no decoder, hash, file identity, ownership or display budget guard changes. The historical logs did not report viewport dimensions, so final confirmation belongs to the new native execution. Non-author review is bound to exact source objects: magnetic reviewer for Feedback, experience reviewer for history.

## Native interaction and absolute-deadline correction

HEAD `a4e811a285e108c2c0752ef054560bcbabd24263` again passed source admission and compiled on both architectures. Its full runs [40834319136](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40834319136) and [40834326516](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40834326516) exposed the remaining exact interaction: assigning defaultButtonCell changes Keep's key equivalent to Return. Return/default stability passed, while the independent Escape behavior still failed. The source `034913a446ff932966d1c364b10a9e408b54a74d` (tree `798209b5225aa4c3e6fdfbc7e4759b6a0748fa73`) now leaves Keep as the actual Return default and inserts a private cancelOperation responder into only that attached sheet's chain. Escape can only end that same sheet with the non-destructive second response. Completion keeps the unowned chain member alive, restores the original chain by identity, and releases it. No event monitor or upload authority is added. Real Return/Escape dispatch, dismissal, queued/zero-attempt checks remain, with chain stability/restoration assertions.

The unchanged deadline regression recurred on loaded runners. Inspection found that the expiry Task captured a relative sleep before it was scheduled; delayed task start could add that delay again beyond the original absolute deadline. The four-file repair computes remaining time only when that Task starts and immediately uses the original token-cancellation path if already expired. The original 50ms selection/150ms observation test is untouched. This is the only Core implementation change in this increment: target/origin/UNKNOWN, the absolute deadline, pre-dispatch validation and transactional input guards are unchanged. The integration reviewer independently approved its exact blob; actual runtime effectiveness is still pending.

Intel also reported the natural-finish unit test's start() returning false and zero completion. Its test-only trajectory was 50ms; native panel/layer preparation consuming that interval can correctly produce static fallback before an animation exists. This is the best source-consistent explanation, not a measured rejection reason. The test now uses the real 560ms plan while preserving successful-start, existing 1.2s wait, exactly-once genuine .finished, cleanup and closed-presenter assertions. Production magnet code, asset-ready timing and 500ms bounded cleanup are unchanged. The magnetic reviewer independently approved this test adaptation and the sheet repair. The original 46-case/5-MOV and reduced-system visual checks remain required, unchanged and not yet reached.

The a4 native executions did not repeat the history success/minimum-window or replacement errors, the clipboard alias failure or the settings column-width failure; their full workflows still failed, so no complete native or visual PASS is claimed. Both Feedback runs compiled and ran 49 cases with four assertions failing in two Escape-related cases; the following repeated-close/demo stages again did not run.

## 52cd8944 complete execution and independent pixel findings

The source `034913a446ff932966d1c364b10a9e408b54a74d` was tested through exact pin HEAD `52cd894417eafda9ea38c4f26f1f5304b83e8b5a`; PR checkout was `f8f88f3a79340b2e527d477151d246f929e9e3f3`. All source-admission jobs passed. Both Feedback runs (40835658075 / 40835663780) passed 49 unique Swift cases, 117 Python isolation cases and 20 Node service cases. Actual software AppKit Return/Escape dismissal, the 150ms default-button stability check and responder-chain restoration passed. Cloud/native HTTPS delivery remains NOT_RUN.

Native push 40835658068: ARM job123319712741 passed the original full suite, detailed regressions, combined App packaging, original 46 cases / 116 original PNGs / 5 MOVs, six supplemental scenes and actual accessibility variants. Intel job123319712793 passed the original full suite and strict magnet regressions but failed before asset-ready in the original motion-magnet export (`frames=[]`, zero-byte MOV). Its generic catch did not identify which export stage failed; no timedOut or magnetic start was observed in that scene.

Native PR 40835663771: Intel job123319731475 passed the complete invocation, 46 original cases / 90 PNGs / 5 MOVs, six supplemental scenes and actual reduced variants. ARM job123319731531 failed the unchanged deadline assertion: prepared remained instead of failed after the original 150ms wait for a 50ms token. The recent remaining-time correction is therefore insufficient; the total case duration is not a measurement of timer lateness. The original input-authority checks still prevent dispatch after expiry, but the state-cleanup gate remains failed.

Independent review of original ARM PNGs and decoded MOV frames proves a visual defect: the new image is already shown at the target in frame-02 / MOV frame33 (PTS2.110s), then disappears from the target as flight begins in frame-03 / MOV frame34 (PTS2.208s). Natural finished=true was separately observed at ready+663.668ms and ended.finished at +667.852ms. Successful completion does not excuse this flash. The row and flight first-commit ordering require repair and complete revalidation.

The Q03 supplemental PNG lacks the countdown and next-mode text even though metadata strings reported true; its first readiness predicate did not await the actual presentation commit or existing cancel-slot transition. This scene is visually FAIL. The other five supplemental original images were independently inspected as readable and within their intended window bounds. No boolean metadata is used to overrule the pixels.

The owned production-capture probe is PARTIAL: region import passed with exact original PNG/private-copy identity and applicationScreenshot isolation; window and fullScreen were NOT_RUN under FOREIGN_OVERLAP_VETO. Physical input, actual system-screenshot user workflow, real ChatGPT attachment and cloud Feedback remain separately unverified.

Next repair is confined to production first-presentation ordering, supplemental native readiness, safe white-listed export diagnostics, and opt-in DEBUG deadline timing. No original scene, threshold, assertion, 560ms trajectory or upload/origin authority is relaxed; temporary timing trace must be removed after diagnosis.

Further independent PR Intel pixel review: portrait history preview is blank and still says loading despite imageLoaded metadata; that run has 4/6 acceptable supplemental images, whereas ARM has 5/6. Await the real existing display update for this helper scene as well, then review the new original pixels. No decoder or product behavior is changed to manufacture evidence.

## Reviewed first-presentation repair and bounded diagnostics

Source `79480baff484d0d7abcc911afff68faf8076b5b0` / tree `567a59e756a6cc7547821b90e50d1869ab502d48` contains the ten exactly reviewed source files. Non-author integration review covers the production magnetic first-commit and owner restoration changes, the native helper readiness/white-listed export diagnostics, and the temporary deadline timing; root independently reviewed magnetic and helper diffs. The actual sources and original 560ms trajectory, 1.2s natural-finish assertion, 50ms token / 150ms deadline observation, original 46-case / 5-MOV driver and historical audit policy remain intact.

New regression observes decoded contents only after target hiding, verifies cache refresh cannot reveal the active owner, and verifies cancellation/Reduce Motion restores static content without blocking original input. The helper now waits for actual existing slot motion, valid visible label geometry, and native history/status display commits; the six-scene verifier rejects 68 unsafe or premature observations. Original 18 visual-manifest tests pass locally. These checks are not macOS compilation or new pixel acceptance.

The original full native test step alone enables DEBUG deadline timestamps. It records only runtime token identity, monotonic clock values, phase, count and error type, with no arbitrary reason/error payload. The trace can perturb timing and is diagnostic only; remove it after resolving the failed original gate. No extra diagnostic workflow or candidate branch was created.

## a8c9 complete execution and independent review

Exact HEAD `a8c9ca9a13e72944b511a073ca1441f6e836377e`, reviewed source `79480baff484d0d7abcc911afff68faf8076b5b0`, and PR checkout `feab43de8fa980e94e85a3bdb93ea18c76a6ce0e` completed Native push [40842900740](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40842900740) and PR [40842908347](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40842908347) successfully. Every ARM/Intel job executed 725 unique native cases, the original detailed regressions, strict natural magnet completion, unified App packaging, all 46 original scenes and five MOVs. Actual reduced system variants completed separately. The four jobs do not multiply the unique case count.

Feedback push [40842900775](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40842900775) and PR [40842908348](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40842908348) passed 49 unique Swift cases, 117 Python cases, 20 Node service cases and three repeated close-regression rounds. These results cover software AppKit and offline service fixtures, not cloud delivery.

| Native artifact | Original cases / PNG / MOV | Reduced cases / PNG / MOV | Independent supplemental pixels |
| --- | --- | --- | --- |
| Push ARM `12884330772` | 46 / 121 / 5 | 3 / 17 / 1 | 6/6 PASS |
| Push Intel `12883559634` | 46 / 103 / 5 | 3 / 15 / 1 | 6/6 PASS |
| PR ARM `12884017726` | 46 / 120 / 5 | 3 / 18 / 1 | 6/6 PASS |
| PR Intel `12884147774` | 46 / 90 / 5 | 3 / 13 / 1 | 5/6 PASS; Feedback stale saving frame FAIL |

Non-author reviewers decoded and examined the actual magnetic MOV frames on all four runners. The recorded sequence no longer shows the old target image appearing and disappearing before flight; genuine `animationDidStop finished=true` and `decorationEnded finished` were also observed. Normal settling may show the flight image at the destination before the delayed delegate callback; that is not the former first-frame flash. Sparse Intel recordings do not establish behavior between captured frames or latency percentiles. Countdown/next-mode and portrait history content are now present in all four sets of original pixels.

Independent inspection still rejected the PR Intel Feedback supplemental PNG: it shows the previous saving state without visible retry/copy controls although metadata reported enabled controls. Automated CI success does not override this pixel failure. Its exact repair is below; all historical failed evidence remains preserved.

All four original deadline cases passed in the trace-enabled full suite, but successful XCTest output did not preserve any timing events. The concrete cancellation timestamps therefore remain NOT_OBSERVED; the passing runs do not prove a scheduling root cause. The temporary instrumentation is removed in the next reviewed source.

## Reviewed final cancellation and Feedback display cleanup

Source `901a22a5d69d9c1c50c268557fa73f0d52c2dca4` (tree `1aeab64d78eb80a97c2657dde35f79ded0fbd405`) removes every temporary deadline trace and restores the original workflow/test files byte-for-byte to their pre-trace bodies. The original 50ms token, 150ms observation, awaits and assertions are unchanged. The conditional cancellation read and existing strict transaction now execute synchronously in one QueueStore actor turn. Missing, UNKNOWN and terminal operations remain read-only no-ops; prepared work retains the transaction's phase recheck, and only the original invalidTransition is caught. Other database errors still propagate. A regression holds a real independent SQLite write transaction while checking that these no-ops do not attempt a write or alter original operation/asset/reason identity. This closes an avoidable actor scheduling gap without claiming it was the sole historical failure cause.

Final source `beecd723bf5c72546af2c32d3bf7277f030fd72a` (tree `dda32f36ca7eba086d16ec7674ab09a61ad62d83`) adds only the two Feedback helper/verifier changes after that cleanup. It waits for the actual failure text and recovery controls, completes the existing engine stop, performs normal native layout/display, yields 50ms, and rereads same-window identity, alpha, complete visible bounds, editable preserved text and clean display/layout state. It neither retries nor copies the draft and does not modify production Feedback. The verifier checks these actual geometry/window observations; the old incorrect PR Intel manifest is rejected. The local supplemental self-check now rejects 78 unsafe observations, and all 18 original manifest regressions still pass.

Both exact source commits have independent integration and magnetic code reviews; root also reviewed the Feedback helper. The source gate changes only its reviewed-source literal; historical pins, metadata exceptions and the original 46-scene / 5-MOV driver are unchanged. Full native execution without diagnostics and new original Feedback pixels are required before closing this checkpoint.

The authorized Mac was checked again and an actual read-only execution attempt returned offline. GitHub macOS runners supplied the execution above. Owned production-capture probes remain PARTIAL: original region PNG/private-copy identity and applicationScreenshot isolation pass; window/fullScreen are NOT_RUN under the existing FOREIGN_OVERLAP_VETO. Physical system-screenshot workflow, real ChatGPT attachment, screen/Space transitions and Feedback HTTPS-to-private-Issue delivery are not promoted by these fixtures. Endpoint remains nil; no main merge or public release occurred.

## 850200 complete failures and native alignment correction

Exact HEAD `850200c6fe00f99c6fe6bde266c2cdeabbfa30b3` was executed with all deadline diagnostics removed. Native push [40846190712](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40846190712) ARM/Intel and PR [40846200828](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40846200828) ARM each passed the full 726-case invocation, the unchanged 50ms/150ms deadline regression, the new independent-writer no-op regression, strict natural magnetic completion, unified App packaging and all original 46 scenes / 5 MOVs. Original PNG counts were 119, 101 and 117 respectively. Their supplemental step failed the new Feedback geometry validator; actual reduced-system scenarios were consequently NOT_RUN. These are overall failed workflows, not complete passes.

All three new original Feedback PNGs independently show the preserved body, actual failed-save text, retry and copy controls. The precise false rejection was the pair of standard button outer frames: retry `[17,37,125,32]` and copy `[136,37,86,32]` intersect by 6pt, while the visible button content has a gap. The other window, alpha, viewport, text and display checks all passed. AppKit documents that constraint layout uses [alignment rectangles](https://developer.apple.com/documentation/appkit/nsview/alignmentrect(forframe:)) while full frames can include shadows and other decoration. Changing product button spacing or inventing a fixed inset would misrepresent this measured issue.

Source `25609879978557e21ce42e781f2d1c2e41120752` records each real button's `alignmentRect(forFrame:)`, converts it through its actual superview into content coordinates, and requires it to be positive and contained in the original full visible bounds. Only the two buttons' mutual non-overlap uses this native alignment. Status text and editor viewport still keep their original non-overlap checks against full button bounds. No product code, button layout, 50ms display yield, two-second readiness bound, fault assertion or original 46-case / 5-MOV driver changes. The verifier requires the new actual observation; old manifests are not supplemented or relabeled. Independent review is bound to both source blobs, with 84 negative checks and the original 18 manifest tests passing locally. New macOS capture remains necessary.

PR Intel job `123354198576` failed earlier in the unchanged round-three offline network probe, at `network-probe.test.cjs:55`, called from line128: `changeHashOK` was false after the original fixed 20ms tick. The test blob `78780be3135a6b15b60478f73682c25e9d3d6947` and template blob `6b538be9a7f7c44455663f3df64f8d09f7a84014` are identical to a8c9, the prior formal source and PR #14. The template awaits File.arrayBuffer and WebCrypto digest asynchronously. A delayed completion is a plausible explanation, but the log lacks state/events to distinguish pending from rejected hash; it is not a measured root cause. The original script passed all 12 groups locally, which does not replace macOS. It remains unchanged and the complete next Intel job must pass it. No assertion or legacy evidence is removed.

Feedback [40846190810](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40846190810) / [40846200799](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40846200799) both passed 49 unique native, 117 Python and 20 Node cases plus three close-regression repeats. The current browser connector was also tried for existing cloud authorization, and returned an unavailable originating-browser context; a logged-in Cloudflare session could not be reused. Registered Mac checks remained Offline. Cloud delivery and physical acceptance stay separately NOT_RUN, without blocking authorized software repairs.


## Completed 8525 execution and initial fixture readiness

HEAD `8525a36d878acdc70be26b673e468cee456278a3`, reviewed source `25609879978557e21ce42e781f2d1c2e41120752`, PR checkout `33fc28c1c234d8c669b84ac4d81f93c90efe000a`. Full job/artifact/hash records, earlier attempts and non-author pixel observations are preserved in results.json.

| Execution | Actual result |
| --- | --- |
| [Native push 40848521633](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40848521633) ARM | 726 cases; original 46 / 117 PNG / 5 MOV; supplemental 6/6; actual reduced 3 / 16 PNG / 1 MOV. SUCCESS. |
| Same run Intel | 726 cases, strict natural magnet and unified App package PASS. Original motion-magnet fails missingProductPixels/pngPixelComparison before asset-ready, with zero PNGs and unfinished zero-byte MOV. Overall FAIL. |
| [Native PR 40848529234](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40848529234) ARM | 726 cases; original 46 / 120 PNG / 5 MOV; supplemental 6/6; actual reduced 3 / 18 PNG / 1 MOV. SUCCESS. |
| Same PR Intel | Attempt1 failed unchanged historical probe before Swift. Authorized full rerun passed that original probe, 726 cases, strict magnet and package; then feedback-records-light failed missingWindow/staticPreparation. Original 45/46 / 95 PNG / 5 MOV; supplements/reduced NOT_RUN. Overall FAIL. |
| Feedback [40848521666](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40848521666) / [40848529259](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40848529259) | Both PASS: 49 unique Swift, 117 Python, 20 Node, plus three rounds of the same two close cases. Offline synthetic; cloud NOT_RUN. |

Both ARM supplemental sets received actual non-author PNG review. Failure text, retained body, recovery buttons, countdown and complete history previews are visible. Actual button alignment rectangles are `[[24,44,111,20],[143,44,72,20]]`; full bounds remain recorded and checked. Independent ARM and Intel PR movie reviewers observed natural finished sequences without the old initial flash in recorded frames. The Intel movie is sparse (26 frames; about 226ms to its first post-ready sample), so no claim covers unsampled instants or performance.

The current source `de0fbdfe8ca08c1efe30eca931c481598cc2970f` fixes two code-visible helper preparation gaps. In the failed push Intel log, the helper was still inactive and its backdrop occluded at timeline start; key/active notifications arrived after the planned first PNG. This is compatible with the pixel rejection, not proof of a sole cause because failed pixels were not saved. Before either clock now starts, a bounded two-second preparation observes actual self-owned window identity, visibility, drawn-row/backdrop occlusion, geometry and layer order, performs ordinary layout/display, and rereads after a normal run-loop yield. One origin then starts both original recording and two-second injection. No frame is captured, discarded or retried in preparation; failure remains FAIL.

The failed PR Intel records-page log does show a real Feedback window; its shared missingWindow enum cannot identify the exact failed preparation guard. Controller creation does not finish asynchronous draft/record loads. The helper now waits at most two seconds for the same controller's actual fixture draft, editable editor and both exact record identities/bodies/states, then clicks the existing disclosure once. Every original visibility/body/state/scroll assertion, 700ms/350ms delay and seven-second static process bound remains. There is no product change, record action, transport call or capture retry.

The original 46-case / 5-MOV driver remains byte-identical (SHA256 `f1f7ba966e1e57640490338dad4bc248c3da3de1f4ab5e56f47bd498d0664747`). Product 560ms motion, strict natural finish, 64-pixel/channel-delta-greater-than-8 comparison, original keyframes and 6.45-second recording bound remain unchanged. All three exact Git blobs received non-author review. Preparation facts do not replace new original WindowServer pixels or complete workflows. Physical Mac, real system-screenshot end-to-end, real ChatGPT and cloud Feedback remain independently NOT_RUN; the authorized Mac remains Offline.

</details>

</details>

</details>

</details>
