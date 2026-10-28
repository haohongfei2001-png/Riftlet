# Riftlet 内置截图专项交接

日期：2026-10-29（北京时间）。独立候选分支 `codex/builtin-capture-completion-20261029`。本轮不修改或合并正式 PR #1，不要求创始人体验 Beta。

## 工程基线与任务边界

- 实时核对的正式 PR #1：Open / Draft，`0e7ea8be148e1124b387e799fd886a7830e96559`。
- 预测入口 PR #11：`5d6a683652d255af8c1d3e0d9533587fcc27a24d`。
- 最终设计：`7e03bd2c26c6aa43dbac07b073e00d08d1951b71`。
- 本分支直接父基线：薄界原生交接 `443d21da1a55c0061eafced823b5406879b96024`，其已测源码为 `00dedc7f8164643c3435e3f87aa462e28af0b1c8`。
- 本轮仅在独立克隆写入。最新正式 Feedback 增量未重复合入本分支；正式负责人先完成薄界/Feedback 合流，再接本增量。
- 最新活跃薄界集成为独立 Draft [PR #15](https://github.com/haohongfei2001-png/Riftlet/pull/15)：`codex/riftlet-real-mac-acceptance-internal-beta-thin-edge-20261029`，观察 head `fea485ce5226ab519af8f5325412b2ef43ba4a5a`，已审 source `cba039bae3fb976295d00869d5117fbaab50a26d`，基于正式 `0e7ea8be`。本轮不修改该 PR 或工作树。

独立 Draft PR：[#14](https://github.com/haohongfei2001-png/Riftlet/pull/14)。已独立审阅的实现提交依次为 `86ed9cf63f2aed0ea3114275d109b0e54287d74f`、`6540f1981897c1cda6957c38f88243b2b1ed763e`（自然退出后误超时）、`bd83e84e49fe7f50ad6c483bf9ccb1885ce70fc8`（来源隔离）、`b32d358f9cfb1dda59cab7d23aa0f04be1ffc52a`（真实路径失败修复、安全暂存发布、实际生产引擎 CI）、`9ebd89cf6067ffb2c21dba3034a48dae64bfda52`（正式候选偏好迁移）。最终审查源为 `9ebd89cf6067ffb2c21dba3034a48dae64bfda52`，完整 tree 为 `091965c27c191f6a9880da5c6061013e3b47269f`。准确候选、CI run / job、审查和制品记录位于 [results.json](../engineering/evidence/2026-10-29-builtin-capture/results.json)。未执行的项目始终保留 NOT_RUN；中间提交不能单独当作可用发行。

## 本轮真实代码

### 启用内置截图

在薄界统一原生设置的「截图入口」页增加「启用内置截图」及开启/关闭状态；窗口/区域/全屏默认模式在同页保留。使用原 `capture-entry-settings.json`，v1 缺少新字段时按此前候选行为保留开启及原默认模式；显式关闭可持久化。没有写入 macOS Screenshot.app 偏好或系统快捷键。

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

可独立验收的实现路径是：内置曝光 → 原 PNG 保存 → 私有导入 → 微图/历史。普通模式仍为 capture-only；既有受限系统截图候选不变。

**新 `applicationScreenshot` 的真实 ChatGPT 输入、uploadStarted、快速吞噬与后台完成未获真实证据，保持关闭。** 不改旧 UNKNOWN、目标身份、原操作锁、去重或 safe-retry。需要在授权真实 Mac 上取得一张新来源原图与原点击目标的一次输入/开始/完成证据，以及拒绝/目标变化/未明结果；之后以独立新 profile 和新操作登记做最小准入扩展。不能仅删除 origin guard，也不能重标来源。

## 技术复用与测量

[技术审计](BUILTIN_CAPTURE_TECHNOLOGY_2026-10-29.md) 对照 Apple 公共 API 和许可兼容开源实现，决定保留现有后端。没有已证实的完整链收益支撑生产替换。

[独立测量工具说明](../scripts/benchmark-builtin-capture.md) 和 Swift 源码支持原后端、macOS14+ SCScreenshotManager、可用旧系统上的 CGWindow 捕获比较。先检查权限，不自动请求/改 TCC；默认只拍自建不透明窗口及其内部区域，全桌面需要额外显式 flag 且永不保留图像。可选合成预览经过全像素验证和元数据清理；其不是原始 PNG 画质证明。报告保留原始尺寸、编码、颜色 profile/hash、首个/后续样本时间和进程内存范围。没有权限即 NOT_RUN。

## 验证与独立审查

当前作者环境 Linux；登记的 Mac 离线。macOS CI 配置包含 Apple Silicon `macos-15`、Intel `macos-15-intel`，最低部署目标仍是 macOS13；这不代表实际在 macOS13运行通过。完整原生、Web、历史证据回放、Feedback、包装和签名自检保留，新增开关/权限重入/迟到结果/子进程/尺寸/来源/设置回归。

旧 thin-edge composition gate 及 Beta/入口/arrival 原审计保持原字节。新 gate 从不可变 Git blob 复用旧实现，先审原基线，再对独立审阅的源提交做完整路径、blob、类型和权限比对；仅新 gate 与本交接/结果两条精确元数据允许后续更新，没有整个目录例外。

非作者已审引擎、Host、统一设置、来源隔离和测量工具；发现的设置层级遮挡、缺失测试 import、保存失败提示、旧 numberGap 迁移覆盖以及标注颜色范围声明已修复。最终审查范围及 CI 状态只以 results.json 为准。

真实捕获已发现并修复软件回归未暴露的路径问题：`b901b5e` 的双架构原生软件流水线成功，但两端各 15 个 CLI 样本全部没有可读 PNG，故该候选被否决。独立诊断 run `40758912572` 在 Intel 上证明“隐藏父目录＋普通文件名”可用；arm64 被曝光前外部窗口遮挡安全拒绝，不能借用 Intel 结果。之后新增实际生产引擎→发布→读回→私有 importer/SQLite→重复导入/重开数据库测试，并同时运行真实系统目录收录器；只有双 CI 环境开关及已有权限才执行，自有图案不能完整覆盖时逐模式 NOT_RUN。实际引擎或导入错误必须使 CI 失败。另加输出门禁，原来“软件成功但实际 CLI 全失败”的情况不会再静默绿色。

[证据目录](../engineering/evidence/2026-10-29-builtin-capture/README.md) 保存路径诊断以及两张真实 SCScreenshotManager 合成图案预览。预览经全像素白名单与 sRGB 重编码，不能证明生产 CLI、原始 PNG 色彩/HDR或最终 UI 已验收；原图不作为公共制品。最终候选的实际三模式文件/导入结果与失败历史分开记录于 results.json。

## 物理验收与发行门槛

| 项目 | 本轮状态 / 最小下一步 |
| --- | --- |
| 三模式实际引擎、原件与私有导入 | 以最后 source 的独立 opt-in CI 逐模式结果为准；不等于产品选择层验收 |
| 三模式物理输入、真实像素与主观响应 | NOT_RUN；以最终 App 在真实屏幕运行，不能用 fake controller 代替 |
| 1× / Retina / 负坐标 / 混合缩放跨屏 | NOT_RUN；尤其半点、奇数像素、跨屏统一采样 |
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

冻结本源时 PR #15 又推进到 `c8c92f81c51a9235f25200f026552e9db692d6ec`（source `49735b821bf8aae8f8327048a3c0ba159e1963d1`），包含新的截图 Controller、SystemCapture 和 Output 文件。上面的 9 路径试合表明确仅适用于 `fea485ce` 快照；最终合流必须再次核对这批重叠引擎改动，不得认为 Capture 目录可自动无冲突合并。对应只读更新审计及最终 CI 由 results.json 记录。

本轮不新增 SQLite schema；父基线已支持 applicationScreenshot。早于原截图入口增量、无法识别该来源的旧二进制不应读取同一数据根；兼容回退由集成负责人核对，不通过清库/删除原件解决。不改 main，不改现有 PR #1，不升级为正式发行。
