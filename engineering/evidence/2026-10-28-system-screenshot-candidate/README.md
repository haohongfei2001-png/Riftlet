# 系统截图 Web 内部候选：源码、验证与准入边界

日期均为 Asia/Shanghai。本目录记录本轮实际工程交付，不新增总体计划，也不把 CI 改称真实截图验收。正式入口仍为 Draft PR #1。

## 不可变来源与可运行成果

| 项目 | 提交／范围 |
| --- | --- |
| 正式基线 | `b83923068064f6d82f2d253a3c177661fdabc294` |
| 独立实现分支 | `codex/system-capture-candidate-20261028` |
| 候选代码 | `3da1288f8b16fbf46082ebf78eab92a1e2089d22` |
| 截止边界修复及最终已测源码 | `4d352c28dcb70e8f6dc42ef93d9df46042a9215d` |
| 已测源码 tree | `c7a25f27976b47604fdec7c41097e9aec3cea3ce` |
| 正式集成 | 经非作者审查后，从 b839230 快进至 4d352c2；不重复合并第五至七轮，不写第八轮分支 |
| 最终证据／文档检查点 | 见 PR #1 的本轮最终交接评论；核对其构建/测试输入与上列源码一致 |

实际新增/修改22个源码、测试、资源/CI文件：本地输入资格preflight、真实截图候选scope/profile、有界首观察journal、共用App模式/组合、菜单入口、准确状态及原字节回归。既有截图文件监测、私有导入、v3状态、原单一Coordinator、Chrome执行器、v12 JS/MAIN、首用和历史均复用。没有浏览器扩展、云服务、新依赖、第二套队列或图片转码。

普通App菜单「打开真实截图内部候选…」或 `--system-screenshot-candidate` 打开 `Riftlet REAL TEST`，使用独立 `Riftlet-System-Screenshot-Candidate` 数据目录。符合上限的真实PNG可测试输入；当前start/completion/safe-failure仍全部为空，所以**未准入观察保持UNKNOWN且可见，不吞噬、不写成功、不重传**。普通capture仍不上传。完整入口与格式矩阵见[候选契约](../../../docs/SYSTEM_SCREENSHOT_WEB_CANDIDATE.md)。

## macOS 自动化证据

### 首次失败与修复：保留，不抹除

[Run40551210402](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40551210402)，job122355143771，源码3da1288：编译通过，432个原生case被调度；候选App自检在 `TransferCoordinator.swift:85` 的AcceptedSelection初始guard报告 `invalidTransition`。之后的详细复跑、包装拒绝测试、Release和App/helper自检均跳过，不算通过。

负责人随后找到可确定复现的原有浮点边界：`accepted=64.0.nextDown`，App构造 `deadline=accepted+30=94.0`；反减得到 `30.000000000000007`，旧条件拒绝合法选择。修复验证为与App同式 `deadline<=accepted+30`，不加epsilon、不放宽ACK/取消/dispatched/到期，新增恰好边界、nextUp及到期回归。非作者独立数值复现并审查通过。**初次CI没有记录实际uptime，不能把确定性示例说成初次运行捕获的具体值。**

### 独立候选完整 CI：PASS

[Run40551804340](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40551804340)，job122357244974，push/attempt1，actual checkout **4d352c28dcb70e8f6dc42ef93d9df46042a9215d**，于2026-10-28 **01:36:14** completed/success。完整日志229,199字符，由root和独立审查者分别获取核对。

- macOS14.8.9 / 23J631 / arm64 / Apple Swift5.10。
- **433个唯一原生case、52个suite**：Core135 / Adapters136 / Capture65 / UI53 / App44。
- 14组详细复跑100项passed、0skip，已包含433，不能累加宣传为533。
- 页面VM72、legacy54；原证据回放55files/19case/89prefix，2项迟到错误明确为SIMULATED。
- 8组离线fault、12组只读probe、第五轮helper9/4/2、12项Python打包测试通过；离线MID工具不证明真实MID注入。
- Release、资源/许可校验、ad-hoc签名及五个App/helper自检通过；原filePromise deprecation仍存在，没有伪称零warning。

### 正式 PR #1 组合 CI

[Run40553084871](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40553084871)，job122361764858，输入head4d352c2。于2026-10-28 **01:54:27** completed/success，17个步骤全部成功；完整日志228,373字符。重新执行的433个唯一原生case与候选集合一致，14组详细100项全部passed/0skip；72页面/54legacy、回放/故障/probe/helper/包装、Release/签名与五自检全部通过。

GitHub临时组合 `d3a1143ed9ff9e799f44819eecb0ec571ee0834d` 的双亲为main `eba1a4fc77648a665e1d5c1f2609df1314c3b079` 与4d352c2；root及非作者逐项比对13组原生/资源/构建/测试/回放输入，Git对象完全一致。**整个tree含main网站差异，不称整tree相同，也没有把main合入正式工程或改动网站。** 原候选push CI不能替代此组合运行。

精确run/job、全部原生测试名、软件回放统计、输入Git对象、日志hash与保护路径见 [verification.json](verification.json)；[ci-excerpt.txt](ci-excerpt.txt)仅摘录实际日志行。此目录不包含真实用户图片、聊天、私有数据库或浏览器凭据。

### 关键保护的实际回归

本轮完整原生测试实际执行冻结v1→v2→v3、v2→v3、迁移失败回滚/未来版本拒绝、原UNKNOWN和跨profile锁、原start/迟到失败补偿、错目标/附件拒绝、原点击等待/权限乱序/取消/唤醒及重启不恢复旧点击。

新增候选回归覆盖：格式/字节/像素/origin在prepare前拒绝；伪PNG头拒绝；头检查后hash损坏保持保守UNKNOWN且零begin/commit；旧不支持格式UNKNOWN仍只读；synthetic fixture不能用于真实图；journal只保存完整原身份六类首值、并发不覆盖、损坏/冲突不能替换；App普通模式与候选独立；开始/成功/安全失败权限互不推导。生成的>8MiB PNG与16-bit/P3 PNG原字节/hash/元数据在本地复制和恢复后保留。

新增候选自检明确输出：

```text
RIFTLET_SYSTEM_SCREENSHOT_CANDIDATE_SELF_CHECK_PASS:
original-byte import, one software input, closed admission,
durable candidate observations, read-only restart;
GENERATED_FIXTURE; CHROME_NOT_RUN; SYSTEM_SCREENSHOT_NOT_RUN; GUI_NOT_RUN
```

这里是为可读性换行的marker内容，精确日志行在摘录中。人工设置screenshot metadata的生成文件仍然是fixture；它不证明普通系统截图或真实浏览器输入。Bundle还明确 `NOT_NOTARIZED; GATEKEEPER_NOT_RUN`。

## 非作者审查

实际独立并行审查由未参与代码的Core/adapter、App/UI/格式和CI审查者完成，负责人亲自实现App/Core/adapter接线、修复、集成和证据。源码审查PASS，范围是**可取证且关闭准入的内部候选**，不是人类GitHub批准或生产验收。完整范围见 [review.json](review.json)。

已解决的真实问题：候选GUI启动不能把NSWorkspace回调当成初始化成功并退出普通收录；现在只启动独立实例、保留普通实例。初次CI后修复上述确定性deadline边界。文档把“已输入后”修为“持久intent后”，准确保留输入尚未发生时的保守UNKNOWN。没有对第八轮进行中实现提出替代方案或争写。

## 生产准入仍缺少的证据

| 门 | 必须取得的真实证据 | 本包状态 |
| --- | --- | --- |
| SC-INPUT | 原生系统截图metadata、原件/私有副本/hash/尺寸、原点击ACK/完整target、asset/op/attempt与唯一输入绑定 | NOT_RUN |
| SC-START | 原图原操作的严格正向开始、真实请求/进度与输入的因果次序；排除占位、错目标、错图和迟到开始 | NOT_RUN；start map空 |
| SC-COMPLETE | 同一图片实际ATTACHED及原草稿归属，未聚焦编辑器亦不改文字/选区/旧附件；明确页面/版本范围 | NOT_RUN；completion map空 |
| SC-ANOMALY | 真实网络/导航/身份变化、观察丢失、重启及迟到错误；保留旧UNKNOWN并禁止第二次输入 | NOT_RUN |
| SC-FAILURE | 真正关联强失败，旧上传安全终止、无迟到成功和残留自动retry；须补齐既有absence-only信号缺原attachment ID的退役身份关联，新尝试仅由新点击 | NOT_RUN；failureSignal为nil、safe-failure map空 |
| SC-UX | 开始准入后真实一次点击→开始→快吞噬测量、冷首击、透明透传、按住补位/屏幕、自包含及系统延迟 | NOT_RUN；第八轮成果等待独立交接 |

候选journal不是最终准入证据的替代品，仍需真实执行上下文和完整身份。真实截图与原日志留在本地，公开只提交经脱敏且可核对的记录。获得并审查真实start后可只登记候选start策略并复用原UI快吞噬；最终成功、安全重试和普通生产启用分别审查，不能一次打开所有门。

第七轮双图限定PASS、冷首击FAIL、CLEAR透传FAIL、GAP软件范围与业务ABA/MID/物理GUI开放项都保持。没有把生成图POST100或DOM故障注入升级为真实系统截图安全失败，也没有把旧时延复制为当前候选实测。第八轮本地工作树、真实Mac和私有数据本包未访问。

## 开发 App 与续做

[正式组合制品12756447786](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40553084871/artifacts/12756447786)，包含开发App/helper/测试日志；1,868,417 bytes，GitHub metadata和上传日志SHA-256 `341391a32abd2c8a3685a1a4dc26824720aa59f8d2c123bb30a44399b381debf`，保存至2026-11-11 **01:54:21**。制品按actual checkout d3a1143命名；原生/构建/测试输入与4d352c2一致，整个merge tree仍含main网站差异。

候选push制品另存于[12754788283](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40551804340/artifacts/12754788283)：1,868,665 bytes，GitHub metadata/上传日志SHA-256 `7b24c0c491250cfe96b1cf34ec844ded166b32377e1e7698d5905ee7273cc5a1`，到期2026-11-11 **01:36:07**。未下载并独立重算ZIP；永久来源是本仓库代码与上述证据。开发包仅ARM64/ad-hoc，不是公开发行。

本地Codex在第八轮适当结束、与root正式交接之后，从PR #1最终SHA新建worktree，按[直接入口](../../../docs/INTEGRATION_HANDOFF.md#下一次真实mac直接入口)开始真实截图取证。保留原数据库/私有图片/旧UNKNOWN/补偿，不清库、不重传、不自动Send。main不改，PR #1继续Draft，无发布。
