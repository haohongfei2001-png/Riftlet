# Feedback v0.1 最小运维说明草案

仅覆盖专用 Feedback 服务；不修改 Riftlet 官网、DNS、品牌资产、截图服务或生产准入，不购买套餐。现有已授权资源优先复用。本说明本身不是实际部署或验收通过证明。

## 当前资源与停止点 · 2026-10-29 14:17 UTC

授权账户为 `b10365c5c641bd88cb1b9f35a4172d37`。专用 D1 `riftlet-feedback` 的 ID 为 `4167f4a2-5dfd-422d-86ca-077176fc8600`，已创建和初始化，限额观察为 daily=100、hourly=20。14:00:19.183Z 的独立 Console 查询确认 plain/diagnostic 两条原 ID/正文哈希的 pending 记录，均无 Issue 身份；后续三条测试身份的 D1 最终状态尚待独立核查。

业务 Receiver 已部署，`07497aa3` 曾被实际观察为 active；Secret/开关后续变更后的最终 active version 尚待读取。`DB` 已保存，Logs/Traces/Issues OFF，`ACCEPT_ENABLED=true`，32-byte 随机 `IP_HMAC_KEY` 已安全安装。实际 endpoint 为 `https://riftlet-feedback-receiver.haohongfei2001.workers.dev/v1/feedback`；实际 workers.dev 开启、compatibility date 为2026-10-29。早期 HelloWorld、0行及未保存 settings 属于历史检查点，不是当前状态。

真实HTTP累计36项通过；14:11:33的原lost_receipt授权GET返回received后，14:16:42–43对plain/diagnostic/lost逐条DELETE均202/deleted，14:16:54–55对原5ID各GET均200/deleted，但 Delivery 尚未创建；它的 cron、retention 执行和 GitHub 投递尚未验证。私有单仓库 Metadata read / Issues write token 已创建，2026-11-28 到期，只在授权浏览器会话内，尚未安装 Delivery。不给报告、源码或日志写入秘密，不把“token 已创建”写成“服务已授权投递”。

用户已登录正确账户。14:04 后浏览器控制连续 MCP 超时，14:12 最新结果明确为 `No connected browser was found`，控制台操作当前 BLOCKED；恢复连接后读取已保存设置和最新 active version，再继续同一资源，不重复 provision，不要求用户重复授权。

客户端 Host 仍为 nil。Receiver 的实际接收阶段不等于完整链路：只有同一部署的 Receiver→D1→唯一私有 Issue 及必要删除证据经审查后，才应用已准备的真实地址候选并重建 App。原生 Mac 验收尚未运行，也未安排执行器。

## 继续部署前的最小核对

复核 Receiver 最终部署 bundle/source hash 与 active version，不重复生成或打印已安装的 HMAC Secret。Receiver 不安装 GitHub 凭证。创建/复核唯一 Delivery 后部署精确 `delivery.mjs` 与 `contract.mjs`，绑定同一 `DB`，把现有最小权限 credential 安装为 Delivery-only `GITHUB_TOKEN`，目的仓库固定 `haohongfei2001-png/Riftlet-Feedback`。秘密不得进入源码、命令历史、公开截图/日志或客户端。

Delivery 初始明确保存 `DELIVERY_ENABLED=false`，关闭日志并保持无公开 route，核对实际 binding、`*/5 * * * *` cron 和环境。Receiver 当前已为测试启用，Wrangler的workers_dev/date/ACCEPT_ENABLED声明已与实际保存值对齐；Delivery计划配置仍为date2026-10-28/disabled且未部署。最终active version仍需读取。

完成最小权限/私有目的地核对后，仅在已授权测试范围启用 Delivery，执行有界真实验收并逐条登记清理义务。没有 cron 执行证据前，不声称90天 retention 已在云端自动运行。GitHub 仓库 private 是每批投递实际检查，不可为测试方便改成公开或去掉检查。

最终授权清理已经执行：原5ID均由HTTP报告deleted，未执行retry-dropped/新POST/重建身份/创建Issue。后续只读核查五个原ID的D1唯一墓碑、payload NULL、删除标志及无Issue身份；当前因无连接浏览器而BLOCKED，HTTP deleted不能替代独立查询或证明备份清除。不能再为这批已删除身份重试POST、重置pending或删除墓碑以复活。原私有测试状态仅以0700/0600暂留待root最终核验与清理，不复制到仓库；清理本地文件也不声称物理介质安全抹除。

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

授权仓库维护者逐条查看 `deletion_pending` 的已记录 Issue 身份，完成实际永久删除并核实后，才可把**这一条** D1 义务标为 deleted。写入时必须限制完整 feedback ID、原 issue number/node ID、`delete_requested=1`、`payload IS NULL` 和当前 deletion_pending 状态，保存原观察/结果；不执行整类状态强制更新。未知结果且没有 Issue 身份的记录不能仅凭一次空列表结案。

七天为现有运维响应目标，不是已经建立的自动履约保证。交付需明确实际负责删除的维护者及访问条件。每条测试反馈也必须有删除完成证据或仍待处理的义务记录。

当前账户的 D1 backup/Time Travel 保留窗口尚待实查。正文在线清空不证明所有备份立即消失；对用户必须准确解释此限制。任何数据库历史恢复前先停止新接收和 GitHub 投递，保留当前 tombstones/已创建 Issue 对应记录，核对恢复数据中的原身份与远端现状；不能把旧 pending 行直接放回定时投递，否则可能重建曾经存在的 Issue。

## 有界测试与证据

`services/feedback/acceptance/cloud_acceptance.py` 是真实 HTTPS 服务验收辅助脚本。`prepare` 只准备合成文字/诊断和原单条凭证，不发网络请求；私有状态目录为 0700、文件为 0600，不能入库。后续 send/validate/status/delete 等命令须明确使用已准备的同一目录，不能为重试另生成身份。

脚本输出 HTTP 状态、受控结果和测试 ID，不输出正文、凭证、任意错误原文。实际 D1 查询、GitHub private 检查、完整分页的唯一 Issue 核查，以及永久删除证据仍由操作者独立获取。脚本合成诊断不等于真实 Mac 业务事件诊断；脚本通过不等于原生窗口端到端通过。

最终运维交接最少包含 source SHA、Receiver/Delivery 部署版本、实际开关/route/cron、D1 ID/limits、私有仓库 ID、Secret 权限与安装状态的非秘密证明、一次原始接收/唯一投递/删除对应链、剩余义务以及最小恢复步骤。准备交给 Codex 的真实 Mac 清单见 `CODEX_REAL_MAC_E2E.md`；尚未设置后续自动执行器。
