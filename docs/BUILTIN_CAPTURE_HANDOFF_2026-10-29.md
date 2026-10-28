# Riftlet 内置截图专项交接

日期：2026-10-29（北京时间）。独立候选分支 `codex/builtin-capture-completion-20261029`。本轮不修改或合并正式 PR #1，不要求创始人体验 Beta。

## 工程基线与任务边界

- 实时核对的正式 PR #1：Open / Draft，`0e7ea8be148e1124b387e799fd886a7830e96559`。
- 预测入口 PR #11：`5d6a683652d255af8c1d3e0d9533587fcc27a24d`。
- 最终设计：`7e03bd2c26c6aa43dbac07b073e00d08d1951b71`。
- 本分支直接父基线：薄界原生交接 `443d21da1a55c0061eafced823b5406879b96024`，其已测源码为 `00dedc7f8164643c3435e3f87aa462e28af0b1c8`。
- 本轮仅在独立克隆写入。最新正式 Feedback 增量未重复合入本分支；正式负责人先完成薄界/Feedback 合流，再接本增量。
- 最新活跃薄界集成为独立 Draft [PR #15](https://github.com/haohongfei2001-png/Riftlet/pull/15)：`codex/riftlet-real-mac-acceptance-internal-beta-thin-edge-20261029`，2026-10-28 20:16 UTC 观察 head `c8c92f81c51a9235f25200f026552e9db692d6ec`，已审 source `49735b821bf8aae8f8327048a3c0ba159e1963d1`，基于正式 `0e7ea8be`。此前 `fea485ce` 仅用于保留早期冲突快照。本轮不修改该 PR 或工作树。

独立 Draft PR：[#14](https://github.com/haohongfei2001-png/Riftlet/pull/14)。已独立审阅的实现提交依次为 `86ed9cf63f2aed0ea3114275d109b0e54287d74f`、`6540f1981897c1cda6957c38f88243b2b1ed763e`（自然退出后误超时）、`bd83e84e49fe7f50ad6c483bf9ccb1885ce70fc8`（来源隔离）、`b32d358f9cfb1dda59cab7d23aa0f04be1ffc52a`（真实路径失败修复、安全暂存发布、实际生产引擎 CI）、`9ebd89cf6067ffb2c21dba3034a48dae64bfda52`（正式候选偏好迁移）。最终审查源为 `9ebd89cf6067ffb2c21dba3034a48dae64bfda52`，完整 tree 为 `091965c27c191f6a9880da5c6061013e3b47269f`。准确候选、CI run / job、审查和制品记录位于 [results.json](../engineering/evidence/2026-10-29-builtin-capture/results.json)。未执行的项目始终保留 NOT_RUN；中间提交不能单独当作可用发行。

## 本轮真实代码

### 启用内置截图

在薄界统一原生设置的「截图入口」页增加「启用内置截图」及开启/关闭状态；窗口/区域/全屏默认模式在同页保留。使用原 `capture-entry-settings.json`：canonical `builtInScreenshotEnabled` 存在时严格优先，否则兼容严格读取旧 `isEnabled`；两者都缺少时才按此前候选行为保留开启。显式关闭、原默认模式和用户布局均保留，异常类型不被静默转换为开启。没有写入 macOS Screenshot.app 偏好或系统快捷键。

关闭先撤销引擎和当前会话，立即隐藏入口、关闭菜单/标注、释放入口鼠标监听和定时器。权限调用即使嵌套运行事件循环，迟到返回也不能重新创建选择层。重新开启只恢复待机入口，下一次用户点击才开始截图或请求权限。保存失败时本次仍保持关闭；开启必须保存成功才生效，界面明确提示保存失败。

开关与「暂停截图收录」「隐藏裂缝」独立，不改变 CaptureService、SQLite 记录、历史或上传 profile，不删除已保存文件。关闭前已经完成并持有原文件的导入可以完成，不能因此重开相机；尚未完成的选区/倒计时/子进程被取消。用户主动打开统一设置、历史、反馈、引导或动效窗口先结束当前截图会话，避免选择面板截走这些窗口的点击。

### 三种截图与连续操作

复用原 AppKit 选择层及系统非交互 `screencapture`。固定模式槽、活动槽取消盖片、成功后保持展开和当前模式、X/Escape 退出均保留。

本轮修复：显示器完整拓扑及 scale 冻结；窗口 ID/PID/矩形复核；按下与松开之间模式/显示器变化；Space、休眠/显示器休眠中断；取消子进程与立即重开之间的竞态；旧选择窗口/任务回调误作用于新会话；无效或错误尺寸输出。仅清理身份未变的空预留文件，所有非空原始 PNG 保留。单显示器区域/全屏校验实际像素尺寸，窗口阴影与混合屏尺寸不凭猜测校验。

预览与最终截图统一使用整数逻辑点网格，消除了最后一刻 `.integral` 扩大选区；选区边框按对应屏幕 scale 绘制为一个物理像素。**这尚不等于支持 Retina 奇数像素/半点选区**，具体后端分数解析及混合屏采样仍需真机像素证据。

### 原文件、来源与标注

所有内置截图均为 `applicationScreenshot`，即使 macOS 工具写了真实系统截图 xattr，也不会借用 `systemScreenshot` 或 synthetic 上传准入。原 PNG 和元数据不改写，沿用 PrivateAssetImporter 的文件身份、完整验证、容量、哈希、journal、SQLite v3 和去重。

系统截图位置与私有 `captures` 目录重叠时，新自有原件先使用独占隐藏目录 `captures/.capture-UUID/`（0700）中的普通 PNG 文件名（0600）。真实 CLI 完成后，利用持有的目录描述符和 `linkat` 排他发布为隐藏最终原件，发布及读回核对文件身份，已有最终文件绝不覆盖。派生文件也隐藏，复用系统收录器既有非递归枚举及隐藏文件排除规则；同目录真正系统截图仍正常收录。显式 built-in 导入命中已有其他来源时拒绝返回为成功，不重标已有记录。旧候选留下的可见原件不被回溯重命名或净化，不扩大其来源、旧 UNKNOWN 或旧操作准入。

失败/取消后保留非空原件，不搜索工具意外写入的其他文件名；只清理身份未变的空预留和确认空的自有目录。原存储统计对保留的 stage 目录标记不完整，目录内字节暂不纳入总数；正常完成的最终原件正常计数。此前直接把隐藏 basename 交给 CLI 的候选已经实测失败并否决，不得取其中间提交单独发行。

可选标注维持矩形/撤销/保留原图/完成的小范围。派生 PNG 的私有持久写入移到已有 importer actor；未修改原图。编辑器仅接受已知 sRGB / Display P3 的 8-bit SDR RGB，其他格式保留原图并给出轻量说明，避免静默降位深。内置截图目前走既有队列的静态入场降级，未借用未准入的系统源矩形；磁力仅保留原有已批准模式，不宣称内置轨迹已通过。

## 上传范围：仍有发行阻断

已实现路径是：内置曝光 → 原 PNG 保存 → 私有导入 → 既有微图/历史队列。实际生产组件 CI 当前验证到区域截图的原件、私有 importer、SQLite、去重与重开数据库；没有据此宣称最终 App 的微图显示或物理点击已验收。普通模式仍为 capture-only；既有受限系统截图候选不变。

**新 `applicationScreenshot` 的真实 ChatGPT 输入、uploadStarted、快速吞噬与后台完成未获真实证据，保持关闭。** 不改旧 UNKNOWN、目标身份、原操作锁、去重或 safe-retry。需要在授权真实 Mac 上取得一张新来源原图与原点击目标的一次输入/开始/完成证据，以及拒绝/目标变化/未明结果；之后以独立新 profile 和新操作登记做最小准入扩展。不能仅删除 origin guard，也不能重标来源。

## 技术复用与测量

[技术审计](BUILTIN_CAPTURE_TECHNOLOGY_2026-10-29.md) 对照 Apple 公共 API 和许可兼容开源实现，决定保留现有后端。下述实际测量显示 SCScreenshotManager 的后续调用明显更快；首调用、像素/颜色、取消、排除和完整产品路径的组合收益仍未得到验收，当前不据局部速度替换生产后端。

[独立测量工具说明](../scripts/benchmark-builtin-capture.md) 和 Swift 源码支持原后端、macOS14+ SCScreenshotManager、可用旧系统上的 CGWindow 捕获比较。先检查权限，不自动请求/改 TCC；默认只拍自建不透明窗口及其内部区域，全桌面需要额外显式 flag 且永不保留图像。可选合成预览经过全像素验证和元数据清理；其不是原始 PNG 画质证明。报告保留原始尺寸、编码、颜色 profile/hash、首个/后续样本时间和进程内存范围。没有权限即 NOT_RUN。

## 验证与独立审查

当前作者环境 Linux；登记的 Mac 离线。macOS CI 配置包含 Apple Silicon `macos-15`、Intel `macos-15-intel`，最低部署目标仍是 macOS13；这不代表实际在 macOS13运行通过。完整原生、Web、历史证据回放、Feedback、包装和签名自检保留，新增开关/权限重入/迟到结果/子进程/尺寸/来源/设置回归。

旧 thin-edge composition gate 及 Beta/入口/arrival 原审计保持原字节。新 gate 从不可变 Git blob 复用旧实现，先审原基线，再对独立审阅的源提交做完整路径、blob、类型和权限比对；仅新 gate 与本交接/结果两条精确元数据允许后续更新，没有整个目录例外。

非作者已审引擎、Host、统一设置、来源隔离和测量工具；发现的设置层级遮挡、缺失测试 import、保存失败提示、旧 numberGap 迁移覆盖以及标注颜色范围声明已修复。最终审查范围及 CI 状态只以 results.json 为准。

真实捕获已发现并修复软件回归未暴露的路径问题：`b901b5e` 的双架构原生软件流水线成功，但两端各 15 个 CLI 样本全部没有可读 PNG，故该候选被否决。独立诊断 run `40758912572` 在 Intel 上证明“隐藏父目录＋普通文件名”可用；arm64 被曝光前外部窗口遮挡安全拒绝，不能借用 Intel 结果。之后新增实际生产引擎→发布→读回→私有 importer/SQLite→重复导入/重开数据库测试，并同时运行真实系统目录收录器；只有双 CI 环境开关及已有权限才执行，自有图案不能完整覆盖时逐模式 NOT_RUN。实际引擎或导入错误必须使 CI 失败。另加输出门禁，原来“软件成功但实际 CLI 全失败”的情况不会再静默绿色。

[证据目录](../engineering/evidence/2026-10-29-builtin-capture/README.md) 保存路径诊断以及两张真实 SCScreenshotManager 合成图案预览。预览经全像素白名单与 sRGB 重编码，不能证明生产 CLI、原始 PNG 色彩/HDR或最终 UI 已验收；原图不作为公共制品。最终候选的实际三模式文件/导入结果与失败历史分开记录于 results.json。

### 已完成的最终源 CI 与真实组件证据

已独立复核 source `9ebd89cf6067ffb2c21dba3034a48dae64bfda52`、tested head `1dd340017f1a51bebdcb5c6d0b41e2b0d789464a`、PR merge checkout `2fb2d5c7f4582ebddee01ac71b7a654b18c10944`。两架构的 macOS15.7.9（24G830）/ Swift6.1.2 原生 [run 40761667038](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40761667038) 与 Feedback [run 40761666854](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40761666854) 均已完成 SUCCESS。日志中的 composition 均 PASS，825 条受保护路径无差异。后续证据提交只允许本交接和 results.json 更新，不改变该已测产品源。

| 验证范围 | Intel / Apple Silicon 实际结果 |
| --- | --- |
| 原生完整测试步骤 | 两端成功；每端日志调度 671 个不同测试方法，不能等同 671 条逐一 PASS；默认未开启的真实 fixture 不在普通软件组授予真实验收 |
| 截图与设置详细组 | 两端各 98 passed / 0 failed / 0 skipped；包含 15 项进程生命周期用例、5 项偏好用例，不重复加总 |
| 新增测试 | 相对基线 620 → 671 个方法定义，共新增 51；重复详细执行不增加唯一测试数 |
| Feedback | isolation 65 passed，Node 18 passed，Swift Feedback/UI 33 passed；三次 Close 重复不另计唯一覆盖 |
| 打包与自检 | 两端 release build、包结构、签名/资源及离线 synthetic 自检成功；未公证，Gatekeeper、真实 GUI 与云端上传仍 NOT_RUN |

实际生产引擎 probe 使用默认 `screencapture`、安全 stage/排他发布和真实 private importer，并同时运行真实系统目录收录器。两端均为单显示器 1×：Intel 1920×1080，ARM 1024×768。

| 模式 | 两架构实际生产组件结论 |
| --- | --- |
| 区域 | **PASS（限定组件范围）**：128×96 PNG；原件隐藏且0600，私有副本与原件逐字节一致，applicationScreenshot 来源、普通收录器排除、重复导入同 ID、SQLite 重开均验证 |
| 窗口 | **NOT_RUN**：引擎返回后、读取验收元数据及导入之前，外部窗口重叠守卫拒绝；不能凭 engineReturned 宣称完整链 PASS |
| 全屏 | **NOT_RUN**：曝光前外部窗口重叠守卫拒绝 |
| 总评 | **PARTIAL**；物理选区、颜色、最终微图、真实 ChatGPT 上传均未授予验收 |

两端区域 PNG 均带真实系统截图元数据，实际入库仍为 `applicationScreenshot`，这使来源隔离验证不只依赖模拟 marker。Intel 原件7612字节、ARM原件3322字节；原件 SHA256、完整逐模式 JSON、日志摘要/hash 和制品 ID 均保存在 results.json。原图不上传为公共证据。

区域组件只有各一次样本：捕获/发布/读回 Intel **206.491ms**、ARM **61.754ms**；随后原件验证 **1.921 / 0.617ms**、private import **12.682 / 4.492ms**。这些不能称为点击到微图延迟、p50 或 p95。

独立 API 比较另在每架构得到 CLI 15 个、SCScreenshotManager 15 个可读 PNG，输出错误0；每个后端/变体5次。以下为首个变体调用 / 后续4次中位数，单位ms，边界是 API或进程开始至 PNG 可检查，未包含用户选择及完整收录：

| 架构 / 变体 | screencapture 首个 / 后续中位数 | SCScreenshotManager 首个 / 后续中位数 |
| --- | ---: | ---: |
| ARM 窗口480×320 | 167.552 / 87.667 | 146.241 / 23.899 |
| ARM 整数区域128×96 | 71.213 / 69.972 | 370.758 / 21.069 |
| ARM 半点实验区域 | 62.950 / 60.527 | 42.559 / 18.055 |
| Intel 窗口480×320 | 419.329 / 151.940 | 863.621 / 67.654 |
| Intel 整数区域128×96 | 155.377 / 119.789 | 54.562 / 58.548 |
| Intel 半点实验区域 | 151.238 / 143.514 | 798.989 / 76.832 |

SCK 内容枚举另计 ARM32.083ms、Intel158.053ms，未包含在上表各样本中；首个变体调用也不等于系统冷启动。半点仅为1×探针实验，不能外推 Retina 或声称生产选择器已支持半点。两端各6项 NOT_RUN 为旧 CGWindow API/macOS15边界及未主动开启的独立全屏采样。探针总进程峰值 ARM37,814,272字节、Intel26,177,536字节；子进程累计峰值分别17,874,944、10,530,816字节，均不是逐后端隔离峰值或产品 App 内存。

ARM 全像素隐私白名单允许保存25张合成预览（CLI15、SCK10，SCK半点5张不匹配）；Intel30张均未满足全像素白名单，虽4个颜色 canary 匹配，仍没有保留任何图像。这个白名单不是 HDR/广色域正确性认证。当前 ARM [制品12849455162](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40761667038/artifacts/12849455162) 中另有实际 CLI 的窗口/区域预览；它们经 sRGB 重编码、不复制源 EXIF，但编码器可写 ColorSpace/尺寸 EXIF，不能称为原 PNG 或完全无元数据。证据目录原有两张 SCK 预览的历史来源不变。

## 物理验收与发行门槛

| 项目 | 本轮状态 / 最小下一步 |
| --- | --- |
| 三模式实际引擎、原件与私有导入 | 当前双架构区域 PASS；窗口在捕获后被守卫拒绝、全屏在捕获前被拒绝，均 NOT_RUN；总评 PARTIAL，不等于产品选择层验收 |
| 三模式物理输入、真实像素与主观响应 | NOT_RUN；以最终 App 在真实屏幕运行，不能用 fake controller 代替 |
| 1× / Retina / 负坐标 / 混合缩放跨屏 | 受控CI单屏1×区域已实测；Retina/负坐标/混合跨屏 NOT_RUN，奇数物理像素/半点生产选择尚未实现 |
| 窗口圆角/边框/阴影/遮挡、不同窗口类型、全屏应用 | NOT_RUN；确认目标与实际 PNG，不将窗口枚举等同图像正确 |
| 曝光期间自身 UI 排除、Escape、快速双击穿透 | NOT_RUN；WindowServer 元数据检查不能替代最终像素和物理路由 |
| TCC 允许/拒绝/撤销/恢复 | NOT_RUN；CI 注入权限回归与真实权限操作分开 |
| 真正休眠/唤醒/断屏/Space | NOT_RUN；通知/拓扑注入仅软件回归 |
| 原 PNG / 颜色 / HDR / 大图内存 / 完整延迟 | 见 CI probe 实际可执行范围；真实广色域/HDR及端到端 p50/p95 仍 NOT_RUN |
| 系统与内置并存、关闭后系统工作流 | 软件 SQLite/importer 和旧系统 suite 回归；真实双来源同时截图 NOT_RUN |
| 内置截图 → 当前 ChatGPT草稿 → 快吞噬 → 后台完成 | NOT_RUN，来源准入保持关闭 |
| 内置截图磁力源映射 | 尚未接入新来源；静态降级有效，真实映射后再扩展 |
| 正式组合与发行 | 唯一负责人合流后重跑组合 CI、实机及发行候选审查；本分支不发行 |

## 精确合流方法

先确认正式负责人已完成薄界与最新 Feedback 的整合，然后取得本分支相对 `443d21d` 的增量。不要把整个旧薄界工作树覆盖到正式目录。

```sh
git fetch origin codex/builtin-capture-completion-20261029
git diff --stat 443d21da1a55c0061eafced823b5406879b96024 origin/codex/builtin-capture-completion-20261029
git log --reverse --oneline 443d21da1a55c0061eafced823b5406879b96024..origin/codex/builtin-capture-completion-20261029
```

由负责人在其独立组合工作树 cherry-pick 本增量源提交及必要修复；新 composition pin 必须针对合流后的实际完整树经非作者审查重新固定，不能把本分支 CI 当组合 CI。保留正式 Feedback 对象和旧证据、所有 Core/Adapters/SQLite/sourceKey/profile。

实现增量的精确顺序如下（由正式负责人执行，本轮未在正式分支执行）：

```sh
git cherry-pick -x 86ed9cf63f2aed0ea3114275d109b0e54287d74f 6540f1981897c1cda6957c38f88243b2b1ed763e bd83e84e49fe7f50ad6c483bf9ccb1885ce70fc8 b32d358f9cfb1dda59cab7d23aa0f04be1ffc52a 9ebd89cf6067ffb2c21dba3034a48dae64bfda52
```

中间及末尾的 pin/交接提交只更新三条元数据，不要把其中的旧完整树 pin 直接当作正式组合 pin；先保留门禁失败关闭，再对实际组合源码独立审阅后固定新 pin。

只读 `git merge-tree` 对固定 `443d21d` 与正式 `0e7ea8be` 发现的**继承冲突**为 `Sources/RiftletFeedbackUI/FeedbackWindowController.swift`、`docs/EXECUTION_BOARD.md`、`docs/INTEGRATION_HANDOFF.md`。本截图增量不修改 FeedbackWindowController；前述冲突由正在工作的薄界正式负责人处理。本增量重点接点是 `RiftletMain` 的 host/设置回调和窗口打开边界、`RiftSetupController` 的截图页及两个 CI workflow；最终组合可能还需按其最新演进做局部手工合流。

对当时发布的本候选 `b901b5e` 与 PR #15 `fea485ce`，以 `443d21d` 为共同基线做只读三方文本试合，发现 9 条重叠路径，7 文件存在文本冲突：两个 CI workflow、`RiftletMain`、`ScreenshotEntryHost`、`ScreenshotEntryPreferences`、`RiftSetupController`、`EXECUTION_BOARD`。`ScreenshotEntryController` 和 `ScreenshotEntryIntegrationTests` 文本可合，但偏好属性名的编译/语义仍需人工对齐。没有在正式树执行 merge，也没有把试合视作最终组合测试。

PR #15 使用 JSON `isEnabled`，本候选使用 `builtInScreenshotEnabled`。最终增量兼容读取旧键：新键存在时严格优先，否则严格读取旧键，均缺省才保留此前开启行为；保存只写新键。该迁移防止正式候选已保存的关闭状态在升级后意外开启。合流时所有 Host、设置和测试调用统一使用新属性，不能仅选择一侧整个文件、保留两套开关或用编译成功代替关闭生命周期验证。最终完整树仍须基于最后 SHA 重新审阅并固定 composition pin。

冻结本源时 PR #15 又推进到 `c8c92f81c51a9235f25200f026552e9db692d6ec`（source `49735b821bf8aae8f8327048a3c0ba159e1963d1`），包含新的截图 Controller、SystemCapture 和 Output 文件。上面的 9 路径试合表仅适用于 `fea485ce` 快照。重新以 `443d21d` 为基线，对本候选已审 `b32d358` 与 `c8c92f8` 进行匿名内存文件中的 `git merge-file -p --diff3`，得到 **14 条交集路径、10 个文本冲突文件、34 个冲突块**。后续 `9ebd89cf` 只补偏好兼容及证据文案；没有构建或运行正式组合树。

| 交集路径 | 文本冲突块 | 必须保留和接合的行为 |
| --- | ---: | --- |
| `.github/workflows/feedback-v01.yml` | 2 | 两条固定历史审计和 isolation suites；最终新完整树 pin |
| `.github/workflows/native-foundation.yml` | 5 | 本候选双架构、实际生产 probe、输出失败门禁；PR #15 统一产品详细组及原生视觉取证；按架构命名制品 |
| `Sources/RiftletApp/RiftletMain.swift` | 5 | PR #15 统一设置及 applySettings；本候选真实关闭、保存失败和菜单状态；不恢复独立动效设置窗 |
| `Sources/RiftletApp/ScreenshotEntryHost.swift` | 8 | 可逆关闭、迟到回调、编辑器归属、application 来源；对方屏幕变化后设置刷新；单一通知回调 |
| `Sources/RiftletApp/ScreenshotEntryPreferences.swift` | 1 | canonical/legacy 严格迁移、默认模式与用户布局；一个状态来源 |
| `Sources/RiftletCapture/InteractiveScreenshotController.swift` | 3 | 保留本候选 startAttemptID/isEnabled 前后检查，去除重复 startAttempt；保留双方权限提示取消/新会话测试 |
| `Sources/RiftletCapture/InteractiveScreenshotSystemCapture.swift` | 1 | 本候选隐藏 stage＋普通 CLI leaf＋排他发布；不得回退为直接隐藏 leaf |
| `Sources/RiftletUI/RiftSetupController.swift` | 6 | 保留 PR #15 嵌入式 RiftSettingsForm 与最新引导，将本候选开关语义接入；不恢复第二套 form |
| `Sources/RiftletUI/ScreenshotEntryController.swift` | 0 | 同时保留 Reduce Transparency 修复、可逆关闭、监听 generation 和菜单归属 |
| `Sources/RiftletUI/SetupPresentation.swift` | 0 | 按真实 attachment 能力表达引导，同时保留实际开关和保存失败状态 |
| `Tests/RiftletAppTests/ScreenshotEntryIntegrationTests.swift` | 0 | 将对方 .isEnabled API 映射为 canonical；保留 legacy JSON 与 numberGap 回归 |
| `Tests/RiftletCaptureTests/CompletedScreenshotImporterTests.swift` | 0 | 双方 active/retired watcher、字节、sourceKey、存储检查；通用系统来源用例不用于内置来源准入 |
| `Tests/RiftletCaptureTests/InteractiveScreenshotTests.swift` | 2 | 权限 fixture 同时保留 requestResult 和 onRequest，所有重入/取消覆盖 |
| `docs/EXECUTION_BOARD.md` | 1 | 保留双方任务记录、精确 source、完成状态和限制 |

两项已独立复核的源码风险必须写进合流检查：

1. PR #15 `InteractiveScreenshotOutput.originalURL` 返回隐藏 basename，SystemCapture 直接预留、传给 CLI 并读回同一路径。这与本轮已实测失败的布局相同；**没有执行 PR #15 二进制，不能把布局证据写成其二进制实测**。该 helper 可用于最终/编辑文件命名，不能替代本候选安全 stage 流程。
2. PR #15 Host 仍以 `hasSystemScreenshotMetadata ? .systemScreenshot : .applicationScreenshot` 导入未编辑原件。合流须使用 `importBuiltInScreenshot` 和既有来源冲突拒绝，避免恢复内置伪装系统来源。此为源码来源错误，不是已发生误上传的证据；普通模式和旧准入可能仍阻断上传。

统一设置 API 也要一次接合：对方 `onPreferencesChange` 与本候选 `onPreferencesChanged` 合为一次通知；`selectDefaultMode(throws)` 与 `saveDefault/preferenceSaveFailed` 适配统一 applySettings。关闭保存失败后 form 必须反映实际 off 和未持久化提示，不能恢复旧 on 或声称已保存；保留对方 Return/保存单次提交、失焦不保存、分数小时幂等修复。将 form 的“启用预测式截图入口”升级为正式“启用内置截图”。

PR #11 入口、PR #12 arrival 已是 `443d21d` 祖先，正式 Feedback 已在 `0e7ea8be`，不要重复移植。最终接收点继续推进时，正式负责人须以届时精确 head 重做这份组合检查；任何一支单独 CI 均不能代替组合结果。

最后只读复核于2026-10-28 20:35 UTC：PR #15 已推进到 head `5a9979693ac1bb28fa898d23c60bc791c2c7ec4d`，新审查 source `9a06e1e1a89fababd95cb892a662cbbf63e5c0c9`、tree `bd0663096e3b8510045ee05bf52710137e6e7b80`。相对 `c8c92f8`，新增修补涉及 ArrivalMotionSettingsController、RiftSettingsForm、UnifiedSettingsTests 及三份对方专用元数据，均不在本增量改动集合，未增加前述交集；14路径/10冲突文件/34块仍是原固定快照的文本试合记录。合流须保留对方“同倍率 backing 通知不打断主动预览”和播放前布局修补。最新 head 的直接隐藏 CLI basename 及根据系统 xattr 判来源仍未改变，两项风险继续适用。最终组合树尚未构建、测试或发行审查。

## 当前 Apple API 补充核对

除本轮在 macOS15实测的 `SCScreenshotManager.captureImage` 之外，Apple 当前公开文档还提供 [SCScreenshotConfiguration](https://developer.apple.com/documentation/screencapturekit/scscreenshotconfiguration) 与 [captureScreenshot](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager/capturescreenshot(contentfilter:configuration:completionhandler:))，可配置输出类型、文件 URL、SDR/HDR、local/canonical intent、阴影及子窗口。这些较新接口尚未在本候选当前 SDK/运行环境实际比较，标记 NOT_RUN；不能把本文旧路径测得的 SCK 时间移作新接口性能，亦不能据文档能力替换经过约束的 macOS13兼容后端。

本轮不新增 SQLite schema；父基线已支持 applicationScreenshot。早于原截图入口增量、无法识别该来源的旧二进制不应读取同一数据根；兼容回退由集成负责人核对，不通过清库/删除原件解决。不改 main，不改现有 PR #1，不升级为正式发行。
