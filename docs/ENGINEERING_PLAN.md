# Riftlet 正式工程计划

2026-10-27（北京时间） · v2 自主并行执行 · 工程启动基线 `5a3ab5d7a761d5397f8bc15b6f40d761b29e58d2`

**当前执行方式：负责人自主决策、分模块并行、持续集成，不设日常用户审批环节。** 总体架构与产品要求不变；本次修订拆开实现、验证、启用的依赖。可直接领取的任务、唯一写入责任和解锁条件见 [EXECUTION_BOARD.md](EXECUTION_BOARD.md)。

**2026-10-27 前轮实施增量：** C1/U1/W0由三个独立执行者实际并行，负责人同步实现Core可靠性与App接线；随后完成U2/W1/D1/C2/M0。四批代码通过63/98/127/**134**项macOS测试并保存在检查点b5958d1；本轮不重做这些模块。

**前轮 W2 源码集成（历史97f10b0）：** 已取得并原样归档 `6f415698` 的真实Apple Events源码和异常证据，完成独立审查与离线复现。`97f10b0` 将其输入原语、逐图生命周期和内容证明接入现有适配器及原生App；显式 `--web-acceptance` 使用独立生成图片队列，真实传输，合成来源专属消费权限。macOS CI **139项原生测试、9项页面VM回归、release/签名和迁移后的App资源自检通过**。正式模式仍不上传真实截图。已登记Mac离线，集成程序的真实ATTACHED/首击/焦点/吞噬与N1尚未执行；生产准入及safe-retry没有放宽。原架构不变，精确证据和直接恢复入口见[执行队列](EXECUTION_BOARD.md)。

**M1 独立实现记录（历史PR #3）：** 用户将真实 Mac 的 W2/N1 交由本地 Codex独立负责；root在独立PR #3实现实际AX/NSPasteboard后端、跨实例持久协调及恢复，复用M0接口。已测7dfa8ec的173项原生测试与现有构建/自检通过，生产Mac能力默认禁用；真实客户端结构和逐图完成只阻塞对应provider/profile及准入。没有重做架构或修改Web/Core/App。[执行范围与接口](M1_NATIVE_BACKEND.md)。

**正式合流增量：** 本地真机分支f075b8f（已测1909771）与M1的88f9e36由唯一负责人整合到PR #1；保留四个真实源码提交和原始证据，补齐M1在新Core成功/补偿阶段的只读观察。总体架构与依赖顺序不变；当前集成验证、确切源码与剩余UX缺陷见[集成交接](INTEGRATION_HANDOFF.md)和[执行板](EXECUTION_BOARD.md)。本地Mac已经可用；真实网络异常、普通线程、物理N1、首击/UNKNOWN体验和生产准入仍分别待证据，不能称“全部因环境阻塞”。

## 1. 授权、范围和最小交付

用户本轮明确授权正式开发，取代 P07 的“暂不开发”阶段；历史研究和决策不删除。01「直截」只作可调实现起点，视觉与品牌仍未最终批准。产品契约仍是系统截图、点击微图、正确追加到原 ChatGPT 草稿；不自动发送，只有获准完成证据才吞噬。

**最小完整产品**：一个原生常驻 `.app`，自动感知已保存的系统截图，保留原件并收录私有副本，持久 FIFO 队列，极小非激活裂缝，点击追加到已验证的 ChatGPT surface，逐图回执、失败恢复和未知核对，重启/唤醒/多屏可用，一次性权限及安装说明。没有服务器、云数据库、AI API、图库/OCR/编辑器或新截图引擎。

**本轮交付是工程基础构建，不是完整产品发布。** 本轮编写并集成收录、队列、参数化原生窗口、模拟适配器、单元/集成测试、Mac 构建脚本。生产 ChatGPT 输入默认禁用。正常截图仍可收录，点击保留并在状态菜单说明适配器尚未启用。模拟模式有独立目录、显著 SIMULATION 标识且只接受 synthetic 资产。

第一款可交付版本必须至少使 Web Chat 在明确支持的 Chrome 版本通过完整闭环。Web Work、新版 Mac Chat/Work、Classic 单独准入；若某一 surface 尚未通过，不影响其他模块开发，也不被宣传成已支持。工程版本可先启用已经通过准入的 surface，其余保持禁用；Mac 目标继续保留。公开发行的范围、正式签名和品牌收尾留在发布阶段，不设置为日常开发的用户审批关口。

## 2. 工程结构与依赖

| Target / 文件 | 职责、输入和输出 | 依赖 |
| --- | --- | --- |
| `RiftletCore/Models.swift` | 不可变 ImportedAsset、AssetRecord、TargetLease、TransferOperation、TransferReceipt | Foundation |
| `RiftletCore/QueueStore.swift` | SQLite 唯一写入者、FIFO、source去重、操作状态、checkpoint、恢复 | 系统 SQLite（CSQLite shim） |
| `RiftletCore/ReceiptPolicy.swift` | 成功准入和安全重试准入分别验证；生产注册表默认空 | Core模型 |
| `RiftletCore/TransferCoordinator.swift` | 点击去重、目标冻结、串行输入、先intent后副作用、UNKNOWN仅reconcile | QueueStore + AttachmentAdapter |
| `RiftletCapture/FileValidation.swift` | 文件身份/稳定性、截图metadata真值、ImageIO完整性和有限解码 | Foundation、ImageIO、CryptoKit、Darwin |
| `RiftletCapture/FolderWatcher.swift` | 目录事件、FD取消关闭、失效、带最大延迟的事件合并 | Dispatch、Darwin |
| `RiftletCapture/PrivateAssetImporter.swift` | staging→manifest→media→DB；源前后复核，SHA256和恢复 | Core + FileValidation |
| `RiftletCapture/CaptureService.swift` | 先watch后扫描、首次baseline、共享稳定窗、有限重试、唤醒/目录重建 | Watcher + Importer |
| `RiftletCapture/CaptureSourceBinding.swift` | 可注入来源、系统偏好文件/父目录事件、自动重新绑定；epoch和旧目录未完文件持久交接 | CaptureService + FolderWatcher |
| `RiftletCapture/StorageUsage.swift` | 按需、非递归、无内容读取的私有存储计量；明确partial/unknown | Foundation、Darwin |
| `RiftletUI` | 配置、纯布局、下采样缓存、小NSPanel、连续编号和状态动画 | AppKit、ImageIO、QuartzCore、Core |
| `RiftletAdapters` | 有界观察归一化、Web原生传输及捆绑实测输入派生程序、独立Mac基础；Web仅生成图片验收，生产profile为空 | Core、系统原生框架；内置JS资源，无外部包 |
| `RiftletGUIAcceptance` | 独立2/3/12合成场景、焦点/下层点击/asset身份观察；不连接ChatGPT | UI + Core；非常驻组件 |
| `RiftletApp` | 菜单栏、独立实例锁、组合以上模块、配置加载、离线模拟/真实Web合成验收和self-check | Core、Capture、UI、Adapters |

只有 App 组合模块；Capture 不依赖上传，UI 不写数据库、不执行上传、不删除文件。不引入第三方 Swift package 或常驻 helper。需要浏览器扩展时再增加一个 stdio native host，不预建两套生产 transport。

## 3. 本地资产与事务

- `Application Support/Riftlet/` 为真实截图根；`Riftlet-Simulation/` 保存离线演示；`Riftlet-Web-Acceptance/` 保存真实Web生成图片验收，后者在journal恢复后再次核验所有来源。目录0700、媒体/数据库0600；实例锁防止同时打开同一App数据目录。系统截图源保持不动。
- 默认只读 `com.apple.screencapture` 的保存位置，缺失则Desktop。识别读取 `com.apple.metadata:kMDItemIsScreenCapture` 的实际bool；不靠中英文名字，不把普通自定义目录中的全部图片当截图。剪贴板/Preview目标暂不支持文件路径收录。
- 首次启动建立原有文件baseline；监听先于扫描，扫描期间变脏补扫。后续重启/唤醒收录未处理的新来源。事件只意味着重扫，不意味着图片完整。元数据迟到、部分写入分别有限重试。
- 文件事件身份与内容hash分开。sourceKey来自稳定文件身份；两个独立截图即使字节相同也各有 UUID。显示编号不是身份。capturedAt不可证时保留nil；firstSeenAt不冒充捕获时刻。
- 复制源前后核对身份、size/mtime；拒绝symlink。对私有staging核验ImageIO完整状态、实际下采样解码和hash。实际编码决定扩展名/MIME，不仅改后缀。
- `staging/<id>.part`同步落盘，写持久journal manifest，原子提升到`media/<id>.<codec>`，最后SQLite入队。没有假设文件与SQL存在跨系统原子事务。崩溃恢复使用manifest收养孤儿；校验失败保留并报告，不收录半图。
- SQLite WAL、synchronous FULL、foreign_keys、schema版本、quick_check；asset、operation、receipt同一事务写入。source唯一约束只消除重复事件；每asset至多一个未决操作，每target至多一个已分派未决操作。
- 外部输入前持久化dispatch intent。崩溃发生在intent前：可证明未输入；intent之后：UNKNOWN。即使崩溃实际发生在外部调用前，也保守核对，不宣称远端exactly-once。
- 成功只更新used记录，不删除原图或私有副本。自动清理语义暂缓，保守默认保留；UI不全量加载used历史。磁盘计量、空间不足处理和可恢复性现在开发，自动淘汰/物理删除独立排到收尾，不等待用户决定才继续收录工程。

## 4. 状态与上传接口

Asset可见状态：pending、transferring、unknown、failed、missing；used退出待用队列。Operation区分prepared、dispatchIntent、inputTriggered、attachmentPresent、unknown、compensated、failed、succeeded；compensated保留原成功与迟到错误、恢复可见性且仅观察，不授予新输入。

`AttachmentAdapter`只有 `captureTarget / validate / append / reconcile`，没有Send。`TargetLease`包含adapter/surface/app/session/window/tab/document/composer/draftGeneration。adapter必须在同一目标执行片段内复核lease并追加，不以之前一次validate替代临界区验证。

回执绑定operationId、assetId、attempt、hash、完整lease及profile版本。INPUT和ATTACHED仅观察状态；verifiedReady仍须已准入profile、正向ready、原草稿成员关系、准确attachmentId、无error/上传中。明确失败还须**独立的retrySafeProfiles准入**、无残留自动重试；否则保持UNKNOWN。晚到/错草稿/错attempt回执不得消费另一条。

当前生产成功/失败准入表均为空，没有通过配置文件跳过验证的开关。离线演示仍要求simulation store + synthetic asset + simulation target + simulation-v1；显式Web验收则使用独立目录、仅synthetic的adapter、拒绝真实来源的integratedDevelopment观察及Core合成来源专属profile。该权限不能给真实截图或safe-retry使用。

`verifiedReady`是获准的产品完成语义，不要求读取名为READY的私有内部字段。对应真实源码和范围证据现已独立审查；新合并程序还需真实目标/完成/恢复验证才可准入生产吞噬。现已实现事务化迟到失败补偿，并有活跃原卡片DOM故障/重启证据；这不等于真实网络异常或后台旧草稿恢复通过。成功与安全重试分别判断。

详见 [ADAPTER_CONTRACT.md](ADAPTER_CONTRACT.md)。

## 5. 微型窗口的实施边界

01「直截」候选参数来自原始R2 JSON：72×56pt包络、25%遮挡、60pt间距、0.7pt线宽、11pt数字，均在`RiftConfiguration`可调。全部真实图片保持原比例；每图一个nonactivating NSPanel，装饰细线单独忽略鼠标；外侧8pt和行间不设输入窗口。不依赖`hitTest(nil)`宣称下层穿透，不轮询指针。

收录220ms、浅入80ms/2.5pt、成功240ms、补位/失败180ms；reduced-motion缩短有限过渡，无持续空闲动画。只看到持久`.used`才吞噬。mouse-down锁定assetId，按下期间延缓重排，双击后半段不点击补位图片。编号上移结束后统一改成1…n。

缓存16MiB/32项，ImageIO按目标屏幕scale下采样。布局以配置的displayID锚定，断屏回退main；不用文件保存时鼠标位置猜截图来源。12+小屏使用可滚可见窗口，新图进入可见末端，保留所有条目；这是待评审实现，不是最终视觉裁决。

全屏/Spaces采用公开collectionBehavior和floating候选层级。首击、透明像素穿透、实际全屏和合盖/多屏仍需要真机；`.sharingType.none`不作为系统截图排除保证。

## 6. 按依赖组织的实施阶段

以下按**实际依赖**安排；同行并行推进。代码完成、CI通过、真机验收、生产启用是四个不同结论。F0–F3已集成的事实不代表它们的全部真机场景已通过。

| 阶段 | 实现前置条件 | 可交付物 / 通过条件 | 当前状态 |
| --- | --- | --- | --- |
| F0 工程与协议 | 本轮授权 | SwiftPM、系统SQLite、模块边界、可运行test/build入口 | 本轮完成；Mac构建通过 |
| F1 资产与恢复 | F0模型 | 完整图片→私有副本→持久队列；半图拒绝、原件不动、重启补漏、孤儿恢复、同图事件去重 | 自动来源切换/持久交接、C2故障回归、特殊文件拒绝和按需计量已通过CI；真实系统捕获待验 |
| F2 状态与协调 | F0；不依赖真实ChatGPT | 操作intent、防重、目标锁、unknown不重传、成功/失败分开准入、used持久 | 已有代码/CI通过；新增适配器继续用同一契约回归 |
| F3 原生裂缝 | F0/F1输出；F2状态 | 参数化小panel、2/3/12项、模拟三态；确定性布局测试及GUI验收辅助程序 | 辅助程序、7项配置/重排/屏幕策略边界已通过CI；真实GUI待验 |
| W0 Web证据与契约测试 | F2现有接口 | 将去隐私观察映射到版本化fixture；覆盖错图/错草稿/导航/迟到/模糊失败 | 已实现，14项合成契约测试通过；可接真实去隐私fixture |
| W1 Web候选实现 | F2；使用W0的fixture契约 | Apple Events单一路径、可替换transport、同一目标复核和一次append | 已完成；W2沿用该传输，没有重建transport或Core |
| W2 Web真实验证与准入 | W1实际路径 + 真实INPUT/IDENTITY/完成/RECOVERY证据 | 原文/旧附件保留；失败/导航/并发不误判；成功与safe-retry分别准入 | 已取得源码/证据并完成页面/App生成图片集成及CI；等待在线Mac执行集成真机验收，生产准入保持禁用 |
| M0 Mac独立基础 | F2接口；系统pasteboard类型 | 目标身份边界、fileURL/PNG表示、剪贴板所有权/恢复状态机及测试；AX观察入口 | 已实现19项合成流程/所有权测试，默认禁用；真实AX/NSPasteboard后端与跨实例/重启协调仍在M1接入范围 |
| M1 Mac真实验证与准入 | M0 + 特定bundle/version/surface的真实AX/输入证据 | composer绑定、正向逐图完成、明确失败、不会覆盖用户后续复制；按surface准入 | 新版Chat/Work与Classic各自验证，未通过的继续禁用 |
| R0 可重复工程构建 | F0及当前已集成模块 | 每个有意义的代码增量可测试、可打包、可下载；ad-hoc构建/合成smoke | 已有CI通过；持续维护，不等证书/Logo/完整适配器 |
| R1 发行候选 | 对应功能验收 + 至少Web Chat W2 | 真机全链路、资源/延迟测量、权限体验、正式签名/公证/安装验证 | 发布阶段；缺条件只停相应发行动作，不停开发 |

依赖关系的关键变化：F1/F2/F3、W0/W1、M0、R0可以独立推进；W2/M1的真实证据只控制对应能力的验收/启用。W1不再以“收到完整异常研究包”为整个任务的开工前提。Apple Events先作为可替换的开发候选；有具体阻断证据时才切换MV3，不同时建设两套生产transport。

**当前续做入口**：C1/U1/W0完成后已自动完成U2/W1/D1/C2/M0及具体审查修复；实际提交、验收范围和下一条动作见执行队列。N1/W2/M1保留各自真实系统/页面证据和native backend的接入工作，不把已完成实现重新列为未开工，也不把接口测试写成真实接入通过。

## 7. 验收与执行责任

当前工程集成负责人维护单一集成分支和Draft PR；模块可用独立worktree/分支或互斥写入范围并行，main不直接覆盖。负责人亲自处理核心契约、App组合、冲突和最终集成。代码作者以外的执行角色做独立技术审查，负责人解决意见，不把常规取舍转交用户。每次修复对应具体失败用例；不以测试数量替代产品闭环。本文“准入/评审”均指证据和工程质量检查，不隐含用户必须点击批准。

- **单元层**：身份/排序、SQLite持久、操作状态、错target/attempt拒绝、默认策略不消费、失败准入、mock隔离、布局/点击门闩。
- **文件集成层**：真实临时目录、ImageIO合成PNG、xattr真假、半文件、复制前后变化、symlink、manifest恢复、已用不复活、首次baseline/停机补漏/批次公平。
- **协调层**：fake adapter调用计数，重复点击、目标变化、append异常、UNKNOWN仅reconcile、FIFO与并发。
- **构建层**：Mac Actions执行`swift test --parallel`、release build、生成`.app`、ad-hoc签名验证、打包二进制`--self-check`。self-check只用合成图，不是ChatGPT测试。相关源代码/资源/测试/构建入口发生变化必须有对应的新运行证据；纯文档变更核对原已测代码未变，不主动额外重复长测。现有PR触发器若自动运行，照常观察并记录，不通过跳过检查节省时间。
- **Mac GUI层**：按 [MAC_ACCEPTANCE.md](MAC_ACCEPTANCE.md) 一次会话验证截图→可点、焦点/首击、透明/间隙、全屏、屏幕热插拔、合盖唤醒、自包含、资源采样。执行者记录真实环境与结果，不在Linux伪造GUI证据。
- **真实上传层**：复用技术包 [03_MAC_VALIDATION.md](../research/technical-decision-2026-10-26/03_MAC_VALIDATION.md) 的W00–W07/M00–M06；只用合成图及获准草稿，绝不发送消息。

## 8. 自主调度、默认决策与局部阻塞

本轮用户进一步授权：持续高速并行推进，工程过程中不要求用户审批或参与。负责人承担任务排序、成熟方案取舍、可逆默认值、修复与技术审查，不在每个完成点询问“是否继续”。

1. **领取与拆分**：一次启动最多三个相互独立的实现/审查包；负责人保留集成能力。每包写明依赖、唯一写入范围、最小交付和可执行验收。任务太大就按可独立验收的边界拆分，不制造没有产品作用的并行任务。
2. **完成一包后继续**：实现→相关检查→非作者审查→负责人集成→更新证据和队列→领取下一个READY项。接口先协商；修改共享Core/App/Package/CI只由负责人落地。集成基线推进后检查实际受影响的调用方，避免多支长期分叉。
3. **阻塞只停局部**：缺环境/证据/凭据时记录准确缺项、受影响能力、已有产物、解锁触发及可替代READY项。能做的壳、隔离实现、fixture和自动化先完成；不得把未跑的场景标成PASS。没有新证据不重复巡检同一个缺失环境。
4. **按成本和影响排队**：先保护数据与身份、消除公共依赖、交付可集成增量，再处理视觉细节。与现有缺陷/风险无关的测试扩张或重新竞品研究不占关键路径。若一个packet发现阻断正确性的缺陷，由该lane修复，其他lane继续。
5. **不等待个人审批**：工程默认与取舍记入执行队列/决策记录；用户无需逐项答复。最终视觉和Logo继续是候选；已验证技术准入由负责人按证据完成。涉及尚未具备的权限、账号或发布条件时只登记相应后续项，不自行绕过访问控制。
6. **可恢复的持续性**：会话可用时持续领取；会话结束/环境不可用时保存commit、队列状态、检查证据及下一条动作。下一执行会话从该检查点续做。当前没有常驻编码执行器；CI已是自动测试/构建，不宣称已经启用24小时无人编码服务，也不新增无产出的定时提醒。

| 事项 | 工程默认 / 当前动作 | 只约束什么 |
| --- | --- | --- |
| 最终尺寸、线宽、动画、Logo | 采用可调R2 01候选，保留配置；不标最终批准 | 最终视觉/品牌收尾 |
| 已用历史/自动删除 | 保留原件和私有副本，先实现计量与磁盘错误处理 | 自动清理功能；不阻塞收录、队列 |
| Web集成真机证据 | 原始异常包已取得/审查，页面/App验收模式已接入；直接运行现有构建 | 真实完成/安全重试与相应surface启用 |
| Mac GUI/AX机器不可用 | 辅助工具、构建和离线测试先做；用例保留待验 | 真机验收、支持声明和发布 |
| Developer ID/公证/安装凭据 | 维持可重复ad-hoc工程制品 | 正式签名和公开发行 |
| 已知丢数据、错目标、错误吞噬、UNKNOWN重传或许可缺失 | 修复或隔离该改动，继续其他lane | **该改动不得带缺陷集成/启用，不能简单留到最后** |

## 9. 后续低成本接入

收到Codex真实结果后只做：(1)归档去隐私环境/用例/receipt profile；(2)补充W0已经建立的fixture；(3)校准W1候选adapter的观察/输入细节；(4)针对surface/build分别审查成功/安全失败profile；(5)协调器回归及真实合成图全链路通过；(6)在App组合层启用对应adapter/profile。证据不成立则仅保留观察/UNKNOWN，或根据具体问题调整transport。Capture、SQLite身份、RiftPanel、动画不因READY判据变化而重构。

不将“严格内部READY尚未证实”泛化成所有工作阻塞；已取得的范围性实测证据用于本次实现，但不自动成为新集成程序的生产准入。

## 10. 原始依据与变更记录

- 本轮用户正式工程授权（2026-10-27，北京时间），记录于DECISIONS的P09。
- 同日后续授权自主并行开发、无需日常用户审批，记录于P12/P13；v2拆分实现/验证/启用依赖，并增加[可执行队列](EXECUTION_BOARD.md)。这没有追认视觉候选、真实上传或发布结果。
- [原始产品契约](PRODUCT.md)、[R2候选](../design/explorations/round-02/README.md)。
- [已核验技术交接包](../research/technical-decision-2026-10-26/README.md)：ZIP SHA-256 `70c30972238caac5e6d4d4f3f629af43a6748871cc4ca3d3d8c2f44b32abbe0a`，PACKAGE_INDEX 16/16通过；包内研究基线较本轮旧，原文保持不改。
- [精确复用与许可](REUSE_IMPLEMENTATION.md)、[本轮验证记录](VERIFICATION.md)。
