# Riftlet 完整体验补充：状态转换与 AppKit 接线规格

版本：2026-10-29。性质：**独立补充设计提议，不是原生实现或新的运行验收。** 本文只定义 Q03、Q04、Q05、Q10。所有原生改动均须等待正在进行的正式集成结束，重新读取正式 HEAD 后，在独立实现分支完成；不得覆盖 PR #1、正式设计基线、当前候选或其他工程工作树。

## 依据与判定口径

- 正式设计：[`7e03bd2`](https://github.com/haohongfei2001-png/Riftlet/tree/7e03bd2c26c6aa43dbac07b073e00d08d1951b71/design/final-system-20261028)。其中 `APPKIT_SPEC.md` §7 已定义非激活轻反馈，§6 定义动效和辅助功能，§8 定义辅助窗口。
- 原生候选：[`00dedc7`](https://github.com/haohongfei2001-png/Riftlet/tree/00dedc7f8164643c3435e3f87aa462e28af0b1c8)；原生交接：[`443d21d`](https://github.com/haohongfei2001-png/Riftlet/tree/443d21da1a55c0061eafced823b5406879b96024)。本文工程路径和行号以交接中的候选源码为准。
- 审计起始时 GitHub PR #1 为 Draft/open，正式头为 `0e7ea8be148e1124b387e799fd886a7830e96559`。候选尚未进入该正式头属于集成状态，不据此判断设计缺陷。
- 事实分为：代码可证、现有测试/证据可证、正式设计已覆盖但未完成呈现、尚未验证。本文没有进行新的 macOS 真机、真实上传、权限撤销或物理鼠标验收。

**共同原则：** UI 投影事实，不能授予上传、重试、目标替换或数据删除权限。关闭说明、结束截图、隐藏裂缝、退出 App 是不同动作。原图、本地历史、UNKNOWN 和已持久化操作必须保留。普通成功不增加 Toast。

---

## Q03 · 已选目标的倒计时、模式切换和结束截图

**优先级：P1。判定：已有安全状态机；倒计时及“本次／下一张”的呈现存在可代码证明的缺口。**

### 证据

| 代码位置 | 能确认的事实 |
| --- | --- |
| `Sources/RiftletCapture/InteractiveScreenshotController.swift` 224–250、254–267 | 用户完整 down/up 选择目标后，先冻结请求，再进入倒计时。倒计时发生在目标选择之后。 |
| `Sources/RiftletCapture/InteractiveScreenshotTypes.swift` 113–149 | 模式/选项变化不会覆盖已确认 pending 请求；请求保存原 `sessionID / requestID / mode / target / options`。 |
| `Tests/RiftletCaptureTests/InteractiveScreenshotTests.swift` 58–71 | 已测模型语义：region + 5秒请求继续完成，期间切换的 fullScreen 对下一张生效。 |
| `Sources/RiftletApp/ScreenshotEntryHost.swift` 65–90 | 当前没有绑定 `capture.onStateChange`；因此 countdown 状态没有接入专门的剩余时间呈现。 |
| `Sources/RiftletUI/ScreenshotEntryModel.swift` 85–124；`ScreenshotEntryController.swift` 445–452、550–565 | 本次会话模式槽位置固定；语义立即更新，X 覆盖随 active mode 移动。 |
| `ScreenshotEntryHost.swift` 198–208；`InteractiveScreenshotController.swift` 123–139 | X 最终结束整个截图会话，取消 pending 请求和 capture task，清旧 session；并不只取消“下一张模式”。 |
| `ScreenshotEntryHost.swift` 156–169、198–208；`ScreenshotMarkupController.swift` 65–83 | 已拍摄后进入编辑时，保留原图/关闭/结束截图仍保留已拍好的原图。 |

### 设计目标

让用户随时知道这次已经选定什么、何时拍摄，以及模式切换对哪一张生效。保留固定槽、移动 X、连续截图与冻结请求，不另加确认步骤。倒计时不是上传计时，也不能用于推断上传开始。

### 高保真呈现约定

在固定模式列左侧 12pt 放一条纯展示的薄界说明，最大宽度 240pt、13/18pt 文字、12pt 内边距、8pt 圆角；不改变模式槽几何，不覆盖移动 X。位置以实际屏幕 `visibleFrame` 夹取；空间不够时优先放在控件下方，仍无法容纳则保留 AX/运行状态说明，不把内容移到另一块屏幕。

- 已选区域、倒计时中：**“已选区域 · 3 秒后拍摄”**。
- 已选窗口/屏幕：替换目标种类，不猜窗口标题或显示私有内容。
- 倒计时中已切换下一次模式：第二行 **“下一张：窗口”**。未发生切换时不增加第二行。
- 计时结束、当前请求仍在执行：**“正在拍摄已选区域”**。不给进度百分比。
- 已完成截图并继续会话：撤去说明，沿用当前模式，允许下一次完整选择。
- 没有确认目标时不出现倒计时；延时为 0 时不闪现“0 秒”。

可以在倒计时期间保留选定目标的薄描边作为位置提示；它必须是纯展示，且在实际曝光前加入现有自排除/WindowServer 核验。当前实现会清除选定高亮，保留描边属于补充提议，不是对既有行为的描述。若难以可靠排除，首轮实现只交付文字说明即可。

### 事实／输入／状态／动作矩阵

| 当前事实 | 用户输入或系统事件 | 下一呈现状态 | 允许动作 | 禁止转换 |
| --- | --- | --- | --- | --- |
| 未启动截图 | 点击入口或菜单截图 | `selecting(currentMode)`；必要时走用户主动的 Screen Recording 请求 | 选择目标、切模式、打开更多、X/Esc | 仅展示入口便截图；仅启动 App 便请求 Screen Recording |
| 正在选择，尚无 pending | 完整合法 down/up | 冻结同一 request；延时>0进入 `countdown`，否则 `capturing` | 当前 X/Esc 结束会话 | 不完整手势发起捕获；用晚到位置替换原目标 |
| countdown(request R, mode 区域) | 切换为窗口 | 仍是 R 的区域倒计时；`nextMode=window`；X 移到窗口槽 | 再改下一模式；X/Esc结束整个会话 | 以新 mode 覆盖 R；静默取消 R 后自动新建请求；把移动 X 当成捕获完成 |
| countdown(R) | 改延时/指针/编辑选项 | R 保留冻结 options；新的 options 只影响下一请求 | 当前 X/Esc 结束 | 修改当前倒计时截止时间；重新执行已选目标 |
| countdown(R) | 再点目标区域 | 仍只有 R | X/Esc；模式切换仍按下一次语义 | 第二个 pending；重复捕获同一次手势 |
| countdown(R) | 截止时间到达 | `capturing(R)`，先核权限和原目标 | X/Esc 尽力取消当前任务 | 因时间到了便宣称已拍好；跳过目标/权限复核 |
| countdown/capturing(R) | X/Esc | 截图会话结束；失效旧 session 和 R 的展示回调 | 后续由新用户操作开始新会话 | 旧 completion 更新新会话；补做原截图；暗中改目标重拍 |
| capture 已完成并交付 `onCapture` | 用户此时结束会话 | 结束选择，但已经完成的原图保持既有收录/编辑保留语义 | 从既有历史/Finder访问已保留内容 | 宣称“此次没有拍摄”；删除已存在原文件；取消完成事实 |
| editing | 完成 | 本地保存编辑副本并保留原图；恢复当前会话 | 下一次完整选择 | 改写系统原图；把编辑副本伪装成系统截图准入来源 |
| editing | 保留原图、关闭、结束截图 | 原图保留；结束截图时关闭选择会话 | 既有本地访问 | 用关闭窗口当永久删除；静默丢弃原图 |
| countdown/capturing(R) | 原窗口关闭/屏幕拓扑失配 | 终止当前 R 的有效交付；显示准确原因，重新选择必须是新手势 | 重新选、结束 | 猜测替代窗口/显示器；旧目标自动迁移 |
| countdown/capturing(R) | 权限撤销 | 权限恢复说明；先安全结束选择，再进入系统设置 | 用户恢复权限后重新检查/重新开始 | 授权回来自动重拍 R；旧点击自动重放 |

**取消的事实边界：** 用户按 X 后统一说“已结束截图”。只有捕获结果已经被验证并交付时，才能补充“已拍摄的原图仍然保留”；不能因系统工具被取消就武断宣称完全没有落盘文件。已完成和未完成请求由业务身份与交付事实判定，UI 文案不制造完成或未完成证明。

### 最小 Swift 适配接口建议

下列为只读接口草案，不是生产代码，不改变既有捕获会话或目标结构。

```swift
struct CapturePresentationSnapshot {
    let sessionID: UUID
    let requestID: UUID?
    let phase: CapturePresentationPhase
    let confirmedMode: ScreenshotMode? // 取自原 pending request，不能取 entry.mode
    let nextMode: ScreenshotMode       // 当前会话 mode
    let remainingSeconds: Int?        // 只用于 countdown
    let issue: CapturePresentationIssue?
}

enum CapturePresentationPhase {
    case idle, selecting, countdown, capturing, editing, issue
}

enum CapturePresentationIssue {
    case permissionUnavailable
    case noDisplay
    case originalTargetUnavailable
    case displayConfigurationChanged
    case captureNotCompleted
    case savedButNotCollected
}

@MainActor
protocol CaptureStatusPresenting {
    func render(_ snapshot: CapturePresentationSnapshot)
    func dismiss(sessionID: UUID)
}
```

建议从 `InteractiveScreenshotController` 暴露只读 projection，Host 在现有 `onStateChange`、`onCapture`、`onError` 边界将其传给呈现器。完整 request、原窗口/区域和捕获权限仍由原 Controller 持有。状态说明器不得调用 `start / submitSelection / append`，也不得根据当前模式重新生成原目标。

AX 在开始倒计时时说明一次“将在 5 秒后拍摄已选区域，Escape 取消”；不要逐秒打断读屏。模式改变时说明“下一张改为窗口，本次仍为已选区域”。X 的名称统一为“结束截图”，帮助根据阶段说明是否会取消当前未完成拍摄。Reduce Motion 下文字直接更新；Reduce Transparency 下用不透明 surface。

### 必须通过的最小验收

1. 目标选择完成后才出现 5→4→3；当前请求只有一次捕获调用。
2. 倒计时中区域→窗口→全屏，槽不重排、X 连续移动，原 request ID、target、mode、options 不变；下一张才用全屏。
3. 切槽后的 X 与 Esc 都结束原请求；新会话开启后，旧秒表/完成回调不能重开说明或插入未交付的旧图。
4. 延时0不显示“0秒”；pending中修改延时不影响当前截止时间。
5. 屏幕断开/窗口失效显示正确原因，不能自动转投；新完整手势可恢复。
6. 截图已交付与尚未交付两种取消边界分别测试；原图保留，文案不互相混用。
7. 可见说明参与自排除；没有可靠排除证据前不交付新增选区装饰。

---

## Q04 · 附加前等待、拒绝、结果待核实和恢复说明

**优先级：P1。判定：正式设计已有方案，原生存在呈现差额；安全后端边界与已有反馈应保留。**

### 现状不可写错

候选 `RiftPanelController.swift` 195–210 保留 `toolTip = feedback` 和 AX label/help；230–235 的单/双短线表达 transferring/unknown；683–688 将 feedback 同步到输入岛。普通 hover tooltip 被取消是为了避让图片 peek，**不表示实际拒绝/等待原因消失**。本项实现正式 `APPKIT_SPEC.md` §7 的附近小型非激活说明，不删除这些已有兜底。

`ProductStatus.swift` 89–101 与 Main 的 owner/revision 保护已经修正 prepared 文案和迟到取消覆盖问题。prepared 是最近观察到的状态，并不证明此刻仍未输入；禁止退回“正在等待，因此本次尚未上传”的持续断言。

### 提议的显示时序

以下是本专项建议的呈现参数，不是对候选性能或既有批准参数的重新认证。

| 触发事实 | 新说明的出现与退出 | 原有呈现 |
| --- | --- | --- |
| 一次点击被确定拒绝，原因已归一化 | 原图复位时立即展示稳定原因，最长 2400ms；离开当前资产/环境变化可提前退出 | 保留按压/回退、tooltip与AX |
| 接受后确实等待，持续≥250ms | **仅原指针仍在同一资产输入岛时**显示短说明，最长2400ms；不是全局悬浮常驻提示 | 短说明退出后，下划线/原状态仍保留 |
| 已显示条超时或用户想再读 | 同资产主动 hover 450ms 可重新读取；AX始终可读原状态 | 普通图片peek仍保持现有450ms机制 |
| 同资产同时具备状态说明与peek资格 | 状态说明优先；不叠两层窗口。状态结束后重新满足正常hover条件才出现peek | 保留完整比例图片peek |
| 无反馈或已清反馈 | 不显示附加状态条 | 普通hover仍使用peek |
| 新 owner/revision、原资产隐藏/移除、换Space、截图曝光隐藏 | 立即撤销旧条和延迟显示令牌 | 不改变业务选择或后台状态 |
| 获准 uploadStarted 已持久化并投影 | 撤去该图状态说明；立即执行既有快吞噬 | 最终成功不补动画、不弹Toast |

规格复用正式设计：最大 240pt、13/18pt文字、12pt内边距、8pt圆角、图左侧12pt。面板 `ignoresMouseEvents = true`，不成为 key/main，不激活 App，不增加图片/数字以外输入岛；不遮住相邻可点截图。没有安全空位时保留原tooltip/AX/运行状态兜底，不扩大命中面。原生tooltip与自绘说明不得重复堆叠；原feedback语义与tooltip兜底仍保留，具体AppKit显隐协调由实现者处理。

### 事实／状态／操作／禁止矩阵

| 原始可证事实 | 呈现文案及可见状态 | 允许用户下一步 | 禁止转换 |
| --- | --- | --- | --- |
| 点击时没有完整有效ACK | “当前聊天仍在验证，图片已保留。”；原图按压后复位 | 等页面确实可用后，由新的用户点击重新选择 | 收到晚到ACK后自动补签旧点击；跳到后台聊天；假吞噬 |
| 当前没有唯一有效草稿/附件入口 | “当前聊天暂时不能接收图片，图片已保留。”；原图不消失 | 返回受支持的当前草稿；运行状态可查原因 | 将最近聊天当目标；把权限已允许当目标已验证 |
| App FIFO中确实尚未提交的接受项 | “已接收，正在等待附加。”；可选次行仅在此明确边界说“本次尚未上传” | 等待；沿用已有可安全撤销边界 | 靠排队时间显示进度/开始；把这句话沿用到prepared/intent后 |
| prepared投影，后续可能已input | “附加处理中，结果尚待确认。”；原图保留 | 查看原草稿；维持既有输入锁 | 说“本次未上传”；显示可以无条件取消/重新上传 |
| 确定在input intent之前取消/过期/原草稿变化 | “此次附加已取消，图片保留；本次未上传。”，原因按闭集细分 | 新用户点击可以走现有完整校验 | 旧任务迟到后仍dispatch；关闭说明就认定取消已生效 |
| dispatch intent已提交，但开始/结果不能确认 | “附加结果待核实，不会自动再次附加。”；是否可见遵守Core原visibility | 查看本地记录和原草稿；只读核对 | 只凭超时/离线说失败；使同图重新输入；虚构上传开始 |
| 获准、同身份的真实uploadStarted | 既有快速吞噬；退可见队列 | 用户在当前草稿看附件状态 | 等READY才吞；把吞噬当成功；触发新输入 |
| 已开始后UNKNOWN | 保持隐藏；历史“结果待核实” | 仅本地查看、既有Finder定位；原操作只读核对 | 自动重生、自动重试、恢复为可重输图、清历史锁 |
| 独立完成证据且Core确认succeeded | 继续隐藏；历史“已附加” | 在ChatGPT决定是否发送 | 第二次吞噬、成功Toast、自动发送消息 |
| 明确且独立获准的safe failure | 原图重生为正常、可点击的图；“上传失败，图片已保留” | 用户新的点击才产生下一attempt | 灰掉为永久失败死卡；后台自动重传；以普通网络异常伪造safe failure |
| 用户已移除/归档，迟到start/成功/失败 | 尊重用户可见性意图；保留事实审计 | 仅Core授予资格的既有恢复操作 | 迟到失败把已移除图自动复活；删除远端附件 |
| 仅网络断开/页面跳转/观察器失联 | 如不能确认结果，按UNKNOWN/原visibility处理 | 查看原草稿，等待只读核对 | 宣称“肯定未上传”或“可以安全重试” |

当前 safe failure/retry 准入仍关闭。原型中的安全失败重生只能标为“目标状态／隔离模拟”，不能当作真实候选功能已开放。反馈发送服务的自动重试策略与截图附加策略不同，本项不把二者混用。

### 最小 Swift 适配接口建议

仅用于表达 UI 身份和归一化文案；工程可复用既有类型，不需要重复建立业务状态机。

```swift
struct AttachmentFeedbackOwner: Equatable {
    let assetID: UUID
    let operationID: UUID?
    let selectionOwnerID: UUID
    let visibilityRevision: Int64
    let presentationGeneration: UInt
}

enum AttachmentFeedbackReason {
    case acceptedWaiting
    case preparing
    case noVerifiedClickTarget
    case targetUnavailable
    case cancelledBeforeInput
    case expiredBeforeInput
    case targetChangedBeforeInput
    case resultUnconfirmed
    case localImageUnavailable
}

struct AttachmentFeedbackProjection {
    let owner: AttachmentFeedbackOwner
    let reason: AttachmentFeedbackReason
    let primaryText: String
    let helpText: String?
    let observedAtUptime: TimeInterval
}

@MainActor
protocol AttachmentFeedbackPresenting {
    func render(_ projection: AttachmentFeedbackProjection)
    func clear(ifOwnerMatches owner: AttachmentFeedbackOwner)
    func dismissPresentation() // 仅显示，不是业务cancel
}
```

250/450/2400ms令牌同时绑定 owner、revision、generation 与同一hover输入岛。令牌到期先核对身份和原指针位置；不能仅凭相同assetID接受旧attempt文字。开始/完成/UNKNOWN由既有Core投影驱动，不能从该文案enum推导；`dismissPresentation`不得调用取消、重试或改变Store。

### 最小验收

- 249ms离开岛，不出现等待条；250ms仍在原岛且owner有效才显示；鼠标移到下一图时不携带旧原因。
- 拒绝说明最长2400ms；重新hover450ms可读；自动超时不清数据库原因、不重放点击。
- 同asset发生新selection/attempt后，旧取消、旧定时器、旧AX更新不覆盖新状态。
- prepared推进后无持续“本次未上传”；未知错误不显示原始异常/网页字符串。
- 任意说明显示/隐藏均不改变begin/chunk/commit/input计数；透明面板不截断底层原生点击。
- started→UNKNOWN→重启仍是同一旧操作，保持隐藏/只读；safe failure仅隔离fixture允许正常重生。
- 最终成功无新增Toast；正常peek未被永久取消；已实现下划线、tooltip/AX仍可用。

---

## Q05 · 权限与环境变化的准确恢复

**优先级：P1。判定：已有权限分离和安全拒绝；补充按功能解释、就地原因和返回规则，不增加一揽子授权流程。**

### 权限应按用户所做的事分开

| 需求 | 实际能力/权限 | 请求时机 | 正确解释 | 不能声称 |
| --- | --- | --- | --- | --- |
| 收录用户用macOS系统方式产生的新截图 | 实际系统截图目录的读取访问；当前source可用性 | 来源确实不可读时，用户主动授权实际目录 | “允许读取截图保存位置”；不更改系统保存位置 | 必须先开Screen Recording才能读取已有系统截图文件 |
| 使用Riftlet主动截图入口 | Screen Recording预检/请求 | **用户主动点击该入口或菜单截图时** | “Riftlet需要读取屏幕，才能拍摄你选择的区域/窗口。” | 首次启动即弹此权限；要求用户为不用的入口完成授权 |
| 向受支持Chrome当前草稿附加 | macOS Automation针对Chrome；独立页面能力/原目标校验 | 用户主动连接/授权；被动检查不重复弹授权 | “允许Riftlet与Chrome通信”；授权与目标是否可用分开 | 授权完成即上传能力准入或当前草稿已验证 |
| Chrome页面连接 | Chrome的Apple事件JavaScript设置 | 仅在实际需要的支持流程中说明 | 设置由用户在Chrome打开，Riftlet不代改 | 用macOS Automation通过来表示此开关也已开启 |
| 当前工程模式能力关闭 | 代码/准入范围 | 直接如实显示 | “当前仅本地收录”或受限候选范围 | 将功能关闭包装成用户权限错误，诱导多给权限 |

证据：`InteractiveScreenshotSystemCapture.swift` 14–17 采用 `CGPreflightScreenCaptureAccess / CGRequestScreenCaptureAccess`；Controller 75–85只从用户截图动作请求。Main 691–709 的目录选择只接受实际系统来源；`AutomationPermission.swift` 96–107 区分被动inspect与显式request，34–35说明不启动/激活Chrome，也不授予上传准入。

### 恢复矩阵

| 可证事实/触发 | 现场呈现 | 用户动作及恢复 | 保留与禁止 |
| --- | --- | --- | --- |
| 系统截图目录访问被拒绝/目录不可用 | 设置/运行状态标“暂时无法读取截图位置”，已有图仍可查看 | 主动选择实际目录授权或重新检查 | 不把暂停误判拒绝；不扫其他目录补录；不删除旧图 |
| 目录变化 | 显示当前真实来源和读取状态 | 沿既有source binding重新核验新来源；用户可授权 | 不用旧路径伪装正在收录；不重新导入历史已见截图 |
| 用户主动进入截图，但Screen Recording拒绝 | 入口回到真实可再试状态；“屏幕录制权限不可用” | 提供系统设置说明；按macOS实际要求完成后重新检查/新点击 | 不显示无效X假装正在选择；不循环权限弹窗 |
| 活跃截图期间Screen Recording撤销 | 取消当前未完成选择会话，解释原因 | 打开系统设置前撤掉选择面板；返回只重新检查 | 不自动恢复旧目标并拍摄；不把旧pending视为成功 |
| Chrome Automation撤销 | 已接受但未intent的选择按原权限逻辑撤销；图保留 | 设置中恢复；被动/主动核验后，新点击才产生新选择 | intent后结果不明按UNKNOWN保留；不回放旧选择 |
| Chrome退出/重启或换页面/草稿 | 原lease失效；准确显示当前目标不可用或仍在验证 | 沿既有session/ACK机制重新验证；用户自行回目标 | 不切换后台聊天；不沿用旧进程/session身份；不要求先点击编辑器作为常规步骤 |
| 空闲时换Space/全屏/显示器参数变化 | 撤旧说明/peek/磁力装饰；按现有几何策略重排 | 保持当前可见性/隐藏意图 | 不改asset顺序、operation身份、原target或权限 |
| 按下未释放时改变屏幕布局 | 旧手势取消；新布局等待新完整手势 | 用户重新点击 | 不把旧up交给新位置的别图；不把视觉reset当上传取消 |
| 已确认截图倒计时期间显示器/原窗口失效 | “屏幕布局已改变，请重新选择”或“刚才的窗口已不可用” | 新完整手势；或X结束 | 不猜替代目标；不在新屏幕自动重拍 |
| 唤醒/重启 | 恢复持久可见性、隐藏/暂停；原未决只读核对 | 用户看到真实状态后自主操作 | 不重建旧dispatch，不清UNKNOWN，不为去提示重置数据 |
| 原图已保存但未收录 | “截图已保存，尚未加入裂缝”；避免统一归因磁盘 | 当前只使用既有Finder/本地数据入口；告诉用户该入口的真实范围 | **本轮不新增“重试导入”按钮**；没有稳定ownership及已保存路径安全API前，不显示可执行的单文件恢复承诺 |

对于最后一项，未来只有在受控source ownership、不可变来源身份和安全文件定位API已经存在且经过独立审查后，才能另立任务评估“仅重试本地导入”。该未来条件不属于本次功能实现范围，不得把它混成上传重试或把UNKNOWN素材重建为新资产。当前既有Finder入口若只能打开目录，应明确写“打开本地数据文件夹”，不能伪装为精准“显示这张原图”。

### 窗口与光标规则

- 截图选择期间出现权限恢复说明，不新开阻塞全局modal；用户选择去系统设置时先结束截图会话并释放选择键窗口。恢复权限后不自动拍摄。
- 区域保留十字光标；窗口/全屏保留相机光标；模式变动立即更新cursor rect，不能等X动画结束。代码已有 `invalidateCursorRects`，此项应验证而非重写。
- 系统外观/无障碍变化只重绘和落到当前事实终态；不得从变化中推导新capture/append。
- 用户已主动切去其他App，不因错误结束而强行切回Chrome。沿用现有“仅Riftlet仍前台且原应用有效时才恢复”的受限规则。

### 最小 Swift 适配接口建议

复用 `AutomationPermissionState / SetupSnapshot / InteractiveScreenshotError`，不要用一个 `isReady` 混合权限、目标、生产准入和收录状态。

```swift
struct EnvironmentPresentationSnapshot {
    let screenshotSource: SourceAccessPresentation
    let interactiveCapturePermission: ScreenPermissionPresentation
    let chromeAutomation: AutomationPermissionPresentation
    let attachmentCapability: AttachmentCapabilityPresentation
    let isCollectionPaused: Bool
    let isRiftHidden: Bool
    let pendingResultCount: Int
}

// 各项为现有类型的只读投影；不存放浏览器文本、凭据或新权限令牌。
// 动作适配必须路由现有权限/选择取消入口。
enum RecoveryPresentationAction {
    case inspectAgain
    case requestActualScreenshotFolderAccess
    case openScreenCapturePrivacySettings
    case requestChromeAutomationFromExplicitAction
    case openChromeAutomationPrivacySettings
    case openExistingLocalDataLocation
}
```

Screen Recording系统设置定位应以部署目标上已验证的公开路径或系统App入口实现；目标pane无法打开时退到系统设置并给简短导航文字，不硬编码一个未经验证的成功跳转承诺。

### 最小验收

1. 仅用系统截图文件收录，不请求Screen Recording；点击Riftlet截图入口才预检/请求。
2. 目录读取、Screen Recording、Chrome Automation、Chrome页面设置分别缺失，文案与按钮只指向缺失项；普通capture模式不诱导“授权即可上传”。
3. 拒绝/撤销后已有媒体、UNKNOWN、隐藏/暂停原值不变；恢复权限后无旧capture/input自动发出。
4. 断屏/窗口关闭/Space变化发生在按下、倒计时、拍摄、吞噬、peek解码各时点，旧callback不改变新状态。
5. Finder动作只使用已存在的入口和真实路径范围；本次交付无新增导入重试/上传重试按钮。

---

## Q10 · 环境、辅助功能和原生组合验收

**优先级：P1；其中防错目标、防重复输入和保留数据为P0回归门槛。判定：验证工作，不把NOT_RUN写成已知缺陷。**

### 当前证据边界

候选 `engineering/evidence/2026-10-29-thin-edge-native/README.md` 57–75 已记录合成软件运行、浅深截图、软件路由和原生CI范围，并明确1x、真实多屏、全屏、Spaces、VoiceOver完整使用、系统实时外观变化及最终正式组合跨应用焦点仍NOT_RUN。约126–130ms的swallow start→close为软件回调边界，不是点击至真实上传的性能测量。

历史 H 的 `engineering/evidence/2026-10-28-beta-ux/latency.md` 来源是 `e421e668`；按下→swallowClose约2686.613ms、start→完成独立证明更晚。不能把它认作当前候选新测结果，也不能用更快UI演示宣称真实上传已提速。无ACK冷首击的历史限制仍保留，说明文案只能改善可理解性。

### 最小环境矩阵

| 编号 | 环境/操作 | 真实应观察的结果 | 自动化可证明部分 | 必须单独记录的剩余范围 |
| --- | --- | --- | --- | --- |
| ENV-01 | 1x、2x；不同有效分辨率；负坐标/竖屏副屏 | 固定平面和模式槽不裁切；说明在同屏可见；文字/编号锐利；每张图可达 | 纯几何、pt↔px、分页身份 | 原生像素截图、系统缩放/真实显示效果 |
| ENV-02 | 拔掉首选屏后重连 | 沿既有preferred→main→first fallback；恢复不换asset/顺序；旧装饰撤销 | display选择/布局模型 | 实际拔插、窗口层级和光标路由 |
| ENV-03 | 普通Space↔全屏↔另一Space | 无旧说明/peek/磁力残影；不抢浏览器焦点；新选择只属于当前窗口 | generation/旧callback拒绝 | 真实Spaces/fullscreen切换、跨App键焦点 |
| ENV-04 | 指针down期间重排/拔屏 | 原手势取消或继续绑定原资产，绝不选择补位后的另一图 | PointerSelectionGate、revision | OS鼠标事件及实际底层点击穿透 |
| ENV-05 | 快速连点、补位后双击、100ms内模式反转、立即X | 不重复输入；固定槽不重排；取消覆盖连续转向；X语义立即有效 | 隔离事件/模型 | 物理双击分类、实际指针和系统事件顺序 |
| ENV-06 | Light/Dark运行时切换 | semantic颜色同步、无旧CGColor残留、hit区域不变 | projection/绘制逻辑 | 同一活跃窗口实际像素前后对照 |
| ENV-07 | Increase Contrast/Reduce Transparency实时切换 | 控件与说明可读；不透明surface；状态不只靠颜色 | 颜色函数/通知处理 | 系统实机设置切换和实际可读性 |
| ENV-08 | 磁力/移动X/吞噬中开启Reduce Motion | 装饰立即落到当前语义终态；原业务request/operation不变；旧回调不复现 | 中断/identity测试 | 真实系统通知、动态观察 |
| ENV-09 | VoiceOver/键盘 | 模式、结束截图、等待原因、原图保留和UNKNOWN资格可理解；不逐秒抢读；Esc局部生效 | AX label/help/action接线 | 完整读屏操作、焦点顺序、用户可理解性 |
| ENV-10 | 睡眠唤醒、退出再启动 | 隐藏与暂停独立保留；UNKNOWN同operation/attempt/target；不自动replay；新图正常 | SQLite/恢复fixture | 系统睡眠、权限和窗口恢复组合 |
| ENV-11 | 真权限拒绝/撤销后恢复 | 只恢复可用能力；不重拍、不补签旧点击、不自动附加 | fake permission driver | TCC真状态、系统要求是否需要重启 |
| ENV-12 | Capture说明/附加说明可见时截图 | 自排除结果准确；不可承诺所有系统截图入口均排除 | 受控捕获链/窗口隐藏确认 | 系统原截图方法、自包含边界 |

### 执行与记录规则

- 首先固定正式集成后的 source SHA、实际App包hash、macOS build、架构、显示器拓扑/缩放、app mode和权限状态。不能复用旧候选截图称新组合已通过。
- 优先用现有合成素材、原生helper、软件AppKit和已有自动化，补足本次改动引入的具体风险。原生像素截图和录屏分别标明来源；屏幕绘图原型不计作运行证据。
- 真截图/上传测试只在既有授权且可用的Mac执行器与已获准surface范围内执行；独立设计任务不启用生产/重试profile，不新增真实上传来“填满矩阵”。
- 创始人不承担本轮Beta体验或例行验收。设备、账户或权限不可用时，受影响项保持 `NOT_RUN / BLOCKED`，说明前置条件；其他可验证项继续完成。
- 真机失败需保留原证据并定位，不通过删测试、改状态定义或把软件点击改名物理点击关闭问题。
- 无 P0新缺陷证据时，不制造P0缺陷数量。P0是受影响改动必须守住的门槛：错目标、重复输入、丢原图/历史、UNKNOWN重输、模拟准入泄漏、伪造开始/成功。

### 统一结果格式

```text
Case: ENV-xx / Q03-xx / Q04-xx / Q05-xx
Source SHA / App SHA-256:
macOS build / architecture / display topology / backing scales:
Application mode / permission preconditions:
Input type: model | software AppKit | synthetic CGEvent | physical input
Observed facts:
Expected facts:
Result: PASS | FAIL | NOT_RUN | BLOCKED
Evidence paths and original capture time:
Explicitly unproven scope:
```

每个PASS只覆盖该次实际操作、版本和环境；旧UNKNOWN原记录不得为方便复测而清理、重置或更换profile。

## 实施交接顺序

| 阶段 | 可立即做的事 | 等待正式集成后才做的事 |
| --- | --- | --- |
| 本设计专项 | 审阅上述状态表与高保真原型；确认不改变产品约束 | 无原生改动 |
| Q03 | 检查图稿准确表达已选目标→倒计时、当前/下一张、X取消范围 | 修改Host/Controller只读投影、说明呈现、对应回归 |
| Q04 | 对照APPKIT_SPEC§7审核文案与250/450/2400ms提议 | 连接既有owner/revision反馈和非激活小面板；不改Core上传逻辑 |
| Q05 | 审阅权限分离和返回规则；复用已有Finder入口 | 接入真实能力状态、就地错误及系统设置导航；不新增导入重试 |
| Q10 | 整理现有证据和明确剩余NOT_RUN | 固定正式新App，执行受影响最小回归与可用Mac环境验收 |

## Apple 官方实施依据

以下文档用于核对AppKit实施方式，不作为本候选已在所有环境验收的证明。

- [viewDidChangeEffectiveAppearance](https://developer.apple.com/documentation/appkit/nsview/viewdidchangeeffectiveappearance())：外观变动时更新自绘/自持层颜色。
- [accessibilityDisplayOptionsDidChangeNotification](https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayoptionsdidchangenotification)：通过 `NSWorkspace.notificationCenter` 观察辅助功能显示变化。
- [accessibilityDisplayShouldReduceMotion](https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshouldreducemotion)：减少大幅运动，处理运行时变更。
- [accessibilityDisplayShouldReduceTransparency](https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshouldreducetransparency)：减少透明度时使用不透明界面底层。
- [Supporting Dark Mode in your interface](https://developer.apple.com/documentation/uikit/supporting-dark-mode-in-your-interface)：持有的 `CGColor` 不会自行适应，应在更新绘制/层的合适回调中重算；候选已使用 `RiftLineView`，不得拿正式旧基线初始化颜色指控候选。
