# Riftlet — 受限准入完整 macOS CI 非作者结果审查

日期：2026-10-28
审查角色：`admission_completion_review`，未编写被审源码/测试。
结论：**PASS。新源码完整 macOS CI 的实际日志支持受限候选工程交付；新真实截图快吞噬体验仍为 NOT_RUN。**

## 1. 准确源码与运行绑定

| 项目 | 核验结果 |
| --- | --- |
| 本次成功 push CI | `40673128250` |
| macos job | `122764686050` |
| 新测试/构建源码 | `34caed4a5c5b7264c1699b62ea1438e1ce5646ca` |
| Git tree | `d1b5c73c4d3c7eda94c7675a18f87b1ee08bafcf` |
| 前一组合提交 | `375f52d84007ea6644ddcc0380fa52a3591c74ab` |
| runner | macOS 14.8.9 (23J631)，arm64，Apple Swift 5.10 |
| 完整日志 | `engineering/evidence/2026-10-28-sc-restricted-admission/ci-40673128250-success.log` |
| 日志字节数 / 行数 | 258,764 bytes / 2,597 lines |
| 日志 SHA-256 | `4388ddd293cbce26d7ef8dc0ac561ae46d918779c117a5906fb27232e2c5fdc2` |

[新 push CI](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40673128250) 的 API 状态由集成负责人核验为 completed/success，完成时间10:36:20Z。本角色独立读取保存的完整实际日志：fetch 指定34caed4，checkout后的 `git log -1 --format=%H` 实际输出该完整SHA；不是仅依据artifact名称或分支名推定。源码文件的12项Git blob指纹已在实现审查附录逐项绑定该SHA；其中新测试fixture采用修正后SHA `576633b2a6ac096eca2ad122caff7cd2a12574d4fd69cabb818ef5a1e84631a8`。

同源 PR CI `40673134992` 也由集成负责人核验success。本报告的独立详细计数与结论只依据上述push完整日志，不把两个CI重复累加。旧485源码CI `40656871851` 没有被用来替代本次新构建。

## 2. 原生全量与详细复跑：避免重复计数

本角色程序化核验日志中 native progress：

- 恰有457个 `Testing` 条目。
- 编号完整覆盖1至457，没有缺号；457个测试名称均唯一。
- `swift test --parallel` 步骤完成并继续后续构建/打包，日志没有error/failure输出。
- 并行条目本身不区分pass与XCTSkip，因此进一步核对关键17组详细复跑。
- 详细复跑恰有120个唯一 `Test Case ... passed`，17组，**0失败、0跳过**；120个测试全部已属于前述457个集合。
- 日志的suite/bundle/selected三层汇总是同一次结果的重复打印，不能各加一次。**不能写成577项独立原生测试，也不能把13项新回归再次加到457之外。**

| 详细测试组 | 明确 passed 数 |
| --- | ---: |
| RiftLifecycleTests | 13 |
| RiftInputIslandTests | 3 |
| DeferredChromeActivityBindingTests | 3 |
| RiftSetupControllerTests | 3 |
| ReleaseCaptureTests | 15 |
| PresentationBoundaryTests | 4 |
| WebAcceptanceIntegrationTests | 5 |
| PassivePermissionResumeTests | 8 |
| ChromeActiveTabDescriptorTests | 5 |
| AcceptedSelectionQueueTests | 18 |
| SelectionAuthorityTests | 4 |
| SelectionSubmissionQueueTests | 3 |
| SystemScreenshotWebCandidateTests | 7 |
| SystemScreenshotCandidateAdmissionTests | 13 |
| SystemScreenshotObservationJournalTests | 8 |
| SystemScreenshotCandidateIntegrationTests | 6 |
| SystemScreenshotFidelityTests | 2 |
| **17组详细复跑合计（457的子集）** | **120** |

全量日志亦包含 SQLite v1/v2→v3迁移、迁移失败rollback、UNKNOWN原锁、成功后不重复视觉退出、错误原身份不能吞噬等既有回归。权限/原点击保护的详细组明确运行：PassivePermissionResume8、AcceptedSelectionQueue18、SelectionAuthority4、SelectionSubmissionQueue3；没有把权限恢复等价于恢复旧ACK授权。

## 3. 新增13项准入回归全部实际通过

已将最终源码的13个测试方法集合与详细日志中的通过集合逐一比对，精确相等，不是只看到suite名称或总数。

特别核验的关键测试：

| 测试 | 实际结论 |
| --- | --- |
| `testNewAppendStartsOnceAndRestartedCompletionNeedsItsSeparateAdmission` | PASS：唯一输入；start先吞噬但非used；重启只读；start-only拒绝成功，独立completion获准后才succeeded；不重复visibilityRevision，保留原marker/start |
| `testCompletionOnlyPolicyCannotAdmitStartAndProductionDefaultsRemainClosed` | PASS：仅completion不能写upload_starts，普通默认和retry保持关闭 |
| `testLegacyUnknownStartAndAttachedNeverAcquireAdmissionOrReleaseOriginalLock` | PASS：旧无登记UNKNOWN收start/attached仍锁定、可见、无输入、无升级 |
| `testLegacyReconcileDoesNotApplyNewInputTargetOrPNGScope` | PASS：旧格式/旧target仍可只读观察；不会借新profile获权 |
| `testPreparedAndStaleDispatchSnapshotsCannotEnrollActualUnknown` | PASS：prepared、伪dispatch与已成为UNKNOWN的快照不登记 |
| `testEnrollmentChecksPersistentAssetAttemptEntireTargetAndStore` | PASS：全原身份和持久数据库均核对；修复的入参assetID自洽case已通过 |
| `testConcurrentAdmissionInstancesClaimOnceAndCannotReplayAppend` | PASS：并发只登记一次，不能重复append |
| `testMissingCorruptAndForeignMarkersNeverAuthorizeInputOrGetReplaced` | PASS：坏marker不授予、不重写、不输入 |
| `testExtendedNoncanonicalAndDuplicateKeyMarkersFailClosedOnReadOnlyObservation` | PASS：扩展字段、非规范文本、重复key拒绝并保留原记录 |
| `testUnsupportedHomeLocalUnknownDraftWorkAndNonChromeTargetsRefuseBeforeInput` | PASS：Home/local/unrecognized/Work/其他浏览器等新输入拒绝 |
| `testUnsupportedPNGDepthColorAndCorruptFileRefuseBeforeEnrollmentOrInput` | PASS：RGB8、RGBA16、gray8、Adam7与坏SHA拒绝，不能登记 |
| `testPassingAdmittedProfileDirectlyCannotBypassPerOperationAdmission` | PASS：直接构造v2 profile不能绕过资格 |
| `testAdapterWithoutExplicitAdmissionRetainsObservationOnlyProfiles` | PASS：无登记actor继续v1观察，无隐式准入 |

App六项详细集成测试也全部通过，包含 `testPackagedCandidateCheckStartsThenCompletesAndPreservesLegacyUnknown` 与 `testRestrictedStartAndCompletionAreIndependentAndFailureRemainsClosed`。这些是构造桥与生成fixture的软件验证；它们验证正式App composition与Core链，却不构成真实Chrome上传。

## 4. Web、旧版本与辅助回归

下列实际TAP结果全部fail=0，合计193项；它们属于Web/脚本离线回归，与457项Swift测试分开列示。

| 离线组 | 实际数量 |
| --- | ---: |
| 已归档Web证据replay | 19 |
| 当前集成页面程序synthetic DOM | 86 |
| 旧版本只读观察 | 61 |
| 第五轮page-evidence helper | 9 |
| 第五轮progress diagnostic probe | 4 |
| 第五轮versioned probe | 2 |
| 系统截图第二阶段诊断fixture | 12 |
| **TAP合计** | **193** |

日志明确通过“PNG重新编码仍须精确sRGB RGBA，一张不同preview不得通过”与“v9 UNKNOWN保留原lease、v13借用不重输”等检查。另有第二轮fault harness的8组PASS以及第三轮read-only network-probe的12组PASS；后者输出仍明确真实MID interception/abort NOT_RUN。这些脚本运行均为离线fixture，不能把MID或safe retry变成准入。

Packaging Python rejection suite：12 tests，`OK`。包含缺失/重复/陈旧资源、非Mach-O/非可执行文件、错误发布metadata、许可证、symlink与布局拒绝路径。

## 5. Release构建、打包与可执行自检

日志实际完成release构建，`RIFTLET_BUNDLE_CHECK_PASS` 后由原build script执行开发ad-hoc签名与 `codesign --verify --strict`；脚本 `set -euo pipefail`，最终输出Created build/Riftlet.app。没有把开发签名称作notarization或Gatekeeper通过。

以下五个**实际可执行输出**均出现PASS：

1. `RIFTLET_SELF_CHECK_PASS`：private import、durable upload-start visibility、delayed synthetic completion、restart。
2. `RIFTLET_WEB_ACCEPTANCE_SELF_CHECK_PASS`：bundled page source、synthetic-only policy、隔离mode；仍 `CHROME_NOT_RUN; GUI_NOT_RUN`。
3. `RIFTLET_FIRST_USE_SELF_CHECK_PASS`：presentation persistence、disabled-production permission isolation；仍 `PERMISSIONS_NOT_REQUESTED; GUI_NOT_RUN`。
4. `RIFTLET_SYSTEM_SCREENSHOT_CANDIDATE_SELF_CHECK_PASS`：original-byte import、one software input、restricted start then independent completion、durable new-operation registration、legacy UNKNOWN unchanged、read-only restart；仍 `GENERATED_FIXTURE; CHROME_NOT_RUN; SYSTEM_SCREENSHOT_NOT_RUN; GUI_NOT_RUN`。
5. `RIFTLET_GUI_HELPER_SELF_CHECK_PASS`：12 synthetic PNGs、2/3/12布局状态fixture；仍 `GUI_NOT_RUN`。

候选自检确实运行的是打包后临时拷贝App中的可执行文件。界面动画和状态链的软件回归通过不等价于真人物理点击、系统截图或真实Chrome输入通过。

归档日志显示35个文件成功上传，包含App development ZIP、GUI helper ZIP和test-results：

- artifact名称：`native-foundation-34caed4a5c5b7264c1699b62ea1438e1ce5646ca`。
- artifact ID：`12809587008`。
- 外层GitHub artifact ZIP：1,972,728 bytes。
- 日志报告外层artifact ZIP SHA-256：`7c4165ec311fc0ea19d0507c4980ad08e2b4ad05839de3211d5151593d6565c8`。
- [artifact入口](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40673128250/artifacts/12809587008)。

本角色没有下载并解压该artifact；上述是成功上传日志事实，外层ZIP摘要不能冒称内部Riftlet App ZIP或可执行文件摘要。交付负责人可进一步下载核验候选App及资源，单独记录其准确hash。

## 6. 首次失败及修复被保留

上一新PR CI `40672786893` 的4项新增测试失败由fixture evidenceID违反既有36字符UUID契约导致。其FAIL日志保留。修复只把构造bridge字符串改为有效UUID，原严格validator与生产source不变。修复后的本次完整新CI从实际34caed4重新编译、运行全量、详细回归、打包及自检均通过；没有用skip、删测试、放宽比较或旧CI替代失败。

## 7. 可以交付和仍不可宣称的结论

可以准确交付：**已独立审查的受限候选源码34caed4，完整新macOS CI40673128250通过，13项新准入回归及正式composition的软件完整状态链通过，新的开发候选App已构建归档。**

继续分别记录：

- 原F的SC-INPUT/SC-START/SC-COMPLETE仍是source485上的限定真实证据；其历史DB仍UNKNOWN，不追溯授权。
- 新候选App在**另一张全新真实系统PNG**上的“一次点击→真实开始→快速吞噬→最终succeeded”体验尚未运行，**NOT_RUN**。执行者仅做这一次新图验证，不重输F、D或其他旧UNKNOWN。
- 普通生产、安全失败、安全重试继续关闭；无ACK冷首击、物理鼠标、MID、其他格式/浏览器/界面不由本次CI升级。
- 若后续正式HEAD仅增加文档和交接，必须列明其准确SHA与所继承的34caed4测试/构建输入完全一致；不要把40673128250重新标成该文档commit新触发的CI。
- PR #1继续Draft，不合main，不公开发行，不将反馈系统进行中代码混入此结果。

本角色不再要求重复完整CI或重复上传已验F。没有发现阻止当前受限工程候选交付的未解决测试/日志矛盾。
