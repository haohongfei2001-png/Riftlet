# Riftlet 当前工程队列

本文件是官网部署前的已审检查点；[最终公网发行与实际更新回执](https://github.com/haohongfei2001-png/Riftlet/pull/101#issuecomment-6879797338)在原 PR 按真实执行结果持续更新。

2026-11-14：[PR #101](https://github.com/haohongfei2001-png/Riftlet/pull/101) 已通过标准流程合入 main `5b73c755ec1eb6d1aa2ef5b9390da6200b6108b9`。本轮产品实现已集成，不再重新开展设置、历史、三形态或附件架构开发。精确源码与逐项范围见 [progress.json](../engineering/quality/2026-11-14/progress.json) 和 [ITERATION_STATUS.json](quality/ITERATION_STATUS.json)。

正式 Riftlet 1.0.2／24 来自审查源 `876c7e829abeef865e442f9e46eaae495d1a9e09`，已完成 Developer ID 通用签名、App 与 DMG 两项 Apple 公证及贴票。最终 DMG SHA-256：`374fbe7b5a49938bf7d67c38a52a018941b672c382abdace63efbb4f73393931`。真实 merge 的五项 main CI 已完成并通过。GitHub v1.0.2 已公开；官网部署、公开 stable feed 与正式公网下载核验仍单独待完成。

官网原版 1.0.1 经实际 Sparkle 窗口下载、安装并重启至该最终正式 DMG，见 [正式包升级回执](../engineering/quality/2026-11-14/actual-formal-sparkle-update.json)。这是隔离 ARM64 macOS 27.2 图形环境、私有正式密钥签名回环 feed 的真实安装，不是公开 feed 的验收。升级前后 12 条资产、5 条操作、3 条 START、旧 UNKNOWN、媒体、设置、反馈与目录书签精确保留；随后真实系统截图成为第 13 条，历史预览正常。旧 12 条资产不变，新截图后续按已有规则自动归档。最终 App 的 Chrome 连接检查为 Connected；不把书签相同当作全部 TCC 权限已验证。

源码 `624e1b5` 私有公证候选的三张真实 ChatGPT 附加、逐图 START／吞噬、正文与旧附件保留和重复点击检查仍按 [附件回执](../engineering/quality/2026-11-14/actual-chatgpt-attachment.json) 的范围继承。`positiveReady=false`；不宣称服务端最终 ready，也没有在正式升级后再次附加。更早源码 `31258e2` 的 [私有升级记录](../engineering/quality/2026-11-14/actual-private-sparkle-update.json) 保留原包身份，不替换为本次结果。

下一步仅收口签名 stable.xml 与官网部署，以及实际公网更新验收。个人安装与生产数据保持不变。公开状态按各通道实际回读更新；GitHub 发布不能自动标记官网和 feed 已上线。

未覆盖范围继续明确保留：完整 VoiceOver 语音、实体 Intel、最低 macOS、未执行的权限与多显示器组合。#83 远端保护是独立治理缺口；#95 永久删除未实施；PR #77 不属于本次已集成功能。没有将全部质量矩阵标为 PASS。

[原始审计](quality/ISSUE_REGISTER.md)、历次 FAIL／BLOCKED／NOT_RUN 及 [旧任务板](quality/history/docs_EXECUTION_BOARD.before-20261114.md) 均保留。
