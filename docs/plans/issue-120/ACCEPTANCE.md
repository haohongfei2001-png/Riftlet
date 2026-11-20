# 统一功能完成标准、测试矩阵与发布门槛

本文件规定未来实现的验收。当前新版本未实现，[compatibility-matrix.json](compatibility-matrix.json) 的核心格全部 NOT_RUN。既有1.0.7证据不迁移成下一候选的PASS。

## 1. 功能完成标准

一个组合只有同时达到以下结果才可公开支持：

- 普通签名Riftlet、普通浏览器会话、真实已登录AI对话；无需扩展/API Key/调试端口/WebDriver/手工粘贴或选择目标。
- 原生系统截图自动收录；单击图片即附加到点击时正在使用的原草稿。新/冷首击也要成立，不能靠强制预热或第二次点击。
- 每次operation输入配方最多执行一次，原草稿实际新增本图恰好一个；原文字/富文本/选区/旧附件保留；零发送。
- 只有原目标、本图、本operation的正面证据允许收起；普通反馈只说“已交给平台”。处理完成另证，假成功为P0。
- 输入前失败保留图片；输入可能发生则不自动重发；同卡明确后续失败恢复本图的可处理入口；本地媒体与旧UNKNOWN不丢。
- 不支持/登录/权限/限额/模式/导航等负例短反馈且不误投；失败局限对应组合或surface，其他能力保持可用。

## 2. 证据等级和状态

| 等级 | 实际运行对象 | 能证明什么 | 不能证明什么 |
|---|---|---|---|
| L0 source / official | 代码审查、浏览器源码/官方文档 | 设计依据与可检验假设 | 原生/线上实际成功 |
| L1 simulated | Node/合成DOM/Swift fake driver | 状态机、协议、故障分支、确定性反例 | 原生Apple Events、真实浏览器、网站 |
| L2 native fixture | 实际Chrome/Edge/Safari/Brave二进制 + 普通签名App + 无敏感受控页 | 真权限/执行world/字节传输/目标守卫/时序与故障 | 线上网站实际结构、账号模式和接受 |
| L3 live service | 同一最终签名候选 + 普通浏览器 + 正式AI已登录原草稿 | 该版本/模式/环境下真实接受和保留体验 | 未测其他模式/未来网站稳定性、模型是否理解图像 |

状态使用 `NOT_RUN`、`PASS`、`FAIL`、`BLOCKED_ENV`、`BLOCKED_TECHNICAL`、`NOT_APPLICABLE`；理由字段必填。`UNKNOWN` 是操作/服务事实状态，不可以作为测试全绿。脚本成功运行、fixture成功、签名成功都不能把L3改PASS。

Playwright/WebDriver可用于fixture布置和独立观察；**不能用其文件注入代替Riftlet真实输入**。Playwright WebKit≠Safari；Terminal的Automation权限≠Riftlet App权限；未公证开发包≠最终发行候选。

## 3. 核心4×4初始矩阵

每格填写同一candidate ID + app hash + host/provider版本 + L1/L2/L3结果与证据链接。下面的“待测”针对下一阶段最终候选。

| Browser / Provider | ChatGPT | Claude | Gemini | DeepSeek |
|---|---|---|---|---|
| Chrome | 待测，继承1.0.7回归 | 待测 | 待测 | 待测，当前模式能力待证 |
| Edge | 待测，继承1.0.7回归 | 待测 | 待测 | 待测，当前模式能力待证 |
| Safari | 待测，26.2+能力及冷绑定门槛 | 待测 | 待测 | 待测 |
| Brave | 待测，实际world/权限/默认Shields | 待测 | 待测 | 待测 |

Kimi、国内千问、豆包、Perplexity的四Host格在机器表中独立登记。国际Qwen为另一Provider变体；Firefox原型通过后才新增正式四核心格。扩展并不免除组合实测：只在Chrome测过不能宣称Safari也支持。

一个格可包含多个 `surface/mode/locale/accountTier` 子结果。初始公开支持为各站**普通对话的可编辑草稿**；项目库、头像、反馈、Canvas/Gems配置、浏览器侧面板、图片生成器、嵌入iframe均不得因同域名自动继承。新/临时与保存聊天是核心常见surface；有该能力而未测时不能笼统声明全部聊天。

## 4. 最小真实正向覆盖

每一个核心格，使用同一最终签名候选至少执行：

1. **F01 冷首图**：普通启动，未在该页预热Riftlet脚本；系统截图收录后单击。带原文、非空选区、一个旧附件。
2. **F02 暖首图**：原草稿中再次附加另一图；核对正确卡片与既有附件。
3. **F03 快速双图**：至少3组不同图片、点击间隔<2秒（含约0.5秒和约1.7秒）；逐图独立operation、一次输入、原图关联、各新增一张，无丢图无互借回执。记录实际间隔，不能仅按脚本计划间隔。
4. **F04 草稿类型**：上述成功样本至少涵盖新/未发送草稿和普通已保存聊天；临时模式若平台支持且拟宣称支持，另测。已有聊天用非敏感合法测试会话，禁止通过本产品自动发送来制造。
5. **F05 保留与交互**：至少一次富文本/多行/emoji/中文选区；至少一次上传等待中用户继续输入或IME组合，不被旧快照覆盖。两种输入状态可与F01–F03复用。
6. **F06 相同图片新意图**：前一次已确认后明确再次附加同图，创建新operation；不得因SHA相同吞掉合法新操作。双击/旧回执不能额外触发第三次输入。

平台确不提供某种surface可以NOT_APPLICABLE并附证据；缺登录/套餐为BLOCKED_ENV；曾失败的样本不能从统计中删除。零误投/零发送/零重复是硬条件；常规路径失败应修复并复验，不以“多数成功”宣称正常可用。

## 5. 异常与对照用例

不把所有维度做成无穷笛卡尔积。共用状态机在L1全面注入；每Host在L2覆盖原生差异；每Provider在L2覆盖自己证据/事件规则；每核心格L3至少实际执行目标切换阴性对照、保留场景及正常双图。特殊实现组合补齐对应反例。

| Case | 场景 | 最低层/覆盖 | 预期 |
|---|---|---|---|
| T01 | 点图后切同URL另一tab/窗口；Chrome/Edge/Safari/Brave同时开 | 每Host L2；每核心格L3一个真实切目标反例 | 原输入前拒绝或仍能证明原目标；不改投 |
| T02 | 首次nonce生成前tab重排、延迟、A→B→A、同URLreload；标签跨窗口移动 | 每Host L2，Safari冷绑定必做 | 事后mint nonce不能自证；无法锁原对象即零输入 |
| T03 | 新聊天/编辑旧消息/切模式或账号/SPA route含query/hash变化 | 每Provider L2；高风险模式L3 | 原draftEpoch/surface/capability失效，不沿用旧ticket |
| T04 | 浏览器退出/重启、PID/窗口ID复用、document替换/BFCache | L1+每Host L2 | 进程出生/epoch不匹配即失效；旧op只读不可重放 |
| I01 | commit回执丢失、AE超时、actor取消、重复callback/重复commit | L1+每Host L2 | 最多一次输入配方；只读原operation，不换transport |
| I02 | app在prepared/intent/staging/setter后/START持久化前崩溃 | L1故障注入+L2代表Host | UNKNOWN保留；明确零输入才允许新用户尝试；数据一致 |
| I03 | input重建/hidden/portal/detached、多个editor、iframe/shadow boundary | 每Provider L1/L2 | 只有可证明原composer入口可写；不在所有input试传 |
| I04 | 网站同时监听input与change、旧FileList、重复派发 | 每Provider L2+L3正向 | 配方固定，新增本图恰好一次，旧附件不重传 |
| E01 | 旧卡/邻卡/头像/历史消息图/嵌套次级卡/同名错误图 | 每Provider L1/L2 | 不能授权本operation START |
| E02 | 原图与一像素差图、同图不同op、缩放/压缩卡、blob/dataURL更新 | 每证据策略L2 | 原件/payload/卡关联正确；不以视觉相似放行 |
| E03 | remove按钮仅hover、卡替换、多视图、短暂START | 每Provider L1/L2+实际遇到的L3 | 保留正面事实且不误认归属；轮询不丢有效START |
| E04 | 正面START后本卡明确失败；邻卡失败/全页红字阴性 | 每Provider L2；线上出现则记录L3 | 本卡才恢复本图，不重传；历史START仍是真实事实 |
| E05 | 用户移除附件/自己发送后卡消失/目标不可用 | L1/L2（发送仅在受控fixture）；L3可测移除，不发消息 | 不等同失败，不自动把图片放回网页 |
| P01 | TCC拒绝/撤销、JS关闭、receiver变更、浏览器未安装/无窗口 | 每Host真实签名App L2 | 精确按需引导，不改投/不丢图/不反复弹窗 |
| P02 | 未登录、配额/大小/格式限制、离线/服务拒绝 | 每Provider L2；可合法触发则L3 | 明确拒绝保持图；可能输入未知不自动重试 |
| D01 | 文本/选区/旧图保留，菜单暂移焦点，用户并行输入/IME | 每Provider L2+每核心格L3 | 无旧快照覆盖，无粘贴板改动，无自动发送 |
| R01 | App重启只读续查、页面proof过期、browser重启 | L1/L2 | 本地原图可恢复；失去页面证明不凭URL复活 |
| R02 | 1.0.5/最终1.0.7→新候选升级；旧UNKNOWN/START/失败/找回/书签 | 真实签名App，隔离数据库 | 增量迁移无丢失/重放；同包安装升级可用 |
| X01 | 一个Provider页面更新/selector不匹配，其他Provider继续 | L1/L2 | 只隔离该scope；无远程任意JS、无全局crash |

所有线上动作仅使用无敏感测试图片和获授权独立草稿。不得发送聊天消息以获取模型回复，不得绕过验证码/地区限制、付费或复制登录profile；授权会话不可用只阻塞其格。

## 6. 自动化实现与独立oracle

一份数据驱动runner：`HostDescriptor × ProviderDescriptor × CaseID`，不同Host只负责环境和原生触发，不重写测试逻辑。既有fixture先复用；增加可控制导航/重排/事件配方/卡替换/明确失败的受控站点。

**受控origin准入不放宽生产白名单。** 复用现有独立acceptance composition，采用显式native测试模式、隔离data root和签名包内受控fixture manifest，仅该composition允许受控origin；普通模式不能因URL/页面参数启用localhost。Host、transport、once fence与要验证的Provider实现使用同一产品字节，fixture receipt保持独立测试profile，永不进入production准入/用户库。L2在同签名App的测试composition运行，仍不等同普通线上L3；线上验收必须使用正常产品模式。

真实网站的输入必须经普通Riftlet UI或同一路径的授权测试触发，不绕过权限或直接调用setter。测试可用已授权系统UI自动化和辅助观察工具；观察器与产品回执分离，用实际卡片、独立截图/可访问树与脱敏上传成员证据核对结果。仅有产品自身 `accepted=true` 不足。不要为获取数据给产品加入默认截图录屏、抓cookies或网络代理。

L1/L2可统计原文件字节、setter和事件次数、接收事件、自动发送计数；L3至少独立确认原草稿各图一次、原文/选区/旧附件、无发送和操作关联，不能把无法观测的网络细节标PASS。源代码/受控统计与线上结果一起构成结论，不把网站内部网络重试误称Riftlet重复输入。

## 7. 时延与资源

统一记录 `click→nativeBound`、`click→inputEntered`、`click→positiveReceipt`、`positiveReceipt→trayHidden`，以及CPU/RSS/主线程最长阻塞。区分冷/暖、截图大小、网络、服务处理时间；不拿服务处理完成替代附加交接时延。

设计预算（不是本次测得结果）：在指定基准Mac及2 MiB内PNG受控页，输入前主线程连续阻塞不超过150ms，普通本地输入交接p95≤1.5s，收到正面证据后托盘反馈p95≤150ms。Chrome/Edge×ChatGPT相同环境相对最终1.0.7 p95不得恶化超过20%。超预算必须定位、修复或在RC报告说明明确的外部条件，不能单纯调大超时。

每Host L2至少30次有效样本后报告p50/p95/max；每核心格L3保留全部实际样本、成功率/失败数及延迟数组。小样本p95注明n并不给人群统计保证；失败/超时必须另列，不能从成功时延表隐去。受控30次为确定性容量测量，不等同线上可靠性统计。

连续100张受控截图、10分钟闲置与观察过期后检查缓冲/observer/tombstone边界、CPU/RSS趋势，不能线性保留完整图片。原图与受控大图库回归沿用1.0.7规则；不为追求性能删除未知操作或唯一媒体。

## 8. 结果schema

机器表按每个组合和case保存版本、证据等级、状态，至少含：

```json
{
  "candidate": {"sourceSHA": "...", "appSHA256": "...", "dmgSHA256": "...", "build": "..."},
  "environment": {"macOS": "...", "arch": "...", "browser": "...", "browserVersion": "...", "profileKind": "test-session"},
  "provider": {"id": "...", "revision": 1, "surface": "ordinary-chat", "mode": "...", "locale": "...", "accountTier": "..."},
  "caseID": "F03",
  "level": "L3",
  "status": "NOT_RUN",
  "reason": "No test executed yet",
  "operations": [],
  "evidenceRefs": [],
  "reviewer": null
}
```

每次真实operation填脱敏operation/target摘要、原件与payload hash、inputEntered计数或其可观察范围、原卡证据、acceptance/processing各自状态、原文/选区/旧附件结果、发送计数/可观察事实、四段耗时。未知填null/unknown，不填0冒充通过。用户真实URL、文本、图片、账户标识/cookies不进公开JSON；公开材料只用专用合成测试资产。

## 9. 统一放行规则

### 完整范围完成 / #120可以关闭

1. 16核心格在**同一个最终签名产品字节**全部满足F01–F06及本格必需反例；特殊scope明确。Safari实际版本/冷绑定/world门槛通过；Brave默认保护通过。
2. P0=0；核心P1=0；没有错投、自动发送、重复输入、假成功或旧库数据损坏。Chrome/Edge×ChatGPT最终1.0.7基线无回退。
3. T/I/E/P/D/R/X共同异常门槛通过，source/fixture/native/live等级不混淆。线上无法自然出现的服务终态失败可保持未观察，前提是同卡失败的L2证明充分，正常L3接受成立；不得因此伪造READY。
4. 独立非作者代码/产品/证据审查；原B→G→H准入和五个正式CI不降门槛。无源码共享覆盖、无绕过测试或假审批。
5. universal Developer ID签名、公证、staple、Gatekeeper、真实安装/升级、ARM64/Intel构建及既有要求通过。物理Intel/旧macOS未测如实写NOT_RUN，不能将Rosetta称物理Intel。App最低系统与各Host能力范围分开。
6. 如公开发行已获授权，Release、网站双语、Sparkle签名feed及实际下载指向同一最终hash；否则交付已验证可安装候选与待发行具体动作。任何包变化重新确认其证据范围。

### 允许继续推进、允许诚实部分候选，不允许冒充完整交付

扩展Provider/Firefox/旧Safari技术受限不阻塞已完成核心；未通过组合默认不启用，清楚标范围。核心某格 `BLOCKED_ENV/TECHNICAL` 时其他任务继续，可以交付部分候选；但#120保持打开、总报告标PARTIAL，不能称4×4已完成。若范围缩减涉及最终公开发行承诺，记录准确支持清单并遵循已有发行授权，不偷偷拆成多版本计划。

一次timeout/站点403只证明该次受阻；技术不可行必须有允许路线的最小复现与不变量缺口。完成确定测试后停止无目的扩大矩阵，不无限等待偶发线上失败，也不降低正面接收标准。
