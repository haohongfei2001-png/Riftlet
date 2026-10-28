# Riftlet 内置截图专项交接

日期：2026-10-29（北京时间）。独立候选分支 `codex/builtin-capture-completion-20261029`。本轮不修改或合并正式 PR #1，不要求创始人体验 Beta。

## 工程基线与任务边界

- 实时核对的正式 PR #1：Open / Draft，`0e7ea8be148e1124b387e799fd886a7830e96559`。
- 预测入口 PR #11：`5d6a683652d255af8c1d3e0d9533587fcc27a24d`。
- 最终设计：`7e03bd2c26c6aa43dbac07b073e00d08d1951b71`。
- 本分支直接父基线：薄界原生交接 `443d21da1a55c0061eafced823b5406879b96024`，其已测源码为 `00dedc7f8164643c3435e3f87aa462e28af0b1c8`。
- 本轮仅在独立克隆写入。最新正式 Feedback 增量未重复合入本分支；正式负责人先完成薄界/Feedback 合流，再接本增量。

准确源提交、最终候选、CI run / job、审查和制品记录位于 [results.json](../engineering/evidence/2026-10-29-builtin-capture/results.json)。未执行的项目始终保留 NOT_RUN。

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

## 物理验收与发行门槛

| 项目 | 本轮状态 / 最小下一步 |
| --- | --- |
| 三模式真实像素与主观响应 | NOT_RUN；以最终 App 在真实屏幕运行，不能用 fake controller 代替 |
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

只读 `git merge-tree` 对固定 `443d21d` 与正式 `0e7ea8be` 发现的**继承冲突**为 `Sources/RiftletFeedbackUI/FeedbackWindowController.swift`、`docs/EXECUTION_BOARD.md`、`docs/INTEGRATION_HANDOFF.md`。本截图增量不修改 FeedbackWindowController；前述冲突由正在工作的薄界正式负责人处理。本增量重点接点是 `RiftletMain` 的 host/设置回调和窗口打开边界、`RiftSetupController` 的截图页及两个 CI workflow；最终组合可能还需按其最新演进做局部手工合流。

不使用旧二进制读取已经包含 applicationScreenshot 的同一数据根；不通过清库/删除原件回退。不改 main，不改现有 PR #1，不升级为正式发行。
