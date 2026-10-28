# Riftlet — 受限准入实际实现非作者审查

日期：2026-10-28
审查角色：`admission_completion_review`。该角色没有编写任何被审源码或测试，仅写本审查记录并向作者报告发现。
工作树：`/workspace/scratch/16d4559e9aa8/Riftlet-sc-admission`
基线：正式 `871d825a43a759bb6dd8ded9cdc99a340d8e0e64`，组合证据 `493d1d8b898d18e34709463d2dceca8c85ad4014`。
对应完成证据审查：`/tmp/riftlet-admission-completion-review.md`。

## 结论

**实际实现及回归源码非作者审查 PASS；当前没有未解决的 completion / App 自检 / 状态链阻塞。**

该结论适用于本文列出的最终文件指纹。集成负责人仍须在最终提交上完成完整 macOS CI、打包和可执行自检；本环境没有执行 Swift/macOS 程序，不能把静态审查称为测试运行通过。新候选 App 的真实“一次点击→原开始→快速吞噬→最终成功”仍由本地 Codex 使用另一张全新系统截图验证。F 的旧事实和所有历史 UNKNOWN 均不回填。

## 审查内容

### 1. 新操作资格与历史隔离

- App 仍以 observation-only v1 profile 构造 Web adapter，`requireEnabled` 拒绝把 v2 profile 直接传给构造器进行绕过。
- `SystemScreenshotCandidateAdmission.enroll` 只在 append 的本地格式和完整 SHA 检查成功后、首个 begin 之前调用。reconcile、normalization、恢复和 journal 不登记资格。
- `QueueStore.claimDispatchCheckpoint` 在同一 SQLite 事务中核对 production store、实际 `dispatchIntent`、完整持久 `TransferOperation`、完整 immutable asset 和 active operation，然后 INSERT OR IGNORE。它不改队列状态、visibility、receipt、成功或重试权限，不改变 schema 3。
- 随机 enrollment UUID 与保留字节比较保证两个并发候选实例至多一个登记成功。已有登记也不能授权第二次 append；已登记操作重启后只能沿原 observe 路径续查。
- `admits` 要求版本、v13 sourceID、新 start/completion profile、完整原 identity、入参 operation/asset 自洽、允许阶段、production store、实际 immutable asset/active operation/attempt/target 全部一致；非规范 JSON、扩展字段、重复 key、损坏或外国 marker 均不能被静默修补。
- 缺失 marker 返回 v1；旧 F/UNKNOWN 即使收到完全合法的 start 或 attached，也不能命中新 v2 map。原 operation/attempt/target、原锁和 journal 均保留。

### 2. completion 与 start 确实独立

`SystemScreenshotCandidateConfiguration` 的 start map 只含新 v2 start profile；completion map 只含新 v2 attached profile；failure/retry map 为空。它们不来自 page JSON、arguments 或 preferences。正常 capture composition 仍是 `UnavailableAdapter` 和默认空 policy。

动态 normalizer 仅对登记已核验的原操作使用 v2，继续使用原 `ObservationNormalizer` 的身份、schema、来源及 clean-attachment 判据。没有凭 marker、input、开始、100% 或吞噬写成功的路径。failureSignal 仍 nil，provenance 仍 `integratedDevelopment`，不存在 synthetic→真实来源转换。

Core 原有顺序保持：真实 start 被 policy 接受后，首次 `upload_starts` 与 swallowed visibility 持久化；最终独立 verifiedReady 被 completion policy 接受后才变为 `succeeded/used`。后者不改已吞噬的 visibilityRevision，不再触发一次退出动画。若没有独立 completion 准入，attached 仍使后端保持 UNKNOWN，不能由 start 直接推出成功。

### 3. exact sRGB 和既有上传机制保持

再次从实际 `48574df` git blob 计算 bundled JS SHA，并与当前工作树核对：

`c0afbd8a652c7a0e8fe6875ddbbd54f075e9c60bcda512eeb4df610e72f8948b`

两者完全相同。该 JS 仍要求原 operation/card/image/source/final-load 的完整严格 proof，精确文件 SHA 或相同尺寸且全部普通 sRGB RGBA SHA 完全相等；未引入像素容差，也没有更换 begin/chunk/commit、状态机或动画。v9/v10/v12 root-monitor 兼容和历史只读观察未改。

`TransferCoordinator`、`ReceiptPolicy` 的状态/授权实现以及原吞噬控制器均未变；唯一 Core 增量是上述事务登记 helper。`RiftletMain.swift` 的改动仅为三处候选说明/软件自检日志文字，没有触碰权限恢复、原事件 ACK 或反馈接线。

### 4. 输入范围与实际字节绑定

新输入的 capture/validate/append 均要求 `com.google.Chrome`、`webChat`、已识别的 persisted ordinary-thread logical UUID；Home/no logical ID、local/new draft、Work 和其他 Chrome/浏览器 profile 不在新准入范围。原 v13 继续检查中文 composer、committed React root、非 Home/Work/temp/readOnly、原路由和原节点。旧 reconcile 没有错误地套用新输入限制，仍可只读观察其原 Home/local/旧 PNG 身份。

RGBA8/type6/noninterlaced 检查既用于早期 preflight，又从**实际全 SHA 校验及上传的同一个 no-follow fd 的前 33 字节**再次校验，随后才能登记。这消除了“预检文件是合格格式，实际打开上传文件是另一表示”的范围不绑定问题；仍使用原两遍 SHA、逐块 ACK 和唯一 commit。noninterlaced 是本轮保守缩小的新策略，注释没有再称其为公开 F 证据已直接记录的事实。

原 8 MiB / 16,777,216 像素、完整原文件、真实系统 origin、独立候选 mode 等限制保留。未转换其他 PNG 表示，没有增加 JPEG/HEIF/HDR/高位深输入。

### 5. App 可执行自检与用户说明

App 自检共用正式 `ApplicationAttachmentComposition`，以明确标记的 generated fixture 和构造 bridge 验证：一次软件 begin/commit、start 先持久吞噬且尚未 succeeded、重启后 UNKNOWN 仍隐藏、只读 attached 再变 succeeded、visibilityRevision 不变、原登记/首 start 保持，另一个 F-like 无登记历史 UNKNOWN 继续 visible/locked 且不能获成功。

自检独立旧样本使用唯一 basename 和真实 private copy，不再违反 `assets.file_name UNIQUE`。RGBA8 generated fixture 明确保留 alpha，并断言真实生成 IHDR。旧文本已更新为受限新候选行为；日志仍明确 `GENERATED_FIXTURE; CHROME_NOT_RUN; SYSTEM_SCREENSHOT_NOT_RUN; GUI_NOT_RUN`。这些标签不得在最后交接中删去或改称真实 Mac 快吞噬 PASS。

## 发现与闭环

| 发现 | 作者修复 | 复审结果 |
| --- | --- | --- |
| 新自检 oldImage 复用已有 fileName，违反 SQLite UNIQUE，必导致自检失败 | 独立 UUID basename，复制原 fixture 字节为独立 private copy | 已复审，关闭 |
| 新格式准入仅依赖独立 preflight fd，未绑定实际 hash/上传字节 | 全 SHA 扫描同一 fd 保留首 33 bytes，成功后再次验证 header，再 enroll；不增加独立读取/传输路径 | 已复审，关闭 |
| `admits` 未核对入参 request.operation.assetID 与 request.asset.id；特制不自洽 request 可过资格 helper（后续 normalizer 仍拒绝） | 补入参 assetID 自洽与允许阶段，保留实际持久身份核对 | 已复审，关闭 |
| 安全 reviewer 指出的 marker JSON 额外字段/非规范编码及 noninterlace 注释范围 | canonical sorted JSON roundtrip 严格等值；改为“保守仅接受 noninterlaced” | 本角色复审实际最终实现和新增回归，关闭 |

## 回归源码覆盖评估

新增 `SystemScreenshotCandidateAdmissionTests.swift` 已由作者冻结，本角色逐项只读审查，共 13 个测试：

1. 新 append 只发生一次 begin/chunk/commit；重复 append 在应用 receipt 前也拒绝；start 先吞噬但不是 used；重启只读 completed，start-only policy 拒绝成功，独立完成 map 后才 succeeded，原 start/marker 与 visibilityRevision 保持。
2. completion-only policy 不允许 start、不产生 upload_starts；默认 production 空 policy 和 retry 闭锁。
3. 无显式 admission actor 的 adapter 继续 v1 observation-only。
4. 无 marker 的旧 UNKNOWN 收到 start/attached 仍 UNKNOWN/visible、原 attempt/锁保持，不允许 append。
5. 新 target/PNG 限制不阻止旧原身份 read-only reconcile，也不给其新 profile。
6. prepared、伪装 dispatch 与真实阶段已经 UNKNOWN 的旧快照不能登记。
7. 持久 asset、attempt、完整 target、不同 store、同 key 身份改变不能登记或获准。
8. 缺失/损坏/外国 marker 不授权、不替换、不输入。
9. 两个 admission actor 并发只登记一次，登记后不得再次 append。
10. 额外字段、前导空白、重复 key 的 marker 在 admits/reconcile/append 都 fail closed，观察不会修复或覆盖。
11. Home、local、新未知 profile、无效 UUID、Work、Safari/Canary 等新输入在 begin 前拒绝。
12. RGB8、RGBA16、gray8、有效 Adam7 RGBA8 及 SHA 损坏都在登记/输入前拒绝。
13. 直接传入 admittedProfile 不能绕过 per-operation 资格。

此外现有 App 集成测试继续断言 ordinary mode/混合库隔离和 v1 无准入，新增加 v2 start/completion 独立及 failure 关闭，调用完整 packaged selfcheck。现有 Core/UI 测试已覆盖开始先于成功、最终成功不重复视觉退出、原 receipt identity 错误不能吞噬、旧数据迁移及 UNKNOWN。工作流新增专门的 admission 详细日志，保留原全量 Swift 测试、Web 页面回归、旧版本、迁移/权限/点击保护、打包和可执行自检。

本角色未重新运行测试作者对 PNG fixture 的 CRC/zlib/Pillow 校验，也未运行 macOS Swift 测试；这些执行结果应分别归属测试作者和最终 CI。

## 实际只读检查

- 公开 F 证据的 14 项一致性检查已记录在前一份 evidence review。
- 修改前后 bundled JS 的 SHA 与 source485 精确相等。
- `git diff --check` 最终返回 0；merge 文档冲突标记已被作者清除。
- 确认既有 transfer/receipt policy/动画状态机没有改动。
- 完整读取最终源增量、新增 13 项测试、App 集成测试、自检和工作流新增日志步骤。

## 最终审查文件指纹

以下 SHA-256 可由集成负责人对最终提交逐文件复核；若仅文档/交接随后变化，不影响此源码审查。任何源码/测试变更须检查相应增量。

| 路径 | SHA-256 |
| --- | --- |
| `Sources/RiftletAdapters/SystemScreenshotCandidateAdmission.swift` | `32327ee95cc51aa467ea8bfcb4a6269679946f3b9ca2b41cd41e6cb7573b282c` |
| `Sources/RiftletAdapters/SystemScreenshotWebCandidate.swift` | `93f69480ff0d8d9c8e6755336e69999750d6e2046699f558b96a0c2b340c73ae` |
| `Sources/RiftletAdapters/WebAttachmentAdapter.swift` | `a3209235123335be26903d1286b8822554487c8e98bac50c82970827a42569ad` |
| `Sources/RiftletApp/SystemScreenshotCandidateConfiguration.swift` | `21f689146ac99838a7aacbd485000926518bfadf10909be48db3b8b0b11b0858` |
| `Sources/RiftletApp/SystemScreenshotCandidateSelfCheck.swift` | `e9db6da908ebe79455e6239ccedf6564edf60c700201fe362ad697b1874dbb1e` |
| `Sources/RiftletApp/RiftletMain.swift` | `a4a67f2c8f1f713bc117140430e35ed1b45ee79c7821c67fff138d577b5ea531` |
| `Sources/RiftletCore/QueueStore.swift` | `d42e0437572fe5670eb769576e26d09ede74802f7aed699755d2262345f54e85` |
| `Sources/RiftletUI/SetupPresentation.swift` | `7654fd5a7ca16e26287aaa67ad8418cb0d2e161e267e8a5afc229803bf8f93dc` |
| `Tests/RiftletAdaptersTests/SystemScreenshotCandidateAdmissionTests.swift` | `35a5a6194ca1b5899b5c9f2f5eb097a11d238798be927975fa86032302c3da05` |
| `Tests/RiftletAppTests/SystemScreenshotCandidateIntegrationTests.swift` | `d31ca406fa41d77ce656bd01dafe461fea089ac205a930d9888230bbb651aa53` |
| `.github/workflows/native-foundation.yml` | `fa6f799804cdd30ff44ad788364d3fdd5a45ce9cf2823e950db2dcb7445a842b` |
| `Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js` | `c0afbd8a652c7a0e8fe6875ddbbd54f075e9c60bcda512eeb4df610e72f8948b` |

## 继续保持的边界

PR #1 Draft；不合 main、不公开发行、不引入反馈分支进行中代码。普通生产、安全失败、安全重试关闭；F 和全部旧 UNKNOWN 不重传、不清除、不解锁。下一次实际体验只使用另一张新的真实系统 PNG；未经真实开始不得伪造 uploadStarted，未经严格最终 proof 不记 succeeded。真实 Mac 体验复测尚未运行，不能从本报告或 CI 推导为 PASS。

## 准确发布提交绑定 — 375f52d（2026-10-28）

本角色在发布后实际读取 `git show 375f52d84007ea6644ddcc0380fa52a3591c74ab:<path>` 的12个Git blob并逐一重算SHA-256，全部与上表审查指纹、当前工作树文件完全一致。另实际核验：

- commit：`375f52d84007ea6644ddcc0380fa52a3591c74ab`。
- tree：`ad081286e07e12c43cb0b7b750c45032078a8734`。
- 按顺序的parents：`871d825a43a759bb6dd8ded9cdc99a340d8e0e64`、`493d1d8b898d18e34709463d2dceca8c85ad4014`。
- 本地 HEAD 精确等于该commit；工作树 clean。
- 因而本报告实际实现非作者 PASS 准确绑定到该源码提交及tree，不是只凭分支名推定。

新的 macOS CI push run `40672755431` / job `122763418622` 与 PR run `40672786893` 的运行结果在本次绑定时尚未由本角色审查；不得以旧40656871851代替。等待集成负责人提供新run实际日志后独立核验13项新增回归、全量测试和packaged selfchecks。

## 新 CI 失败记录与唯一 fixture 修复审查 — 2026-10-28

已实际读取新 PR CI run `40672786893` / job `122763525170` 的完整保存日志 `engineering/evidence/2026-10-28-sc-restricted-admission/ci-40672786893-failed.log`，日志 SHA-256：`2e6aa20dd8c7777f29f2b0cac2e9b2891ff725630353cbf3d54e1cc4721d42d3`。该运行编译完成；全量 native 执行显示457个测试条目，其中4个新增 admission 测试报告 `invalidField("upload start")`，作业 exit 1，**本次新 CI 为 FAIL，不是通过**。后续打包/可执行自检不能由这个失败运行声称通过。

四个失败都在构造 bridge 返回 uploadStarted 时发生。原严格 `ObservationDecoder` 要求 start.evidenceID 为36字符且可解为UUID；fixture误填 `constructed-admission-start`，所以未到所测策略/生命周期断言就被正确拒绝。已逐字对比375提交与当前测试文件：唯一源码差异是将该fixture字符串替换为 `00000000-0000-4000-8000-000000000003`。新值为有效36字符UUID，原validator、生产Sources、App、工作流及其余测试字节均保持。

**该一行测试fixture修复的非作者审查 PASS。** 未放宽观察校验或任何生产准入。此处也明确修正初审遗漏：上一轮静态审查未发现这个fixture evidenceID违反既有UUID契约；实际CI发现后按原契约修正fixture。

当前有效测试文件指纹（替代上方原375指纹表中这一行；原375绑定仍保留为历史事实）：

- 路径：`Tests/RiftletAdaptersTests/SystemScreenshotCandidateAdmissionTests.swift`。
- 375原SHA-256：`35a5a6194ca1b5899b5c9f2f5eb097a11d238798be927975fa86032302c3da05`。
- 一行修复后SHA-256：`576633b2a6ac096eca2ad122caff7cd2a12574d4fd69cabb818ef5a1e84631a8`。
- 其余11个审查文件的工作树SHA仍与原表一致。

新的完整 macOS CI 尚待下一次运行；本修复审查不等于复测通过，不使用旧485 CI代签。最终后继准确commit/tree与完整成功日志仍须另外绑定。

## fixture 修复发布提交绑定 — 34caed4（2026-10-28）

发布后实际读取 `git show 34caed4a5c5b7264c1699b62ea1438e1ce5646ca:<path>` 再次逐项核验12个审查文件：11个保留原指纹，新增测试文件使用上一附录的一行修复指纹，全部与Git blob及工作树一致。

- 准确commit：`34caed4a5c5b7264c1699b62ea1438e1ce5646ca`。
- tree：`d1b5c73c4d3c7eda94c7675a18f87b1ee08bafcf`。
- 唯一parent：`375f52d84007ea6644ddcc0380fa52a3591c74ab`。
- 本地 HEAD 精确相同；已跟踪文件无差异。核验时仅存在本轮待归档的未跟踪日志/审查文件，不涉及源码修改。
- 本报告实际实现PASS及一行fixture修复PASS共同准确绑定该commit。

直接sourceSHA的新push CI `40673128250` / job `122764686050` 和PR CI `40673134992` 此时尚待实际完整结果日志；不提前声明复测通过。

## 新完整 macOS CI 结果绑定 — 40673128250

本角色已独立审查实际push完整日志，checkout精确为 `34caed4a5c5b7264c1699b62ea1438e1ce5646ca`。结果审查PASS；完整记录在 `/tmp/riftlet-admission-ci-completion-review.md`。457个原生全量条目、17组120个详细passed（457子集，不重复加算）、新增13项精确测试集合、193项TAP离线回归、12项packaging Python tests、release构建及5个实际可执行自检均核对，详细组0失败/0跳过。

成功日志SHA-256：`4388ddd293cbce26d7ef8dc0ac561ae46d918779c117a5906fb27232e2c5fdc2`；run `40673128250`，job `122764686050`。上一fixture FAIL及一行修复历史保留。当前代码工程验证通过，不改变新的真实系统截图快吞噬体验 `NOT_RUN` 的边界。
