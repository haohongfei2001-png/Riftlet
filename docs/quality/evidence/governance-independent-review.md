# 当前治理精简独立复核

日期：2026-11-14（Asia/Shanghai）。审查者：settings_audit（非这些根文档的作者）。基线：`44f745a15ecb3682a9da0bda17f17a5d9fc1f07e`。审查对象为工作区待提交文档，不是最终G源码准入。

## 结论：PASS

根代理的新AGENTS、主线治理、产品约束、决策入口与执行入口，将已发布事实和当前质量任务从历史阶段限制中分开，没有放松B/G/H、五项正式CI、数据与发行保护。根决策仍将未实现方案写为“应/裁决/须验收”，未把新的设置IA或历史标签说成已经发布。当前范围没有发现必须阻止文档PR的安全退化。

最终提交G形成后，仍需核对完整B→G文件清单、源码树、链接和确切内容，再生成准入所用的reviewedSource/reviewedTree JSON；本报告不能代替最终SHA准入。

## 已检查范围

- `AGENTS.md`
- `docs/MAINLINE_GOVERNANCE.md`
- `docs/PRODUCT.md`
- `docs/DECISIONS.md`
- `docs/EXECUTION_BOARD.md`
- `docs/quality/DECISIONS.md`
- `docs/quality/ENGINEERING_DEBT.md`
- `docs/quality/history/`五份原文快照与`manifest.json`
- 对照`engineering/mainline/source-admission.json`及当前只读baseline evidence，确认没有变更准入能力字段或伪称远端保护已启用。

## 保留边界核对

| 范围 | 结果 | 证据/判断 |
|---|---|---|
| B/G/H源码准入 | PASS | 当前main B；完整G；非作者原文JSON；H只改准入且单父直接后继；精确tree/source/report SHA；main变更后重做准入仍明确 |
| 实际合并与事件 | PASS | `[B,H]`顺序双父、GitHub实际PR合并树、repo/ref/base/head、文件字节与mode一致；无直接main push/force/squash/rebase |
| 五项CI | PASS | Native source admission / Native ARM64 / Native Intel / Feedback source admission / Feedback native and service均保留；文档PR也执行，无skip或continue-on-error |
| 历史证据 | PASS | engineering/evidence、research、既有冻结objects不重写；旧结论按旧SHA；纠错用新记录 |
| 真实权限与远端保护 | PASS | main protected:false / rulesets空仅为2026-11-14观测，未把request JSON说成已生效；不能伪造身份或静默弱化审批要求 |
| 数据 | PASS | 原件只读、现库不重建、不回放/清理UNKNOWN、不删private media、不用旧backup覆盖最新库；journal/hash/identity/迁移/锁和凭证保留 |
| 发行 | PASS | 本PR无新二进制、正式下载/feed/签名keys不变；开发CI不冒充Developer ID/公证发行；发布与真实功能分别验收 |
| 产品方向 | PASS | 三形态/托盘2×2/原点击目标/用户自己发送保留；PR69仍候选；START不升READY，呈现不授retry |
| 证据诚实性 | PASS | Source/controlled/native/real-service/signed-release区分，NOT_RUN/BLOCKED保留；没有声明Codex后台执行已启动 |
| 新流程成本 | PASS | 当前任务只有一个QA-ID/Issue系统，旧任务板成为历史入口；未新增全产品签字/用户反复审批仪式 |

## 原文归档验证（实际执行）

对每份manifest记录执行`git show 44f745a:<originalPath>`，与archivePath字节比较，并核对archive SHA-256；五份均EXACT/HASH_OK：

- AGENTS.md
- docs/MAINLINE_GOVERNANCE.md
- docs/PRODUCT.md
- docs/DECISIONS.md
- docs/EXECUTION_BOARD.md

实际`git diff 44f745a --name-only`核对以下范围均UNCHANGED：`scripts/`、`Sources/`、`Resources/`、`Package.swift`、`.github/workflows/`、`engineering/evidence/`、`research/`、`website/`、`engineering/mainline/source-admission.json`。`git diff --check`没有输出。

## 最小文字修正建议（非阻断）

1. **原生GUI截图的许可更精确。** AGENTS当前“Public commits/Issues contain no real screenshots”容易被后续AI解释为连合成素材的真实原生App实拍也不能提交，与本次视觉证据要求冲突。建议改为禁止真实用户截图/私人聊天/敏感数据，并明确允许使用合成测试内容的原生GUI截图。不能放松任何私人信息保护。
2. **避免给动效虚构批准身份。** PRODUCT“批准的两种动效”可改“现有两种出现动效选项”。代码对none/magnet和默认值仍有provisional历史注释，保留当前行为即可，不必新写为用户明确批准。
3. **最终G核对链接。** 当前工作区中的ITERATION_STATUS.json、CODEX_HANDOFF.md、ISSUE_REGISTER.md、ACCEPTANCE_MATRIX.md尚在由作者补全；最终G必须全部存在并能相对解析。此为提交完备性检查，不应变成新的流程。

没有要求修改生产代码、松动CI、迁移数据或新开用户确认。此结论仅覆盖上述治理精简文档；最终质量判断仍受已知P0/P1和真实验收缺口约束。

## 后续修正复核：PASS（2026-11-14）

按作者完成后的工作区重新读取，前述两项非阻断措辞建议均已落实：

- AGENTS现在准确禁止 `real user/private screenshots` 等私人内容，同时明确 `Native UI captures using synthetic fixtures are allowed as review evidence`，未放松私人信息保护，也不会误阻断原生视觉证据。
- PRODUCT现在使用“现有两种出现动效选项”，没有再赋予历史默认/实现并不存在的用户批准身份。

前述尚在生成的README、AUDIT_REPORT、CODEX_HANDOFF、ISSUE_REGISTER、ITERATION_STATUS、ACCEPTANCE_MATRIX现均存在；对本报告审查范围内Markdown相对链接实际检查，未发现缺失目标。本地问题登记含22条独立Issue链接，编号78–99；本地状态统计为P0=1、P1=4、P2=15、P3=2，QA-GOV-002按作者校准归入P2。此处只核对本地登记与状态一致，不替代根代理的远端Issue创建回读证据。

状态文件仍写 `overallAcceptance: NOT_ACCEPTED`、`productEngineeringState: AWAITING_CODEX_EXECUTOR`，没有用文档完成冒充产品修复或真实Codex派发。

**最终结论维持PASS。** 本报告及追加为治理专项非作者复核。最终G的全量B→G和准入JSON将由未参与编写这些文档的独立审查者核验；本报告不自我签发最终源码准入。
