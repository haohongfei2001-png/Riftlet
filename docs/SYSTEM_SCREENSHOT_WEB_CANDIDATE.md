# 真实系统截图 Web 内部候选 · 2026-10-28

本页是已实现源码的使用／准入交接，不重订整体计划。基线 `b83923068064f6d82f2d253a3c177661fdabc294`；候选分支 `codex/system-capture-candidate-20261028`。实现提交 `3da1288f8b16fbf46082ebf78eab92a1e2089d22`，截止边界修复 `4d352c28dcb70e8f6dc42ef93d9df46042a9215d`。最终正式检查点和组合 CI 见 [集成交接](INTEGRATION_HANDOFF.md) 与 PR #1。

## 当前可以运行什么

**普通启动仍是本地收录，不能上传真实截图。** 新的显式内部候选已接通系统文件收录与既有 Web 输入链，能够供授权 Mac 执行者取得真实截图观察；尚未批准生产使用，也不宣称真实两次操作闭环通过。

| 入口 | 数据目录（Application Support 下） | 来源与输入 | 准入 |
| --- | --- | --- | --- |
| 普通 `Riftlet.app` | `Riftlet` | 系统截图收录；`UnavailableAdapter` | 开始／完成／重试均关闭，不检查 Chrome 权限 |
| `--simulate` | `Riftlet-Simulation` | 生成图，离线状态演示 | 仅 simulation store/target |
| `--web-acceptance` | `Riftlet-Web-Acceptance` | 生成图，真实 Chrome 输入 | 保留已审生成图开始／完成；安全重试关闭 |
| `--system-screenshot-candidate` | `Riftlet-System-Screenshot-Candidate` | **原始系统截图**，显式内测输入 | **开始／完成／安全失败全部关闭**；保存未准入观察 |

普通 App 菜单新增 **“打开真实截图内部候选…”**。一次说明后启动独立实例，菜单标识为 `Riftlet REAL TEST`；首用窗口、截图位置访问、暂停、隐藏、历史与 Chrome 权限恢复沿用既有实现，不要求改 JSON 或打开终端。普通实例继续保留，macOS 的 launch 回调不会被误当成候选已初始化；执行者确认候选状态后，可按需要退出普通实例以免同时显示两组微图。此启动界面仍须真实 Mac 验收，CI 不证明它已通过。

本地 Codex 可使用同一显式入口：

```bash
bash scripts/build-macos.sh
./build/Riftlet.app/Contents/MacOS/Riftlet --system-screenshot-candidate --acceptance-trace
```

首次收录沿用 Capture 的持久 epoch／历史基线，只收录开始后出现的符合系统截图 metadata 的文件。不要把旧图库导入为新截图，也不要删除候选数据库来绕过 UNKNOWN。重开候选仍使用原目录，原操作只读恢复，旧点击不恢复。当前没有可用完整 ACK 仍安全拒绝，不能把第八轮尚未交接的冷首击工作算入本版本。

## 实际接线与保持不变的部分

- `ApplicationMode` 明确分开系统收录、生成图 seed 与 Web 能力；候选兼具收录和 Web 能力，却不能 seed 生成图。全库 origin 检查在私有导入恢复后、构造 transport 前进行。
- `ApplicationAttachmentComposition` 是 App 与软件自检共用的实际组合。候选复用 `CaptureService`／`PrivateAssetImporter`、SQLite v3、AcceptedSelection／同步序号、**原单一 Coordinator**、Chrome Apple Events、MAIN 桥接和 v12 页面程序。
- `AttachmentAdapter.preflight(asset:fileURL:)` 是新增的**本地、无外部副作用**资格检查；其他适配器默认空实现。Coordinator 先处理已有原操作；只有新输入才 preflight，随后 reserve／prepare。格式不支持不会先制造 intent／UNKNOWN／目标锁。
- 候选只采用已有页面源 `chatgpt-web-zh-20261027-integrated-v12`。当前页面 JS、Chrome 身份读取／执行器、MAIN envelope、旧版本只读路由均未修改；每块最多 256 KiB、逐块 ACK、同一 no-follow descriptor 两次完整 SHA256、唯一 commit 和完整原目标复核保留。
- 传输使用 `riftlet-<operation UUID>.png`，不传系统原文件名。只读取私有副本；不转换、重新编码、改后缀冒充编码或修改原图。开始事件仍由既有严格 v1/schema2 正向证据产生，input.files／change／占位图不能替代。
- `ObservationNormalizer` 新增原生控制的 `systemScreenshotCandidate` scope；默认 scope 仍拒绝真实来源的 development 观察。候选保持原 `integratedDevelopment` provenance，**不伪装为 sanitizedReal，也不把真实图改为 synthetic**。scope 只有对应候选 profile 可以使用。
- `SystemScreenshotObservationJournal` 把未准入观察保存在原 SQLite v3 `checkpoints` 表。每原 operation/attempt 最多六条首值：input、start、干净 attached、干净 ready、error/invalidated、unknown；每条最多 64 KiB。原子 first-write-wins，完整检查已持久 asset/op/attempt/hash/target，重复或重启不覆盖。它不写 `upload_starts`、不改 queue、不生成授权，磁盘失败不能变成安全失败。
- 持久 intent 后才发现私有文件损坏或传输不明，仍按原 intent 边界保守 UNKNOWN；此时可能尚无实际输入，不会为了“没有看见输入”授予重试。文件头/格式预检不被宣传成完整 SHA 校验的替代。

没有浏览器扩展、云服务、额外 SDK、依赖包或第二套 Coordinator。Capture 继续复用已登记的 Screenshoss 完整性原语与原生文件监测；Web 继续复用已归档的 Oracle 派生输入／观察实现，版权与许可文件不变。

## 文件格式、大小与保真范围

| 系统文件 | 本地收录 | 当前候选输入 | 保真策略／尚未验收 |
| --- | --- | --- | --- |
| 单帧 PNG，≤8 MiB、≤16,777,216 像素 | ImageIO 完整检查后原字节复制 | 有资格进入内测输入；仍需原目标／权限门 | 不重编码；实际 ChatGPT 对真实截图的身份／开始／完成待验收 |
| 带 ICC／高位深的 PNG | 原字节、编码尺寸、ICC／位深保留 | 同一 PNG 资格上限，不擅自转 8-bit | CI 的 16-bit/P3 保真只证明本机复制；浏览器／服务端颜色、HDR、gain map 与最终呈现不据此通过 |
| JPEG | 单帧原字节，EXIF 方向和颜色信息留在文件中 | 本地拒绝，零 begin／commit | 不转 PNG、不改质量；方向预览使用 ImageIO transform，但真实旋转图外框／遮挡几何仍须观察 |
| HEIC／HEIF | 实际 ImageIO 类型可用且为单帧时接受 | 本地拒绝 | 不调用隐式有损转换；HEIC 编码器测试不能冒充所有 HEIF／HDR 场景 |
| TIFF | 单页原字节接受，多页拒绝 | 本地拒绝 | 不丢页、不自动扁平化 |
| PNG >8 MiB，但在本地上限内 | 原样保留并可恢复 | 输入前明确拒绝 | 不压缩；新增真实编码 >8 MiB 的生成 PNG 验证本地保存与重启原字节一致 |
| PNG >16,777,216 像素，但在本地上限内 | 原样保留 | 输入前明确拒绝 | 不缩放；这是已有 v12 页面观察上限，不声称是 ChatGPT 通用产品限制 |
| >128 MiB、>160,000,000 像素或单边 >50,000 | 按现有 Capture 上限拒绝收录 | 不输入 | macOS 原文件保留，显示收录限制 |
| PDF、多帧／不完整或无法解码的图片 | 拒绝或等待完整性恢复，按实际原因 | 不输入 | 不抽帧／改成另一种格式 |

附件拒绝使用“**已保存在本机，未上传／未转换**”的独立文案，不能说成“未收录”。本轮没有转换策略开关；要增加 JPEG 或更大输入，须扩展当前页面和关联证据并独立审查，不能仅增大 Swift 数字或把 MIME 改成 PNG。

## 三个独立准入与当前视觉结果

候选 manifest 固定两个不同于生成图的 profile：

- 开始：`chatgpt-web-system-screenshot-start-candidate-20261028-v1`。
- 完成：`chatgpt-web-system-screenshot-attached-candidate-20261028-v1`。
- 安全失败：目前没有启用的 failure signal/profile。

`SystemScreenshotCandidateConfiguration` 的 `uploadStartProfiles`、`completedAttachmentProfiles`、`safeFailureProfiles` **均为空**。它们由源码持有，不读取外部 JSON／环境变量／页面传来的“enable”。默认普通模式仍独立使用 `UnavailableAdapter`；权限允许不等于切换到候选或生产。

所以当前候选的准确结果是：**允许测试输入 → 保留原 start／attached 候选观察 → 队列仍待核实且可见，不假吞噬、不写 succeeded、不重传。** 同草稿下一张仍受原 UNKNOWN 锁保护；不要把这说成双图成功排空或快吞噬已经通过。

取得并独立审查真实截图开始证据后，只需在对应候选开始策略进行受限准入，既有 Core/UI 会走已实现的 `uploadStarted → 极快吞噬`；完成和安全失败仍分别关闭。最终成功准入后才允许记录 `succeeded`；安全失败还需要证明旧操作终止且无残留自动重试。此前合成测试与生成图真实样本都不能自动填入这三份表。普通生产启用还需显式审查 App 组合与支持范围，不能从“候选启动成功”推导。

安全失败并非只填一条表就已经可实现：当前候选 `failureSignal == nil`；既有 absence-only 失败路径没有原非空 attachment ID，而补偿释放要求该原身份。这个既有退役身份缺口仍须真实证据及对应适配器小改动解决；本包没有制造新的失败信号，也不把 POST100/MID 中断或附件消失当成安全终止。

## 已自动化与尚缺的真实证据

软件回归和 packaged self-check 覆盖原字节导入、真实 origin 分离、格式本地拒绝、同 descriptor/hash、唯一输入、未准入开始／完成、首条观察持久化、UNKNOWN 重启／再点击只读、默认生产关闭以及三个准入互不推导。它们全部使用生成文件、构造观察与 fake bridge；不建立真实截图上传许可。[实际 CI／审查](../engineering/evidence/2026-10-28-system-screenshot-candidate/README.md)。

本地 Codex 在第八轮工作适当结束、与负责人按最新正式 SHA 合流之后执行以下**缺证据项**，不争用正在运行的工作树：

| 证据门 | 必须取得的真实证据 | 目前状态 |
| --- | --- | --- |
| SC-INPUT | 普通 macOS 截图入口、真实 screenshot metadata、源与私有副本/hash/编码尺寸、原点击/ACK/目标/operation/attempt、begin/chunk/commit 与 inputCount=1；不发送消息 | NOT_RUN |
| SC-START | 同一真实 asset/op/attempt/完整 target 的严格正向进度或请求证据、一次输入关联和时间顺序；排除占位、错图、错目标及迟到开始 | NOT_RUN；候选审计可取证，开始准入关闭 |
| SC-COMPLETE | 同一附件产品级 ATTACHED 的实际完成证据，原正文／选区／旧附件保留，已聚焦和未聚焦编辑器分别记录；既有对话／Home 范围明确 | NOT_RUN；完成准入关闭 |
| SC-ANOMALY | 真实网络异常、目标变化、观察丢失、重启和迟到错误；UNKNOWN 不输入第二次、首条观察／私有图保留；真实业务 ABA/同 URL 和多 profile 不猜测 | NOT_RUN；继承原未通过项 |
| SC-FAILURE | 与原图关联的真实强失败，旧流程已终止、不会迟到成功且无残留自动 retry；新的尝试只由新点击触发 | NOT_RUN；不因 MID/POST100、超时或成功准入授予 safe retry |
| SC-UX | 开始证据获准后，真实物理点击 → 开始 → AppKit 关闭／屏幕消失的各时间边界；冷首击、CLEAR 真实透传、按住补位、屏幕切换、原图自包含／系统延迟 | 依赖对应第八轮及后续独立实测，不继承为 PASS |

当前版本没有运行真实 Chrome、真实系统截图或物理 GUI。继续保留第七轮限定双图 PASS、CLEAR 透传 FAIL、GAP 软件事件通过、缺 ACK 冷首击 FAIL，以及业务 ABA、MID、真实安全失败、自包含等开放边界；第八轮未交接源码／证据没有被读取或整合。

审计在候选私有 SQLite 中；公开交接只放经过人工检查的匿名身份摘要与必要时序。原图、完整私有数据库／日志、ChatGPT 正文／浏览器状态不进入公开仓库。不存在把历史 UNKNOWN 图重新输入以制造“通过”的验收步骤。
