# Engineering verification record

2026-10-27 Asia/Shanghai. Initial foundation branch based on `5a3ab5d7a761d5397f8bc15b6f40d761b29e58d2`.

## Evidence categories

- Source implementation is not runtime validation.
- Linux static checks and the inherited Oracle offline fixture do not prove macOS or ChatGPT behavior.
- macOS CI compilation/tests/package smoke do not prove interactive focus, click-through, Spaces or real upload.
- No real user screenshots, chats or browser sessions are used in automated tests.

## System-screenshot internal candidate — current tested source

正式基线b839230；实现3da1288，已测修复 **4d352c28dcb70e8f6dc42ef93d9df46042a9215d**。独立候选push [CI40551804340](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40551804340) / job122357244974于2026-10-28 **01:36:14北京时间** completed/success，actual checkout为同一4d352c2：**433原生**（Core135/Adapters136/Capture65/UI53/App44，52 suites），72页面/54legacy、原55files/19case/89prefix/2明确SIMULATED迟到错误回放、8fault/12probe/9+4+2helper/12包装、Release/签名与五自检。14组详细复跑100项passed、0skip，已计入433；未用复跑数增加总数。

原v1→v2→v3/v2→v3、rollback/未来版本、UNKNOWN/旧观察/补偿/跨profile锁、权限乱序/等待/取消/唤醒/旧点击不恢复本次完整执行。新候选仅生成PNG/人工截图metadata/fake bridge；16-bit P3与>8MiB原字节保存是本地保真证据。候选可执行自检明确输出GENERATED_FIXTURE/CHROME_NOT_RUN/SYSTEM_SCREENSHOT_NOT_RUN/GUI_NOT_RUN，不能准入真实截图开始、最终完成或安全重试。

正式PR #1的独立组合运行是[CI40553084871](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40553084871)，于2026-10-28 01:54:27北京时间completed/success，17步骤全部通过，433唯一原生与候选集合相同，100详细项0fail/0skip，原页面/回放/迁移恢复/Release/五自检通过。actual checkout d3a1143与4d352c2的13组原生/构建输入对象一致（非整个tree一致）；228,373字符完整日志、artifact、hash与非作者审查保存在[本轮永久证据](../engineering/evidence/2026-10-28-system-screenshot-candidate/README.md)。候选push与正式PR运行分别记录，不互相冒充；最终文档HEAD见PR #1交接，并核对原生/构建/回放输入未变。

首次[CI40551210402](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40551210402)确实失败：432项中候选App自检在AcceptedSelection初始guard报告invalidTransition，后续Release/自检跳过。修复原先 `deadline-accepted<=30` 的可确定复现浮点误拒，使其与App原 `accepted+30` 同式验证；新增exact/nextUp/到期回归。未记录失败时uptime，不声称首轮日志证明了具体浮点值。修复后重新完整运行通过，不把原失败隐藏或计为通过。

## Round-seven accepted-selection integration — preceding tested source

已测 **`595142d0345adc0d06f54371f50406879310610d`**，在双亲合流2aaaadb（e3175f3 / 3b089b2）上补齐原UNKNOWN点击的权限接收进程保护。[完整macOS CI40543025253](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40543025253) / job122326159138于2026-10-28 **00:41:17北京时间** completed/success，17步骤全部成功。**410原生**：Core134 / Adapters121 / Capture63 / UI53 / App39；页面72/legacy54，原回放55文件/19case/89prefix/2明确模拟迟到错误、8fault/12probe/9+4+2helper/12包装，Release/签名及四自检通过。

新增定向权限回归2项；AcceptedSelectionQueueTests17、SelectionAuthorityTests4、SelectionSubmissionQueueTests3与原7详细组共77项均passed、0skip，已含410。实际冻结v1→v2→v3/v2→v3、回滚/未来版本拒绝、UNKNOWN/重启/原start/补偿/跨profile锁均在完整列表。两项新XCTest类隔离warning已消除，既有filePromise deprecation仍保留。

[永久验证](../engineering/evidence/2026-10-28-integration-round7/verification.json) · [非作者审查](../engineering/evidence/2026-10-28-integration-round7/review.json) · [100行实际日志摘录](../engineering/evidence/2026-10-28-integration-round7/ci-excerpt.txt)。完整日志209,434字符；root核对13组输入，非作者另通过GitHub tree核对9根。实际checkout1965e22为main eba1a4f +595142d的临时组合，原生/构建/测试/回放输入一致，整tree含main网站差异；未合main。macOS14.8.9/23J631/arm64/Swift5.10。

[制品12751661331](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40543025253/artifacts/12751661331)，1,800,286bytes，GitHub metadata SHA-256 `7c490ad62ebdbe588ff16862bd1d5a1a8f7fff92aecab3d0603a36e67ab5fb0e`，到期2026-11-11 **00:41:12北京时间**；未声称本地下载重算。CHROME_NOT_RUN/GUI_NOT_RUN/PERMISSIONS_NOT_REQUESTED/NOT_NOTARIZED保留。2aaaadb的run40542404369被后续源码推送取消，不计通过；来源9de6a85的408项CI40525056642另独立核实。

原15份第七轮证据及此前15目录未改。真实双图与非空草稿保留只属于f6417c6的生成图/software AX样本；CLEAR防误选属于9de6a85软件实击。冷首击仍FAIL，CLEAR透传FAIL，GAP仅software；业务ABA/MID/安全失败/物理GUI/自包含/正式修复后真实权限时延仍独立。不得用本CI批准生产或重传。

## Round-six transfer and identity with first-use — preceding tested source

已测 **`81b6a61b4e648a1b8d6ccf4b569fd6d727a0cc76`**，双亲1246c4a/65f7d54。[CI40523594732](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40523594732) /job122256992376 completed/success，2026-10-27 **22:44:24北京时间**。380原生：Core117/Adapters121/Capture63/UI52/App27；72页面/54legacy；原回放19、故障8/probe12、第五轮helper9/4/2、包装12、Release/签名与四自检通过。生命周期13/首用3/Capture15/呈现4/Web组合5/权限恢复8/严格descriptor5均详细passed、0skip，全部包含在380内。

[永久验证](../engineering/evidence/2026-10-27-integration-round6/verification.json)记录所有测试名、迁移/原操作恢复、原13文件hash、16个未改对象及13个CI输入；[非作者审查](../engineering/evidence/2026-10-27-integration-round6/review.json)另独立取完整192,634字符日志。实际checkout ba63e76由main eba1a4f与81b6a61临时组合；原生/构建/回放对象一致，完整tree含网站差异，不宣称整个tree相同，未合main。来源c000cc1的CI40513086114另独立确认325原生通过，原queued记录保留为历史。

[开发制品](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40523594732/artifacts/12743890195)1,656,810bytes，GitHub元数据SHA-256 `471f46ba8b32e14d0a7335a240e180c796ac16d29fd85233a91862769389b554`，保存至2026-11-10 22:44:17北京时间。未声称本地下载重算。macOS14.8.9/23J631/arm64/Swift5.10；真实Mac27.0/Swift6.4的证据另列。

5.51→3.67秒是7878de3+overlay单次对照；c000cc1仅真实只读capture，无新上传。新正式权限前置/时延、fallback、物理GUI等NOT_RUN，冷首击与第二图targetBusy产品FAIL，生产/安全重试未开放。第七轮只有[共享审查边界](ADAPTER_CONTRACT.md#第七轮顺序调度共享边界-v1实现待正式交接)，没有本轮队列实现或双图准入。

## Round-five Web start with first-use — preceding tested source

已测 **`caa6a65b69c6038154a2fff65f2fb1157125bb7e`**，双亲e655b1e/3bb13999，[macOS CI40515643640](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40515643640) /job122228775354 completed/success，2026-10-27 **21:53:30北京时间**。369原生（Core117/Adapters110/Capture63/UI52/App27），页面68/legacy45，第五轮离线helper9/4/2，包装12，旧55文件/19用例/89轨迹前缀/2明确SIMULATED迟到错误、故障8/probe12，Release/bundle/签名与四项App/helper自检全部通过。

生命周期13、首用窗口3、Capture15、新呈现边界4、Web组件组合5、被动权限恢复8详细复跑全部passed/0skip；均已包含在369内。真实SQLite v1→v2→v3/v2→v3、回滚/未来拒绝、UNKNOWN重开/旧锁/补偿回归实际执行。新Web组合使用真实adapter/normalizer/Core/App policy及假桥/假权限，不是Chrome/TCC或网络验收。

[第五轮合流证据](../engineering/evidence/2026-10-27-integration-round5/README.md)记录完整测试名、原27文件hash和18个未变保护对象；[非作者审查](../engineering/evidence/2026-10-27-integration-round5/review.json)由各作者之外的执行者完成，实际CI另独立从GitHub取证。实际临时checkout ed5397665b6586729237244211a9fbcc0ef175c5的13组输入与正式源码相同，父为实际main eba1a4f和caa6a65；未合main。macOS14.8.9/23J631/ARM64/Swift5.10。

[开发App/helper/日志](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40515643640/artifacts/12739217183) 1,650,427bytes，SHA-256 `98bb5f342e02d4196b6ec8acd8cf56835c6eaf5e1179c7d84761b2d889369d4d`，保存至2026-11-10 21:52:28北京时间。原27份证据字节保持；raw patch的原上下文空白不改写，作者源码格式检查通过。

第五轮真实v11限一个预绑定/聚焦空草稿/software AX生成图，并非本合流二进制权限/时延验收。新真实TCC、权限恢复、冷首击/业务转换/网络故障/物理GUI仍未通过；生产和safe retry未准入。第六轮进行中源码未读取或合并。

## First-use and release foundations — preceding tested source

已测 **`2449d40a88225acba9d413cc6a4cb5d84fcae6a1`**，[run40508109228](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40508109228) / job122202566296 completed/success，2026-10-27 **21:00:40 北京时间**。344 原生：Core117 / Adapters102 / Capture63 / UI48 / App14。新增38项已包含在总数；详细复跑生命周期13、首用窗口3、Capture15全部 passed/0 skipped，HEIC和受控 POSIX 权限拒绝均明确执行。Python包装12，页面48/legacy14，原55文件/19用例/89轨迹前缀/2明确SIMULATED迟到错误，故障8/probe12、Release/签名及四个 App/helper 自检全部通过。

完整测试名、实际阶段、Git 对象、制品及范围见 [verification.json](../engineering/evidence/2026-10-27-release-ux/verification.json)；非作者分别从 GitHub 读取实际日志复核，见 [review.json](../engineering/evidence/2026-10-27-release-ux/review.json) 与 [原日志摘录](../engineering/evidence/2026-10-27-release-ux/ci-excerpt.txt)。macOS14.8.9/23J631/ARM64/Swift5.10；实际临时checkout `f3531dfc6143bdf95816c8d77ff17af3fb8cf2c8`，父为实际main `eba1a4f`和已测2449d40；12组构建/测试输入与正式源码相同，未合并main。

[可运行开发 App/helper/日志](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40508109228/artifacts/12735493443) 1,585,247 bytes，GitHub SHA-256 `edb3bf6742907d35bdbbf37e260c65a13839067f41e280ac439027873e7a9412`；保存至2026-11-10 21:00:36北京时间。首轮4e080aa的run40507790526在两处测试自动闭包缺少try时编译失败，native NOT_RUN、后续Release等SKIPPED；2449d40只补两个try后完整重跑，未改断言/策略。失败制品只有日志，不当成可运行App。

真实 TCC、文件夹书签、Finder/Gatekeeper、物理VoiceOver/窗口/屏幕、真实HDR/EXIF命中及新增权限查询的实际Web点击时延仍NOT_RUN。自检保留PERMISSIONS_NOT_REQUESTED/CHROME_NOT_RUN/GUI_NOT_RUN/GATEKEEPER_NOT_RUN。Core/SQLite v3与Web源保持起点e89d49f不变，原迁移/UNKNOWN/补偿回归包含在完整CI中；本次没有新增真实上传证据，不改变生产准入。直接入口见 [FIRST_USE_ACCEPTANCE](FIRST_USE_ACCEPTANCE.md)。

## Round-four Web + v3 lifecycle — preceding integrated source

**完整合流 macOS CI 与独立复核已通过：** 已测源码 [`c85020b`](https://github.com/haohongfei2001-png/Riftlet/commit/c85020b0ae250eaa37f7ed812c3c43587dca5a91)，[run40484855920](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40484855920) / job122123985228，于2026-10-27 **17:59:57北京时间**记录完成成功。**306项原生**（Core117 / Adapters102 / Capture48 / UI39），48页面VM、14旧观察器VM、8故障离线组、12只读probe组、55文件/19用例/89轨迹前缀/2明确模拟迟到错误回放全部通过。生命周期详细13 passed /0 skipped，包含7项软件面板测试，未重复计入306。Release、ad-hoc签名、三个App/helper自检通过，CHROME_NOT_RUN/GUI_NOT_RUN保留。

[验证与11份原证据清单](../engineering/evidence/2026-10-27-integration-round4/verification.json) · [非作者审查及首轮编译修复](../engineering/evidence/2026-10-27-integration-round4/review.json) · [实际日志摘录](../engineering/evidence/2026-10-27-integration-round4/ci-excerpt.txt) · [development App/helper/日志](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40484855920/artifacts/12724099125)。本页所在的最终文档检查点与c85020b的12组源码/测试/构建/回放输入对象相同，确切正式HEAD以PR #1最终交接记录为准；不能把c9c68a6或b848920的旧运行冒充本次验证。

SQLite真实冻结schema的v1→v2→v3/v2→v3、迁移整体回滚、未来版本拒绝，以及UNKNOWN、旧nil/cross-profile锁、补偿重开、迟到错回执、M1恢复均在本次原生执行中。新增12项只针对本轮身份和精确诊断，不代表增加真实GUI或网络样本。

最初2ddd406的run40484533371在新增测试227行缺少右括号处编译失败，native未运行、后续Release/selfchecks跳过；c85020b仅补1字符后重跑完整pipeline成功。静态审查漏掉该语法错误与后续非作者复核都保留于review记录。生产/安全重试策略未调整。

实际CI临时checkout为8d0a1aa17b181951f2b45ea3a8f6e5a4e8ba0b3b，父为当时实际main eba1a4f和c85020b。root读取Git对象逐项核对12组构建输入与正式源码相同。GitHub run所附PR base元数据仍报告5a3ab5d，不能替代实际checkout来源；本轮没有写main。Artifact12724099125为1,469,787bytes，GitHub SHA-256 `95d2aad5719216772f2925275354684cb14e9355e90f71cbb59edbceb124497b`，2026-11-10到期。runner为macOS14.8.9/23J631/arm64/Swift5.10。

真实证据只保留第四轮一次预绑定、空草稿、editor未聚焦的生成图片物理首击。旧v6直接只读观察input3→3，但结果invalidated/exactfalse；不等于App重启或livev7恢复通过。无可观察ABA反例仍FAIL，冷首击、原非空正文/附件/选区、MID、物理GUI、自包含、实际uploadStarted快吞噬均不被本次CI关闭。

## Approved interaction lifecycle — preceding implementation


**本轮完整 macOS CI 与非作者审查通过：** 已测输入 [`d834a3a4a76cacedd0cb763044085c9c2093680c`](https://github.com/haohongfei2001-png/Riftlet/commit/d834a3a4a76cacedd0cb763044085c9c2093680c)，[run 40479556833](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40479556833) / job 122106130530。**287 项原生**（Core 110 / Capture 48 / UI 39 / Adapters 90）、38 项页面 VM、8 组故障工具、12 组只读 probe、历史回放 55 文件 / 19 用例 / 89 trace 前缀 / 2 明确模拟迟到错误全部通过。Release、ad-hoc 签名和三个 App/helper 自检通过。新增逐项输出确认 **13/13 生命周期测试 passed，0 skipped**，其中 7 项实际 AppKit 面板软件测试；重复报告这 13 项没有增加测试总数。

[永久验证](../engineering/evidence/2026-10-27-interaction-lifecycle/verification.json)、[非作者审查](../engineering/evidence/2026-10-27-interaction-lifecycle/review.json)、[日志摘录](../engineering/evidence/2026-10-27-interaction-lifecycle/ci-excerpt.txt)、[可运行 development App/helper/日志](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40479556833/artifacts/12721893223)。Swift 5.10 / macOS 14.8.9 / ARM64；artifact SHA-256 `cea0daab14fcbbc3b18509e1ec902ec913d776bc07acf19621983b71a37d0122`，保存期限至 `2026-11-10T09:18:09Z`。临时 PR checkout `e0b2688cf99ed83ae949af700dedee58094fa2d1` 与 main `eba1a4fc77648a665e1d5c1f2609df1314c3b079` 的合流只用于 CI；**没有合并 main**。后续文档检查点保持本次已测 Sources/Tests/构建输入不变。

This is execution of the new source, not a relabel of the earlier 228-test run. The 59 new regressions comprise Core lifecycle 33, frozen-schema migration 4, UI lifecycle 13 and history projection 9. SQLite v1→v2→v3, migration/receipt rollback, UNKNOWN/restart, late-failure compensation and ownership/selection races are included. No real upload-start profile or safe-retry profile was admitted.

The first two runs (40478082614, 40478471194) and their concrete fixture failures are retained in the machine record. Run 40478942469 first completed the full pipeline; the current run adds detailed software-panel outcomes. Seven screen-dependent tests passed in the CI WindowServer; physical input, focus, Spaces, multiple monitors, real upload start/failure and resource/latency acceptance are separate. Current successful completion does not erase those limits.

## Round-three formal integration — historical a441c70

**第三轮完整工程 CI 通过：** 已测正式输入 [`aa4fd2b9ed64efb83d9b7c8b29102cbd91d03e2b`](https://github.com/haohongfei2001-png/Riftlet/commit/aa4fd2b9ed64efb83d9b7c8b29102cbd91d03e2b)，[run 40471069966](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40471069966) / job 122078052804，于 **2026-10-27 16:06:16 北京时间**成功。**228/228 原生**（Capture 48 / Core 73 / UI 17 / Adapters 90）、**38/38 页面 VM**、**8/8 故障工具离线组**、**12/12 只读网络 probe 离线组**、历史回放 55 文件 / 19 用例 / 89 trace 前缀 / 2 明确模拟迟到错误、Release、ad-hoc 签名及三个自检全部通过。实际日志已核对 SQLite v1→v2 迁移/回滚、UNKNOWN、迟到失败补偿、逻辑草稿、预绑定、MAIN 回执和 M1 恢复。

[永久验证记录](../engineering/evidence/2026-10-27-integration-round3/verification.json)、[非作者审查](../engineering/evidence/2026-10-27-integration-round3/review.json)、[实际日志摘录](../engineering/evidence/2026-10-27-integration-round3/ci-excerpt.txt)、[工程制品 12718636844](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40471069966/artifacts/12718636844)。制品 SHA-256 由 GitHub 元数据提供：`fe204a7566b4dc0fb6c0d94d7e7cb4d73d786d36c038278b40985cd624de0d1e`。CI 临时 PR 合并为 `f202d50cad83b9ea132fe3f4d478a08956255752`，检查与当时 main `eba1a4fc77648a665e1d5c1f2609df1314c3b079` 的兼容性；没有合并 main。最终交接只更新文档/记录，未改变已测构建输入。自检明确 `CHROME_NOT_RUN` / `GUI_NOT_RUN`；CI 不扩大真实 Mac 验收范围。

The non-author native reviewer identified a concrete observer-cache defect: a new Chrome launch reusing an old PID could retain the previous AX observer. Root corrected the cache to require both PID and launchDate, reject missing launch identity, and clear both on stop. The reviewer approved the correction. Full native compilation and existing regressions passed on the integrated build; no real OS PID-reuse trial is claimed. All other product, test and workflow inputs equal `159b3ef`; Core, Capture and M1 remain identical to `7d6bca6`. The original 12 files, including 8 JSON records, are unchanged. Integration records are stored separately.

The predecessor [run 40467839636](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40467839636) tested `159b3ef`: 228 native tests, 38 page VM cases, 8 fault groups, 12 probe groups, archive replay, Release/signature and three self-checks passed at 2026-10-27 15:35:07 Beijing. Independent review distinguishes that compiled source from the earlier uncommitted native/helper exploration. The original probe author's self-review is now supplemented by two actual non-author reviewers.

The [third-round source handoff](../engineering/evidence/2026-10-27-real-mac-round3/README.md) records 600.002383 seconds and 61 resource samples from the actual capture-only App, including one CLI screenshot imported from 5 to 6 pending items and no upload. The resource summary was recalculated from the samples; CPU time of 0.73 seconds comes only from the archived `ps` summary. Ordinary root commits, restoration and AX scheduling are scoped observations; they do not establish first-click or real business A→B→A acceptance. The isolated App screenshot self-inclusion test is **FAIL**. CLEAR was not actually hit, and the automated GAP result covers one point. Physical N1, MID, complete latency and the production loop remain NOT_RUN or NOT_EXERCISED. This round performed no new real upload. Loss of some old v6 observation capability under v7 remains an explicit compatibility defect despite preservation of media, databases and audits. See the [current handoff](INTEGRATION_HANDOFF.md) for direct fourth-round actions and unchanged admission gates.

## Round-two formal integration — historical 7d6bca6

**第二轮完整工程 CI 与非作者审查通过：** 已测正式输入 [`39046d16823401c50ce3527ec1204e7517e1078a`](https://github.com/haohongfei2001-png/Riftlet/commit/39046d16823401c50ce3527ec1204e7517e1078a)，[run40462287936](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40462287936) / job122049461297，于2026-10-27 **14:39:36北京时间**成功。**227/227原生**（Capture48/Core73/UI17/Adapters89）、**31/31页面VM**、**8/8故障工具离线组**、历史回放55文件/19用例/89前缀/2明确模拟迟到错误、Release/签名及三个自检全部通过。SQLite v1→v2迁移/回滚、UNKNOWN/补偿、logical11、scheduler8、MAIN7和M1恢复均在实际日志核对。

[永久验证](../engineering/evidence/2026-10-27-integration-round2/verification.json)、[非作者审查](../engineering/evidence/2026-10-27-integration-round2/review.json)、[实际日志摘录](../engineering/evidence/2026-10-27-integration-round2/ci-excerpt.txt)、[工程制品12714722940](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40462287936/artifacts/12714722940)。源码/测试与fff0e8c一致，最终文档提交不修改已测输入。临时PR测试合并17dc667不是main合并；PR #1保持Draft，不发布。CI自检明确CHROME_NOT_RUN/GUI_NOT_RUN；不冒充本地真实验收。

Artifact12714722940: **1,123,280 bytes**, SHA256 `68505ec7e5cfb2d59827a1a4ac1132128b5e6376aaf451e0049ec9cf4c46248a`, expires2026-11-10. Runner: macOS14.8.9/build23J631/arm64, Apple Swift5.10. Root and the independent evidence reviewer each read run/job/full logs/artifact metadata. The 48 selected actual regression execution lines are retained alongside compiler, fixture and self-check lines; they are not a new test suite. Build times27.79s(debug/tests),18.22s(release) are CI durations, not screenshot latency.

The source predecessor's [run40458148137](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40458148137) atfff0e8c passed227native/31page; that historical run did not contain root's new8-group CI step. The current full run above did. Root did not add unrelated product tests merely to increase counts. All11 incoming evidence files are identical to8d7007e, including the eight JSON records and fault template/test. New integration evidence is kept separately. Core's non-author additionally executed the exact extracted migration SQL in Linux SQLite3.53.1 at8rollback/reopen boundaries; this is not Swift, process-kill or power-loss proof.

### Current inherited real-Mac scope

Second-round local sourcefff0e8c and [handoff8d7007e](../engineering/evidence/2026-10-27-real-mac-round2/README.md) record scoped existing-thread generated-image success, UNKNOWN observe-only recovery, original background proof/DOM-marker compensation, and an actual bound POST100 XHR abort after UI100 with UNKNOWN/restart retention. These are separately classified: synthetic VM is not live network evidence; DOM compensation is not post-consumption network failure; queued complete progress after abort is not server success. Raw private pixels/network payloads were not imported or newly captured by the integrator.

MID did not bind/abort its bytes. Full UX-01/02, unobservable React A→B→A, physical N1, screenshot self-inclusion isolation, full source→clickable latency/resources and production two-operation loop remain open/NOT_RUN. The two extra system images were collected with originals/private bytes retained; approximately61.5s after shortcut-return is not a proven watcher delay. Normal production queue had5pending/0operations, acceptance6used/4unknown with3compensation audits in the incoming local preservation record; this session did not inspect or modify those private stores. Production screenshot input/consumption, safe retry and Mac client profiles remain disabled.

## Previous formal integration — historical c1456534

<!-- INTEGRATION_STATUS -->
Tested combined source [`76a8385be063bf225248c057262eb8d57e4be43f`](https://github.com/haohongfei2001-png/Riftlet/commit/76a8385be063bf225248c057262eb8d57e4be43f) preserves both f075b8f and88f9e36 as parents. [Run40453748396](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40453748396) / job122022173576 completed successfully2026-10-27 13:11:09Beijing: **201/201 native** (Capture48/Core54/UI17/Adapters82), **20/20 page VM**, archived replay55files/19cases/89prefixes/2simulated late-error vetoes, release/ad-hoc signature and all three packaged self-checks. The actual CI checkout21600647f30a2d6da1ca109f1f7db55c3e81bf6c is a temporary PR test merge, not a main merge.

Actual XCTest logs include v1→v2 data/receipt/order/lock preservation, migration rollback, compensation rollback and recovery, UNKNOWN/compensated tab serialization and the three new M1 completed-observation regressions. Both root and the non-author reviewer independently verified the logs. [Machine verification](../engineering/evidence/2026-10-27-integration/verification.json), [review](../engineering/evidence/2026-10-27-integration/review.json), [selected actual log lines](../engineering/evidence/2026-10-27-integration/ci-excerpt.txt) and [integration handoff](INTEGRATION_HANDOFF.md) preserve exact input trees, code hashes, scope and next actions.

[Artifact12711707097](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40453748396/artifacts/12711707097):1068262bytes, SHA256`11d788d77e8e23fac3c01ce2583c1e6c0eb94648664a8cd0b37f9cc5b36b6c24`, expires2026-11-10. No real GUI/ChatGPT is exercised by CI; CHROME_NOT_RUN/GUI_NOT_RUN remain explicit. This documentation/evidence checkpoint leaves tested source/build inputs unchanged. The local live evidence and predecessor CIs below remain their own historical results.
<!-- END_INTEGRATION_STATUS -->

## First local Mac execution — historical 1909771

Source `1909771d45ad00290dffe245b9a42e6e9f55203c`, isolated acceptance branch, successful [run40449181125](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40449181125). See the [real Mac handoff](../engineering/evidence/2026-10-27-real-mac/README.md), [sanitized live evidence](../engineering/evidence/2026-10-27-real-mac/live-evidence.json) and [checks](../engineering/evidence/2026-10-27-real-mac/verification.json).

Across the local acceptance source revisions ending at1909771, five integrated generated-image inputs reached verifiedReady on real Chinese Home Chat. Identity-correlated late DOM failure restored the queue, persisted across restart and did not re-upload; real tab A→B→A revoked the old lease; v4 blocked a new input on a compensated tab after rearming. Three native system window captures imported exactly once with matching private bytes; helper 2/3/12 scenes ran. Full existing-thread/network anomaly/physical GUI acceptance and the production two-operation loop remain unaccepted. Ordinary mode is capture-only; production completion and safe retry remain disabled.

Local Swift 6.4 CLT builds and actual SQLite smokes passed; local XCTest was unavailable. CI is a distinct macOS runner. No real screenshot or private conversation content was committed. The following earlier execution record is historical and does not describe the current local Mac availability.


## M1 predecessor branch — historical CI

The user's local Codex owns real-Mac W2/N1/Web acceptance. This session did not access that device or general pasteboard. Its isolated branch `codex/m1-native-backend-20261027` / [Draft PR #3](https://github.com/haohongfei2001-png/Riftlet/pull/3) targets the PR #1 engineering branch; these are pre-integration checks; current integration status is recorded above. No main merge occurred.

- Tested head [`7dfa8ecbd221095f6c99d289aba794b51ce37e95`](https://github.com/haohongfei2001-png/Riftlet/commit/7dfa8ecbd221095f6c99d289aba794b51ce37e95), based on485fa87. [Run40446467852](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40446467852), job121998836427, completed/success2026-10-27 11:52:40Beijing; temporary PR test mergec1ef59f3f9d014987aa1f7e1731de028d9649f79 is not a branch merge.
- **173/173 native tests:** Capture48/Core30/UI17/Adapters78. **9/9 inherited page VM tests**; archived replay unchanged. Release build, App/ad-hoc signature and all three existing self-checks passed. CHROME_NOT_RUN/GUI_NOT_RUN remain explicit.
- New34 M1 cases cover eight actual unique named NSPasteboard tests, native local AX object/GetPid primitives plus injected AX scenarios, actual file/journal/two-instance/separate-process flock, and SQLite/native-coordination recovery. They do not query the real ChatGPT client or prove actual menu Paste, selection preservation or per-image completion.
- Initial run40446176770 compiled but had two pasteboard fixture failures: an OS-generated UTF-16 representation and invalid legacy promise UTI setup. The reviewed test-only correction retains full materialized snapshot restoration and uses a modern type reported by AppKit. The successful run above is the final execution evidence.
- [Artifact12707859277](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40446467852/artifacts/12707859277): 1005479bytes, SHA256`fc9da0dc19092ae6e09da94817b63a282f14ccf87cb3c4382a9deeb304b59c3c`, expires2026-11-10. Contains development App/helper/logs, no release or notarization.
- [Permanent verification](../engineering/evidence/2026-10-27/m1-native-verification.json), [CI excerpt](../engineering/evidence/2026-10-27/m1-native-ci-excerpt.txt), [non-author review](../engineering/evidence/2026-10-27/m1-native-review.json) and [M1 interface/scope](M1_NATIVE_BACKEND.md).

Root authored coordinator/M0 integration/recovery tests; native AX and pasteboard authors worked concurrently; m1_review independently read all nine files and final CI, with cross-review by the other authors. Findings fixed nil-read classification, resolution-before-Core-commit recovery and coordination-error receipt admission. Native Mac profiles remain empty and disabled; App/Core/Web paths did not change. The docs/evidence checkpoint after7dfa8ec does not alter tested native/build inputs.

## Inherited PR #1 execution at485fa87


| Check | State | Scope |
| --- | --- | --- |
| Library handoff PACKAGE_INDEX | PASS 16/16 | Exact byte lengths and SHA-256; original archive SHA-256 in engineering plan |
| Repository baseline + working branch | VERIFIED | main pinned, independent feature branch; no merge |
| Swift / macOS GUI in authoring environment | UNAVAILABLE | Linux; no local Swift toolchain. Actual native tests/builds run on GitHub macOS Actions |
| Authored-source `git diff --check` | PASS | Authored code/docs only. Exact upstream licenses/research retain their original whitespace. |
| macOS Swift tests | PASS 139/139 | Capture48 + Core30 + UI17 + Adapters44 at `97f10b0`; actual macOS runner |
| Actual Web handoff source/evidence | VERIFIED + OFFLINE REPLAY PASS | Exact6f415698 archive, 55manifest entries, 19historical cases, 89real-trace prefixes, 2simulated late-error vetoes; not new live tests |
| Integrated bundled page program | PASS 9/9 synthetic VM | Actual shipped JS against controlled DOM events; no live Chrome or GUI |
| Release build + `.app` + ad-hoc signature verification | PASS | ARM64 development application, not notarized or publicly released |
| Packaged executable `--self-check` | PASS | Actual built executable; synthetic private import→queue→receipt→restart, no GUI or ChatGPT |
| Relocated `.app` `--web-acceptance-self-check` | PASS | Page resource loaded from the copied app, isolated mode/policy checks; explicitly `CHROME_NOT_RUN; GUI_NOT_RUN` |
| GUI acceptance helper fixture `--self-check` | PASS | 12 generated PNGs, 2/3/12 scenes and layout/state checks; explicitly `GUI_NOT_RUN` |
| Inherited Oracle offline cases | REPRODUCED 4/4 | Node24.22.1/Linux; source fixture counterexamples only |
| First-click focus / transparent hit / fullscreen / multi-monitor | NOT_RUN | Requires authorized real Mac GUI |
| Real system screenshot latency and idle resources | NOT_RUN | No fabricated measurements |
| Integrated real ChatGPT completion / anomaly matrix | NOT_RUN | E07 actual source/scoped inherited evidence now reviewed; this combined program still needs live test. Registered Mac offline; ordinary App remains capture-only |

Production successful-completion and safe-retry profiles are both empty. Real screenshot automatic consumption is not enabled.

## W2 prior source integration — historical native evidence

- Source commit: [`97f10b0bf03fbd9421083a15eefec0eb22ead606`](https://github.com/haohongfei2001-png/Riftlet/commit/97f10b0bf03fbd9421083a15eefec0eb22ead606), parentb5958d1; same Draft PR #1, no main merge/release.
- [Successful run40437937532](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40437937532), job`121971048580`; completed2026-10-27 10:22:41Beijing. Runner macOS14.8.9/build23J631/arm64/Swift5.10, Node22.23.2. Temporary PR test merge`26fcd175e60ad144f8a7ad4d279c454632cf8542` is not a merge into main.
- Tests:139/139 native,9/9 integrated page VM; inherited archive replay55files/19cases/89prefixes/2simulated late errors. All successful. Release build, ad-hoc app/signature, capture/queue self-check, relocated Web resource/policy self-check and existing GUI helper fixture self-check passed.
- [Application, GUI helper and logs](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40437937532/artifacts/12705495014), artifactSHA256`961936e9931175b469c1196527fd20a627a2cab8990019e25a526dbcdbc33e34`, expires2026-11-10. This is a development artifact, not a released/notarized app.
- Permanent [machine record](../engineering/evidence/2026-10-27/web-integration-verification.json), [exact log excerpt](../engineering/evidence/2026-10-27/web-ci-excerpt.txt), [handoff review](../engineering/evidence/2026-10-27/web-handoff-review.json), and [program review](../engineering/evidence/2026-10-27/web-integration-review.json).

Actual parallel ownership: root implemented App/Core policy/resources/build integration; `w2_implementation` implemented the page/adapter; `w2_evidence_review` independently audited source and inherited traces; `n1_native_acceptance` checked the authorized Mac and reviewed root's integration after finding it offline. Review fixed original-node equality, transient removal/source restoration, proof provenance, bounded invalid buffers and post-journal-recovery synthetic isolation. These distinct agents are technical non-authors, not human GitHub approvers or extra Macs.

The only real uploads in the imported evidence are the other Codex session's recorded experiments. New NodeVM cases and Swift fake transport tests do not add real uploads. The integrated acceptance mode can exercise generated-image consumption with its own profile, but cannot consume real screenshots or grant retry. At that historical checkpoint, production late-failure revival was still absent. [MAC_ACCEPTANCE](MAC_ACCEPTANCE.md) supplies the direct live continuation steps; no extra planning or module rebuild is needed.

## Original foundation macOS run — historical evidence

- [Successful workflow](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40377481770), job `121764396954`, completed 2026-10-27 02:25:32 Beijing.
- Tested source head: `2f60f01657cc29e7a4cabe41792c6ccd558d6974`. PR's temporary integration commit: `88119b980c8546079129626877b8057709934f3c`. This temporary test merge is **not** a merge into main.
- Environment: macOS14.8.9 / build23J631 / arm64 / Apple Swift5.10 (`swiftlang-5.10.0.13`).
- Debug/test compilation 12.81s; release compilation13.07s. These are CI build durations, not screenshot/upload latency.
- [Build artifact and logs](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40377481770/artifacts/12675615934): contains `Riftlet-macOS-development.zip` (app zipped with executable permissions) and test/build/self-check logs. Artifact retention14days; source, workflow and this evidence remain in git. Artifact outer ZIP SHA-256 `b5d33fbbd2e46b67f69448a47ccceeb8899bf01a309bb916c4c6436a39e17f7d`.
- [Machine-readable evidence](../engineering/evidence/2026-10-27/verification.json) and [compiler/test excerpt](../engineering/evidence/2026-10-27/macos-ci-excerpt.txt).

The first run exposed nested weak-reference capture concurrency errors; these were fixed in the tested source commit. The successful run compiles all native targets and runs all40 tests, not only a stub. The final evidence/documentation commit changes no source/build/test files, so it does not repeat this completed gate.

## Continuous delivery — actual code and native execution

| Tested source commit | Native test count | Successful workflow | Included increment |
| --- | --- | --- | --- |
| `94df78c74e75cf79b7832e62a228c6fd37913cf9` | 63 | [40386356404](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40386356404) | Q1/Core recovery, W0 normalization and U1 helper |
| `3e7b8eac6c3bd235f4e376172d6085ab0d5b4426` | 98 | [40387437225](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40387437225) | C1 source binding, U2 layout, W1 transport and D1 storage |
| `1afd849a9b2d2cfada0d01cd47b5f1ee31f83d37` | 127 | [40388958638](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40388958638) | C2 faults/recovery and M0 injected Mac flow |
| `e76e7985c05197c487dd4e7f585dc028ed64b1af` | **134** | [40389753080](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40389753080) | C1 review fixes and nonblocking special-file rejection |

All four runs completed successfully on macOS14.8.9 arm64 / Apple Swift5.10. Each ran `swift test --parallel`, release build, actual ad-hoc `.app` packaging/signature verification, packaged App self-check and the separate GUI helper fixture self-check. The final run's job is `121807449326`; its temporary PR test merge `847471105ad2520e897a0d32e3a3e8337e5db0e1` is not a merge into main.

The [previous foundation artifact](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40389753080/artifacts/12682330742) includes `Riftlet-macOS-development.zip`, `Riftlet-GUI-Acceptance.zip` and test/build/self-check logs. Outer artifact SHA-256: `5f7c9eb727e8fb751c569b0b2e6e67254e7bf01f63d327b928f439dd62179d19`. Artifacts expire after14days; source, workflow and the durable evidence records remain in git.

Permanent records: [machine-readable run/review/scope data](../engineering/evidence/2026-10-27/continuous-verification.json) and [native log excerpts](../engineering/evidence/2026-10-27/continuous-ci-excerpt.txt). Documentation/checkpoint commits after the final source commit change no native source, tests, dependencies, resources or build entry points. PR-wide path matching may trigger another automatic run; such a run is separate, not predeclared successful.

### Independent review and concrete fixes

The root integrated and implemented Core, App wiring, part of C2 and the special-file fix. Three independent agents actually ran C1/U1/W0 concurrently, then took C2/U2/W1/D1/M0 or reviewed another author's code. This was one shared workspace with disjoint ownership, not three separate Mac machines or an unattended background coding service.

- Core/Q1 was reviewed by `ui_u1` and `adapter_w0`; the root's missing-media recovery fix and transaction rollback tests were independently checked.
- U1/U2/D1 modules were reviewed by root; C1/D1 App wiring was reviewed by `ui_u1`. The GUI helper no longer logs key codes, and large configured insets no longer move fitted rows outside narrow screens.
- W0/W1 were reviewed by root and `ui_u1`. Nested unknown observation fields are rejected, and AppleScript runs on a shared serial utility queue rather than blocking MainActor.
- C1's initial CI pass did not close its later review findings. `ui_u1` identified the handoff-await arrival gap, stale start after stop and unreadable terminal-enumeration gap. The author fixed these and added five targeted tests; the final134-case run covers them.
- C2 was authored by `capture_c1` and root and reviewed by `ui_u1`. Journal rename transfers ownership before directory sync; stage-directory ordering, persistent SQL locks, recovery IO errors, unreadable journals, malformed JSON isolation and used-record preservation are tested. The author also independently read root's additions.
- M0 was reviewed by root and `ui_u1`. A separately admitted terminal failure now releases the local input lease for a later explicit retry, while retaining clipboard bytes; UNKNOWN and unadmitted failures do not unlock or paste again.
- Root fixed the FIFO open-before-fstat issue found by `ui_u1`; the reviewer also caught and helped bound the regression harness's rescue path. The two tests use actual `mkfifo` files and pass on the native runner.

Review here means non-author technical review by distinct execution agents. It is not a human GitHub approval or authorization to merge/publish. The branch and PR remain isolated and draft.

## Material remaining limits

- C1 now automatically rebinds from preference-file/parent events, with durable old-directory handoff and startup generation guards. Temporary-file watcher cases are automated; actual Screenshot.app propagation, TCC/permission UX and real sleep remain system acceptance.
- Delayed metadata/partial writes get five bounded retries; a later event/wake/rescan can retry again. No indefinite polling is used. Real-system coverage must establish whether a supplementary metadata observer is needed.
- Used media and journals are retained because archive/delete semantics are undecided. Unjournaled staging fragments are not auto-imported or auto-deleted. Retention/recovery cleanup remains a scoped follow-up.
- Recovery preserves journal ownership across IO/SQL failures and never labels an unreadable journal as safely discarded. A storage IO error conservatively stops that recovery call; startup may therefore remain paused until access is restored. Malformed JSON is isolated from unrelated valid journals. These are distinct behaviors, not a claim that every IO failure is isolated per image.
- C2 interruptions use real temporary files/SQLite and deterministic in-process fault hooks plus reopening; no SIGKILL, OS crash or power-loss test is claimed. `fsync` ordering was reviewed and executed, not certified as hardware power-loss protection.
- ARM64 macOS CI and local macOS 27 / Apple M5 compilation and scoped live acceptance ran. Intel and other OS versions remain unverified; local results do not establish the entire GUI matrix.
- Transparent minimum-hit rectangles, fullscreen behavior and exclusion from Apple's own screenshots are not established by pure layout tests.
- Developer simulation is not an upload adapter, and the production build intentionally retains real images.
- The integrated Web program now has scoped live Home/Chinese/PNG success and controlled late-DOM-error compensation/restart evidence. Prearmed target freezing and page epoch revocation address queued capture, but unarmed first-click availability, the complete race matrix, same-URL business-draft replacement and actual network-failure behavior remain unaccepted. Exact Chinese Chat/Work mode identification is implemented; arbitrary existing conversations remain unsupported. Production remains disabled. Mac includes the M1 native AX/NSPasteboard drivers and durable cross-instance coordination. Actual version/surface binding, input, selection and completion evidence remain required before client enablement.

## Autonomous execution plan v2 — historical documentation increment

The follow-up authorization was recorded in AGENTS, decision entries P12/P13 and the v2 engineering plan, with a concrete execution board and PR template. Web/Mac implementation is separated from real-evidence admission. Reuse provenance was rechecked; Oracle's archive count is now described precisely as six source/fixture files plus LICENSE.

This increment changes documentation and the PR template only. Native sources, tests, resources, licenses, `Package.swift`, build scripts and the native workflow are unchanged relative to the tested source head above. The macOS run was read back as completed/success at that exact SHA; that existing evidence is not relabeled as a new validation. No extra manual native run is needed for the documentation, but the existing PR-wide path trigger may automatically run CI again; any such result belongs to its own SHA/run and is not predeclared passed. New plan packets marked READY are not claimed implemented.

Validation for this increment: authored `git diff --check`, relative Markdown target checks, conflict-marker/whitespace checks, non-author execution-plan review and a separate actual-reuse/license audit. The audit confirmed the two adaptations, independently implemented Tendedero-informed panels, reference-only Oracle/Maccy status and license packaging. Main was observed at `6dfba79f9ccef295cc0234580a3adc99f0757e09`; its additional website-only change was inspected and left untouched.
