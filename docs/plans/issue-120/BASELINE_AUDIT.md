# 实际基线、独立源码审查与证据边界

2026-11-20（北京时间）。基线是本次读取时的 GitHub 状态，开工 W0 和最终交付前必须重新读；任何历史版本名都不能代替 Git SHA。

## 1. 实际状态

| 对象 | 本轮读取事实 | 对下一阶段的约束 |
|---|---|---|
| [main](https://github.com/haohongfei2001-png/Riftlet/tree/9fd8ad15fca043915069904113e5fb67d82b4948) | `9fd8ad15fca043915069904113e5fb67d82b4948`，#114，公开1.0.5（31）的官网/feed提交 | 规划分支可基于它；实现不可从它重做1.0.7 |
| [PR #117](https://github.com/haohongfei2001-png/Riftlet/pull/117) | open，未合并；head `cf697d7ece7e052ccaa2ea5c4bca42a16fd0ebdf`；说明为1.0.6 build44 | #118 初始正文的 build42/b40 已过时；以最新源码/报告为准 |
| [PR #119](https://github.com/haohongfei2001-png/Riftlet/pull/119) | open / draft，base main；初审f27后已更新为 **`e852af3996cb6fea17ed107d8fb8073e06f582ae` / build49**，本轮补审23文件增量 | 最新已推送代码已核对；不改其源码、refs、评论、CI或验收 |
| [#119 验收评论](https://github.com/haohongfei2001-png/Riftlet/pull/119#issuecomment-7028325810) | build49 产品 `b431931eba1d31b5ac7a5fcc110db8613e11ac7d`，独立报告 `bd83b9ae0c8091fc686e87f82d0e263f1eb42446`；此前45漏收、46误认次级卡、47 Chrome绑定超时 | 最初查询b431返回422，随后已随e852推送并补读；历史不可读已解除。真实G1–G6仍在收口，不将新源码/包报告当最终线上放行 |
| [Issue #118](https://github.com/haohongfei2001-png/Riftlet/issues/118) | 仍是1.0.7集成、G1–G6标准 | 本规划不覆写它；后续需继承最终通过的行为 |
| [Issue #120](https://github.com/haohongfei2001-png/Riftlet/issues/120) | 单周期多浏览器/多AI授权 | 本目录深化其架构/验收，不重新拆成多个版本 |

PR #117/#119 的 CI、签名、公证和实机结果属于各自提交/包的原报告，本轮没有重做它们。最新实际 GitHub Release 已核对仍为 `v1.0.5`，DMG digest `99276347932e231adf743664a54cfc782d8e345d89221587d54b7299a5c9f315`；发布前再核对官网及signed feed。main仍`protected:false`、rulesets为空，本轮没有变更仓库治理。

### Build49增量结论（最终设计已吸收）

补审 [f27→e852完整差异](https://github.com/haohongfei2001-png/Riftlet/compare/f27c2473891bd37ac4227ca424c1bb2c4ce56c41...e852af3996cb6fea17ed107d8fb8073e06f582ae) 与49的RC/独立报告：

- `WebPageProgram.pinSource`、loader的 `RIFTLET_CLICK_PIN_END` 边界及 `ChromeClickDocumentWitness` 已共享轻量resolver/witness；mouse-down只enqueue一次，回执通过独立Mach receive right在线程外读取。不能再把“大脚本同步pin”列为未修当前问题。
- 页面绑定仍限原150ms预算（脚本扣5ms容差），confirmation读取/核对为1s；wall clock与uptime差需≤5ms。跨Host复用要实测该时钟/预算契约，不是调长deadline来通过。
- route cache现保存原`ChromeProcessIdentity + route`；写入沿用原进程，只读observe才允许查找原receiver。保留此修复。
- 原卡规则已覆盖外层`composer-attachment-surface`、精确原图/文件名/本卡移除控件，允许hover-only移除按钮，排除嵌套次级卡。跨Provider抽取时这三类反例必须保留。
- Navigation API、ChatGPT route/profile依赖和单adapter边界仍存在，因此Host/Provider/Resolver架构仍适用。49未改变本轮核心拆分裁决。
- 49报告的正式DMG hash为`67aea5fd067d405701e10cdc512d8657e91db569d0ba6715614a035fb9891023`，13,415,624字节；属于#119包报告，不是本轮重新签名/安装验证。

## 2. 本轮确实执行的验证

- 仓库只读克隆并分离 main / #119 worktree，核对相关 Swift、AppKit/Apple Events、页面 JS、模型、持久化、测试与治理文件。
- Linux / Node `v24.22.3` 执行：`node --test Tests/WebPageProgram/acceptance-program.test.cjs Tests/WebPageProgram/legacy-web-observe.test.cjs`。
- 结果：**263 tests / 263 pass / 0 fail / 0 skipped / 0 cancelled**，约60.79秒；源码 `f27c2473891bd37ac4227ca424c1bb2c4ce56c41`。属于 **L1 合成 DOM fixture**，不是浏览器或登录网站测试。
- build49推送后在 **`e852af3996cb6fea17ed107d8fb8073e06f582ae`** 重跑同一集合：**263/263 PASS**，51.84秒，0 fail/skipped/cancelled。它验证新JS对已有fixture无回归，仍不证明原生pin时序或真实网站通过；两次不相加为526项独立覆盖。
- 独立审查者也运行上述集合中的 acceptance 单文件（202/202），属于重叠覆盖，不能相加为465项。
- 未执行 macOS Swift/AppKit、原生Apple Events、新Host、真实已登录网站、签名安装或新版本发行。新核心矩阵的 L2/L3 均 NOT_RUN。

## 3. 源码依据与必须处理的耦合

下表路径及行号对应 [#119 初审不可变源码树f27](https://github.com/haohongfei2001-png/Riftlet/tree/f27c2473891bd37ac4227ca424c1bb2c4ce56c41)；**以上49增量结论优先，C03及C07已按49修正**。这是源码事实和扩展约束，没有将未执行的竞态或网站错误写成已复现缺陷。

| ID | 依据 | 裁决 |
|---|---|---|
| C01 | `TransferCoordinator.swift:144–154,325,640` 单 adapter 与id等号 | 增最小 resolver，新旧operation按不可变Provider/adapter revision路由；全产品一个coordinator/store，不伪装chatgpt-web |
| C02 | `ChromeCommandRouting.swift:21–50`、executor `51,69,85–88,185–197`、JS `23–28` | ChatGPT域名/路径/历史UUID移入Provider；query/hash是否影响草稿由各站决定；新增opaque历史locator且旧字段兼容 |
| C03 | f27 executor `23–44,408–426`、`ChromeClickDocumentWitness.swift:9–12`；49增量见上 | f27原有完整JS同步pin；**49已实现pinSource/异步回执**。继承并跨Host验证，不重复修复、不退回旧实现 |
| C04 | JS `699–703,1456–1485`、Models `100–119` | pin依赖Navigation API；Safari门槛/替代单独验证。新pin不需React私有树，旧logicalDraft profile仅保留历史兼容 |
| C05 | executor `173–195,239–245`、JS `246–251,716–736,1599–1605` | AE多次读取不跨进程原子；固定对象、出生身份、pin、写前校验组合防错。必须测same-URL reload/ABA/延迟/重排 |
| C06 | JS `1571,1618–1621` | committed fence先于setter应保留；input+change事件配方不能对所有站无条件复用，必须验证实际新增附件恰好一个 |
| C07 | f27 JS `1276–1300,1388–1409,1607`及49原卡规则增量 | encoded-preview技术可复用；必须以49外层原卡/hover-only/嵌套阴性规则为准。卡片/移除/失败语义归Provider，不按品牌堆业务分支 |
| C08 | JS `1409,1435–1443`、coordinator `596–598` | START、ready、同卡失败、用户移除、unknown分开；spinner/文件名/计数不独立证明接受 |
| C09 | JS `197–210,1485`、`ChromeSessionCache`、coordinator `640–662` | 当前页面proof约10分钟；媒体历史持久不等于永久可核验原草稿。证据过期/重启不可凭URL复活旧operation |
| C10 | adapter `734–780` 与 `verifyAfterRead` | 原件与转码payload分开记hash/MIME/bytes，原件不变；不要把不同字节冒充原字节，也不重做媒体库 |
| C11 | adapter `521–548,660–666`、`SystemScreenshotCandidateAdmission.swift:25–40,85–101`、ReceiptPolicy `66–156` | 将硬编码准入变成签名包内Provider/profile注册表，不能删除guard变成任意网页布尔回执；旧profile保持只读 |
| C12 | `AutomationPermission.swift:50–105`、`OriginalReceiverPermission.swift:23–41`、Main `136–137,604,655–657,1292–1310` | 复用确切receiver及异步授权顺序；只在当前浏览器首次使用时引导，权限等待不改投后来前台 |

## 4. 已验证骨架应保留

- QueueStore `562–598,618–664`：事务内 prepared/selection核对、invocation、dispatchIntent、原owner回执。
- WebAttachmentAdapter `257–299,304–388`：tab输入锁、operation tombstone、begin/chunk/commit、回执丢失后原identity观察。
- JS `1511–1527,1560–1629`：原operation登记、一次性fence、写入前最后核对、setter后禁止换路径。
- TransferCoordinator `364–397,586–618`：重启不append、确定未dispatch才恢复、未知保留、观察不长期阻塞下一张。
- ChromeProcessIdentity `8–78`：PID+kernel birth+bundle，旧session只读兼容。
- QueueStore `813–879`、ReceiptPolicy `66–85`：保留首个START，完成和重试资格分别判断。

## 5. 最小必要重构及不做的重构

必须做：Host/Provider分层、唯一resolver、版本化target/profile、Provider事件和证据策略、真实浏览器测试入口、来源隔离、按需授权和准确恢复文案。

不做：另建事务引擎、16份独立脚本、删除旧UNKNOWN、重置媒体/SQLite、重新依赖React私有状态、热加载远程执行JS、复制#69数百份历史证据、改托盘外观或引入Nearpane模块。

49已经修复C03及部分C07；W0仍需获取最终收口版本并复核49之后的增量。不能把历史审查表变成重复施工清单。
