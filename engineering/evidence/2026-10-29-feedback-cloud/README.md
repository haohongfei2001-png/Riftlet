# Feedback v0.1 真实云端服务交付证据

## 最终云端检查点 · 2026-10-29T15:39:38.614578Z

**服务端真实接收、D1持久化、三条唯一私有Issue投递、原Issue迟到协调和测试反馈删除已经完成有范围的真实验证。全部8条测试记录的active正文为空、状态为deleted；创建的3个私有Issue已由owner永久删除并独立核实。真实Riftlet原生窗口端到端仍NOT_RUN，不能宣布Feedback v0.1真实原生端到端交付完成。**

本记录只覆盖实际服务脚本与云端操作，诊断为合成白名单。云端服务终态已通过[非作者启用门禁](host-activation-gate/decision.json)，集成人已实际将Host唯一一行从nil改为固定真实HTTPS endpoint，其他Host字节未改。**源码已配置真实接收；配置本身不表示某条反馈已接收或投递。** 准确新源码、实际CI和对应统一App包从[正式工程定值元数据](../2026-10-29-final-product/results.json)和[PR #1最终交接](https://github.com/haohongfei2001-png/Riftlet/pull/1)解析；本页不预测SHA或未运行结果。Mac连接与实际窗口/截图操作按用户决定准备交给Codex，未设置执行器。

## 实际资源、部署与运维边界

| 项目 | 最终已观察值 / 范围 |
|---|---|
| Cloudflare账户 | `b10365c5c641bd88cb1b9f35a4172d37`，现有授权有效 |
| 专用D1 | `riftlet-feedback` / `4167f4a2-5dfd-422d-86ca-077176fc8600`；实际daily100/hourly20 |
| Receiver | `https://riftlet-feedback-receiver.haohongfei2001.workers.dev/v1/feedback`；最终版`39f6277e-11f2-455b-be27-8f0b6a795685` |
| Delivery | `riftlet-feedback-delivery`；最终普通版`3c749b91-ace3-45d9-86e5-62e2dab06c35`；cron `*/5 * * * *`；无公开route |
| Delivery生产bundle | SHA256 `0236e5582362b1f74d21aad2ab04ef0d3333fed75f3e49fd7d924ccbef8ce7db`；6356bytes；UI源复制逐字一致、独立重建字节一致 |
| 最小权限 | Receiver仅IP_HMAC_KEY；Delivery仅私库Riftlet-Feedback的Metadata read/Issues RW；token2026-11-28到期；不含秘密值 |
| 日志与临时诊断 | Logs/Traces/Issues关闭；临时变量已删除并实读；普通bundle无测试注入，D1临时probe表为0 |
| 私有目的仓库 | `haohongfei2001-png/Riftlet-Feedback`，ID1437354611，private；唯一专用反馈仓库 |
| Actions | 14:49实际仍enabled；14:50选择Disable actions、Save并reload后确认disabled；不沿用创建时即已禁用的旧假定 |
| 备份限制 | 14:58已登录D1 Time Travel页面显示过去7天，未restore；在线清空不等于该可恢复历史清除或物理备份即时删除 |
| 范围 | 免费资源，未升级套餐，未改DNS/官网/品牌/main/截图准入 |

生产bundle审查：[production-bundle-independent-review.json](production-bundle-independent-review.json)。 当前Actions禁用、D1过去7天恢复窗口及普通Delivery变量表的[直接UI读回](final-operational-ui-readback.json)另行归档；较早操作时间保留为操作者记录。到期前轮换token是有权维护者的运维义务，没有设置自动轮换执行器或定时用户任务。恢复D1历史前必须暂停投递并核对既有Issue与删除墓碑，避免恢复旧pending造成重复创建。

## 实际投递阻断修复

Workers运行时在发送GitHub请求前拒绝两处`redirect:error`。最小修复为`redirect:manual`，保留不跟随跳转、目的仓库private核验和一次创建意图。三项新回归分别覆盖仓库门禁、未知结果核对及Issue创建跳转，每项检查301/302/307/308。

[独立决策](redirect-manual-fix/decision.json)与原日志证明：旧源码21 PASS/新3 FAIL；修复后24项具名本地测试PASS。24是本地已执行回归，不是尚未产生的C2/H2 CI。H已完成服务CI仍为21。所有原失败保留。

## 真实接收、持久化、幂等与预算

最终去重归档合并两份主事件日志一次，共64条唯一事件：54/54实际HTTP合同检查通过、4次原始丢回执尝试（含1次写出前DNS失败）、两次独立完整列表的6项正文核验。实际创建Issue为3个，最终deleted精确语义另有3/3断言；不把正文核验次数写成6个Issue，也不把失败drop改写成HTTP成功。最终events SHA256 `839473fea9af437543a4a5b6c585338f4225012134e8004589d50d4bcbd0cdda`；见[最终安全归档](final-acceptance/summary.json)。

14:53:12.901Z直接D1确认第二批三条原ID各一行、原正文hash一致；客户端丢回执身份`2b2dd0e6…`在14:53:48使用原ID/凭证/正文重试，14:54:22.535Z仍一行，created=1793285562和hash不变。真实503阻止新接收而授权GET继续可用；真实429之后拒绝ID无行、反馈行数和日配额计数均不增加，100/20限额已恢复。

证据：[控制台观察](control-plane-live-observations.json)、[阶段HTTP](delivery-phase/post-client-retry-events.jsonl)、[开关](delivery-phase/kill-switch-summary.json)、[额度](delivery-phase/quota-rejection-summary.json)。最初36项HTTP/三次drop保留独立阶段，不能把重叠summary直接相加。

## 三条唯一私有Issue

实际cron在15:20:59后创建Issue。15:22:10.156Z独立读取repo metadata确认private，完整state=all短页共3条，逐条原ID/marker/完整正文和诊断均一致，各只有一条。[原创建与完整正文核验](delivery-phase/github-deletion-race-20261029T152244Z/summary.json)保留创建前后事实；下表Issue已删除，链接可返回Gone，不是交付证据缺失。

| 场景 | Feedback ID | 已创建的私有Issue / node ID | 完整列表唯一数 / 正文 | 最终清理状态 |
|---|---|---|---|---|
| plain | `9650fede-d514-4672-81f7-c92d2fa1afd2` | #1 / `I_kwDOVaxKc88AAAABa8HXFg` | 1 / 精确一致 | Issue永久删除；D1/授权GET均deleted |
| diagnostic | `5b11fd1c-80a9-4a41-8790-0b1296bd6401` | #2 / `I_kwDOVaxKc88AAAABa8HZEQ` | 1 / 精确一致 | Issue永久删除；D1/授权GET均deleted |
| lost_receipt | `2b2dd0e6-c966-4910-93a0-e96b5510a056` | #3 / `I_kwDOVaxKc88AAAABa8HbSw` | 1 / 精确一致 | Issue永久删除；D1/授权GET均deleted |

### GitHub返回不确定性与迟到协调的精确范围

已部署经过审查的单测试ID丢返回响应版本。诊断记录实际创建Issue #2后，15:21:30.844Z D1为uncertain、Issue身份NULL；15:22:36授权DELETE返回deletion_pending，15:23:17Z内容NULL且删除意图保留。**没有直接捕获该诊断请求的HTTP201响应或该注入分支的执行踪迹**，不能写成“已独立抓到201丢响应”。

普通生产恢复后，15:31:23.323Z真实cron认回原Issue #2/node，仍为deletion_pending/delete_requested=1/payloadNULL，原attempt_at1793287259不变。15:32:05.141Z独立完整列表仍仅原3个Issue，ID/node/正文/state/created/updated均未变化，原helper3/3精确通过；随后原凭证GET仍为deletion_pending。源码协调路径不会重新POST；直接证据是原创建意图未重置且完整列表无新Issue，不声称取得了完整出站POST抓包。

证据：[D1迟到协调](d1-late-reconcile.json)、[独立列表及状态](delivery-phase/late-reconcile-snapshot-20261029T153217Z/summary.json)。这充分支持已观察到的实际创建→不确定→原Issue协调且删除意图不倒退；未直接捕获部分单独保留。

## 永久删除与D1/协议状态结案

1. owner在15:32–15:33:48对准确Issue #1/#2/#3执行“Delete issue”并确认Delete，未用Close代替；[实际owner操作](github-owner-permanent-deletion.json)。
2. 15:34:26.371Z同一有权限连接成功读取正确private仓库，每个精确Issue GET均为 **410 Gone，provider明确deleted**，完整state=all列表成功返回空数组。[独立API证据](delivery-phase/permanent-delete-api-observation-20261029T153426Z/summary.json)。
3. [非作者复审](permanent-deletion-410-review/decision.json)核对原始读数、owner操作及[官方Get issue语义](https://docs.github.com/en/rest/issues/issues#get-an-issue)：有read access时已删Issue返回410；缺少read access可能404。原404准备预期保留为已更正的历史，不能把410改写成404，或把任意错误/401/403/断网/空列表单独算删除证明。
4. 经复审后，集成人执行三条原ID+原Issue number/node+delete_requested=1+payloadNULL+deletion_pending的精确guardedSQL。15:38:01.664Z直接D1确认8行全部deleted/delete1/payloadNULL，新三行保留原Issue1/2/3身份。[逐行结案](d1-final-deletion-closeout.json)。
5. 15:39:00.373Z直接aggregate：**rows8、deleted8、body0、pendingDelete0、probe0、daily100/hourly20**。[最终总数](d1-final-summary.json)。15:39:38三条原单条凭证GET均为200/原ID/deleted/durable=true；额外精确语义断言3/3 PASS，[原始事件与断言](delivery-phase/final-client-deleted-20261029T153938Z/summary.json)。这些GET由验收脚本发起，不是原生App操作。

远端合成测试反馈的正文/Issue删除义务已结案，保留无正文墓碑及原Issue身份，禁止复活旧8个ID。D1过去7天可恢复窗口、平台物理备份不在即时删除证明内；真实Mac本地SQLite/Keychain清理未执行。临时私有验收状态只由集成人在验证结束后处理，绝不进入公开仓库；其文件移除结果不由本检查点推断。

## 本地验收材料收口 · 2026-10-29T15:47:56.261645+00:00

[独立归档审查](final-archive-cleanup-review/decision.json)通过后，集成人移除了清单内7个临时测试目录及18个文件，包含单条测试凭证和原始私有Issue响应副本；[实际移除记录](private-temporary-cleanup.json)确认全部路径不再存在。最终安全归档及[限定410原始字段摘录](final-archive-cleanup-review/provider-410-safe-extract.json)保留。没有移除服务器Secret、浏览器状态、D1墓碑、正式工程或真实Mac数据；普通文件移除不等于物理介质或云端备份擦除。早先快照中“尚待本地清理”保持其当时事实，由本后继记录结案。

## 当前工程与产品边界

H `2f30885644c9dc597e47d8f1dc89b9e16828092a` 的[完整Native ARM/Intel](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40891805452)和[Feedback CI](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40891805617)已成功，49项唯一Feedback/21项服务及固定门禁通过；[十项客户端风险](client-risk-evidence.md)已逐项映射源码/审查/原日志。这是历史H的CI和local-outbox-only包证据；本轮Host已实际配置公开真实endpoint，不把旧H包改称新启用包。

客户端已实际应用已审查的固定公开HTTPS URL一行接线。最终源码、独立全差异审查、既有source admission、完整macOS/Feedback执行及准确统一Beta引用统一以[正式工程定值元数据](../2026-10-29-final-product/results.json)和[PR #1最终交接](https://github.com/haohongfei2001-png/Riftlet/pull/1)的已发生记录为准；下载包的build-info必须绑定该源码，不能引用旧H的local-outbox-only包来证明新能力。本文不硬填预测SHA/CI，不修改截图准入或main。

[Codex真实Mac清单](CODEX_REAL_MAC_E2E.md)仍NOT_RUN：原生窗口到云、真实IME/VoiceOver/Keychain、退出/网络恢复和截图隔离。未安排执行器，也不要求用户本轮安装。只有这些原生实际要求完成，才能按用户标准宣布Feedback真实端到端交付完成。

## 历史与运维入口

[初始36HTTP与3drop](live-http/summary.json)、[14:17部署状态](deployment-checkpoint.json)、[原Receiver部署](receiver-deployment.json)、[早期空Issue](delivery-phase/github-observation-20261029T145732Z/summary.json)、原诊断失败/旧404预期都保留事实。早先断连、未建Delivery、待删状态属于历史，不能作为当前阻塞。完整旧H文档由[固定Git对象](https://github.com/haohongfei2001-png/Riftlet/blob/2f30885644c9dc597e47d8f1dc89b9e16828092a/engineering/evidence/2026-10-29-feedback-cloud/README.md)复查。

[最小运维](MINIMUM_OPERATIONS.md) · [部署/源码核对](DEPLOYMENT_RECONCILIATION_CHECKLIST.md) · [结构化终态](delivery-checkpoint.json)。
