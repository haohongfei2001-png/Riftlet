# 第五轮：真实开始 → AppKit 快吞噬 → 独立最终成功

2026-10-27。本轮限定生成图片、中文普通已有 ChatGPT 对话的新版链路 **PASS**；不是生产系统截图或全部日常交互准入。用户要求自行操作后，使用已有 `RiftletGUIAcceptance` 的精确单次 AXPress 完成，未再请求人工点击。AX 是软件事件，不能冒充物理鼠标。

## 精确来源与边界

- 独立分支：`codex/riftlet-real-mac-round5-20261027`。
- 最终实际源码：`53ebcc4da4b0df508edc11f6ead9ea4d8a843dad`，页面 v11/schema2。
- 起点正式 SQLite v3 `b84892071d7711177bb856051251a337f2c2c4f5`；继承第四轮 adapter 增量，随后合入 Pro `e89d49f763036781c90618422da256e03cbca2ac`。交付前远端正式分支仍为该 SHA。
- 工作树的 `Sources/RiftletCore/`、`Sources/RiftletUI/`、`Sources/RiftletApp/` 对 e89d49f 的 diff 为空。真实验收使用从精确源码导出的独立临时构建，追加两个下述补丁；正式接线仍交 Pro。
- 最终真实 App 可执行文件 SHA-256：`30fa313bc0aee80176263dfcb8f09f7575c35018cac5a579c62543ab12d97268`。
- 环境：macOS 27.0 (26A428)、arm64、Swift 6.4、Chrome 156.0.8078.48。已有 Web store 升到 SQLite v3；真实普通截图 store 未降级或清理。

## 真机发现并修复的两处缺陷

1. **v9 初始进度缺值误拒绝。** 原进度条先没有 `aria-valuenow`，再出现真实递增数值；v9 在初始缺值时永久撤销 start。v10 先绑定同一节点，初始缺值仅等待；第一有限值只作基线，第二有限递增且小于 100 的值才可能证明开始。数值后缺失、回退、替换、移除仍拒绝。见 [v9 实证](v9-start-failure-analysis.md)。
2. **真实 NodeList 导致观察回调异常。** v10 对 `MutationRecord.removedNodes` 直接调用 `.some()`；真实 NodeList 没有该方法，数组测试夹具掩盖了缺陷。v11 改为展开后检查，全部相关夹具使用 NodeList-like 类型，并证明 start 早返回后无需 native query，原事件也能独立完成证明。真实 v10 的 100% 与移除分别发生在两个 batch，相隔 2619.5 ms，不能把本轮失败归因于合批。见 [v10 实证](v10-fast-swallow-analysis.md)。

完整 identity、唯一 input=1、原 File SHA、唯一原附件、原进度节点、两个有限递增样本、时间/序列严格先后仍必需。单独 files/change/占位图/上传布尔不授予开始。最终 100%→移除→原图片 load→字节或像素证明判据未放宽。旧 v6/v7/v8/v9/v10 只读路由始终 schema1，不借用新 start、不修补旧闭包、不回填旧证明或重新输入。

## 最终实际结果

完整原始数值与脱敏关联见 [v11 证据](v11-fast-swallow-evidence.json) / [分析](v11-fast-swallow-analysis.md)。

- 新生成 asset `A69D72AA-1616-4D12-BC70-8FA5A77B8AE0`，operation `D53F7E0E-871B-4118-84DB-FB00772E1FE7`，attempt 1；只有一次 selection、begin、commit、input，没有发送聊天消息。
- 3,147,775-byte 纯生成 PNG，SHA-256 `494d7d015dc1a91073b356e1d6d64a546497aab37f8c47c4f82c630d7033f5bb`。进度 4.084106969654981 → 8.622003602604961，完整原 target / attachment 在开始及最终回执中逐字段一致，公开证据只保存摘要。
- 页面 input 154145.8 ms；start 156323.7 ms；最终独立 proof 161791.5 ms。**开始先于最终证明 5467.8 ms**。
- Core 先持久 `upload_starts` 和 `swallowed/uploadStarted`，状态仍未决；AppKit scheduled/start/close 各一次。动画调用至窗口 close **252.683 ms**；按跨时钟采样界，真实 start 至 AppKit 调用约 **59–322 ms**，窗口关闭早于最终 proof 约 **4.89–5.16 秒**。
- 点击至窗口 close 约 **5.51 秒**，包含传输和等待真实开始，不应缩写成“点击后 253 ms”。保留原本地配置 `swallowDuration=0.24`（正式源码默认 0.120），本轮没有改配置或为了演示加速。
- 后台随后读取最终回执，Core 为 `used/succeeded`，仍 `swallowed/uploadStarted`；首份开始审计保留，无第二次动画。页面完成与 Core 持久成功的读取上界分开记录，不能把观察间隔全称上传耗时。
- 这是启用诊断的 AppKit 实际调用/close 测量，`pixelPresentationMeasured=false`；不是像素首帧或精确 SQLite COMMIT 时间。日志存在无操作归属的 `-1728`，不归因新图，也不称整次运行无错。

## 准入与最小 Pro 补丁

[独立开始审查](v10-start-admission-review.md) 后，只在显式 synthetic Web acceptance 临时构建授予 `chatgpt-web-zh-progress-start-development-20261027-v1`。正式源码所有生产 start/completion/retry registry 仍空，正式 App 的 synthetic start registry 也仍待 Pro 接线。

- [App 开始策略及诊断 overlay](app-acceptance-overlay.patch)，SHA-256 `f686da6cf50b0f1c4e10d0d952b0ab88a4489a0120aefb9e7a4a27a9b0dbfea6`：只改显式生成图 start 组合和观察回调；不重写 Core/UI 生命周期。
- [synthetic AX identifier/Enabled 最小补丁](acceptance-synthetic-identifier-overlay.patch)，SHA-256 `d9638001fc0afb8bfbc13ad9b9f36a66ebc8289121c71b07d75058fd7b3ca7f0`：现有 helper 精确定位实际图片所需，保留原按钮选择保护。
- [App 接口说明](app-integration-proposal.md)。AX 窗口排序尝试 [FAIL](cua-panel-routing-proposal.md)，其 overlay 仅作为失败实验留存，**不要集成到最终 App**。

## 验收矩阵

| 项目 | 结果 | 证据范围 |
|---|---|---|
| 53ebcc4 完整 macOS CI | PASS | [40497953468](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40497953468)：314 native、68 page、45 legacy，13 lifecycle 逐项 passed；Release、签名和三个自检。 |
| v9 真实 start | FAIL，已修复 | 两张单次生成图最终成功但初始 missing 导致 start 丢失；不是新版吞噬 PASS。 |
| v10 真实 start / 未准入不吞 | PASS，限定 | 原进度证据早返回；默认 registry 保持 visible/unknown。其最终完成仍 UNKNOWN。 |
| v10 start 后实际 AppKit 吞噬 | PASS，限定 | 253 ms 动画段，后端证明缺失保持未决；不是最终成功。 |
| v11 start→吞噬→独立最终成功 | PASS，限定 | 预绑定普通已有线程、发言框聚焦、空文本/零旧附件、软件 AX 单击。 |
| 旧附件/选区保留 | PASS，局部 | 前两轮 v9 上传保留已存在附件节点及选区；不覆盖非空文字或所有选区情形。 |
| v6–v10 旧操作只读 / 无重复输入 | PASS，限定 | 回归与本次保留原操作；旧缺失证据不被新版本补写。 |
| 真实网络中断后 UNKNOWN / 安全失败重生 | NOT_RUN | 不能用本轮 observer 缺陷代替网络异常；retry 未准入。 |
| MID 真实字节请求中断 | NOT_EXERCISED | 没有新增命中真实请求的证据。 |
| 无 ACK 冷首击 / 业务 A→B→A / 同 URL 草稿替换 | NOT_RUN | 不以预绑定成功或新独立对话测试关闭这些项。 |
| 物理点击、CLEAR/GAP 穿透、多屏等完整 N1 | NOT_RUN | helper AX 不是人工物理点击。 |
| 系统截图自包含 | FAIL（第三轮既有证据） | 本轮未重测、未宣称解决。 |
| 生产系统截图上传与安全重传 | NOT_RUN / disabled | 不因生成图成功解除隔离。 |

## 保留与交接

原 11 个 Web asset、17 个 operation 身份、3 个补偿审计及 11 个私有文件 hash 全保留；普通截图 store 的 6 个原文件 hash 也保留。新增 5 个生成 asset/operation 各仅输入一次，其中 3 个最终成功、2 个保留未决；两份获准 start 审计仍在。见 [最终保存检查](final-preservation.json)。没有重试旧 UNKNOWN，没有删除原图、数据库、历史分支、原页面监视器或剪贴板协调资料。两个含未决操作的验收标签已显式标记 handoff，最终附件草稿标记 deliverable，保留后续只读观察。

实际验收 App 已退出。原数据和 v3 snapshot、原始日志、签名 App 私有副本保存在本机 `Riftlet-Round5-Backups`，公共仓库只有代码和脱敏证据，没有真实截图、聊天、认证资料或完整 target。CUA 标签创建能完成但页面快照/定位会超时，逐次核对实际创建结果后沿用授权的 Chrome Apple Events 路径；最终通过已文档化的 browser.user.claimTab/markHandoff 接口完成标签保留。最终只读可视截图定位仍超时，故无像素级证据。未把工具超时当成操作未发生。

Pro 可先集成 adapter/helper 源码与回归，再按上述真实 synthetic 范围合入两个最小补丁；正式分支、PR #1、main、网站和设计成果本轮均未修改。其后优先无 ACK 冷首击与同草稿多图策略、业务转换和物理 N1；安全失败及 MID 独立继续。不要重新输入本轮两个旧版本未决图来补演示。
