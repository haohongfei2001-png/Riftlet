# 登录启动：当前实现与真实系统闭环

2026-11-07，基线 `2e779f646ac4874344fac94f79103e8ddf9b02c8`。当前安装包只读核验为 Personal Beta 3 `0.3.0 (3)`，ARM64，二进制 SHA-256 `fe5b09c4146a363e45685f8441d081fbd62a3238ed83b115287882b9158e29f3`。严格签名验证通过，签名仍为 ad-hoc；这不是公证或公开发行验收。

本专项没有发现新的 owner 缺陷，没有修改产品源码或正式登录项。PR44 已修复的真实问题是：旧 owner 和设置开关把 `notFound` 当作开启前的永久否决，根本没有调用系统注册。现有代码仅在用户明确开启时尝试一次 `register()`，随后以实际状态和 NSError 为准。原始生产系统为何最初返回 `notFound`，仍没有足够证据归因于签名、安装位置或启动方式。[原始失败与修复证据](../../beta2-real-acceptance-20261107/README.md) 保留不变。

本页是当前状态说明，补充历史 [WP07 backend 文档](../../../docs/SETTINGS_LOGIN_BACKEND.md) 中“尚未接入 Main”及“notFound 暂不注册”的旧实现描述；不改写该文档当时的测试事实。目前 Main 的 SettingsProductHost 已接入 owner，设置页允许从 `notFound` 发起明确开启。没有本地 `enabled` 布尔值、自动注册、LaunchAgent 或 `LSRegisterURL` 修补路径。

## 新增实际证据

[完整脱敏记录](lifecycle-evidence.json) 绑定当前 owner 原始字节、编译结果、独立测试 App 身份和七份原始报告。仅测试 App 自己的 `SMAppService.mainApp` 被调用，采用唯一新 bundle ID；实际 owner 原文件直接编译，使用专用真实 ServiceManagement adapter 注入。未调用产品 live factory，也未把这个小程序当作完整 Riftlet 主进程。

| 操作 | 实际状态 / 调用次数 |
| --- | --- |
| 第一次启动，只读查询 | `notFound`；自身 LaunchServices URL 列表为空；零注册/注销 |
| 明确开启，然后再次明确选择同目标 | `enabled`；register 共 1 次，第二次不重注册 |
| 退出后启动新进程，只读查询 | `enabled`；零注册/注销 |
| 同路径仅将测试 App build 从 1 改为 2 并重新 ad-hoc 签名，再启动新进程 | `enabled`；严格签名通过，零重注册 |
| 明确关闭，然后再次明确选择同目标 | `notRegistered`；异步 unregister 共 1 次，第二次不重复注销 |
| 再启动新进程，只读查询 | `notRegistered`；零注册/注销 |
| 最后专用清理检查 | 已是 `notRegistered`，没有额外注销；七个进程均退出 |

所有实际注册/注销 NSError 均为空。测试程序没有创建窗口、调用应用激活或打开系统设置；每个进程的前后前台 PID 采样一致，这只证明这些采样点，并非持续全局事件监测。正式 App 的二进制没有变化，没有访问生产数据库、媒体或权限设置。

## 系统契约与结论边界

Apple 将 [`mainApp`](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp) 定义为调用方主应用的登录项服务；因此不能从另一个探针查询它自身的结果，冒充正式 Riftlet 的当前状态。[`notFound`](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum/notfound) 表示查找服务发生错误，不等于禁止明确注册。当前系统上的受控实测已证实这一点。

Apple 的 [`register()`](https://developer.apple.com/documentation/servicemanagement/smappservice/register()) 文档区分主 App 的后续登录启动与 helper 的立即启动；[`unregister()`](https://developer.apple.com/documentation/servicemanagement/smappservice/unregister()) 不会退出正在运行的主 App。真实 owner 等待异步注销完成再读回状态。SDK 要求使用 SMAppService 的 App 具有代码签名；本次 ad-hoc 主 App 成功不替代 Developer ID、公证或 Gatekeeper 的分发要求。

本轮证明的是当前 macOS 27.0 / ARM64 上独立主 App 的注册、进程重启读回、同路径版本重签读回、注销及清理。尚未执行正式 Riftlet 登录项注册、注销账户再登录或重启电脑、真实用户拒绝/撤销再恢复、其他 macOS 版本。这些结果不可标记为自动登录实际启动通过，也不可借用 fake service 测试填补。

## 复验入口

原始 probe 源码、逐阶段报告及 `run-lifecycle.py` 保留在本次私有 productization/login 证据包；本页 JSON 逐项绑定 basename 和 SHA-256，不公开个人路径、PID 或系统窗口信息。每次新的实测必须生成新的唯一 bundle ID、先证明没有既有注册，仅允许清理自身，并由唯一 GUI 负责人串行安排可能出现的系统通知。不得对 `com.riftlet.app` 套用该探针，不得靠复制路径执行旧 runner。

当前 owner 的 23 个 XCTest 定义未改动。本地本次实际编译并运行了上述原生 ServiceManagement 探针；没有重跑完整 XCTest，也没有新增产品行为需要用重复构建补证。下一有价值工作是独立高分辨率性能验证，而不是继续重写已经修复的登录状态层。
