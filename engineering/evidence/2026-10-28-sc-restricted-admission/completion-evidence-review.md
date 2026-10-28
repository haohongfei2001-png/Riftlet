# Riftlet — 真实系统截图内部候选 completion 独立审查

日期：2026-10-28
审查角色：`admission_completion_review`，非源码作者、只读证据与源码审查。
正式基线：`871d825a43a759bb6dd8ded9cdc99a340d8e0e64`
真实完成证据：`493d1d8b898d18e34709463d2dceca8c85ad4014`
真实 Mac 运行源码：`48574df19f34e5681ee98815750e279540e9eb9b`
审查工作树：`/workspace/scratch/16d4559e9aa8/Riftlet-sc-admission`

## 决定

**证据层面 PASS：支持独立开放受限的真实系统截图内部候选 completion 准入。** 该决定独立于 uploadStarted 的准入；完成依靠原附件最终加载后、绑定完整原操作身份的严格内容 proof。

准入只适用于升级后以明确的新准入资格创建和派发的新操作，且必须满足下述 ordinary-thread、真实系统来源、8-bit RGBA PNG 和原有有界传输限制。**不能仅把现有 completion profile 加入允许表**：旧 F 和其他历史 UNKNOWN 的 reconcile 会使用应用当前的 normalizer，因此必须在持久操作资格层防止追溯授权。旧 F 在证据中的事实仍是 `unknown/visible`，不是本轮新实现的 `succeeded`。

本审查批准的是受限策略的证据依据，不是尚未审查的最终新代码、CI 或新的真实 Mac 快吞噬体验。最终实现仍须由非作者审查并完整运行 macOS CI；新的“开始→吞噬→后台 succeeded”体验由另一张新截图验证一次。

## 审查范围和证据可信度

本轮独立读取公开证据目录 `engineering/evidence/2026-10-28-system-screenshot-complete/` 的 README、result、timeline、review、verification 和 private-evidence-sha256，审查实际源码的 page proof、原始身份检查、normalizer 和原候选范围控制；没有执行浏览器动作、文件输入、真实截图上传、旧操作 replay、私有数据库读取或任何源码写入。

公开材料有意删除原图、完整 target/operation 标识、私有文本和数据库，因此本轮**没有亲自重新解码私有 F，也没有独立逐字段重算原始数据库**。完整原图/私有副本 SHA、完整身份逐字段比较、独立浏览器像素提取、旧数据库保持和私有 hash 索引核验，来自交付包中上一位非作者 `native_gui` 对原始私有证据的只读审查记录。本轮对这些记录做一致性审查，并独立确认对应生产源码确实具有记录所需的严格判据。不能把公开 SHA 索引本身称为原始文件真实性证明。

本轮实际执行的 14 项公开内部一致性校验全部通过：真实运行源码 JS 的 git blob SHA、当前 worktree JS SHA、runtime/verification/CI 源 SHA、尺寸与通道数量、两份 RGBA SHA、零差异、preview 与索引 SHA、一张旧附件的原件/预览 SHA、29 项索引格式、唯一输入数量、严格序列、48 字正文和 8..11 选区、最终非上传/非错误/非失效，以及 F 未获旧准入。此检查不冒充 macOS 原生测试或新的真实截图验收。

## 证据核对

| 项目 | 独立审查结果 |
| --- | --- |
| 原系统截图 | 新 selection 截图 F；交付记录 `kMDItemIsScreenCapture=1`，不是给生成图片伪造 metadata。1746×1164，8-bit RGBA，PNG color type 6，6,796,322 字节。系统原件/私有副本 SHA 相同：`0c19cb16f5c6dfdcaf0958284d6f40450912ea03babe5a79e1d268c2f06ff596`。这些原始文件由前一位私有证据 reviewer 核验。 |
| 操作和目标 | 公开记录确认 asset/operation/attempt/hash 与 Chrome PID/session/window/tab/document/composer/draft、logicalDraftIdentity 在预点击、page、journal 和 DB 一致；完整标识未公开。本轮确认源码 `sameIdentity` 和 Swift normalizer 要求同一完整身份，并非只按文件名或卡片文字匹配。 |
| 原点击 | 原 ACK 提前 1208.909 ms，绑定已知目标；不是无 ACK 冷首击。一次 CGEvent 软件 down/up 穿过原生缩略图窗口，不是物理鼠标验收。 |
| 唯一输入 | 1 begin / 26 chunk / 1 commit，全回复成功；page input=1、独立 change=1、native selection=1。26 次传输分块没有被误认为 26 次页面输入。源码 commit 的一次性 tombstone 在异步校验前设置，最后检查与 setter/change 之间无 await。 |
| 开始与完成分离 | 有真实原节点 2.4538636→3.6807954 正向进度，input→start 2151.4 ms。完成另外要求原节点 100%、进度移除、原 image 最终 data-PNG load、proof；不是用开始推导完成。 |
| 最终完成顺序 | input sequence 2 < hash 7 < start 17 < hundred 50 < ended 59 < loaded 60 < proof 62，input→proof 8784.0 ms。原卡片/原 image 均 connected，invalid/error/uploading=false，progressCount=0；proof identity/nodes/source 均为原对象。 |
| 独立内容证明 | 原文件在独立解码前再次 SHA 校验。显式普通 sRGB OffscreenCanvas RGBA8，不带 willReadFrequently，不容差；原件与预览尺寸一致，完整 RGBA SHA 均为 `6f20aa4069b1d28a3693527e3b7d1402e424a393271a3d38ec081c98b0f5d129`。1746×1164×4 = 8,129,376 通道，differentChannels=0。独立读取后仍是原 image/source。 |
| 附件字节范围 | preview PNG 6,673,150 字节，SHA `3eaa650ed13568739c4835244275a939b44d19e0cbe7e3ab538e0c198f20bcff`，与 private hash 索引一致；它不同于原 PNG。证明的是浏览器普通 sRGB 内容精确一致，不是服务端保留原 PNG 字节，也不是 HDR/高位深保真。 |
| 正文和选区 | 原正文 48 字符，前后相同；非折叠选区 8..11，两端均在原 editor，选中文字保持。页面有焦点而 editor 没有键盘焦点。24 个输入后快照与最终快照均保持；不外推为每个未采样瞬间。 |
| 旧附件 | 一张稳定完成的 48×32 PNG，原 card/image/source/尺寸/完成状态保持；最终共两张卡片。旧附件的准备文件与最终 preview SHA 均为 `fd25db98549203ca48d59e8fe1bb54f5077d0b0ef7b4efa23d19ee2315d94385`。其单次独立准备输入发生在 F 正式试验之前，不混入 F 计数。 |
| 没有发送 | 公开记录无 Send、消息节点保持；源码输入路径只给原 file input 赋值并 dispatch change，不操作 Send、正文或选区，不通过 editor.focus() 实现输入。 |
| 持久观察 | unknown/input/start/attached 首次 journal 槽属同一个 operation/attempt，input/start/attached 的 attachmentID 相同，来源保留 integratedDevelopment。attached exact identity/original draft=true、uploading/error=false。 |
| 数据保留 | schema 3、quick_check=ok、补偿 0→0；assets 5→6、operations 3→4，仅 F 新增。旧 asset 行和 10 条旧 checkpoint 保持。A/D 只读恢复曾更新观察时间/receipt，D reason 也变，不能说整行完全不变。旧身份、attempt、UNKNOWN、target/hash 保持。 |
| F 的最终本地状态 | F 仍 `unknown/visible`，reason=`observer-v2:attached:integratedDevelopment`，upload_starts=0；当时开始/完成/失败准入均关闭。该历史行必须继续保持未授权。 |

## 完成判据的源码审查

实际 source485 的 bundled JS SHA 为 `c0afbd8a652c7a0e8fe6875ddbbd54f075e9c60bcda512eeb4df610e72f8948b`。本轮从 git blob 重新计算，并与公开 runtime 记录及当前工作树一致。证据493相对于其父提交只增加/更新文档及证据，没有生产源码变化。

`chatgpt-web-20261027.js` 的 `beginProof` 要求 fileHashVerified、最终 loaded、ended、原 operation/card/image membership、停止上传、image.complete。优先接受完整 preview 编码字节与原文件 SHA 和长度精确相等；否则独立解码原文件并与原 image 在显式 sRGB canvas 下比较**完整尺寸和全部 RGBA 的 SHA**。不存在近似像素、颜色误差阈值、只看缩略图或只看文件名的替代通过条件。异步 proof 完成后再次确认同一 card/image/source/load sequence、未重新上传、无 associatedError；任何不一致将 markBad。

attached 输出另外要求 `sameIdentity(proof.identity, identity)`、proof.completed > loaded > hundred、已 started/ended、file hash verified、inputCount==1、原 membership、proof 原 card/image/source/load sequence、未 uploading、image.complete。因此只看到 positive progress、100%、卡片出现或 image.complete 都不等于 attached。

`ObservationNormalizer` 先校验 schema、原 operation/asset/attempt/hash/full target 与 profile adapter/surface，禁止 synthetic evidence 授权真实来源。候选 integratedDevelopment 只在明确候选 scope 和精确 candidate profile 下解释；来源标签不改为真实。attached→verifiedReady 要求 exactImageIdentity、belongsToOriginalDraft、有 attachmentID、非 absent、无 error、非 uploading，且 profile.completionSignal=.attached。`ReceiptPolicy` 对 completion、uploadStart 和 safe retry 分别控制；本次不得给 candidate 配 failureSignal 或 retry map。

**已确认旧代码的范围风险，须由实现解决：** `.webChat` 本身同时包含 Home 和 ordinary thread；旧 PNG preflight 只验证 PNG IHDR/尺寸，不检查 bitDepth/colorType；normalizer reconcile 默认使用当前 profile，允许表若复用旧 ID 会使历史 F 的 attached 被重新授权。这些不是上传 mechanism 的失败，不应重写 JS 状态机；应在原有候选配置/资格与格式边界收窄。

## 必须落实的受限范围

1. 仅显式 `--system-screenshot-candidate` 路径。普通 production mode 继续 unavailable/closed；不能通过 synthetic 测试 profile 借权。
2. 对未来操作使用新的独立 uploadStart/completion profile 或等价的明确、持久且不可追溯的操作准入版本。在派发之前记录与原 asset/operation/attempt/target/hash 相绑定的新操作资格；恢复进程不能把无此资格的旧操作补登记。历史 F、A/D 和其他 UNKNOWN 不重传、不清除、不解锁、不转 succeeded。
3. 仅当前已验证的 Chrome、ChatGPT 中文普通已有 thread。保守实施可要求 `chatgpt-composer-react-persisted-20261027-v1` 与 bare UUID logical draft；不要顺带开放 Home 或 `local-chatgpt:` 新草稿。公开材料删除了 F 的实际 logical ID，所以上述 persisted-only 是收窄实现建议，不是本轮声称亲眼读取私有 ID。v13 仍须维持同一 committed React root、非 Home/Work/temporary/readOnly、thread placement、原路由和原文档/编辑器/input 的连续检查。
4. 仅真实系统来源、原始未转换 PNG、8-bit RGBA（IHDR bitDepth 8 / colorType 6），保留原 8 MiB、16,777,216 像素及单帧/完整文件校验约束。不得顺带开放 JPEG、HEIF、HDR、高位深、调色板或其他 PNG 像素格式；不改用近似 sRGB 比较。
5. 严格使用当前有效 ACK 的原点击和唯一输入。原正文/选区/旧附件保留；没有 autoSend。原目标不可证明或失效时 fail closed，不能切换到当前新目标并重输。
6. completion 仍由最终 attached proof 单独授权；可先持久真实 start 触发现有快速吞噬，再由 background observation 写 succeeded。缺少 start 时不能伪造 start 来展示效果；缺少 completion 时不能由已吞噬推断成功。
7. safe failure、safe retry、MID、物理鼠标、无 ACK 冷首击、v7/v8 monitor 借用、多屏及普通生产不因本次 evidence 变为 PASS。旧监视器兼容和权限恢复应按现有回归保持，不能为本次准入删除它们。

## 必要后续验证与停止边界

最终实现非作者审查应检查：新操作资格持久且原身份绑定；旧 F/UNKNOWN 经过 reconcile/restart 仍无准入；Home/Work/temp/local draft/非 RGBA8 被拒；strict attached 与 uploadStarted 可分别关闭；普通模式与 retry maps 保持空；不改动上传 JS/原吞噬状态机；反馈分支不混入。

CI 应由负责集成的主代理针对最终 SHA 执行完整 macOS 工作流。证据包的 40656871851 是485已有 completed/success；本轮未重跑，不能标为新候选 App 的 CI。本报告不声称新 macOS CI 或新构建通过。

真实 Mac 后续仅需使用**另一张全新的真实系统 PNG**在受限普通 thread 场景中一次点击验证：唯一输入→原 positive start→现有快速吞噬→严格 attached→后台持久 succeeded，同时原正文/选区/旧附件保持。F 和其他 UNKNOWN 不作复测输入。即使最终快吞噬体验通过，也不开放安全失败/重试、普通生产、main 合并或公开发行。

## 最终审查结论

公开证据内部一致，生产源码完成机制与该证据匹配，上一位私有证据非作者审查为 PASS with explicit scope limits；**没有发现阻止受限 completion 准入的证据矛盾或必须重写上传机制的问题**。上述新操作、ordinary thread 和 RGBA8 范围控制是准入实现的必要条件，须在最终代码审查与 CI 中落实。除此之外不需要重传 F 来重复已完成的 SC-COMPLETE 验收。
