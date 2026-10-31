# CUA 定位第二微窗：失败候选记录

最终结果：**FAIL**。实际运行的 AX 列表重排与首次窗口创建顺序两个候选均未让 CUA 定位第二微窗；最终测试没有采用此补丁。已改用现有 GUI helper 的精确单次 AXPress，见 [最终报告](README.md)。下文保留候选开发时的记录，其中“未启动/未实测”只描述当时阶段。

2026-10-27；只读源码 HEAD `1b44e067826f659a0208a6571ba171f6a77a8363`（本次任务收到时为 1f9dec2，检查时已推进）。仅用 `ps` 确认 PID 93866 仍为实际 App；没有读取/操作其 GUI、发送 AX 动作或启动浏览器。候选未应用到正式工作树；现已在指定临时副本应用并编译通过，**未启动 App、未实测 GUI**，不包含 synthetic upload-start grant，不改 Core 或队列。CUA 的输入只能记软件自动化；`.mouse` 也不证明物理真人。

## 静态判断

- UI 每图独立 `NSPanel`；borderless/nonactivating、不能 key/main，row 自身是有序号 label 的 AX button。没有发现第二图缺失 accessibilityPerformPress 的源级差异。
- scroll / Show latest 调整的是分页索引；`RiftLayout.swift:63` 将其夹在 `0...max(0, count-capacity)`。两图均能容纳时，滚动无变化是正常，不会切换 AX 首窗。`showAsset` 对已在 visibleRange 的图片也直接返回。
- standalone helper 是另一个进程，不能读取实际 App 的私有 rowWindows。把 helper fixture 当第二张实际图片，不能完成这次验收。
- 调度方已观察 CUA 只暴露首个 UNKNOWN 微窗，Finder Desktop 截图空白；本报告没有独立 GUI 复现，不能断言 macOS AX 树没有第二窗，也不能确认 CUA 使用哪个列表或创建顺序。

## 最小选择

第一版先对**指定现有 synthetic asset** 的 panel 执行一次 `orderFrontRegardless()`；Apple 文档明确它移到本层前方且不改变 key/main，但没有承诺 AXWindows 排序。若 CUA 仍只取首项，使用下面同一候选的实时 AX 顺序视图，不创建聚合窗口、不隐藏旧 UNKNOWN、不更改元素数量、frame、父子关系或按钮动作。[Apple orderFrontRegardless](https://developer.apple.com/documentation/appkit/nswindow/orderfrontregardless())

`accessibilityWindows()` 是全部应用窗口的公开 getter，`accessibilityChildren()` 是公开子元素 getter。临时 NSApplication 子类每次从 super 获取实时数组，仅当指定 panel 已在该数组内时移到首位。避免 `setAccessibilityWindows` 静态快照留下已经吞噬/关闭的窗口。所有非目标元素保持原有相对顺序，目标不在列表则原样返回。[Apple windows](https://developer.apple.com/documentation/appkit/nsaccessibilityprotocol/accessibilitywindows()), [Apple children](https://developer.apple.com/documentation/appkit/nsaccessibilityprotocol/accessibilitychildren())

## 第一版实际结果与第二版目的

协调方真实运行结果：验收 NSApplication 子类创建成功，AXWindows 三项从 `[49235,49238,49237]` 改为 `[49238,49235,49237]`，candidateInAXChildren/Windows 均 true；CUA 仍只显示 Screenshot 1 旧 UNKNOWN。**AX getter 排序已执行，但没有解决工具定位，不记成功。** 本代理没有自行运行该 GUI；以上为调度方提供的批次事实。

第二版保留第一版窗口置前/实时 AX getter 诊断，只在首次非空 layout 构建时，把指定 synthetic visible 资产的正常 row panel 分配提前到其他 row 之前。它不改变 layout.rows 顺序、queue/records、frame、ordinal、目标或选择行为，不关闭重建已有窗口。假说是工具偏好创建顺序；未实测前不称解决。

## 独立可应用候选（仅临时副本已构建）

已生成 [acceptance-ax-window-overlay.patch](acceptance-ax-window-overlay.patch)，在当前正式源码上 `git apply --check` 通过。只涉及 App/UI，独立于 start overlay；没有 start registry 变化。启用必须同时满足：

```text
--web-acceptance --acceptance-trace --acceptance-ax-asset UUID
```

仅接受一个 asset 参数和合法 UUID；其他启动路径继续使用普通 NSApplication。不能使用 ordinal 猜 UUID。应用首次初始化时通过 `AcceptanceAXApplication.shared` 创建候选子类，并立即校验真实类型；若已有普通 NSApplication 或创建结果不是子类，发闭集失败诊断并退出，不以“已启用”状态继续。日志含实际 class、requested asset；不能仅凭继承的 `.shared` 调用宣称子类生效。[Apple shared](https://developer.apple.com/documentation/appkit/nsapplication/shared)

UI 同时保留只读 `acceptanceExistingPanel(for:)`：要求 controller 未关闭、非 userHidden，指定 row 已存在且 panel.isVisible、record.visibility 为 visible、origin 为 synthetic；返回原 NSWindow，不创建、恢复、render 或 select。

第二版 UI init 新增默认 nil 的 `diagnosticInitialPanelID`，仅从已启用验收子类的 requestedAssetID 传入。首次非空布局且 rowWindows 尚空、目标在当前 layout 且为 synthetic visible 时，提前执行该 row 原有的 panel/view/wire 创建；正常 layout 循环仍逐项运行，预创建目标仍标 `isNew=true`，保留首次 arrival、geometry 和 ordinal 更新。未找到时不以后续新图触发重排，不移动到未显示页。其他 row 正常创建；装饰窗仍为原有结构。

App 在既有 refresh 的 render 后，仅首次找到该窗口时赋给子类的 weak preferredPanel，并调用一次 `orderFrontRegardless`。子类实时覆盖 `accessibilityWindows/Children`，只重排 super 列表中身份完全相同的 NSWindow，其他元素原顺序保留；不插入候选、不改 focused/mainWindow。若 super 返回 wrapper，则安全无效，日志 `candidateInAXWindows/Children` 为 false，不能猜测匹配。panel 关闭/隐藏后 getter 立即返回 super 顺序；没有持久化 AX 快照。

`acceptance_ax_panel_priority` 记录实际 class、assetID、windowNumber、重排前后 AX 窗口编号与元素数、候选是否在原列表、uptime，以及 initialPreferredWindowNumber/initialPreferredPanelCreated，明确 directSelection/physicalInputClaim/uploadStartGrant 均为 false。日志只在启动与首次分配时各一次，getter 内不记录、不轮询。无新增 await、DB 查询、定时器、Chrome 操作或输入动作；缺失/不可见 asset 不自动替换为其他图。Swift 覆盖签名已通过下述临时副本编译；尚未证明 CUA 采用这些数组。

## 验证与退出条件

使用独立临时 App 副本、现有隔离 synthetic 库；**不要应用含 start grant 的 overlay 来测试窗口定位**。运行后先读 CUA 是否出现指定已有窗口与正确序号，再由正常 CUA 操作点击/AXPress，日志按真实输入分支分类。必须比对其他窗口仍可枚举、旧 UNKNOWN/操作/附件不变、前台 Chrome session 不变、未点击时没有 append，随后确认实际目标图身份。

这仍不能保证 CUA 使用 accessibilityWindows/Children；若它固定采用 CGWindow 创建顺序，两个 getter 重排可能无效，不能继续宣称修好。若仍无效，禁止继续重建已存在 row、隐藏其他窗口、改几何或触发 select。撤回临时副本/不带 flags 启动正式 App 即恢复原路径。正式工作树仅保存 patch 和报告，没有 AX 查询或软件点击证据。

## 临时编译记录

按协调授权，在 `/tmp/riftlet-round5-ax-build`（由调度方用 `git archive 1f9dec2dec9cf6ef61f36776a6e4f7c3439f4f8a` 准备）执行该独立 patch 的 `git apply --check`、`git apply`，随后 `swift build --product Riftlet`，退出码 0，22.43 秒。构建含既有 CLT 链接路径/pkg-config、FolderWatcher capture 和 filePromise 废弃警告；没有为这些警告修改源。此副本**只应用 AX window overlay，不包含 start grant**。未启动生成的二进制，未创建应用窗口；实际 class 诊断与 CUA 定位结果仍待独立运行验收。正式工作树 Core/UI/App 保持不变。

第二版临时编译：在同一 `/tmp/riftlet-round5-ax-build` 精确反向撤销第一版 patch，再应用本文件所链第二版 patch；`swift build --product Riftlet` 退出码 0，22.42 秒。未启动第二版 App。正式源码仍未修改；第二版的工具定位效果仍 NOT_RUN，第一版 getter 重排未解决 CUA 的事实不被覆盖。

## 停止排序方向；改用既有 helper 的精确 AXPress

协调方报告第二版运行仍只有 CUA Screenshot 1；以真实 windowNumber 49281 调用工具 windowId 入口，工具明确不支持 macOS。故第一版 AX 顺序与第二版初始创建顺序均未解决定位问题，停止继续重排/重建方向；不伪造 focused/main AX。旧 v2 App 已由协调方正常 SIGTERM 停止，无新操作/上传。本代理未操作这些 GUI。

当前替代仅扩展现有 `RiftletGUIAcceptance`（没有新增独立工具）：

```text
RiftletGUIAcceptance --press-acceptance-asset UUID --app-pid PID --app-path /exact/Riftlet.app
```

`AcceptanceMain.swift` 在 GUI 启动前分流；`AcceptanceAXPress.swift` 使用既有 `AXIsProcessTrusted` 权限，不申请权限。核对实际 PID 的 bundle ID 为 com.riftlet.app、NSRunningApplication.bundleURL/executableURL、指定 Bundle 的 executableURL，以及 proc_pidpath 的真实可执行路径完全一致；执行前重新核对必需内核出生时间防 PID 复用（后续修正，launchDate 仅作诊断）。路径须为指定 .app 内 Contents/MacOS 的真实 executable。

沿 AXWindows/Children 有界遍历（搜索期限 4 秒、每消息 100ms、512 个唯一节点、深度 12、每属性最多 256 子项），任何查询失败或上限使唯一性无法证实即拒绝。只接受唯一、同 PID、enabled 的 AXButton，identifier 必须精确等于 `riftlet-synthetic-UUID`，且有 AXPress action。发送前复核进程、按钮与前台 PID；仅 AXPress 一次，不激活、发键、capture target 或调用 transfer.select，不重试。AX action 返回错误标 `pressOutcomeUnknown`，不能推断未输入；success 仅表示 AXPress 返回成功，不证明附件上传。

日志为有界字段 JSON：source=helperAX、physical=false、before/after foregroundPID、assetID、PID、actionUptime、AX 返回码和闭集结果/拒绝原因；不记录窗口标题、URL、聊天、路径或截图。调用若拒绝，axActionAttempted=false。

[acceptance-synthetic-identifier-overlay.patch](acceptance-synthetic-identifier-overlay.patch) 仅覆写 row 的 `accessibilityIdentifier()`：record 为 synthetic、visibility 为 visible 且 window.isVisible 时返回精确标识，其他状态返回空串（Swift SDK 此方法为非 optional String，不能返回 nil），不改 App、窗口、geometry、record、队列或 start registry。取代旧排序 overlay，**不可叠加旧排序补丁来声称普通 App 行为**；不改变按钮原有 onAccessiblePress→freeze→onSelect 路径。

编译来源明确分开：主工作树（正式 Core/UI/App 零改动）构建新 helper，`swift build --product RiftletGUIAcceptance` 成功，32.87 秒；首次遇到 Swift 不导入 PROC_PIDPATHINFO_MAXSIZE 复合宏，按当前 SDK 定义改用 `4 * Int(MAXPATHLEN)` 后通过。另在协调方提供的干净 `/tmp/riftlet-round5-identified-build`（git archive 精确 1f9dec2）只应用 identifier patch，`swift build --product Riftlet` 成功，35.11 秒，无 AX 子类/排序/start grant。未启动 App、未运行 helper 动作；等待独立审查后由协调方执行。成功编译不代表真实按钮定位或附件验收。

独立审查后的收紧：发送前先记录原 AXWindow，再复核同一窗口 CFEqual、同 PID、仍在应用当前 AXWindows 且 AXMinimized=false；随后再次核对按钮动态 identifier/role/enabled/action。动作后如 foreground PID 改变，保留 attempted=true 与原 AX 返回码，将结果标 `pressOutcomeUnknownForegroundChanged`、退出码 2，绝不重试。App identifier 从静态 setter 改为上述可见性约束的动态 getter，关闭/隐藏/吞噬后不再暴露可匹配标识；第一次 optional String 版本被 SDK 拒绝编译，改用空串保持拒绝语义。此前静态 identifier 产物与 hash 已被替代，不用于执行。

前一收紧版 Release 编译（helper 后被下述 kernel-identity 版本替代）：helper 3.52 秒 exit 0；identifier-only App 打包 26.58 秒 exit 0，ad-hoc 签名 strict 验证通过。日志分别 `/tmp/riftlet-round5-helper-release.log`、`/tmp/riftlet-round5-identified-package.log`（包含本地构建路径，不作为公开日志上传）。最终 SHA256：helper `3bdcee978b125f0e176d67c5633f364f68923b41f009b48cc6ce6e67c3a98c74`；App executable `7a27e4932538188e90563abbd14ae4786da027151c7f5b91eba027604d83bed9`；identifier patch `1a15d349a5a11704de7d2063502df1fe6f7c9206bd1cee548e01a2544fd673ec`。本代理未启动产物或执行 AXPress；运行结果仍待独立验收。


身份观测修正：协调方实际 App PID 9771 的首次 helper 调用立即 `refused/applicationMismatch`，axActionAttempted=false，前后台 PID 均为 59763，没有输入。随后本代理只读核对 NSRunningApplication/Bundle/proc_pidpath：所有 bundle、可执行路径校验为 true，唯一缺项是 `NSRunningApplication.launchDate` 为 nil。另只读 `proc_pidinfo(PROC_PIDTBSDINFO)` 精确返回完整 struct、PID 匹配、出生秒/微秒有效，连续两次相同。未执行 AXPress。

没有删除进程出生身份条件；改为必需 `ProcessIdentity(pid, pbi_start_tvsec, pbi_start_tvusec)`。初次识别与发送前分别要求 proc_pidinfo 返回精确 MemoryLayout 大小、PID 一致、秒数大于 0、微秒小于 1,000,000，再要求两次 ProcessIdentity 完全相同。原 bundle/path/proc_pidpath 条件全部保留，launchDate 只记录可用性。新增闭集 identityPhase、identityChecks（14 个布尔项）、identityFailureStage 和 processIdentityStable；不输出路径或进程起始时间原值。

当前可审查 helper Release：9.44 秒 exit 0，SHA256 `3e12d98f6fe7e911f22b8f4d62ae36244dd7fcbd7549da077fde09ee21bf10b4`，替代上述旧 helper hash。App 与动态 identifier patch hash 不变。只完成编译，等待独立审查后的单次调用；本代理没有执行任何 AXPress。

## Pro AX 可用性发现与最新候选

随后协调方对零 asset 做负例，得到 noMatch/axActionAttempted=false；实际 asset 一次调用得到 invalidButton/axActionAttempted=false，仍没有 AXPress。只读完整遍历 PID 9771 的唯一匹配按钮显示：identifier 精确、AXButton、同 PID、AXPress action 均成立；AXWindow 存在且同 PID、在当前 AXWindows、AXMinimized 成功返回 false。**实际缺失项是 AXEnabled 返回 attributeUnsupported(-25205)，不是最小化属性缺省。** 原产品 row 是自定义 NSView，虽声明按钮角色和动作，却没有有效 enabled 元数据。此项为真实 AX 接口发现，应交 Pro 评估正式无障碍接线；不改变本轮窗口穿透或物理点击结论。

按协调授权，临时 identifier overlay 追加 `isAccessibilityEnabled()`：synthetic row 仅在 record.visible、window.isVisible 且 status 属于 pending/failed/unknown/missing 时返回 true，其他 synthetic 返回 false；非 synthetic 调用 super。原 onAccessiblePress 的 hold/transition/selection 等全部 guard 保留。helper 仍要求明确 enabled=true，未将 unsupported/nil 放行。helper 新增闭集 `attributeErrors`、`buttonChecks/buttonFailureStage`、`windowChecks/windowFailureStage`，只输出 AX 返回码和布尔，不输出标题、文本或路径。

**最新产物替代以上旧 hash**：helper Release `bd2022b53790e9182e7b2a7e36c9a63c8fd65a69abedf7d6b25b6c669070238e`（4.31 秒）；identifier+enabled-only App executable `f0423edc2ec06deb60799630b66cda373af442bd679b284b954ce475d0f0fc71`（打包9.98秒，strict签名验证通过）；patch `d9638001fc0afb8bfbc13ad9b9f36a66ebc8289121c71b07d75058fd7b3ca7f0`。仍无排序子类或 start grant，正式 Core/UI/App 未修改。必须由协调方正常停止旧 PID 并运行新包后再观察；本代理只读诊断、编译、打包，未启动产物、未执行 AXPress。
