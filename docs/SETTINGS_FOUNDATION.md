# WP07：未接入界面的设置状态基础层

本增量实现 `Sources/RiftletUI/SettingsStateModel.swift`，没有修改 Main、现有设置窗口、菜单、配置文件格式、生产数据或安装中的 App。它是后续设置界面的可测试状态层，不是新设置中心已上线。

设计依据是设置设计工作树的 revision-2 `IMPLEMENTATION-HANDOFF.md` 与第一版 `CONFIGURATION-MAP.md`。这些设计未合入本工程分支，不能把网页内存演示值当作原生能力。当前实现继续使用本仓库的真实 `RiftConfiguration`、`RiftSettingsSnapshot`、`RiftSettingsDisplay`、`ScreenshotMode`、`ArrivalMotionMode`。

## 已有 owner 与本次边界

| 当前所有者 | 继续负责 | 新模型负责 |
| --- | --- | --- |
| `RiftletMain`、`CaptureControlGate` | 收录/可见性实际行为，QueueStore 元数据及门禁 | 两个有效意图与各自未确认保存目标的投影 |
| `ScreenshotEntryHost` / `ScreenshotEntryPreferences` | 先关闭入口、保存后才允许重新启用；真实保存结果 | 有效 OFF、最后确认值、失败目标分别保留，不把非 throwing 返回当成功 |
| `RiftConfiguration` / Main 配置写入 | 27 字段解码、校验、原子写入、实际布局更新 | 16 个有效数字字段的文本草稿、完整校验及对最新配置的 patch |
| `LifecycleSettings` | 归档秒数与文件保存 | 独立小时文本、明确保存、与布局域部分成功的记录 |
| `ArrivalMotionPreferences` | absent/unreadable/明确选择与保存 | 未选择的有效 none 不冒充已确认的显式 none |
| `RiftPanelController` / `RiftDisplaySessionSelection` | UUID 匹配、歧义、临时回退、显式恢复及交互保护 | 透传实际屏幕/恢复可用状态，保存明确选择时的具体身份 |

现有 `RiftSettingsForm` 仍在使用原回调。本次没有替换它的控件、修改其保存行为或接入新的权限判断。来源健康、权限、存储统计与 Feedback 仍由既有 owner 提供。外观与登录启动在同一增量另有独立 App owner，分别见 [SETTINGS_PRESENTATION_BACKEND.md](SETTINGS_PRESENTATION_BACKEND.md) 和 [SETTINGS_LOGIN_BACKEND.md](SETTINGS_LOGIN_BACKEND.md)：它们保留各自的读取/明确命令/错误语义，没有接入 Main 或现有 UI，也不把系统登录项塞入几何配置。后续 App 组合层将这两个 typed snapshot 与本模型快照一起提供给既定页面；RiftletUI 不反向依赖 App 模块。设置状态与附件目标、输入、START、UNKNOWN 没有接口依赖。

## 状态与回执合同

`SettingsOwnerSnapshot` 包装现有 `RiftSettingsSnapshot`，补充实际 pause/hidden、主屏/当前实际屏幕和单调 owner revision。`SettingsStateSnapshot` 包含最新 owner、未经改写的编辑文本、可校验的完整配置草稿以及每域保存状态。模型自己的 revision 供界面识别更新；它不表示文件版本。

每个域的 `lastConfirmed`、`pending`、`saveFailure`、`validationFailure` 独立存在。初始化默认没有已确认值；接线者只能传入确实已知的确认事实，不能因为当前已经暂停或关闭而补造磁盘确认。`lastConfirmed` 是该域最后一次明确确认的值，不保证它仍等于此刻磁盘字节；多个配置命令共享同一配置文件时尤其如此。

`SettingsPersistenceAdapter.save` 是 **MainActor 上可 await 的窄异步边界**。现有 `RiftletMain.toggleHidden` 与 `toggleCollection` 需要等待 QueueStore actor，收录还需等待 source binding 的 stop/start；它们不能被同步成功回执代替。

1. 请求含明确 `intent`、调用时 owner revision，以及需要时由最新 owner 配置生成并校验的完整配置。
2. 现有 owner 继续执行真实命令。停止方向先停再保存；恢复方向只在保存允许后恢复。模型不复制 watcher、截图会话或窗口行为，也不自行乐观更改有效状态。
3. 返回 `.confirmed(actualOwnerSnapshot)` 或 `.unconfirmed(actualOwnerSnapshot?, reason)`。即使写入失败，返回的实际快照也可能已经暂停、隐藏或关闭；模型保留这个事实。
4. `ScreenshotEntryHost` 一类不抛错但 `preferenceSaveFailed` 为真的结果必须映射为 unconfirmed。模型也防御性拒绝将相应失败标记当作确认。写完后 chmod 失败同样只能报告未确认，不能声称磁盘必为旧值。
5. 每份回执需比它自己的请求观察推进 owner revision。比已收到的其他观察更旧的有效回执只确认本域，不覆盖新的全局有效状态；同一 revision 的冲突快照、没有推进请求观察的回执不能产生确认。原 pending 留给用户明确重试/放弃。

闭包实现 `SettingsPersistenceClosures` 便于测试和后续 owner 接线。`perform` 等待真实 adapter 返回，不能用启动一个 Task 代替保存完成。每个调用栈保留自己的请求与回执；保存期间编辑、owner 刷新及其他 owner 的保存仍可执行。同域正在写入时，重复提交只返回 `busy`，不排队、不反转意图；layout/placement/display 共享同一个配置文件写占用，避免两份旧整表互相覆盖。这不是全局 UI 禁用或截图输入门槛。

adapter 必须从实际 owner 采集一致快照，沿用现有错误与副作用顺序。配置写入应在 MainActor 上从当前 owner 应用请求字段并立即完成原有同步写入；如果接线者在真正写配置之前引入等待，还必须重新基于当前 owner 校验，不能稍后盲写旧整表。回执按本次明确请求的字段确认，不会因 owner 合法保留了较新的未编辑字段而假报失败。底层取消/错误也应返回真实结果；放弃编辑不能撤销已经开始的 owner 写入。

## 草稿、重试与部分失败

- 数字文本按用户输入保留，包括空串、未完成的小数和本地小数点；只在明确应用时解析整个字符串。配置继续用源码单位，界面百分数和毫秒只在边界换算。所有字段最终仍通过 `RiftConfiguration.validate()`。
- `receive` 不保存、不清错误、不覆盖编辑过的文本。未编辑字段直接跟随最新 owner；完整草稿以最新 owner 为底，再叠加有效字段 patch。因此显示器回退、另一个表面的配置变化及兼容字段不会被旧整表快照覆盖。
- 显示/动效共用布局草稿；归档独立。`applyDrafts` 在首次 await 之前固定两域意图并占用需要写入的 owner，再并行等待两个独立结果，不把第二条命令排到第一条保存之后。它准确记录部分成功，后续应用不重复写已成功且无新更改的域。界面仍需根据剩余草稿/错误决定是否可关闭。
- `retry(domain)` 重用原 pending 意图，不取反当前开关、不自动重试。布局重试将原字段 patch 应用于最新 owner 配置；编辑版本一并保留，失败后或等待期间的新文本即使数值相同，也不能被旧请求完成清掉。
- 放弃布局/归档只清对应候选与错误；不会撤销已生效的暂停/隐藏/入口状态，也不清这些域的未确认结果。输入校验失败与先前写入失败分开，不因新文本暂时非法而抹掉旧失败。
- “恢复本页”仅覆盖本页有效字段，使用真实 main 默认（例如遮挡 25%），不写设计推荐 0%。七个兼容字段始终不进入编辑/reset 集合，原值保留。
- 显式选择新 placement 才迁移旧绝对位置语义，保留配置中原值；旧绝对位置的待重试请求若已不适用，不会伪称成功，用户可放弃该旧草稿或明确应用当前有效字段。
- “使用主显示器”调用现有 `RiftDisplaySelection.choose` 获取当前具体可用身份，不存 null 作为永久 follow-main 策略。临时回退完全属于现有 session owner，不会生成保存请求。显式恢复仍应调用现有控制器，不在新模型复制一套恢复算法。

## 验证与接线前置

`Tests/RiftletUITests/SettingsStateModelTests.swift` 有 21 个无 AppKit 窗口依赖的异步 XCTest，覆盖：三个停止域并存与顺序重试、恢复失败、非 throwing 失败、未知磁盘结果、部分成功、旧请求与新草稿、读取刷新、旧兼容值、单位/空串/精度/归档关闭、具体主屏选择、过时回执、同域重入、延迟回执和跨域完成。延迟测试使用 continuation 与有限时间的 XCTest expectation，不靠固定 tick 猜测。旧配置 fixture 使用真正的 `RiftConfiguration` 解码；owner adapter 是合成测试替身，不是真实磁盘或系统行为。

本地 `swift build --build-system native --target RiftletUI` 已通过；测试文件的 Swift parser 检查也已通过，仅证明语法可解析。本机只有 CommandLineTools，缺少 XCTest.framework。正式 XCTest 的编译和执行 **本地 NOT_RUN**，须由后续 macOS CI 给出结果，不能用模块编译或 parser 结果替代。现有显示器匹配/迁移测试继续使用原算法，没有在此引入第二套实现。

后续 UI 接线还需验证：owner 回执一致性、真实保存/权限故障、MainActor 调用与生命周期、编辑器原节点/选区/组字、AppKit key-view 与关闭确认。状态层保留文本不等于界面已证明不重建 field editor。完成接线、独立源码审查及实际原生验证之前，不把本基础层称为新设置中心或已安装 Beta 的功能变化。
