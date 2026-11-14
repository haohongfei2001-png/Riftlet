# Riftlet 质量审计：存储、历史、启动恢复与维护成本

- 审查基线：`44f745a15ecb3682a9da0bda17f17a5d9fc1f07e`（main 冻结快照）。正式发布基线由总负责人核对为 `v1.0.1`。
- 执行环境：Linux x86_64，没有 Swift 可执行程序、AppKit、WindowServer 或用户的 Mac；下文原生复现步骤是交接验收条件，没有冒充本轮实测。
- 修改范围：本审查没有修改产品源码、正式数据或 GitHub refs。
- 本轮实际执行：`python3 -B -m unittest discover -s Tests/StorageReadiness -p 'test_*.py' -v`，26 项通过，0.420 秒。原日志 `storage-tests.log`，输入源 SHA-256 与范围见 `storage-evidence.json`。它验证离线备份/健康检查/校验/还原 Python 工具在合成文件和真实 SQLite 上的行为；不能替代 Swift 导入、正常 App 启动、GUI 或 ChatGPT 验收。

## 结论与优先级

| ID | 级别 | 类型 | 结论 | 范围与优先次序 |
|---|---|---|---|---|
| QA-DAT-001 | P1 | 源码确认的故障恢复缺陷 | 外观/归档配置损坏会中止整个初始化，截图与历史都不可用，界面没有可执行的恢复路径 | 先修；成本中、回归风险中，保持原文件与库不变 |
| QA-DAT-004 | P2 | 源码确认的恢复入口缺陷 | 已补回的私有副本，点“重新检查”仍不触发本地恢复，状态持续 missing | 与第1轮恢复修复同组；成本小、风险中 |
| QA-DAT-002 | P2 | 源码确认的规模成本/工程债务 | 冷启动两遍全日志/非 used 文件校验，普通刷新全读未终结历史；START 已交接记录持续进入该集合 | 第4轮；先获得真实 App 大库指标，不能用推导伪称卡顿 |
| QA-DAT-003 | P2 | 明确的产品能力缺口，需设计裁决 | 没有私有图片清理路径或保留策略，归档和移出永不回收空间 | 第3/4轮；先把范围和回收语义定清，禁止直接自动删除现有数据 |

没有在本 lane 证明图片已经丢失，也没有把“需要原生验收”本身列成数据损坏。附件目标和 prepared 崩溃恢复由 ATT lane 独立负责，不重复建 Issue。

## QA-DAT-001 — 一个非关键配置文件损坏，阻断整个应用且无法从设置恢复

**严重程度：P1；证据等级：源码确认，原生复现 NOT_RUN。**

**具体位置**

- `Sources/RiftletApp/RiftletMain.swift:383–404`：直接 `try` 读取、解码与校验 `rift-configuration.json` / `lifecycle-settings.json`；任一失败，跳过后面的 panel/history/capture 构造。
- `Sources/RiftletUI/RiftConfiguration.swift:263–327`：例如 `fitWidth` 必须可解码为 Double，正值且不超过 256；坏类型或 `0` 均 throw。
- `Sources/RiftletApp/LifecycleSettings.swift:17–31`：负数/零或不合类型的 `archiveAfterSeconds` throw。
- `Sources/RiftletApp/RiftletMain.swift:250–258`：最外层 catch 只记录 initializationIssue、显示提示、更新设置，没有恢复后续构造。
- `Sources/RiftletApp/RiftletMain.swift:618–619`：直到服务构造完成才 `initialized = true`；`905–907` 的“重新检查”要求 initialized；`1744–1745` 的设置保存同样要求 initialized。
- 对照：`Sources/RiftletApp/ArrivalMotionPreferences.swift:19–39` 已有“保留坏文件、内存安全默认、标记 unreadable”的适当实现，可以复用思路，不必再设计全套配置框架。

**复现条件与步骤（必须在隔离 Mac 数据根，禁止对用户真实库执行）**

1. 创建正常隔离库，含两张合成已归档图片和一条 UNKNOWN，记录 SQLite 完整行、media、journal 的 SHA。
2. 正常退出，把隔离 `rift-configuration.json` 设为 `{"fitWidth":0}` 或截断 JSON；另一独立用例仅将 `lifecycle-settings.json` 设为 `{"archiveAfterSeconds":-1}`。
3. 从 Finder 或验收入口启动同源正式行为 App。预期按源码：仍可看到菜单/设置骨架及失败提示，但托盘、历史与收录没初始化。
4. 在界面点重新检查、修改外观、尝试打开历史：没有修复动作能把初始化完成；再次启动仍重复失败。
5. 当前只有在 App 外修复文件再重启才能恢复，不应要求普通用户编辑 JSON。

**理想行为与最小修改**

为这两类纯偏好增加有界读取、错误分类和非破坏降级：保留损坏/不兼容的原始字节，当前会话使用已验证的默认外观；坏归档策略暂不自动归档，避免未知配置导致可见图片悄悄消失。正常构建截图与历史服务。仅显示一次短提示并给“恢复默认设置”操作；明确只重置该项偏好，绝不重建 queue、删除 media 或改写 UNKNOWN。未知未来格式应保留并允许只读/默认模式，不能借机做破坏式向后迁移。保存成功后再切换正常状态。

无需新增设置模式、恢复向导、多个备用配置目录。保留普通数据错误与纯偏好错误的区别：数据库打不开不能静默创建空库。

**验收条件**

- 合法旧版配置继续读取，用户现有值不被一律重置。
- 截断 JSON、单个错误类型、超界几何、坏归档值各自不阻断截图/历史；有权限时第一次新截图可收录。
- 坏配置原始字节完整保留；数据库 schema/行、UNKNOWN、媒体与来源原件不变。
- 显式恢复默认仅改对应偏好；失败写入应保持当前可用会话并给短反馈；重启后成功读取新设置。
- 真实 GUI 验证错误提示只出现一次，不出现反复 modal 或灰色但不解释的恢复按钮。

## QA-DAT-004 — “重新检查”不重新核对已恢复的私有文件

**严重程度：P2；证据等级：源码确认，原生复现 NOT_RUN。**

**具体位置与调用路径**

- `PrivateAssetImporter.swift:266–272` 在恢复时发现非 used 记录的 media 不存在，会 `markMissingAsset`；`QueueStore.swift:741–745` 将资产状态改为 missing。
- 唯一正常的验证后清除 missing 路径在 `PrivateAssetImporter.swift:219–227`：manifest、数据库、当前媒体、完整 SHA 一致后 `restoreMissingAsset`。
- `CaptureService.swift:163` 的 `recover()` 只在 start 的启动流程里调用；`267–275` 的运行中 recheck 只有重挂 watcher 和 rescan。
- `RiftletMain.swift:920–923` 所调用的 binding.start 是幂等的（`CaptureSourceBinding.swift:279–280`）；同源 setSourceDirectory 不重启运行中的 service。因此正常“重新检查”没有间接 recover。
- `CaptureService.swift:473–475` 对已入库来源立即跳过，不会重新进入 importer 去核对恢复的 media。
- `QueueStore.swift:134–139` 明确不允许 missing 记录恢复到桌面。
- `docs/consumer/RECOVERY-AND-FAQ.md:13` / `CaptureDiagnostics.swift` 有“恢复存储访问后重新检查”的引导，但这个操作不能修复上述状态。

**隔离原生复现**

建立一张已归档 pending 合成截图，记录原私有副本；退出，把这一个测试 media 暂移到同测试目录内的保留位置；启动以建立 missing 状态。应用继续运行时将精确相同的 media 移回原位，点击“重新检查”。按当前源码仍为 missing，“恢复到桌面”不可用；退出再启动才会触发 hash + restoreMissingAsset 并恢复。

**建议最小修改**

让明确的存储/恢复重检调用现有 importer 的只读验证与状态恢复路径，限定于已报告 missing/invalid 或仍待完成的 import journal，不把每个权限重检都变成全库大 hash。完成后重新投影历史、桌面和诊断。恢复状态必须由原 manifest+原 UUID+大小+SHA 证明，不要把“同名文件存在”当作成功，更不能重新生成资产或重放附件。

**验收条件**

- 同一会话中补回正确副本→重新检查→原资产 pending/failed 等正确状态复原，原UUID/sequence与操作记录不变。
- 同名不同内容、symlink、尺寸不符不能清 missing；已有 UNKNOWN 不变，不生成任何输入/START。
- 读取失败能重试且只提示对应问题；正常新图继续收录。
- 测试停留在明确文件恢复用例，不需要整盘断电或回退历史库。

## QA-DAT-002 — 历史增长使启动和每次刷新承担无界工作

**严重程度：P2；证据等级：源代码路径确认，当前正式 App 的延迟/内存测量 NOT_RUN。**

**代码证据**

1. `RiftletMain.swift:379–380` 启动先创建一次临时 importer 并 await recover；正常已授权且未暂停的后续启动进入 `CaptureService.start:163`，另一个 importer 再执行 recover。第一轮报告甚至被 `_ =` 忽略。
2. `PrivateAssetImporter.swift:195–197` 枚举全部 journal；`219–227` 对每条已提交且 `status != used` 的媒体全字节 SHA 校验；`266` 再全读全部 assets。`verifyPreviouslyValidatedMedia:302–303` 证明每次都实际 hash，并非元数据缓存。
3. 归档的 pending、removed、UNKNOWN 均仍被 hash。普通“附件已接收”的 START 在 `QueueStore.swift:604–612` 只改变可见性与 phase，不变为 used；`TransferCoordinator.swift:540–547` 随后移出 currentFileInputs；`600–617` 的独立模式只观察该集合，不会自然把这些历史全部变成 succeeded。
4. `RiftletMain.swift:1243` 每次 refresh 查询 `QueueStore.unresolvedOperations:271–272`，无 LIMIT，解码所有非 failed/succeeded 的 target JSON，然后投影计数、prepared 表和 feedback。`successfulOperations` 有 LIMIT 64，不在此无界结论之内。
5. 这不是说保留历史本身错误。问题是将完整历史扫描置于启动就绪/高频 UI 更新路径；普通可见队列仅2–3张并不能限制历史成本。

**已有正面证据与边界**

仓库 `engineering/productization-20261107/performance/README.md` 与 `RECOVERY-COST.md` 记录真实原生模块探针：曾消除重复像素解码，将固定340条合成历史的恢复降至158ms；有完整一小时340条的合成图片/数据库保留证据。该改进有价值，不能说从未做过性能测试；但它不是正式App双重启动路径、不覆盖数千条正常已交接记录，也不证明当前版本长期延迟。旧11.76秒不是当前正式版数据，不能作为当前性能故障宣传。

**复现/测量交接**

在隔离 Mac 生成固定媒体和对应有效 journal，建立 200 / 2,000 / 10,000 条历史，其中保留十张可见图，分布覆盖 archived pending、START accepted、UNKNOWN。使用实际 App 启动、实际刷新/单图入库路径，记录从进程启动到菜单/历史/首图可交互的时间、读媒体总字节、recover 调用次数、每次 refresh 解码 operation 数、RSS。不要用直接模块benchmark代替整App测量，也不要重复造几十GB样本；可选合理小图/有代表性的图并清楚说明字节规模。

**最小修复方向**

- 在同一启动中共享恢复结果/同一 importer，消除重复全库恢复。
- 启动就绪先完成未提交 journal 和当前可见资产所需恢复；完整历史完整性检查按需/后台有界执行，附件前的源身份/哈希校验继续保留。
- 给 UI 提供独立的聚合计数、当前正在执行的操作快照、当前可见项状态；不要每次读取并解码所有旧 target JSON。
- 与 QA-ATT-003 的“已交给草稿 vs 真正不确定”状态裁决配合；绝不能将旧 UNKNOWN 大规模伪改为 succeeded 来制造性能改善。

**验收条件**

一次启动最多一次同范围恢复；固定活动队列下，refresh 的完整 operation JSON 解码数不随历史总数线性增长；10,000 条库的首个可交互时间有明确预算与真实测量，建议由Mac实现lane依据机器基线提出并独立复核。关闭大库优化后不能损失 crash recovery、损坏媒体拒绝、来源去重、旧UNKNOWN不重放。先修量化瓶颈，不为此引入新的存储引擎、ORM或常驻缓存服务。

## QA-DAT-003 — “归档”不回收空间，用户没有安全的本地清理入口

**严重程度：P2；证据等级：当前产品行为/文档明确；不是已发生数据丢失。**

**位置与现状**

- `QueueStore.swift:118–131,143–176` 的清空/移出/归档仅改 visibility。
- `PrivateAssetImporter.swift:99–187` 为每张系统截图建立私有媒体与保留 journal，原件不动。
- `CompletedScreenshotImporter.swift:10–22`、`ScreenshotEntryHost.swift:47` 内置截图保存于 captures 后再导入 media；成功后没有回收 captures 的路径，标注可能另有 derivative。这是原件保留策略，不能直接叫“泄漏”。
- `docs/consumer/PRIVACY.md:38–42,56` 明确“没有保留期限、永久删除策略或逐图永久删除控件”。故不是遗漏某个隐藏按钮。
- `RECOVERY-AND-FAQ.md:13,20` 让用户到其他位置腾空间、卸载仍保留全部数据。用户没有能在产品内安全回收历史副本的路径，也难以完成隐私清理。

**问题原因与裁决建议**

早期“不删原图/不清UNKNOWN/保留证据”的工程护栏，被扩张成无限期保留所有私有媒体。前者必须保持；后者不应成为成熟公开软件唯一的存储策略。不要因此再增加很多“保留天数/各类自动清理”设置。

本轮先交付一个自然的“存储”入口：只读总量、截图副本量、确认为闲置且可回收的量与清晰的清理说明；设计一个用户主动选中的本地清理动作。默认不自动过期；系统原件永不受影响。正在输入、UNKNOWN、待恢复 journal、尚未安全定性的记录不得作为默认可回收对象。任何删除实现必须先独立审查原UUID去重凭据/最小墓碑的保留与备份兼容，明确删除只影响Riftlet私有副本，并在确认中给具体张数和空间。此审计不授权删除任何现有用户数据或将旧版本数据迁移成空库。

**验收条件**

普通用户不需要理解 SQLite/media/journal 目录就能知道本地副本占多少、归档为何未释放空间、能安全移除哪些副本。真正实施清理前，先通过独立测试证明来源不会再次补收/重复附加、UNKNOWN不丢、系统原图与备份不受影响、崩溃中断不会留下不可判定“删除一半”的库。若本迭代只完成设计，不得将其标成“存储治理已修复”。

## 应保留而不是“清理掉”的工程保护

- staging→journal→原子media提升→SQLite的恢复排序，journal目录 fsync、原图只读、导入源identity、同源幂等：`PrivateAssetImporter.swift` 实质解决中断/写满/重复事件，不是无用抽象。
- SQLite迁移在事务中、WAL、FULL synchronous、schema版本拒绝未来不兼容、旧UNKNOWN保持：`SQLiteDatabase.swift` / `QueueStore.swift`。
- 大图预览的哈希/descriptor身份/预算与后台串行解码：`HistoryPreviewLoader.swift`。不能为“少代码”退回主线程加载全分辨率原图。
- `Tests/RiftletCaptureTests/ImportFaultTests.swift` 的故障点测试可重开真实文件/SQLite；`Tests/Readiness/NativeDiskFullRecovery.swift` 的历史有限卷ENOSPC结果是有意义的证据，但本轮未重跑，且旧结果绑定旧源。
- Python存储工具26项全通过说明已有可靠离线维护基础。优先让当前App正确调用已有能力，不要重写一个“新恢复系统”。

## 工程交接顺序

1. 先实现QA-DAT-001，独立复核失败降级边界、保留坏文件与真实GUI恢复。
2. 同一恢复增量加入QA-DAT-004，在运行中恢复同一资产；不串入清理功能。
3. 配合QA-ATT-003确定状态投影，量化QA-DAT-002后做最小去重/查询优化。
4. QA-DAT-003先提交可审查的删除语义与迁移设计；新清理能力不能混入稳定性补丁，不得用删除旧库来让大库性能测试通过。
