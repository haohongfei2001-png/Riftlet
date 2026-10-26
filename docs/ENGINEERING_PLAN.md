# Riftlet 正式工程计划

2026-10-27（北京时间） · 工程启动基线 `5a3ab5d7a761d5397f8bc15b6f40d761b29e58d2`

## 1. 授权、范围和最小交付

用户本轮明确授权正式开发，取代 P07 的“暂不开发”阶段；历史研究和决策不删除。01「直截」只作可调实现起点，视觉与品牌仍未最终批准。产品契约仍是系统截图、点击微图、正确追加到原 ChatGPT 草稿；不自动发送，只有获准完成证据才吞噬。

**最小完整产品**：一个原生常驻 `.app`，自动感知已保存的系统截图，保留原件并收录私有副本，持久 FIFO 队列，极小非激活裂缝，点击追加到已验证的 ChatGPT surface，逐图回执、失败恢复和未知核对，重启/唤醒/多屏可用，一次性权限及安装说明。没有服务器、云数据库、AI API、图库/OCR/编辑器或新截图引擎。

**本轮交付是工程基础构建，不是完整产品发布。** 本轮编写并集成收录、队列、参数化原生窗口、模拟适配器、单元/集成测试、Mac 构建脚本。生产 ChatGPT 输入默认禁用。正常截图仍可收录，点击保留并在状态菜单说明适配器尚未启用。模拟模式有独立目录、显著 SIMULATION 标识且只接受 synthetic 资产。

第一款可交付版本必须至少使 Web Chat 在明确支持的 Chrome 版本通过完整闭环。Web Work、新版 Mac Chat/Work、Classic 单独准入；若某一 surface 尚未通过，不影响其他模块开发，也不被宣传成已支持。是否以仅 Web 的首版公开发布，属于之后的发布评审，本计划不自行删去 Mac 目标。

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
| `RiftletUI` | 配置、纯布局、下采样缓存、小NSPanel、连续编号和状态动画 | AppKit、ImageIO、QuartzCore、Core |
| `RiftletApp` | 菜单栏、独立实例锁、组合以上模块、配置加载、开发模拟和self-check | 三个库target |

只有 App 组合模块；Capture 不依赖上传，UI 不写数据库、不执行上传、不删除文件。不引入第三方 Swift package 或常驻 helper。需要浏览器扩展时再增加一个 stdio native host，不预建两套生产 transport。

## 3. 本地资产与事务

- `Application Support/Riftlet/` 为真实截图根；`Riftlet-Simulation/` 独立保存合成演示。目录0700、媒体/数据库0600；实例锁防止同时打开同一App数据目录。系统截图源保持不动。
- 默认只读 `com.apple.screencapture` 的保存位置，缺失则Desktop。识别读取 `com.apple.metadata:kMDItemIsScreenCapture` 的实际bool；不靠中英文名字，不把普通自定义目录中的全部图片当截图。剪贴板/Preview目标暂不支持文件路径收录。
- 首次启动建立原有文件baseline；监听先于扫描，扫描期间变脏补扫。后续重启/唤醒收录未处理的新来源。事件只意味着重扫，不意味着图片完整。元数据迟到、部分写入分别有限重试。
- 文件事件身份与内容hash分开。sourceKey来自稳定文件身份；两个独立截图即使字节相同也各有 UUID。显示编号不是身份。capturedAt不可证时保留nil；firstSeenAt不冒充捕获时刻。
- 复制源前后核对身份、size/mtime；拒绝symlink。对私有staging核验ImageIO完整状态、实际下采样解码和hash。实际编码决定扩展名/MIME，不仅改后缀。
- `staging/<id>.part`同步落盘，写持久journal manifest，原子提升到`media/<id>.<codec>`，最后SQLite入队。没有假设文件与SQL存在跨系统原子事务。崩溃恢复使用manifest收养孤儿；校验失败保留并报告，不收录半图。
- SQLite WAL、synchronous FULL、foreign_keys、schema版本、quick_check；asset、operation、receipt同一事务写入。source唯一约束只消除重复事件；每asset至多一个未决操作，每target至多一个已分派未决操作。
- 外部输入前持久化dispatch intent。崩溃发生在intent前：可证明未输入；intent之后：UNKNOWN。即使崩溃实际发生在外部调用前，也保守核对，不宣称远端exactly-once。
- 成功只更新used记录，不删除原图或私有副本。已用历史/物理删除策略尚未批准，因此本轮不加入自动淘汰；UI不全量加载used历史。下一阶段必须评审磁盘保留上限和显式清理语义。

## 4. 状态与上传接口

Asset可见状态：pending、transferring、unknown、failed、missing；used退出待用队列。Operation区分prepared、dispatchIntent、inputTriggered、attachmentPresent、unknown、failed、succeeded。

`AttachmentAdapter`只有 `captureTarget / validate / append / reconcile`，没有Send。`TargetLease`包含adapter/surface/app/session/window/tab/document/composer/draftGeneration。adapter必须在同一目标执行片段内复核lease并追加，不以之前一次validate替代临界区验证。

回执绑定operationId、assetId、attempt、hash、完整lease及profile版本。INPUT和ATTACHED仅观察状态；verifiedReady仍须已准入profile、正向ready、原草稿成员关系、准确attachmentId、无error/上传中。明确失败还须**独立的retrySafeProfiles准入**、无残留自动重试；否则保持UNKNOWN。晚到/错草稿/错attempt回执不得消费另一条。

当前生产成功/失败准入表均为空，没有通过配置文件跳过验证的开关。演示仅在simulation store + synthetic asset + simulation target + simulation-v1四重条件下通过。

`verifiedReady`是获准的产品完成语义，不要求读取名为READY的私有内部字段。经真实异常验证合格的产品级ATTACHED可以映射到它；当前候选尚未通过，仍不能吞噬。

详见 [ADAPTER_CONTRACT.md](ADAPTER_CONTRACT.md)。

## 5. 微型窗口的实施边界

01「直截」候选参数来自原始R2 JSON：72×56pt包络、25%遮挡、60pt间距、0.7pt线宽、11pt数字，均在`RiftConfiguration`可调。全部真实图片保持原比例；每图一个nonactivating NSPanel，装饰细线单独忽略鼠标；外侧8pt和行间不设输入窗口。不依赖`hitTest(nil)`宣称下层穿透，不轮询指针。

收录220ms、浅入80ms/2.5pt、成功240ms、补位/失败180ms；reduced-motion缩短有限过渡，无持续空闲动画。只看到持久`.used`才吞噬。mouse-down锁定assetId，按下期间延缓重排，双击后半段不点击补位图片。编号上移结束后统一改成1…n。

缓存16MiB/32项，ImageIO按目标屏幕scale下采样。布局以配置的displayID锚定，断屏回退main；不用文件保存时鼠标位置猜截图来源。12+小屏使用可滚可见窗口，新图进入可见末端，保留所有条目；这是待评审实现，不是最终视觉裁决。

全屏/Spaces采用公开collectionBehavior和floating候选层级。首击、透明像素穿透、实际全屏和合盖/多屏仍需要真机；`.sharingType.none`不作为系统截图排除保证。

## 6. 按依赖组织的实施阶段

| 阶段 | 前置条件 | 可交付物 / 通过条件 | 当前状态 |
| --- | --- | --- | --- |
| F0 工程与协议 | 本轮授权 | SwiftPM、系统SQLite、模块边界、可运行test/build入口 | 本轮完成；Mac构建通过 |
| F1 资产与恢复 | F0模型 | 完整图片→私有副本→持久队列；半图拒绝、原件不动、重启补漏、孤儿恢复、同图事件去重 | 代码与文件集成测试完成；真系统捕获待Mac |
| F2 状态与协调 | F0；不依赖真实ChatGPT | 操作intent、防重、目标锁、unknown不重传、成功/失败分开准入、used持久 | 本轮完成；macOS XCTest通过 |
| F3 原生裂缝 | F0/F1输出；F2状态 | 2/3/12项、比例/遮挡/编号、模拟三态、非激活panel；真实命中和显示器验收 | 代码与布局测试完成；GUI待真机 |
| W1 Web接入 | 另一个Codex真实异常证据 + F2接口 | 同一adapter绑定真实目标、一次append、可回查；仅选一生产transport | 并行验证，不阻塞F1/F3 |
| W2 Web准入 | W1 INPUT/IDENTITY/READY/RECOVERY证据齐备 | 正常追加不破坏原文/旧附件；失败/导航/并发不误判；通过profile方可开启真实吞噬 | 真正阻塞完整Web交付 |
| M1 Mac独立接入 | 针对新版/Classic的AX实际证据 | fileURL/PNG表示、窗口/composer绑定、逐图ready；剪贴板安全恢复 | 与W1并行，未启用 |
| R1 产品构建 | F1/F2/F3 + 至少一个surface W2或M1 | 真机全链路、资源/延迟测量、权限说明、正式签名/公证/安装验证 | 待前述关口；本轮不发布 |

**今天能做并已开始**：F0/F1/F2/F3、协议fixture与CI。**可并行**：Web异常验证、Mac AX观察、UI真机机制、品牌设计。**必须等真实证据**：成功/终局失败profile准入、生产transport定版、Mac支持声明、自身截图排除和真实资源承诺。

## 7. 验收与执行责任

当前工程集成负责人维护单一功能分支和Draft PR；main不直接覆盖。独立模块可并行实现，但最终构建、状态契约和验收证据统一审查。每次修复对应具体失败用例；不以测试数量替代产品闭环。

- **单元层**：身份/排序、SQLite持久、操作状态、错target/attempt拒绝、默认策略不消费、失败准入、mock隔离、布局/点击门闩。
- **文件集成层**：真实临时目录、ImageIO合成PNG、xattr真假、半文件、复制前后变化、symlink、manifest恢复、已用不复活、首次baseline/停机补漏/批次公平。
- **协调层**：fake adapter调用计数，重复点击、目标变化、append异常、UNKNOWN仅reconcile、FIFO与并发。
- **构建层**：Mac Actions执行`swift test --parallel`、release build、生成`.app`、ad-hoc签名验证、打包二进制`--self-check`。self-check只用合成图，不是ChatGPT测试。
- **Mac GUI层**：按 [MAC_ACCEPTANCE.md](MAC_ACCEPTANCE.md) 一次会话验证截图→可点、焦点/首击、透明/间隙、全屏、屏幕热插拔、合盖唤醒、自包含、资源采样。执行者记录真实环境与结果，不在Linux伪造GUI证据。
- **真实上传层**：复用技术包 [03_MAC_VALIDATION.md](../research/technical-decision-2026-10-26/03_MAC_VALIDATION.md) 的W00–W07/M00–M06；只用合成图及获准草稿，绝不发送消息。

## 8. 后续低成本接入

收到Codex真实结果后只做：(1)归档去隐私环境/用例/receipt profile；(2)将原始证据转为小fixture；(3)实现Apple Events或MV3之一的adapter；(4)针对surface/build分别加入成功/安全失败profile；(5)协调器跑同一回归；(6)在App组合层用获准adapter替换UnavailableAdapter。Capture、SQLite身份、RiftPanel、动画不因READY判据变化而重构。

不将“严格内部READY尚未证实”无限泛化成所有工作阻塞，也不把当前ATTACHED候选晋升为可自动吞噬的生产结论。

## 9. 原始依据

- 本轮用户正式工程授权（2026-10-27，北京时间），记录于DECISIONS的P09。
- [原始产品契约](PRODUCT.md)、[R2候选](../design/explorations/round-02/README.md)。
- [已核验技术交接包](../research/technical-decision-2026-10-26/README.md)：ZIP SHA-256 `70c30972238caac5e6d4d4f3f629af43a6748871cc4ca3d3d8c2f44b32abbe0a`，PACKAGE_INDEX 16/16通过；包内研究基线较本轮旧，原文保持不改。
- [精确复用与许可](REUSE_IMPLEMENTATION.md)、[本轮验证记录](VERIFICATION.md)。
