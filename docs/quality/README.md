# Riftlet 1.0 质量重整

第一版完整审计：2026-11-14。正式版本 **1.0.1（23）**，审计 main **44f745a**。

**当前实现：[PR #101](https://github.com/haohongfei2001-png/Riftlet/pull/101)，整体成熟度验收仍为 NOT_ACCEPTED。** R1修复、四页设置、历史交接状态、性能和核心双语已实施，分别有源码、受控测试和原生证据；当前事实见[工程进度](../../engineering/quality/2026-11-14/progress.json)和[逐项状态](ITERATION_STATUS.json)。不得把首版全部OPEN或旧的“等待执行器”当作现在的工作状态，也不能把CI通过当作真实附件或升级通过。

首版审计在2026-11-14记录22项发现：1项受控复现P0、3项核心源码确认P1，以及正式包真实附件验收一项P1缺口；不是22项都已在真机复现。原审计、findings、台账与原始证据保留当时结论和字节。本次复用来源为PR #100审核源码`67fb373d`，后续修复不改写原失败。

## 从这里继续

| 目的 | 文件 |
|---|---|
| 继续当前实现、核对源码及已执行证据 | [PR #101](https://github.com/haohongfei2001-png/Riftlet/pull/101) · [工程进度](../../engineering/quality/2026-11-14/progress.json) |
| 了解结论、基线与证据限度 | [审计总报告](AUDIT_REPORT.md) |
| 找到唯一问题ID、GitHub Issue与优先级 | [问题台账](ISSUE_REGISTER.md) |
| 接手实现、分包、验收和退回 | [Codex工程交接](CODEX_HANDOFF.md) |
| 看当前轮次、实际执行与下一步 | [机器可读迭代状态](ITERATION_STATUS.json) |
| 检查每项用户流程与真实覆盖 | [验收矩阵](ACCEPTANCE_MATRIX.md) |
| 核对已实施设置、首用、权限与文案的原规格 | [设置设计规格](SETTINGS_REDESIGN.md) |
| 复核正确目标、一次输入、重启和状态 | [附件专项](ATTACHMENT_AUDIT.md) |
| 复核存储恢复、历史和维护成本 | [存储专项](STORAGE_AUDIT.md) |
| 识别真正减负与不能删的保护 | [工程债务](ENGINEERING_DEBT.md) |
| 避免下一位AI再猜产品意图 | [当前裁决](DECISIONS.md) |
| 复跑或检查原始结果 | [证据索引](evidence/README.md) |
| 核对被替换的历史指令原文 | [历史清单](history/manifest.json) |

## 状态约定

Issue是缺陷讨论与关闭记录；`ITERATION_STATUS.json`概括当前轮次及下一动作，精确执行证据由既有`engineering/quality/2026-11-14/progress.json`维护；`findings.json`与台账提供可检索的首版证据和排序。它们使用相同QA编号，不另建平行任务。后续修复更新现有Issue和状态，不把首版基线证据改成“已通过”。

Codex已在隔离Mac开展原生验证。当前继续真实私有签名feed的23→24更新；#82独立浏览器网络阻塞、#83治理条件、#92未覆盖的硬件/VoiceOver范围分别保留。#95只读容量已实现，永久清理必须先完成独立语义审查。PR #77安装提示仍未集成到本PR。没有公开新版本或替换个人安装，也不要求用户代替测试。
