# 一个开发周期的工作包与集成规则

一个实现 PR，内部逐层提交；不按浏览器/AI各发独立版本。版本号由 W0 根据最终1.0.7状态确定，本规划不抢占版本和 build number。

## 1. 唯一集成负责人

接收 [CODEX_HANDOFF.md](CODEX_HANDOFF.md) 的主 Codex 是集成负责人，对共享契约、主程序、数据迁移、最终包与事实报告负责。它可以自行启动子任务；用户不承担跨窗口分工、合并冲突或手动逐格测试。

**共享路径只由集成人修改：** `Sources/RiftletCore/**`、现有 `WebAttachmentAdapter`、`ChromeAppleEventsExecutor` 及桥接/点击绑定公共代码、现有大页面JS的抽取、`RiftletMain`、`Package.swift`、公共UI/权限入口、版本/资源打包、CI、`engineering/mainline/source-admission.json`、最终报告/refs。其他工作包只在冻结接口后的独占新目录或独立worktree提交，提出共享变更建议，由集成人依序应用。

建议同一时刻四个角色：集成人、Host工程师、Provider工程师、独立QA工程师。若使用更多执行者，Provider文件按平台拆独占路径；不得让多个worker同时编辑公共script和store。QA不得自报自己实现的代码为独立审查通过。

## 2. 工作包

| 包 | 必须/条件 | 依赖 | Owner / 独占范围 | 完成标准与交接 |
|---|---|---|---|---|
| W0 基线与环境 | 必须，首项 | 无 | 集成人 | 重读main/#117/#118/#119/comments；记录最终1.0.7产品SHA、准入SHA、包hash/门槛；检查是否合入main。清点可用macOS、签名、各浏览器、合法登录测试会话；缺口只阻塞对应格。建立新的实现worktree/PR，绝不从本规划旧main写产品 |
| W1 契约与兼容桥 | 必须，先于并行实现 | W0代码基线可用 | 集成人 | 实际可编译Host/Provider/Resolver类型、共用JS协议和能力字段；Chrome/Edge×ChatGPT回归；旧UNKNOWN/profile可解码且只读。冻结接口commit和独占文件清单，实际示例Provider可运行 |
| W2 Safari/Brave | 必须，早做技术验证 | W1；S0环境检查可与W1并行 | Host工程师；建议 `Sources/RiftletAdapters/BrowserHosts/{Safari,Brave}*`、对应新测试 | BROWSER_SPIKES S0–S3，冷首次绑定/原生对象/world/Navigation API/权限/真实输入；Brave默认Shields。交付实现、精确能力范围、原生受控证据，后续统一L3矩阵。每个Host可独立合入，不互相等待 |
| W3 核心Provider | 必须 | W1 | Provider工程师；建议 `Sources/RiftletAdapters/ConversationProviders/**`、`Resources/Providers/{Claude,Gemini,DeepSeek}/**`、对应新fixtures | 先Chrome×Claude完整纵向链校准接口，再Gemini/DeepSeek并行；每站输入配方、精确原附件证明、mode/surface、失败、取消和选区已验；不能伪装chatgpt-web；最后与4Host组合实测 |
| W4 扩展Provider | 同轮必须调查并争取实现；启用需证据 | W1，至少一个W3纵向链通过 | 可独立Provider worker；按Kimi/国内千问/豆包/Perplexity目录分工 | 逐站真实能力探查与适配，优先中国用户价值；国际Qwen独立变体；每个公开支持组合L3通过。无能力/缺登录不臆造；Grok仅在不挤占核心修复时加入 |
| W5 统一QA与体验 | 必须，全程并行 | W1接口；基线回归可先行 | 独立QA；建议 `Tests/BrowserProviderMatrix/**`、`scripts/acceptance/**`，UI改动由集成人做 | 一套Browser×Provider×Case runner/证据schema，自动生成兼容表；L1/L2/L3分层、故障注入、原稿独立oracle、性能；首次授权/失败文案有真实App截图，不给用户测试清单 |
| W6 Firefox/旧Safari预研 | 同轮必须结论；不阻塞W2–W5 | W1 | 有空闲Host工程师；独占原型目录/分支 | Firefox一个工程日初始预算，旧Safari一个独立有限验证；最小复现+能力依据+为何通过/受阻。满足全部标准才升级正式Host/版本范围；不能降门槛换数量 |
| W7 集成与候选 | 必须 | W2/W3/W5核心成果；W4/W6可隔离 | 集成人 | 源码整合、最小增量迁移、旧库升级、签名universal候选、manifest只启用已通过范围。接口变动由集成人发布新契约commit，相关worker跟进，不各自兼容猜测 |
| W8 独立复核与交付 | 必须 | W7 | 非作者QA审查；集成人修复/发布准备 | 同最终候选16核心格验收、异常/包/CI/升级门槛；实际支持清单、FAIL/BLOCKED/NOT_RUN、下载候选、简短说明。完成已有授权的发行步骤；无公开发布授权时止于可安装可评审候选，不擅自合并/上线 |

### W0遇到1.0.7仍在收口

不改 #119，不从旧1.0.5复制出另一套附件核心。先并行完成独立的浏览器能力/权限检查、测试fixture、Provider真实DOM能力记录以及明确无需改共享代码的探索。实现总负责人保留 `WAITING_FOR_107_BASELINE` 的短记录；一旦1.0.7收口并进入实际main，自动接续。若最终候选已公开可读但未入main，可以在独立临时worktree验证接口，不把它冒充正式实现基线或合并进main。不要要求用户重复协调已明确的分工。

## 3. 第一条可运行的纵向链

W1不是只写接口的重构。保留最终1.0.7 Chrome/Edge×ChatGPT原行为；然后用Chrome×Claude（如账号环境阻塞，可先Gemini）走通：点击冻结→能力检查→一次输入→原卡片正面证据→原文/选区/旧附件保留→同卡失败恢复→崩溃后只读核查。不能只做到“DOM找到input”。新Provider若揭示契约问题，先由集成人修正，再扩其他平台。

W1/W5复用隔离acceptance composition承载本地fixture，不放宽普通模式生产origin白名单；精确规则见ACCEPTANCE §6。公共manifest同时冻结resource digest和revision；已有相同sourceID不同字节不应被误当同实现。

Safari能力验证从早期同步推进，不等所有Provider写完才发现Host无法绑定原稿。Brave、其他Provider和QA不因Safari/Firefox单个障碍停工。

## 4. 每个工作包交接的最小材料

1. 源码commit、测试命令/结果、独占修改路径、接口版本。
2. 当前能力：输入配方、目标/图片证据方式、已验surface/浏览器版本、受限条件。
3. 已执行证据等级与原始结果引用；未测项/失败样本保留，不以重跑成功覆盖。
4. 集成要求只列具体共享变更，不复制整份历史PR/文档。

质量发现使用 #120 内稳定的 `R120-*` / case ID；不另建重复任务系统。严重风险先汇报给集成人并修复，不等待所有包写完。

## 5. 上下文与提交

- 每完成一个有意义工作包或约60–90分钟有效工作，提交完整可恢复checkpoint，更新短 `PROGRESS.md`：模块、状态、SHA、实际测试级别、下一项。不是每条测试都改源码/触发签名。
- 单次只读相关文件/差异；大型JSON/日志写入本地或适当artifact，不反复输出整棵仓库、全部旧PR或数百份证据。
- 切换会话前保留基线SHA、工作树路径、未提交状态、待集成commit、复现命令、阻塞责任和下一步。预留至少约20%上下文给验证、commit、交付，不等耗尽才交接。
- 源码冻结后把同包实测结果写入单一结果记录/PR验收评论，避免每格结果触发新build。产品字节改变则新包hash，按影响重新验证；改变共享输入/identity/receipt需要整个核心矩阵复验。

## 6. 技术不可行、环境阻塞与优先级

| 等级 | 内容 | 处理 |
|---|---|---|
| P0 | 错窗口/草稿、自动发送、重复输入、私有数据损坏或泄露、假成功吞图 | 立即关闭受影响新输入，修复并独立回归；共享机制有问题则整个版本不能发布 |
| P1 | 核心组合常规路径不可用、冷首击不可靠、明确失败无法找回、原文/选区/旧附件受损、升级/签名不成立 | 对应核心格不通过；集中修复，不能用受控PASS代替线上。共享旧功能回退阻止发布 |
| P2 | 扩展站点未完成、Firefox受限、旧Safari未验、少见surface/locale缺口 | 明确能力范围与合理短反馈；不阻塞已完成工作包，但不能称该格支持 |
| P3 | 无影响的命名/目录美化、推测式框架升级 | 本周期不占核心交付时间 |

`BLOCKED_ENV` 必须说明缺哪个二进制/OS/权限/账号/合法会话，并先寻找现有获授权执行环境。不要复制cookies/整个profile来逃避登录边界。必要的账号登录属于用户身份动作，不是让用户做验收；若确需用户动作，集中给出最短一项，其余任务继续。

`BLOCKED_TECHNICAL` 必须有当前官方依据或最小受控复现、尝试的允许路线、失败的不变量、可行替代及范围影响。不能把“没研究/找不到selector/网络403”写成技术不可能；也不能无限试错掩盖不可行。

完整核心目标：16格L3通过且所有发布硬门槛通过。若因真实技术限制只完成部分，交付明确部分候选、默认关闭未通过格，#120保持打开。公开发布按既有流程及实际授权，不隐式改成下一版本拆分，也不要求用户为了“全绿”接受错误行为。
