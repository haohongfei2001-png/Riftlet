# Feedback v0.1 最小运维说明

仅管理专用Feedback资源，不修改官网/DNS/品牌/截图准入、不购买付费升级。

## 当前服务与已完成测试清理 · 2026-10-29 15:39 UTC

Receiver `https://riftlet-feedback-receiver.haohongfei2001.workers.dev/v1/feedback`，最终版本39f6277e-11f2-455b-be27-8f0b6a795685；普通Delivery版本`3c749b91-ace3-45d9-86e5-62e2dab06c35`，bundleSHA256`0236e5582362b1f74d21aad2ab04ef0d3333fed75f3e49fd7d924ccbef8ce7db`，6356bytes已UI逐字比对/独立重建。DB为riftlet-feedback/4167f4a2-5dfd-422d-86ca-077176fc8600，cron每5分钟，无Delivery公开route，日志关闭，临时注入/变量/probe表均已移除。真实503、429原子回滚、原身份重试和3唯一私有Issue已核验。

三条Issue经owner实际永久删除与独立有权限410/完整空列表核实，再按精确原行/Issue身份guardedSQL结案。15:39 D1为8行deleted、body0、pendingDelete0、probe0、100/20；三条原凭证GET全部200/deleted/durable=true。远端合成测试正文/Issue义务已完成；保留无内容墓碑及原Issue身份，不重置或复活旧ID。原始证据和时间顺序见[README](README.md)。

诊断实际创建→uncertain→普通cron认回原Issue且删除意图不倒退已有实证；诊断HTTP201/注入分支无直接捕获，运维记录不得夸大。临时私有验收凭证文件由集成人在必要核验结束后单独处理，公开证据不含值；真实Mac SQLite/Keychain清理尚未验收。

Actions当前disabled由14:50Disable/Save/reload证实，14:49实际仍enabled。GitHub Secret仅单私库Metadata read/Issues RW，2026-11-28到期；有权维护者需到期前轮换、安装并核实，不表示已设置自动轮换执行器。D1实际可恢复窗口过去7天（未restore），不是即时备份擦除保证。

云端最终独审已通过，集成人已实际应用唯一一行固定公开URL接线；源码已配置真实接收，不能据此声称每条反馈已收到。准确新source、实际CI和统一包引用从[正式定值元数据](../2026-10-29-final-product/results.json)与[PR #1最终交接](https://github.com/haohongfei2001-png/Riftlet/pull/1)解析；H旧包不追溯启用。Mac连接/真实窗口/截图操作准备交Codex，NOT_RUN，无执行器。

## 日常只读观察

从已授权控制台或目的明确的工具读取专用 D1，尽量只看计数、状态和时间；禁止查看或导出非测试反馈正文、凭证、原始 IP 来排障。以下是无正文的基本检查：

```sql
SELECT id, daily, hourly FROM limits WHERE id = 1;
SELECT state, COUNT(*) AS reports, MIN(created) AS oldest_created,
       MIN(checked_at) AS least_recent_check
FROM feedback GROUP BY state ORDER BY state;
SELECT COUNT(*) AS live_payloads FROM feedback WHERE payload IS NOT NULL;
SELECT COUNT(*) AS unresolved_deletions FROM feedback WHERE state = 'deletion_pending';
SELECT COUNT(*) AS quotas FROM quota;
```

追踪一条已授权测试记录时，使用完整 UUID 选择该行，记录状态、issue number/node ID、时间、payload 是否为空和测试正文 digest。不要执行整库正文 dump。验收脚本的 `d1-query` 可生成仅针对五个已创建合成测试 ID 的只读查询；私有状态文件中的访问凭证不得提交 Git。

对 uncertain 的处理必须保持原创建身份。一次创建已 claim 或结果未知后，不把它重新设为 pending，不因有界列表暂时查不到 Issue 就再建一条。新的公平排序只改变轮询先后，不赋予重发创建权限。

## 暂停与故障处理

- 暂停新接收：在实际 Receiver 设置保存 `ACCEPT_ENABLED=false`，读取并验证已生效。现有授权 GET/DELETE 路径按源码继续处理；客户端保留待发送身份。
- 暂停 GitHub 写入：保存 `DELIVERY_ENABLED=false` 并核实。保留已部署定时 Worker 的 retention 执行；当前源码在投递开关之前执行保留/清理逻辑。完全移除 cron 会影响 retention，不能当作等价暂停。
- 不为恢复服务删除反馈表、quota、tombstone、原凭证或 UNKNOWN。网络故障/丢回执按原身份继续；不声称失败或成功已知。
- 回退代码需选取已审查、与当前 schema 兼容的版本，并保持当前 D1 数据与删除义务；记录实际回退版本。历史数据库恢复另按下节处理，不能把普通代码回退和数据回滚混同。
- 如发现令牌泄露，关闭受影响写入口并由授权管理员轮换对应服务器 Secret。报告只记录名称、时间及安装结果，不记录值；不顺带扩大权限。

上述开关操作都必须有保存后读取或请求行为证据；控制台暂存面板不算成功。

## 删除与保留

现有源码对 D1 正文/诊断设 90 天保留。未投递到期记录为 expired；已投递或未知结果到期清空 D1 内容并保留远端删除义务。无内容的已删除/从未投递到期 tombstone 最长保留约一年；未解决的 deletion_pending 不自动清除。具体状态以当前部署源码和 D1 为准。

删除请求会先清 D1 正文并阻止新投递。若 GitHub POST 可能已开始，仍需核对并永久删除实际私有 Issue。关闭 Issue、编辑成空白或只删除本地内容都不等于远端永久删除。

授权仓库维护者逐条查看 `deletion_pending` 的已记录 Issue 身份，执行实际永久Delete issue，并用同一有权限连接成功读取正确private仓库、核查准确Issue返回410 Gone且provider明确deleted、完整state=all列表中不存在原Issue；结合原身份/owner操作完成核验后，才可把**这一条**D1义务标为deleted。原404-only预期已更正；任意错误、401/403、断网、单独404或仅open过滤列表不算删除证明。写入时必须限制完整 feedback ID、原 issue number/node ID、`delete_requested=1`、`payload IS NULL` 和当前 deletion_pending 状态，保存原观察/结果；不执行整类状态强制更新。未知结果且没有 Issue 身份的记录不能仅凭一次空列表结案。

七天为现有运维响应目标，不是已经建立的自动履约保证。交付需明确实际负责删除的维护者及访问条件。每条测试反馈也必须有删除完成证据或仍待处理的义务记录。

集成人14:58在已登录D1 Time Travel页面读到past 7 days，未restore。在线正文清空不代表过去7天可恢复历史已清，也不证明物理备份立即消失；对用户必须准确解释此限制。任何数据库历史恢复前先停止新接收和 GitHub 投递，保留当前 tombstones/已创建 Issue 对应记录，核对恢复数据中的原身份与远端现状；不能把旧 pending 行直接放回定时投递，否则可能重建曾经存在的 Issue。

## 有界测试与证据

`services/feedback/acceptance/cloud_acceptance.py` 是真实 HTTPS 服务验收辅助脚本。`prepare` 只准备合成文字/诊断和原单条凭证，不发网络请求；私有状态目录为 0700、文件为 0600，不能入库。后续 send/validate/status/delete 等命令须明确使用已准备的同一目录，不能为重试另生成身份。

脚本输出 HTTP 状态、受控结果和测试 ID，不输出正文、凭证、任意错误原文。实际 D1 查询、GitHub private 检查、完整分页的唯一 Issue 核查，以及永久删除证据仍由操作者独立获取。脚本合成诊断不等于真实 Mac 业务事件诊断；脚本通过不等于原生窗口端到端通过。

最终运维交接最少包含 source SHA、Receiver/Delivery 部署版本、实际开关/route/cron、D1 ID/limits、私有仓库 ID、Secret 权限与安装状态的非秘密证明、一次原始接收/唯一投递/删除对应链、剩余义务以及最小恢复步骤。准备交给 Codex 的真实 Mac 清单见 `CODEX_REAL_MAC_E2E.md`；尚未设置后续自动执行器。
