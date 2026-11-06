# WP07：登录启动的系统状态 owner

本增量按设置设计 revision-2 `IMPLEMENTATION-HANDOFF.md` §5.5 增加 `LoginItemPreferences`，尚未接入 Main、现有设置窗口或启动流程。当前已安装 App 与系统登录项没有变化。它与布局草稿、暂停/隐藏、截图入口偏好各自独立。

## 唯一状态来源

使用 `ServiceManagement.SMAppService.mainApp`，不保存 `launchAtLogin`/`enabled` 布尔值，不创建 LaunchAgent、helper 或定时任务。最低 macOS 13 与现有 Package 一致。[Apple 的 SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice) 支持主 App 的登录项注册与系统状态查询。

| 系统状态 | 派生开关 | 是否已允许登录启动 | 显式命令 |
| --- | --- | --- | --- |
| notRegistered | 关 | 否 | 开启调用一次 register；再次关闭不调用 |
| enabled | 开 | 是 | 关闭等待 unregister 完成；再次开启不调用 |
| requiresApproval | 请求为开 | 否，等待系统设置批准 | 再次开启不重新注册；关闭注销已有请求 |
| notFound / unknown | 无法确认，不伪造开关值 | 无法确认 | 暂不注册/注销，允许读取重查 |

`requiresApproval` 是已有注册请求但尚不可运行，也可能由系统撤销许可产生，不能显示为已生效成功或普通保存失败。[Apple 的状态定义](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum/requiresapproval) 是该区分的依据。

`snapshot.status` 始终是当前系统读回；`lastCommand` 是最近一次明确命令的历史结果，二者不可混用。临时的目标值仅用于正在进行的命令或错误结果，没有磁盘偏好副本。进入设置页、应用重新激活时可调用 `refresh()`；它不注册、不重试、不打开系统设置，也不清掉尚需显示的上次调用错误。

## 命令与真实结果

只有 `setEnabled(target)` 发起注册/注销，调用前先重新查询系统状态，避免用旧 UI 快照重复注册。同一目标已满足则不重复调用；待批准请求再次开启也不注册。执行期间只有这个 owner 报 busy；同向或反向重复请求不会排队、自动重试或影响其他设置 owner。

真实 adapter 的 register 使用系统同步 throwing 接口；unregister 显式包装 `unregister(completionHandler:)` 并 await completion，没有误用同名同步重载。本机 SDK `SMAppService.h` 说明 completion 在后台 dispatch 队列返回；checked continuation 将后续状态处理恢复到 MainActor。[Apple 的注销语义](https://developer.apple.com/documentation/servicemanagement/smappservice/unregister%28%29) 明确注销主 App 不会退出当前运行的主 App。

正常返回或 throw 后都重新读取 status。结果分开提供当前状态、disposition、调用错误码：

- enabled/notRegistered 与目标一致时，记录该实际终态；若系统调用仍报错，保留错误，`isSuccessful=false`，不假装回滚。
- requiresApproval 与开启目标对应时始终是 awaitingApproval，`isSuccessful=false`；系统调用错误若存在仍另行保留。
- 正常返回但未达到目标也只是 notConfirmed；notFound/unknown 是 unavailable。没有从“没 throw”推断成功。
- 错误只保留 NSError code，不保存可能包含路径的 localizedDescription/userInfo。重试仍必须由新的明确 set 命令发起，并重新核对当前系统状态。

`openSystemSettings()` 只供将来的专门按钮调用；方法返回 true 仅表示发出了打开动作，不代表用户批准。任何读取、初始化、注册结果或重新激活路径都不会自动调用它。

## 隔离与接线边界

具体系统 adapter 是文件内私有类型，只由 `live(mode:)` 工厂建立。工厂读取实际 Bundle、启动参数、现有 `ApplicationMode`、内部验收编译标记及 XCTest 进程事实；仅普通 capture 模式、非内部验收、非测试、`com.riftlet.app` 的 APPL `.app` 与其真实 `Contents/MacOS/Riftlet` 可建立该 adapter。不要求新的付费签名配置或搬到特定目录；系统负责验证应用签名和注册资格，失败由上面的真实回读表达。

模拟、Web 验收、系统截图候选、内部普通验收、self-check、测试进程或未打包 CLI 均保留不可用原因，连系统 status 都不读取。测试的 `LoginItemService` 注入不创建具体系统 adapter；不可用上下文会丢弃注入服务，不读取也不调用。

后续 Main 接线仍应只在用户明确开关时调用 set，进入页面/重新激活只调用 refresh；对待批准状态提供明确说明与专门设置按钮。不能把该 owner 的结果写进几何配置，不能随启动替用户重新注册。

## 验证范围

新增 20 项 XCTest 使用 fake service，覆盖状态映射、只读刷新、同目标幂等、批准待定/取消、正常返回未达到目标、注册/注销 throw 前后不同实际状态、外部状态变化、延迟 completion、忙期间不排队、模式/包身份隔离及显式设置按钮。延迟测试用 continuation 和有限时间 expectation；所有可执行注册、注销和打开动作均为 fake。

本地独立 scratch 的 `swift build --build-system native --target RiftletApp` 已通过（31.83 秒），包含真实 ServiceManagement adapter 编译；测试文件的 Swift parser 检查通过，仅证明语法可解析。本机 CLT 缺少 XCTest，XCTest 编译/执行本地 **NOT_RUN**，须由后续 macOS CI 完成。

本轮禁止并且未执行任何真实 register、unregister 或打开系统登录项设置。真实已打包身份的系统批准、注销、重新登录启动及升级行为仍为 **NOT_RUN**，不能用 fake enabled 代替。编译没有启动 App 或调用该服务。
