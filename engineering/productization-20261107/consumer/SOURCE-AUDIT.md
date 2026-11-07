# 消费者文案源码审计

审计人角色：消费者资料作者；本文件是作者事实核对，**不是本 lane 独立审查**。运行时审计基于 main `2e779f646ac4874344fac94f79103e8ddf9b02c8`；发行工具继承下述已审后继，其余 33 项源绑定未变。当前源文件 SHA-256 见 [source-bindings.json](source-bindings.json)，原绑定逐字保留为同目录 `source-bindings-01.json`。当前包的后续真实验收与发行结论由集成负责人记录。

| 消费者结论 | 当前实现依据（仓库相对路径） | 必须保留的边界 |
| --- | --- | --- |
| 普通启动支持系统与内置截图、Chrome ChatGPT | `Sources/RiftletApp/OrdinaryCaptureConfiguration.swift` 的 unifiedProduct、supportText；`ApplicationMode.swift` 的 capture | source-qualified implementation 不是当前页面全场景认证；旧“普通上传关闭”文档不适用 |
| 点击当前窗口/标签/草稿，不要求编辑器键盘焦点 | `Sources/RiftletApp/RiftletMain.swift` 的 frozenPress/selectionAuthority；`Sources/RiftletAdapters/Resources/chatgpt-web-20261027.js` 的 contextMatches/composer/binding | 不能改写为“任意前台窗口”或“从历史聊天自动挑选” |
| 只接受 ChatGPT 网页域名，不扩大其他服务 | 页面 `route()` 只允许 HTTPS chatgpt.com / chat.openai.com | 不按域名承诺所有模式、账号和页面版本可用；无另一浏览器支持证据 |
| START 不是最终完成 | 页面 sample/observe；`WebAttachmentAdapter.swift` 首次 START 返回；`TransferCoordinator.swift` 删除 currentFileInputs | 详见 [START 审计](START-SEMANTICS-AUDIT.md)；不能把系统层完成 profile 存在当成普通路径会产生完成 |
| 未确认不自动重传，新的不同截图独立 | `TransferCoordinator.swift` 的 independent file input、original reconcile；`QueueStore.swift` markUnknown/canRestoreToQueue | 图片原件和历史可查，不等于 UNKNOWN 可一键重新附加 |
| 移出/归档不删除图片或远端附件 | `QueueStore.swift` removeVisible/setVisibility/archiveIdle/restoreToQueue | 只恢复具资格的 archived/removed pending/failed；并非通用重试按钮 |
| 历史“失败”不是所有异常 | `Sources/RiftletUI/HistoryPresentation.swift` isConfirmedFailure/needsVerification/filter；`RiftHistoryController.swift` stateText/updateDetail | 找不着取消或不确定记录应查“全部”或“待核实”；START 后仍可能显示“结果待核实 · 不会再次附加”，不代表持续跟踪最终状态 |
| 双样式共用同一记录 | `HistoryDisplayStyle.swift`、`RiftHistoryController.swift`、`Sources/RiftletApp/HistoryDisplayPreferences.swift` | current 默认、imageGrid 可选，只改变显示；不能写新图库/迁移/状态清空 |
| 文件收录只取系统新截图 | `Sources/RiftletCapture/CaptureService.swift` 首次 baseline；`PrivateAssetImporter.swift` 的来源标记与限额 | 仅把图片放入目录、改名或复制到剪贴板不等于系统新截图；不补导整个历史目录 |
| 文件目录权限与系统保存位置不同 | `CaptureSourceBinding.swift` readDirectory；`RiftletMain.swift` chooseSourceAccess/recheckSetup | 读实际识别路径，不更改系统保存位置；基线只读 location 键/默认 Desktop，不泛化所有系统版本 |
| 权限分项 | `AutomationPermission.swift` 的显式 request；`InteractiveScreenshotSystemCapture.swift` 的 CGPreflight/CGRequest；`ChromeActivityObserver.swift` 使用已有 AX 授权 | 不要求开启全部权限；AX 活动提示不作为首次附加资格；系统权限不代替 Chrome JavaScript 选项 |
| 三停止控制分开 | `RiftSettingsCenterPages.swift`、`ScreenshotEntryHost.swift`、`RiftletMain.swift` | pause/hide/entry 不混同；停止先有效、持久化失败需如实显示，恢复不能伪成功 |
| 登录启动事实回读 | `Sources/RiftletApp/LoginItemPreferences.swift` | requiresApproval ≠ enabled；notFound 不能归因为已成功；本轮修复后需重新绑定此行 |
| 本机存储和备份 | `StorageUsage.swift`、`scripts/storage-recovery.py`、`docs/STORAGE_RECOVERY.md` | 逻辑大小不等于 APFS 可释放量；App 数据目录不包含完整系统偏好/Keychain/TCC |
| 反馈有明确发送入口及后台续投 | `FeedbackHost.swift`、`Sources/RiftletFeedback/FeedbackEngine.swift`、`FeedbackTransport.swift` | 启动会 pump 已授权 outbox；不能说任何联网都要再点击或整个 App 完全离线 |
| 反馈诊断默认可选且有限 | `FeedbackModels.swift`、`FeedbackDiagnostics.swift`、`Sources/RiftletFeedbackUI/FeedbackWindowController.swift` | 新草稿无诊断；恢复草稿保留同意；自由文本不会自动脱敏；非“完全匿名” |
| 页面会临时读取文本以保护草稿 | 页面 selection snapshot、控件描述及路由校验 | 不声称“从不读取页面内容”；不把临时页面文本等同于持久化/反馈导出 |
| 当前不是签名公证公开包 | `scripts/release-tool.py`、`docs/RELEASE_ENGINEERING.md`，此前个人交付事实 | 有脚本/预检不代表 Developer ID/notary/Gatekeeper 成功；无下载或公开发行声明 |

## 发行工具继承审计（2026-11-07）

已逐项核对 `b9caabcb7fe02d9aae5521c3ada37fda9bd9143c` 与 `d46d47682d9ebe6df2928cebb69411ff8746604c`。后者的工具 SHA-256 为 `2b4cd25440750dc49d168d889f4697d4bbce903f8b73b8ba2df6710f720842da`，与集成工作树相同。下表是对真实实现的审计，不是仅因散列变化而更新绑定。

| 实际变化 | 源码与验证依据 | 消费者文案处理 |
| --- | --- | --- |
| 新构建显式传入版本、build 和显示标签；保留源值及最终值 | `stage_version`、`validate_receipt`、`build --label`；历史源缺标签记录 null，旧 schema-1 回执保持兼容 | 同版本或 Beta 标签不能证明是同一份包；核对交付清单，不修改旧个人 Beta 身份 |
| 新增私有评审 ZIP/DMG | `package_review` 只接受精确 pin 对应的 PREPARED；输出固定 REVIEW_ONLY / NOT_NOTARIZED / Gatekeeper NOT_RUN | 安装指南明确评审包不是已公证安装器，容器核验不证明数据兼容或首装成功 |
| ZIP 必须来自指定候选 | `verify_archive` 比对包内原始 manifest 字节的 SHA；评审与正式打包都传入各自可信候选 pin | 保留散列不能证明来源可信的提醒；另一份内部合法 ZIP 不得冒充当前候选 |
| 正式门禁及手动更新边界保持 | `package_candidate` 仍要求 STAPLED 及实际 Developer ID 校验；`docs/release/MANUAL_UPDATE_AND_RECOVERY.md` 保留双锁、完整备份、只换 App 和解锁后不自动二次交换 | 原恢复/更新/卸载指南仍准确；没有自动更新器、新安装许可或数据清理规则 |

本资料作者是上述发行源码的非作者审查者，已独立复现旧 ZIP 错绑、确认修复后拒绝，并执行 4 项定向检查通过；发行作者的 54 项、既有两组各 17 项日志及真实评审容器另有原始记录。私有正式审查 `release-final-independent.json` 的 SHA-256 为 `c2b5daf085c87665501254eead8bcf9c52835bb587f254bb7e4881bde2b25b7d`，结论为 `PASS_SCOPED_RELEASE_INCREMENT_REVIEW`。这不使本消费者文案成为独立审查结果；本次文案增量仍交另一非作者审核。

真实 ARM64 App 构建属于早先记录的工具 `10c2a2a0…` 和 source `b9caabc…`；最终工具只给同一份 PREPARED 内容重新生成并验证评审容器，没有重新构建、安装或运行 App。既有失败、阶段身份和范围保留于发行目录；本次不重跑这些已完成验收。原集成文案检查 89/90 的唯一失败及此次继承记录见同目录 `release-inheritance-audit.json`。

## 证据归属

- PR41 历史真实五图及冷双图只支持其原始源码/页面范围；[旧支持说明](../../../docs/SUPPORT.md)保留来源，不能据此声称当前 Beta 3 又实测了一轮。
- [历史双样式交付](../../history-dual-style-20261107/README.md)及 PR45 的正常/高对比度、CGEvent、同包重启数据证据用于历史 UI；不扩大成附件、完整辅助功能或干净安装认证。
- 此前个人 Beta 3 安装升级已获独立接受；本轮新用户扩大要求当前包附件复验。两者不互相撤销，不把旧接受升级为本轮所有项已通过。
- 本 lane 没有启动 GUI、读取生产数据库、调用 Keychain、发起新反馈、邀请参与者或运行真实 Chrome。真实服务操作受当前工具策略阻止，记录为 **BLOCKED_TOOL_POLICY**，不是功能 PASS 或功能 FAIL。

## 官方资料（2026-11-07 核对）

| 资料 | 本资料使用范围 |
| --- | --- |
| [Chromium：AppleScript](https://www.chromium.org/developers/applescript/) | Apple Events JavaScript 菜单及默认限制 |
| [Apple：截图](https://support.apple.com/en-au/guide/mac-help/mh26782/27/mac/27) | 常见快捷键、保存文件；不作为 Riftlet 监听所有保存位置的证明 |
| [Apple：自动化](https://support.apple.com/en-ie/guide/mac-help/mchl07817563/27/mac/27) | 隐私设置中的单 App 授权 |
| [Apple：文件与文件夹](https://support.apple.com/en-au/guide/mac-help/mchld5a35146/mac) | 目录访问控制 |
| [Apple：屏幕录制](https://support.apple.com/en-kw/guide/mac-help/mchld6aa7d23/mac) | 系统权限位置与用途；Riftlet 不录制音频 |
| [Apple：安全打开 App](https://support.apple.com/en-nz/102445) | Gatekeeper 的来源与打开提示，不附绕过命令 |
| [Apple：Developer ID](https://developer.apple.com/developer-id/) · [公证](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) | 公开分发前的身份和检查边界，不借此宣称实际公证结果 |

官方网页核对是文案研究，不是外部网页联调；无第三方博客、论坛或推测用作产品支持承诺。
