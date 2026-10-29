# Feedback 源码与实际部署配置核对表

用于集成人继续完成当前已有资源。当前切面为2026-10-29 14:17 UTC，来源是集成人实际平台操作、36项真实HTTP事件，以及14:00:19.183Z的独立D1查询。以前13:25零行、HelloWorld及未保存设置保留为历史；当前业务Receiver已运行，但Delivery尚未创建。未核实项不能写成已部署或通过。

## 一、源码身份

| 文件/集合 | 当前应有内容 | 纳入正式证据时核对 |
| --- | --- | --- |
| `receiver.mjs` + `contract.mjs` | 原严格输入白名单、有界正文、单条授权、D1 持久后回执；业务bundle已部署 | 已观察业务版本前缀07497aa3当时active；补最终active version、bundle哈希与source SHA，两个模块同一已审查版本 |
| `delivery.mjs` + `contract.mjs` | 一次 claim/POST、未知结果核对、删除义务、fair ordering `checked_at,created,id` | 实际部署模块全量哈希、入口和最终 source SHA |
| `schema.sql` | 原表/trigger + `feedback_live_expiry`、`feedback_state_created`、`quota_expiry` | 仅专用远端 D1 上的表、索引、trigger 与应用版本相符；不运行 DROP/reset |
| `feedback.test.mjs` + `retention.test.mjs` | 21 项本轮本地回归保留，包括真实五分钟间隔的饥饿回归 | 固定测试日志、commit/blob、独立审查身份；不冒充真实 Cloudflare |
| 两份 `wrangler.*.jsonc` | account/D1 ID已填写；Receiver声明已对齐真实date2026-10-29/workers_dev=true/ACCEPT_ENABLED=true | Delivery仍只是date2026-10-28/false计划配置，未部署；最终Receiver active version仍待读取 |
| `Sources/RiftletApp/FeedbackHost.swift` | 当前仍 nil | 云端真实私有仓库链路经审查前保持 nil；之后只配置公开 HTTPS literal |
| 四个包装支持文件 | 已采用 source-bound manifest，13 项本地/独立回归通过 | 最终源码及 `--repository` 包装日志；不只引用无 repository 的结构校验 |
| `acceptance/cloud_acceptance.py` | 有界真实HTTPS脚本，原identity/body/capability私有持久保存；36项HTTP通过，含最后3DELETE+5GET清理 | 保存每个执行阶段脚本hash和36项原始HTTP检查；三次drop为不同实际结果，未执行原反馈retry；D1/Issue观察分开 |

## 二、云资源实际值

| 设置 | 已核实或要求值 | 当前实证状态 |
| --- | --- | --- |
| Account | `b10365c5c641bd88cb1b9f35a4172d37` | 已登录授权账户；不得把连接停滞写成缺授权 |
| D1 name / ID | `riftlet-feedback` / `4167f4a2-5dfd-422d-86ca-077176fc8600` | 已创建并初始化 |
| D1 limits | `daily=100`, `hourly=20` | 13:25:39Z 已读到；再次部署 schema 的 `INSERT OR IGNORE` 不应覆盖现有这行 |
| D1 records | 14:00:19.183Z确认plain/diagnostic两条pending，原hash一致、无Issue | 这是该次独立查询；14:16原5ID的HTTP最终状态均deleted；独立D1 payload NULL/flags/唯一墓碑仍BLOCKED，不能仍写0行或把2当最终总数 |
| Receiver name / public host | `riftlet-feedback-receiver` / `riftlet-feedback-receiver.haohongfei2001.workers.dev` | 业务Receiver已真实运行；旧HelloWorld为历史 |
| Receiver business version | 曾观察`07497aa3` active | 后续Secret/flag变更产生的新最终active version尚待读取；不能把短前缀说成最终完整ID |
| Receiver `DB` | 上述专用 D1 | 实际binding已保存 |
| Receiver Logs / Traces / Issues | OFF / OFF / OFF | 集成人实际平台观察；不是未保存草稿状态 |
| Receiver `ACCEPT_ENABLED` | 字符串 `true` | 已保存并真实接收测试；仅测试范围，不等于App已启用 |
| Receiver `IP_HMAC_KEY` | 随机32-byte服务器Secret | 已安装；不读取/打印明文，也不为恢复重复生成 |
| Receiver route / compatibility | HTTPS `/v1/feedback`；workers_dev=true；date2026-10-29 | 实际公开业务路由可达；Receiver源码部署声明已对齐，最终active version待查 |
| Delivery name / route | `riftlet-feedback-delivery`；预定无公开route | 截至14:12尚未创建；恢复后先查inventory再唯一创建 |
| Delivery modules / D1 | `delivery.mjs`, `contract.mjs`；同一专用DB | 未部署 |
| Delivery `DELIVERY_ENABLED` | 初次配置先字符串 `false` | 资源尚不存在，没有可声称已保存的值 |
| Delivery cron | 预定`*/5 * * * *` | 尚未配置/执行，不能宣称投递或retention已运行 |
| Delivery `GITHUB_REPOSITORY` | `haohongfei2001-png/Riftlet-Feedback` | 源码已限定；实际环境和 GitHub private 身份待最终核实 |
| Delivery `GITHUB_TOKEN` | 仅独立私有1仓库、Metadata read / Issues write；2026-11-28到期 | 已创建，当前只在授权浏览器会话内，未安装Delivery；不把权限元数据当安装证明，不输出值 |
| 私有仓库 | repository ID `1437354611`；private；Actions disabled | 此前核实记录存在；正式开始投递前再读取真实值 |
| Backup / Time Travel | 实际保留窗口及恢复约束 | 尚无本轮账户配置实证，不填猜测天数或“立即抹除全部备份” |

14:04后浏览器控制连续MCP超时，14:12最新结果为`No connected browser was found`；用户已登录正确账户，当前是缺可连接浏览器的执行阻塞，不是缺授权。恢复后先读实际已保存配置与最终active version，避免重复创建资源或沿用旧草稿。早期Logs/DB/flag未保存的不确定性已经被后来的实际设置观察更新；旧观察保留在历史检查点。Secret值、Authorization、正文和原始IP不能出现在公共截图/日志中。

## 三、非 Mac 真实服务验收的证据组合

| 验收 | 必须一并记录 | 不能代替它的东西 |
| --- | --- | --- |
| HTTPS 接收 | 原28项 + 最终3DELETE/5GET=36 HTTP PASS；5ID最终HTTP均deleted，原始事件见`live-http/events.jsonl` | HelloWorld 200、仅控制台“部署成功”、把HTTP响应数当唯一反馈数 |
| D1 持久 | 14:00两条原ID/payload hash/pending的独立Console证据已取得；其余身份待补 | 单独Receiver 202；写出请求字节 |
| 输入/幂等 | 非法字段、超限、错凭证、同 ID 内容冲突、原文重试实际响应及 D1 不变性 | 本地 D1 adapter/mock HTTP |
| 限额 | 当前 limits 行、真实配额行为及恢复后的值 | 仅源码默认 1000/20；当前环境实际为 100/20 |
| 私有唯一投递 | private repo 身份、实际 Issue number/node ID、原 marker/body 一致、完整 state=all 列表无第二条 | 仅 D1 state=delivered 或 Issue 标题看起来相同 |
| GitHub 201 丢响应 | 真实创建后返回结果未知、后续只核对原 Issue、不第二次 POST | 在本地直接把状态设为 delivered |
| 删除竞态 | 原四项删除场景及最终3DELETE/5GET均通过；5ID HTTP deleted。D1 tombstone/payload NULL/flags独立查询BLOCKED；无Issue创建，GitHub永久删除NOT_RUN | HTTP `deleted`、关闭Issue、清空本地表、无Issue的有限搜索结果 |

丢回执的三次真实尝试必须分别保留：13:53:13 `gaierror`、字节未写出；14:01:17 写出后立即close，集成人随后观察D1无行；14:06:45 写出后等待三秒且未读原回执；14:11:33另一次授权GET返回200/received/durable=true，独立D1 hash/count仍待查。三次使用同一原ID与payload hash；未执行retry。14:16最终清理后5ID均HTTP deleted，后续只做独立D1只读核验，不再重试或复活这些身份。不能把前两次改写成“D1成功后丢回执”，也不能用第三次的本地写出断言持久成功。

验收脚本的合成诊断只能证明服务接收白名单，不证明原生窗口已基于真实业务事件生成诊断。脚本 `verify-issues` 依赖操作者提供真实完整分页观察；不得把 fixture JSON 当 GitHub 实际证据。

## 四、最终源码与正式 App

把真实资源 ID、配置说明、源码修复与本轮证据纳入 source commit 后，非作者审查准确差异；审查后继只更新现有 fixed-source pin 及既定 metadata，原审计例外不扩大。已有 gate `REVIEWED_SOURCE=683aefb46b7ed774674a3dd2e6199868952b7b46` 不能直接批准本轮新差异。

最终需补：source SHA、reviewed tree/blob、CI runs、Receiver/Delivery version IDs、云端接收样例 ID、唯一私有 Issue 和清理结果、统一 Beta artifact URL/哈希/签名。真实 Mac 接管准备文件为 `CODEX_REAL_MAC_E2E.md`；没有已安排的自动执行器。
