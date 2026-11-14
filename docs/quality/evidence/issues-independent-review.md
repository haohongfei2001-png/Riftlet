# 22 条 Issue 正文独立复核

审查者：`attachment_audit`。日期：2026-11-14。源码基线：`44f745a15ecb3682a9da0bda17f17a5d9fc1f07e`。审查输入：`audit-work/issues-to-create.json` 的 22 条完整正文、`docs/quality/` 专项报告/裁决/既有独立复核，以及有关源码。未修改根代理文件，未运行新的浏览器或完整测试。本审查只评估问题与交接质量，**不是修复代码或正式软件验收**。

## 总体结论

22 条都已具备具体位置、触发/验证条件、证据范围、修改方向和验收要求。设计缺口与验收缺口没有伪装成已发生故障；本轮受控 DOM、源代码、历史原生记录与当前 NOT_RUN 基本区分准确。没有发现虚构本轮真实 ChatGPT 成功、线上数据泄露、永久丢图或当前 App 性能测量。附件保护、原图、原 UNKNOWN、不自动重传及发行身份保护没有被“精简”方案删除。

**建议补齐下列几处后发布 Issues。** ATT003 身份匹配/状态优先级、ATT004 点击目标冻结尤其应直接写入 Issue，不能只依靠实施者继续阅读另一份独立复核。

## 必须明确的最小安全补文

### 1. QA-ATT-003：展示事实必须匹配当前操作，并保留异常优先级

当前 Issue 只写“不可变 START”，尚不足以阻止实现者按 `asset 曾有 START`、`visibility == swallowed` 或 `lastReceipt` 提升成功。`QueueStore.historySnapshot:64–70` 现在没有传不可变 START；`HistoryPresentation:21–39` 已示范 current operation/receipt 身份比较。采用 `evidence/interaction-independent-review.md` 已确认的矩阵即可，无需新机制。

建议在“裁决/验收”补：

> 只读 START 必须属于当前 `activeOperationID`，并与 `operation.assetID / attempt / target / assetSHA256` 一致；在同一次历史快照事务中取得。缺媒体、当前关联的明确后发错误与 `compensated` 优先显示异常，不能被交接标签掩盖。其他旧 attempt 的 START 不能覆盖当前 UNKNOWN。当前操作已有可信 START、仅不知道后续完成结果时仍可显示“已交给 ChatGPT”；无匹配 START 的未知输入保留“待确认”。历史列表/网格/筛选/搜索与设置计数使用同一只读事实；Core 的 restore/retry 权限保持原判定。

验收增加四个反例即可：旧 attempt START+当前 UNKNOWN、当前 START+后发关联错误、START+missing、当前 START+纯完成未知。不能一概让所有 UNKNOWN 优先于 START，否则原问题会重现；不能一概让 START 优先于所有异常。

### 2. QA-ATT-004：非阻塞不能变成延后选择活动标签

正文已有目标不漂移约束，建议再加一句具体禁止事项：

> `activeIdentity()` 使用 `front window / active tab` 动态对象（`ChromeAppleEventsExecutor:404–418`）；把这个调用原样搬进延后 Task/队列不等于冻结点击目标。若用短同步快照，仅冻结绝对 window/tab 身份并给整组统一预算，固定 ID 的 URL/DOM 工作再异步；若用原生异步回复，必须证明点击边界选择与返回绝对 ID 的关联。超时或无法证明关联则结束本次输入，不改读后来活动标签、不自动重试；取消后的迟到回复无副作用。

P1 UI 活性风险成立。现正文正确区分“单次事件配置超时 5 秒”和“整组可能累计数秒”，没有宣称本轮实测精确冻结时间。

### 3. QA-ATT-002：窄恢复仍保留 missing

prepared 崩溃滞留的 P1 成立；移出→历史恢复绕行已如实披露。建议加一句：

> 仅退役证明未 dispatch 的旧 prepared；若资产原状态已是 missing，仍保留 missing 和原可见性，不因取消旧操作而声称媒体恢复。此恢复必须在新 selection 入队前执行，不恢复旧内存 FIFO。

不能直接对所有旧 unresolved 调用宽泛恢复。其余验收已经覆盖一次性输入、旧 UNKNOWN/START/receipt 不变。

### 4. QA-DAT-001：坏偏好降级不能成为覆盖有效/未来字段的入口

P1 与安全默认方案成立，详见既有 `storage-independent-review.md`。建议将以下短约束加入验收，避免“保留原始坏文件”却通过普通保存覆盖配置：

> 启动/退出不得自动回写默认配置；可解码的有效偏好与已有 `PresentationValue` 未知键需保留，修改无关项不能清除它们。整文件不可读时，只有明确恢复默认操作才替换该偏好，原始字节保留。当前配置没有完整版本化 schema，不虚构能自动识别全部未来格式。

## 证据、分级和可执行性小修

1. **QA-ATT-001 命令可直接执行。** 复现脚本确已放 `docs/quality/evidence/attachment-foreign-picker-repro.cjs`，Issue 只写 basename。建议从仓库根使用：`env -u RIFTLET_PAGE_PROGRAM_SOURCE node docs/quality/evidence/attachment-foreign-picker-repro.cjs .`。夹具允许该环境变量覆盖生产 JS，清除它可确保实际复核基线。补脚本及 result.json 的分支链接。退出 0 为缺陷见证而非验收通过，现正文对此表述正确。P0 仅指已复现错误 input 写入边界；真实 ChatGPT 外泄没有被证明。
2. **QA-GOV-002 分级建议改 P2，保留治理门禁。** 无 branch protection/rulesets 是确认的远端控制缺口，但尚非用户定义的“核心功能不可靠/普通用户任务受阻”。P2 治理债务且安排 R4 更一致；如果坚持 P1，应明确它是治理处理优先级，不计入“已确认产品 P1 故障”数量。QA-REL-001 可以保留 P1 发行验收门槛，但同样单独统计为 `ACCEPTANCE_GAP`，不能宣称为已复现核心失败。
3. **QA-GOV-002 原始字段持久化。** `evidence/baseline.json.remoteProtection` 当前仅有 `branchProtected:false / rulesets:[]`，没有正文引用的 `protection.enabled:false`、required checks 空。若会话原返回确有这些字段，补精简原始 read-back；否则将正文收窄为已持久化的两个事实。不是判定该结论虚假，而是需让离线读者自行核对准确字段。
4. **QA-SET-001 / QA-SET-006 修复悬空“下文 IA”。** 独立 Issue 没有下文方案。改成“通用 / 桌面 / 截图 / 帮助”，直接链接 `docs/quality/SETTINGS_REDESIGN.md` 的新信息架构与逐项处置表。QA-VIS-001 同理给规格直链，避免只写文件名。
5. **QA-SET-007 是五种权限用途字符串。** `Resources/Info.plist:25,30–33` 分别为 ScreenCapture、AppleEvents、Desktop、Documents、Downloads，共五项；Issue 与专项报告的“四种”改为“五种”或删数量。这不影响 P2 本地化缺口。
6. **QA-GOV-001 一个源链接在基线不存在。** `https://github.com/haohongfei2001-png/Riftlet/blob/44f745a15ecb3682a9da0bda17f17a5d9fc1f07e/docs/quality/history/` 必然不存在，因为归档由本审计新增。改为审计分支 `tree/.../docs/quality/history/` 或未来精确提交。机械核对了 22 个唯一 pinned source 路径，其余均存在。统一 CODEX_HANDOFF/ISSUE_REGISTER 分支链接应在 PR 形成后作最终存在性核对。

## 逐条 disposition

| Issue | 审查判断 |
|---|---|
| QA-ATT-001 | P0/受控复现成立；补完整命令与证据路径；不可升格为已观测线上外泄 |
| QA-ATT-002 | P1/源码链成立；补 prepared+missing 及恢复时序 |
| QA-DAT-001 | P1/源码链成立；补无默认回写与有效/未知字段保留 |
| QA-ATT-004 | P1/同步主线程风险成立；补动态活动对象不能延后求值 |
| QA-REL-001 | P1 发行验收缺口成立；与产品缺陷计数分列 |
| QA-GOV-002 | 事实成立；建议 P2 治理缺口，补精确 read-back 字段 |
| QA-DAT-004 | P2 成立；已限定运行中、精确媒体补回、重启可恢复，未称永久损失 |
| QA-SET-002 | P2 成立；隐藏字段与 draft inclusion 不一致的源码明确 |
| QA-SET-003 | P2 成立；defer 仅关闭窗口而 started 仍自动展示 |
| QA-SET-004 | P2 成立；1–10 设置与托盘 `min(...,4)` 容量不一致；不扩大已定形态 |
| QA-SET-001 | P2 产品整改成立；补明确 IA 链接 |
| QA-SET-006 | P2 信息架构整改成立；补明确 IA 链接 |
| QA-ATT-003 | P2 成立；加入当前 START 身份及异常优先级矩阵后交接 |
| QA-GOV-001 | P2 治理冲突成立；修新增归档指向旧基线的坏链接 |
| QA-VIS-001 | P2 验收缺口成立；没有把旧画册当当前证明，补规格直链 |
| QA-DAT-002 | P2 结构成本成立；已披露旧性能结果边界，未虚构当前卡顿；保护校验和 UNKNOWN |
| QA-SET-008 | P2 维护债务成立；正确承认旧控制器仍被历史测试使用，未冒称全部死代码 |
| QA-DAT-003 | P2 设计缺口成立；先定主动清理边界，不授权自动删除用户现有数据 |
| QA-SET-007 | P2 本地化缺口成立；纠正权限字符串计数 |
| QA-REL-002 | P2 兼容验收缺口成立；历史 QA identity/loopback 与公共分发验收已区分 |
| QA-SET-005 | P3 命名不准确成立；现 picker 已明确系统位置，不要扩成任意目录监控 |
| QA-WEB-001 | P3 成立；`index.html:69–78` 与语言映射支持已记录公开 UI 观察，不代表本轮 Mac VoiceOver 实测 |

以上补充为交接精度修正，无需重跑全套测试或扩展审计范围。既有产品缺陷仍保持 OPEN，文档/Issue 持久化本身不能关闭它们。

## 修正后复核：PASS（Issue 交接内容）

2026-11-14 追加。重新读取修订后的 `audit-work/issues-to-create.json`、`docs/quality/findings.json`、补充后的 `evidence/baseline.json`，并核对本次涉及的报告文案。**本节替代上文“待补齐后发布”的状态；上文保留为初审记录。** 未重跑测试，未修改生产源码。

- ATT003 已直接写入当前 operation/attempt/target/hash 匹配、事务快照、异常优先级以及七类状态组合；明确同一操作有可信 START 但上传终态未知仍保留交接事实，旧 START 不覆盖当前未知。只读投影不改变 Core 的恢复或重试准入。
- ATT004 已明确禁止把动态 `activeIdentity` 搬到延后 Task，要求短预算取得绝对 window/tab 后再处理固定身份 URL/DOM，或提供可证明点击归属的异步协议。已有迟到回复、切标签、冷首击与一次性输入验收保持。
- ATT002 已加入 prepared+missing 不得被变成虚假可点击状态；既有“不重放旧点击/不自动输入”和窄恢复范围保持。DAT001 已加入会话默认不回写、有效/未知字段保留和明确恢复才替换的约束。
- ATT001 复现命令已使用仓库内实际文件路径，并用 `env -u RIFTLET_PAGE_PROGRAM_SOURCE` 排除 fixture 源码覆盖。缺陷见证退出 0 的含义仍明确。
- GOV002 已改为 P2 治理缺口；baseline 证据已补 `protectionEnabled:false`、`requiredStatusChecks` 的 `off / contexts:[] / checks:[]` 及两个 API 路径。没有将其计作已复现核心 P1。
- SET001/006 已直接写出四页名称，并提供专项方案链接；SET007 权限用途字符串已改五项。新增历史目录指向旧基线的坏链接已消除。
- 对修订后全部 Issue 的固定 SHA 源链接重新用本地 Git 对象核对：**53 个唯一路径均在所指基线存在，0 个缺失**。这项检查证明仓库对象可解析，不冒充远端网页 HTTP 验证。
- `findings.json` 已为 22 个稳定 QA-ID 记录互不重复的 GitHub Issue URL，覆盖 **#78–#99**；其中 GOV002 对应 #83/P2，REL001 对应 #82/P1 `ACCEPTANCE_GAP`。本次核对的是已持久化发布映射与发布用正文，不声明再次逐条远端回读全部 Issue。

**结论：前次实质审查意见已被接受，Issue 内容和工程交接通过本次独立复核。** 产品实现与原生验收仍未因本报告而通过；P0/P1 修复、真实 ChatGPT 冷首图/连续双图和最终签名候选验收继续按原门槛执行。
