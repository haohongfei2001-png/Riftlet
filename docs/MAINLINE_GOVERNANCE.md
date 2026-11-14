# Riftlet 当前主线准入

更新：2026-11-14。本次只精简当前操作说明，**不改变任何gate、workflow、生产能力字段或历史证据**。[旧全文](quality/history/docs_MAINLINE_GOVERNANCE.before-20261114.md)保留其适用的历史事实，不再作为待执行阶段。

## 当前源和授权

`main`是唯一正式工程源；最新版公开Release是发行基线，二者分别核对。当前用户授权全面质量调查、设计裁决、GitHub文档/Issues及由Codex实施修复、独立复核。审计文件提交不等于应用更新或发布授权。候选PR不是主线事实。

使用短期分支，常规双父merge；不直接push main，不force、不squash/rebase、不覆盖其他人的工作。独立工程review不是GitHub真人APPROVED，不得混称。

## 保持现有 B / G / H 流程

1. 读取实际main **B**，从B建立短期分支。解决当前增量与B的整合，保留其他候选。
2. 提交完整源码/文档checkpoint **G**。原 `engineering/mainline/source-admission.json` 已存在，但旧内容不准入G。
3. 非作者审查B→G的完整变更与证据，输出原文UTF-8 JSON，至少含 `reviewedSource`、`reviewedTree`、`reviewer`、`result:"PASS"`。不得自报另一身份或只按HEAD自动通过。
4. 形成 **H**：G的直接单父子提交，**只修改准入JSON**。记录确切B/G/tree、作者与不同审查角色、原文report及SHA-256；保留当前productionAdmission。
5. 正式Native/Feedback在GitHub实际PR测试合并上执行；合并父必须 `[B,H]`，树与H相同，除准入外全树与G一致。事件repo/ref/base/head、源文件字节与mode全部匹配。不得加入skip、continue-on-error或门禁旁路。
6. 独立复核H仅准入差异及所有正式结果后常规merge。如果main变动或源码修改，形成新的G并重新审查/准入，不能用旧B/G冒充。
7. 核对真实main merge、双父、before/after与push CI。没有远端保护时，CI是事后检测，不能阻止坏push先到main。

本地准入检查：`python3 -B scripts/verify-mainline-composition.py H`。正式工作流额外带 `--github-event`。源码检查所需checkout须干净；只有既有 `test-results/` / `feedback-results/` 报告根与Git元数据排除，不能新增豁免目录。当前机器缺macOS不授权跳过远端Native。

## 五项正式检查

| 检查 | 职责 |
|---|---|
| Native source admission | 当前确切源码、实际合并与冻结历史校验 |
| Native ARM64 | ARM64当前原生测试与打包 |
| Native Intel | Intel当前原生测试与打包 |
| Feedback source admission | 同一准入协议 |
| Feedback native and service | 反馈原生/服务与故障回归 |

所有main push与指向main的PR（包括文档）继续运行现有检查。历史固定blob、`engineering/evidence/`、`research/`和已准入证据不重写；纠正旧结论用新记录。网站冻结对象或签名feed变更另做明确政策/发行审查。本次质量文档没有修改它们。

## 远端边界与独立身份

2026-11-14实际读取：main `protected:false`，rulesets为空。`engineering/mainline/branch-protection.request.json` 是拟定请求，不是生效证据。见 [QA-GOV-002](quality/ISSUE_REGISTER.md)。当前GitHub连接的普通仓库权限不能自动视为Repository Administration权限。

有受支持的管理能力时，先核对真实五项check名称、GitHub Actions app ID 15368及可履行的独立GitHub审批身份，再应用/读取保护。既有请求要求最新push非作者审批、过期审批撤销、conversation resolution、管理员适用，并禁止force/deletion。不能假造身份、暂时关闭保护或静默削弱要求；身份/权限缺口单列，其他工程继续。

准入JSON中的hash只证明内容与记录一致，不证明审查者身份。不得把自动生成的声明当成安全边界；真实非作者审查与远端保护各自需要证据。

## 发行与真实验收

CI的开发包不等于Developer ID公证发行。签名、公证、feed、实际下载、数据兼容与真实原生/ChatGPT体验分别验收；见 [质量矩阵](quality/ACCEPTANCE_MATRIX.md)、[发行流程](release/DIRECT_DOWNLOAD.md) 与 [Sparkle流程](release/IN_APP_UPDATES.md)。缺环境只记录受影响的格，不伪造通过、不动生产库。
