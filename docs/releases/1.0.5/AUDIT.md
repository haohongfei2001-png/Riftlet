# 1.0.4 → 1.0.5 审计与修正清单

日期：2026-11-18（Asia/Shanghai）。审计对象是 PR #110 的 `f3153b10dac4445720f1c20c8836ddbbea625c49`，不是旧 1.0.3 界面。本文件所列源码行号均相对此 SHA。产品方向见 [PRODUCT_DIRECTION](PRODUCT_DIRECTION.md)，执行与验收见 [CODEX_HANDOFF](CODEX_HANDOFF.md)。

## 1. 事实与证据边界

GitHub API 读回：main=`3f8149e2313fd81bbaee5a7bbbdbb1efca2fc81b`；PR #110 open、未合并，head 如上；最新公开 Release 为 `v1.0.3-zip`。PR #110 的 Native source admission、Native ARM64、Native Intel、Feedback source admission、Feedback native and service 五项均 success。[候选报告](https://github.com/haohongfei2001-png/Riftlet/blob/f3153b10dac4445720f1c20c8836ddbbea625c49/docs/releases/1.0.4/RC_REPORT.md)仍把真实冷首图和三组 ≤2 秒双图记为 NOT_RUN，原因是测试环境 TLS/连接不可用。

候选包 1.0.4（27）的产品源码为 `c7934adc82d382e78cf23ab96ed6d6784e88b905`；报告中的私有 DMG SHA-256 为 `b841402653082510d82e2278eb5a047ac64166e951b2e74694b9e7aa244fcdd3`。本次核对报告及源码，没有重新下载或执行该 Mac 包；公证、升级等历史结果仍只属于原报告的包和环境。公证与 App Store 审核不是同一件事。

本次看过的当前原生图：

- [中文外观页](https://github.com/haohongfei2001-png/Riftlet/blob/f3153b10dac4445720f1c20c8836ddbbea625c49/docs/releases/1.0.4/evidence/signed-rc27/settings-zh-settings-light-display.png)
- [英文最小截图页](https://github.com/haohongfei2001-png/Riftlet/blob/f3153b10dac4445720f1c20c8836ddbbea625c49/docs/releases/1.0.4/evidence/signed-rc27/settings-en-settings-minimum-capture.png)
- [三图托盘](https://github.com/haohongfei2001-png/Riftlet/blob/f3153b10dac4445720f1c20c8836ddbbea625c49/docs/releases/1.0.4/evidence/signed-rc27/desktop-tray-3.png)

根 evidence 中部分 general/help 图实际是 1.0.3 基线；review 模式的首用图也不能证明普通正式路径行为。不要混用。以下“源码确认”不等于本次 macOS 实测；设计判断与待量测风险单列。

## 2. 总表

P1 为本版必须修正的产品问题；P2 也进入相应工作包，复杂性能改造只在测量证明必要时实施。GATE 是交付证据要求，不等于已复现故障。未发现新的、已经证实的 P0 误投/数据损坏，不凭空使用该标签。

| ID | 优先级/性质 | 当前问题 | 修正目标 | 沿用跟踪 |
|---|---|---|---|---|
| R105-01 | P1 设计/实拍 | 四页已成形，仍有重复层级、空散参数表和旧几何编辑墙 | 少量自然选择、统一原生布局、旧值兼容与普通 UI 分离 | #88、#92 |
| R105-02 | P1 源码 | 实际阻断只进 tooltip，菜单没有看得见的修复入口 | 异常时一条原因、一个准确动作 | #88 |
| R105-03 | P1 源码/需首装验证 | 未请求与已拒绝屏幕权限被混为一类 | 按实际使用申请，未使用不是故障 | #86、#96 |
| R105-04 | P1 源码+受控实验 | START 后停止读失败，原“失败重生”未完整实现 | 即刻吞噬保留，明确同操作失败恢复，UNKNOWN 不重传 | #82 关联；新产品缺口由总任务跟踪 |
| R105-05 | P1 源码/产品 | 历史多维状态混在筛选中，吞噬/未知缺顺畅处理路径 | 找到图、了解状态、执行下一步三者连起来 | #90、#108 回归 |
| R105-06 | P1 源码 | 归档仅隐藏、媒体永久保留、内置截图重复副本、无清理入口 | 一套可恢复清理和留存机制，维护确定垃圾 | #95 |
| R105-07 | P1 源码 | 内置截图在 manifest 前失败，原件存在却无可见恢复任务 | 成功捕获有持久身份，失败/重启后可找回并重试收录 | #95 关联；新故障由总任务跟踪 |
| R105-08 | P2 源码 | 返回设置重复统计；死目标 UNKNOWN 周期观察并写相同状态 | 必要事件驱动、合并更新、退避、无变化不写库 | #93 |
| R105-09 | P2 条件性能 | 冷历史全量 hash、重复 importer 恢复、长会话对象不退休 | 大库首用有界、临时资源释放、防重放身份保留 | #93、1.0.4 T08 继承 |
| R105-10 | P2 源码/待原生验证 | IME 关闭静默拒绝、必要文字11pt、旧术语/诊断重复 | 正常关闭/退出、清楚文字、统一语义样式 | #92、#96 |
| R105-11 | P1 工程事实 | 当前入口仍指旧已合 PR，Issue/版本/通道各说各话 | 一个活动入口、一张真实状态表、各通道有序更新 | #91、#97 |
| R105-12 | GATE 证据缺口 | 最终包真实冷首击/快速双图等关键格未闭合 | 同包完成真实主流程，缺环境不伪造通过 | #82、#97 |

## 3. 具体证据与修正边界

### R105-01：设置仍像参数表；兼容不应等于保留参数墙

当前真实外观图同时出现窗口页名、选中页签、正文大页名；预览与长行控件缺少明确分组。`RiftSettingsCenterController.swift:182–227,258–269` 手工导航；`RiftSettingsCenterPages.swift:329–356` 固定普通行至少44/60pt、分组50pt。英文最小窗口首屏刚到归档项，存储和仓库尚在下方。这是完成度判断，不是“滚动一定错误”。

同文件 `83–116,191–212,406–437` 仍可呈现旧缩略图宽高、编号间距、留白、内缩、色相等数值；每页数量有滑杆与数字输入，闲置时间可输入小数。**保留合法旧配置，但不继续让普通用户维护几何参数。** 保留四页和三形态，合并标题层级，使用真实预览、自然离散选择、统一阅读列与紧凑分组。不可用强制重置旧外观来制造整齐。

### R105-02：有异常模型，没有可见异常操作

[控制器](https://github.com/haohongfei2001-png/Riftlet/blob/f3153b10dac4445720f1c20c8836ddbbea625c49/Sources/RiftletUI/RiftControlCenterController.swift#L159-L217)只创建四个菜单项，`refreshControls` 将原因写入 tooltip/AX；`265–287` 设置入口固定 general。`RiftControlCenterPresentation.swift:58–108` 已经有不能写入、目录失效、Chrome 拒绝等准确投影，却没有接成实际恢复入口。

正常菜单保持简洁；异常才出现一条短原因和一个可点击动作，直达相关页/控件。`RiftControlCenterPresentation.swift:25,28,32` 的旧错误页映射一并校正（visibility/appearance 应到外观）。当前这些 recoveryPage 尚未用于可点击入口，不声称已经实测“跳错页”。

### R105-03：没有申请权限，不等于用户需要去修复权限

`SettingsProductHost.swift:124–125` 将 `CGPreflightScreenCaptureAccess()==false` 一律映射 `.notGranted`；`RiftSettingsCenterRendering.swift:48–51,415–420` 与 Pages `168–169` 显示系统设置入口。真正的请求在 `InteractiveScreenshotController.swift:95–106` 用户调用内置截图后才发生。

在未用功能时不展示故障；一次自然点击触发正常系统授权。已经拒绝、确需系统设置或系统要求重新启动时才出现对应动作。不要虚构系统没有提供的授权枚举；可结合本应用是否已请求和真实请求结果判断。系统截图收录与可选内置截图权限保持独立。新账户真实表现由最终验收确认。

### R105-04：原“失败重生”被 START 截断

[生产页面脚本](https://github.com/haohongfei2001-png/Riftlet/blob/f3153b10dac4445720f1c20c8836ddbbea625c49/Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js#L679-L735)的 `sample(op)` 在 `op.start` 后直接返回；observe 持续返回 `uploadStarted` 和默认 `hasError=false`。`TransferCoordinator.swift:537–545,580–592,639–645` 在 START 后将普通独立输入移出观察，`RiftletMain.swift:1322–1324` 不给 Web click adapter 加 completion watch。库里已有失败恢复能力，普通路径没有供应这类证据。

本次用现有 DOM fixture 做了可重复实验：同一附件先 START，再将该卡标记 failed 并加入 alert；下一次 observe 仍 `uploadStarted/hasError=false`，setter=1、send=0。它证明当前源码的边界，**不证明真实 ChatGPT 采用该 DOM 结构**。可复现脚本与结果见 [evidence](evidence/README.md)。

保留接收即吞噬；补精确同 operation、文件、原草稿的只读失败观察。明确终止且可安全重试的失败恢复图片，仍由用户再次点击；不明结果保留可见处理入口，不能超时就判失败。用户主动移出/归档的图不因迟到回执反复弹回。旧 D04 的“START 后工作留待未来”不能再次当成已经满足用户最初设计。

### R105-05：找得到文件，不等于能完成恢复任务

`QueueStore.swift:218–234` 仅允许 archived/removed + pending/failed 且无未决输入的项目恢复。`HistoryPresentation.swift:34–44,144–158` 继承限制；`RiftletMain.swift:1425–1461` 提供原图/Finder，但“检查原对话”没有实际直达动作。`RiftPanelController.swift:1857–1872` 的未知状态主要用细下划线表现，点击执行观察而非附加，普通用户难以理解。

`HistoryPresentation.swift:50–80,125–158` 与 `RiftHistoryController.swift:490–501` 还把“已附加/已交给ChatGPT/已归档/已移除/明确失败/待核实”等维度塞进同一菜单，存在“已移出裂缝”旧词。

普通筛选收为按任务组织的少数组（全部、桌面中、需要处理）；状态细节保留真实事实。把“重新显示/查看原图/查看原对话”和“允许再次输入”分开：可见性不授予重传权限；原目标不再存在时给真实替代动作，不猜另一个对话。已经实现的全库搜索继续保留，不重做。

### R105-06：正常使用会永久增长，清理还停在说明层

`PrivateAssetImporter.swift:137–180` 为每张图创建 media 与 journal；`QueueStore.swift:194–216,240–258` 的移出/清空/归档只改 visibility。`ScreenshotEntryHost.swift:47,260–317`、`CompletedScreenshotImporter.swift:10–41` 使内置图先存 captures 再复制 media。Pages `181–185` 只有用量与重查。

建立清晰的截图资料生命周期与仓库“管理…”：主动批量清理、明确范围、可恢复删除、简单留存选择；自动清理可再生或确认无主的临时内容。内置成功截图确立一个权威媒体归属，标注原图和派生关联，不留用户不可见的多份完整图。

不得只删 DB 或 media：manifest 会复建、缺文件会变 missing、去重身份消失会导致再次收录。用最小删除状态/记录保持去重和恢复的一致性。处理中的输入、UNKNOWN、未恢复原件、用户外部原图不作垃圾；升级不能默默删除已有历史。具体默认/迁移见产品方向。

`PrivateAssetImporter.swift:141–145,193–199` 的无 manifest 崩溃 `.part`、`InteractiveScreenshotSystemCapture.swift:416–422` 的非空 `.capture-*`、`RecoverablePreferences.swift:139–165` 的重复失败恢复备份一并纳入。先找回有价值图片，再维护垃圾；避免再建第三套备份机制。用量应覆盖管理范围，部分统计继续如实表达，不能把逻辑总量冒称可释放空间。

### R105-07：捕获成功、导入前失败的图成为不可见孤立原件

`InteractiveScreenshotSystemCapture.swift:64–86,370–413` 先发布隐藏的 `captures/.UUID.png`。`PrivateAssetImporter.swift:134–138` 的容量失败发生在 `166–180` 建 manifest 前；`ScreenshotEntryHost.swift:297–317` 只有内存 Task，失败后显示“原文件已保留…请重试”，没有持久记录和对应按钮。`recover:193–212` 只识别 journal/已有资产，不能恢复这类捕获。图片没有被删，但普通用户无法找回；真实故障注入尚未运行。

捕获成功时就登记最小待收录身份；仓库显示“尚未加入”并提供查看/重试。恢复容量或重启后可补收录，去重一次，不附加到任何聊天。标注器持有原件时退出、manifest 后崩溃一起走同一恢复机制。

### R105-08：没有新事实也重复工作

1. `RiftletMain.swift:268–272 → 931–970 → 1919–1937`：返回可见设置无条件重新统计。`StorageUsage.swift:91–110` 枚举四个直接子目录并 stat，每区最多25,000项；没有 TTL/脏标记。**这是有上限的目录元数据遍历，不是全图像读取。** 权限刷新与用量统计分开；管理首次打开或数据变化后后台合并更新。
2. `RiftletMain.swift:785–795` 每5秒观察；`TransferCoordinator.swift:598–637` 对当前会话 UNKNOWN 的已关闭目标继续重查；`QueueStore.swift:535–540,932–939` 即使事实相同也更新时间/写库。完成观察的 backoff 不适用于这条普通路径。给实际观察预算、退避、暂停和事件恢复；同事实不写库。旧 UNKNOWN 仍保留，新截图仍可用。

### R105-09：规模成本仍须收口，不能拿小库空闲数据代替

`PrivateAssetImporter.swift:198–208,259–267,332–342` 启动会读全部 manifest/资产并完整校验非 used 媒体。archived/removed/正常 START 都不自动变 used；`ScreenshotEntryHost.swift:54` 的独立 importer 首次操作还可能再 recover。此项是旧 #93/T08 的剩余风险，普通 refresh 的旧全库解码已修复，不再误报。

JS `registry.operations`、`MainWorldCommandRelay.swift:29–39,88–118` 的 nonce/relay、`ChromeAppleEventsExecutor.swift:13,62,106` routes、`WebAttachmentAdapter.swift:139–141,260` enteredOperations 没有退休边界。本次101次受控 START 后保留101条 operations/binding，但 chunks=0；**不能宣称101张像素数据泄漏，更没有测得 GB 级占用。**

先测实际大库冷启动、首次内置截图、跨多草稿长会话和静置后资源。若有显著负担，优先活跃恢复、后台分批冷历史、共用恢复调度；释放已经退休的 DOM/route/buffer，防重复输入的持久身份不能盲目 TTL/LRU 删除。无需用户调“安全级别/轮询频率/缓存大小”。

### R105-10：原生使用细节仍有明确缺口

- `RiftSettingsCenterController.swift:457–465,495–503` 在 `hasMarkedText()` 时取消关闭/退出而无说明。按原生提交/取消编辑处理，无法提交才定位字段；真实中文 IME 关闭/切页/Cmd-Q 验收，注入完整字符串不代替组字。
- `SettingsNativeStyle.swift:33–60` 的必要 caption=11pt、固定偏绿色，与新原生窗口背景未完全统一。必要说明至少12pt，使用语义颜色和正常字号，颜色只用于确有意义的状态。
- `SettingsProductHost.swift:128` 已返回 `Riftlet 1.0.4`，Rendering `111` 又加品牌名，得到 `Riftlet Riftlet 1.0.4 · 27`。统一格式化，诊断短且有用。
- `ScreenshotEntryHost.swift:291,316` 等失败文案仍硬编码中文/旧“裂缝”术语。普通路径的中英文错误和下一步一起核对，不能只翻译设置标题。

### R105-11：旧任务权威和发行通道混杂

审计时 main 的 AGENTS 仍称“active PR #101”，该 PR 已合并；旧 quality handoff 还以1.0.2公网发布为下一步。open Issues #78–#108 同时包含已修、未修、已做未验，不能把 open 等同当前 bug。1.0.4实现/私有包、公开1.0.3下载、1.0.2 feed 是不同状态。

本规划修当前入口；Codex整合时更新单一当前状态，把旧说明标成有日期的历史证据，按实际依据关闭或迁移已完成 Issue。不批量删除历史或重开同名任务。按运行依赖清理死代码/fixture/重复工具，不因文件大就重写架构；当前 LegacySettingsFixtures 已与生产 target 分离，不当作未修。未来正式推广时让官网、Release、feed、App版本和文案一致，不声称发布了Release就代表其它通道完成。

main实际 `protected=false`、rulesets=[]，沿用 #83 独立处理，不假造审批或削弱五项现有检查。该治理事项不阻止可继续的产品修复，也不授权本次修改远端规则。

### R105-12：最终包的关键真实流程未完成

1.0.4报告明确未跑真实冷首击/快速双图；150ms原生目标捕获路径的冷态延迟也未实测。不要将环境故障写成产品必坏，也不能写成已经可靠。用可用且获授权的测试Mac/草稿验最终1.0.5包；原文、选区、旧附件保留，逐图对应START/收起，发送次数为0。网络问题只阻对应格，继续其他实施与验收。

最低系统、完整系统IME/VoiceOver、多屏/Space等缺口依公开承诺和本轮改动补齐；旧升级样本含UNKNOWN却没有非空START，应补关键升级数据类型。验收完整范围见交接文件。未完成时交付可安装候选和具体阻塞，不能以“零bug”“全部通过”结案。

## 4. 已完成的改进与必要保护

四页设置、默认新用户三图托盘、旧偏好字段保留、独立背景透明度/相机色、共享真实预览、全库先查询再分页、首用延期关闭语义、两个build27原生界面修复均已有实现/对应证据。本轮继承、回归，不重复开发。

缩略图有16MiB/32项限制；诊断trace有128 recent/32 failures/4096字节行上限与固定文件覆盖；manifest之后的恢复、source-key去重、写入前容量检查、坏偏好隔离已存在。没有发现WAL无限增长证据，不安排泛化VACUUM或任意删journal。

目标身份、setter/change每次至多一次、UNKNOWN不自动重传、系统原图只读、旧配置无损、签名更新和数据事务是正确保护。消费级减法减少的是用户被迫做的选择、重复解释和无效后台工作。
