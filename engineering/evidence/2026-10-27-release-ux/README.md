# 首次使用与发行基础体验：实际工程交付

2026-10-27（北京时间）。正式起点 `e89d49f763036781c90618422da256e03cbca2ac`；实现 `4e080aaaf995708f15334011ec3a012fcd968944`；编译修复与已测源码 **`2449d40a88225acba9d413cc6a4cb5d84fcae6a1`**。本目录所在的后续检查点只更新文档与证据，源码、测试及构建输入不变。确切正式 HEAD 见 [Draft PR #1](https://github.com/haohongfei2001-png/Riftlet/pull/1) 的本轮交接记录。

## 已经实现

| 实现 | 代码入口 | 可观察行为 |
| --- | --- | --- |
| 原生首次使用与运行状态 | `Sources/RiftletUI/RiftSetupController.swift`、`SetupPresentation.swift`；App `FirstUsePreferences.swift`、`ProductStatus.swift`、`RiftletMain.swift` | 普通模式首次展示、以后菜单重开；实际来源/访问/收录/隐藏/空队列/待核实/能力分别说明；背景更新不重开、不弹成功通知 |
| 最小权限恢复 | App `AutomationPermission.swift`、`RiftletMain.swift` | 普通模式不访问 Chrome；Web 验收模式先被动检查，明确设置动作才请求；拒绝有系统设置入口；文件夹授权只接受系统实际截图位置 |
| 暂停与重新检查互斥 | App `CaptureControlGate.swift` | 重检不能覆盖较新的暂停意图；旧 token 不能解除新操作；隐藏/历史独立；持久写入失败有持续、准确的重启提示 |
| Capture 诊断与恢复 | `Sources/RiftletCapture/CaptureDiagnostics.swift`、`CaptureService.swift`、`CaptureSourceBinding.swift` | 未检查不等于拒绝；旧目录成功不能替新目录证明权限；旧代际回调不能停止或覆盖新代际；偏好读取拒绝不静默回退桌面 |
| 字节保真与空间保护 | Capture `FileValidation.swift`、`PrivateAssetImporter.swift`、`StorageCapacity.swift` | 单帧 PNG/JPEG/HEIC/HEIF/TIFF 原字节/方向/颜色元数据保留；新复制前检查文件大小加 4 MiB 工程余量；既有 journal 恢复不被该预检阻止 |
| 开发 App 打包 | `Resources/Info.plist`、`scripts/build-macos.sh`、`scripts/verify-app-bundle.py` | 显示名 Riftlet；用途说明；新 staging 验证资源/许可/布局后签名和替换生成制品；保留旧制品的失败恢复；不是公开签名安装包 |

没有增加第三方运行时依赖。Core、SQLite v3、Web/Chrome 源码与测试、上传开始契约、原第四轮证据、research、网站与设计的 12 组 Git 对象相对起点完全相同，清单在 [verification.json](verification.json)。没有清理 UNKNOWN、补偿、媒体、原件或远端附件。

## 实际 macOS CI

[run 40508109228](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40508109228) / job `122202566296`，GitHub 记录 completed/success 于 **2026-10-27 21:00:40 北京时间**。环境 macOS 14.8.9（23J631）、ARM64、Apple Swift 5.10。root 与非作者分别取得实际元数据和完整日志核对。

| 项目 | 实际结果 |
| --- | --- |
| 原生测试 | **344** 个唯一测试名：Core 117 / Adapters 102 / Capture 63 / UI 48 / App 14 |
| 新增原生用例 | 38：Capture 15 / UI 9 / App 14，已包含在 344 内 |
| 生命周期详细复跑 | 13 passed / 0 skipped，已包含在 344 内 |
| 首次使用窗口详细复跑 | 3 passed / 0 skipped，已包含在 344 内；软件 AppKit 测试 |
| 新 Capture 详细复跑 | 15 passed / 0 skipped；HEIC 编码与受控 POSIX 拒绝均明确执行通过 |
| 包装拒绝路径 | Python 12/12；Linux 与 macOS 实际执行 |
| 当前页面 / 旧版只读页面 VM | 48 / 14 |
| 原归档回放 | 55 文件 / 19 用例 / 89 trace 前缀 / 2 个明确 SIMULATED 迟到错误 |
| 故障工具 / 只读 probe 离线用例 | 8 / 12 |
| Release、bundle 与 ad-hoc 签名检查 | PASS |
| 打包 App/helper 自检 | 原持久状态、Web 资源隔离、新首次使用、GUI helper 四项 PASS |

实际临时 CI checkout 是 `f3531dfc6143bdf95816c8d77ff17af3fb8cf2c8`，父为实际 main `eba1a4fc77648a665e1d5c1f2609df1314c3b079` 和已测源码 `2449d40a…`。逐项比对 12 组源码/测试/资源/构建/回放输入相同。PR 元数据中的旧 base SHA 不能替代实际 checkout。没有合并或更新 main。

自检明确保留 `PERMISSIONS_NOT_REQUESTED`、`CHROME_NOT_RUN`、`GUI_NOT_RUN`、`GATEKEEPER_NOT_RUN`。旧 `filePromise` 弃用警告不阻断构建；HEIC 日志的 scaler 消息之后有明确 passed 行，不能由此推断真实 HDR 显示。完整测试名与环境见 [verification.json](verification.json)，实际原日志摘录见 [ci-excerpt.txt](ci-excerpt.txt)。

## 可运行制品与普通用户入口

[下载本次 development App、GUI helper 和日志](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40508109228/artifacts/12735493443)。制品 `12735493443`，1,585,247 bytes，GitHub SHA-256：

```text
edb3bf6742907d35bdbbf37e260c65a13839067f41e280ac439027873e7a9412
```

保留至 **2026-11-10 21:00:36 北京时间**。解压后在 Mac 打开 `Riftlet.app`，即可进入首次使用窗口；基础设置通过原生按钮和菜单操作，不需配置文件或终端。菜单「打开离线合成演示」使用独立数据根，观察快吞噬、成功、重生和 UNKNOWN；不读真实截图、不连 ChatGPT。工程模式命令、自检入口和权限验收表见 [FIRST_USE_ACCEPTANCE](../../../docs/FIRST_USE_ACCEPTANCE.md)。

这是 ARM64、ad-hoc 签名的开发制品，尚未做 Developer ID、公证或 Gatekeeper 首装验收，不声称普通用户公开安装已经通过。最低 macOS 13 是构建目标；不能把 macOS 14 CI 扩大为所有支持版本的实测。

## 首轮失败、修复和非作者审查

实现提交 `4e080aa…` 的 [首次 CI 40507790526](https://github.com/haohongfei2001-png/Riftlet/actions/runs/40507790526) 在 `ReleaseCaptureTests.swift` 两处第二个 XCTest 自动闭包缺少 `try` 而编译失败；原生测试 **NOT_RUN**，后续包装、Release、自检 **SKIPPED**。`2449d40a…` 只增加这两个 `try`，没有改变运行时逻辑、断言预期或准入，然后完整重跑通过。首轮 7,814-byte 制品只是日志，不是可运行 App。

实际并发为 root 加三个独立实现/审查执行者；root 编写 App、权限/互斥接线、测试及构建集成。Capture、UI、打包各有互斥写入者，并交叉审查。已修复真实审查发现的来源与权限混淆、过期回调覆盖、暂停/重检竞态、恢复 latch 顺序、PID 身份复核、持久失败提示丢失及构建恢复问题。首轮编译遗漏及静态审查漏检如实保留。[review.json](review.json) 记录作者、非作者、修复和独立日志核验；这不是人类 GitHub 批准或合并。

## 与本地 Codex 的合流边界

- 继续独占 Web/Chrome 页面、观察、`uploadStarted` 证据、归一化和早返回；[UPLOAD_STARTED_CONTRACT_V1](../../../docs/UPLOAD_STARTED_CONTRACT_V1.md) 字节不变。本包未声称新增真实上传或失败证据。
- App 在 arm、点击和后台观察前新增被动 Automation 检查，原事件冻结的完整 lease 不换目标、不重捕获、不回放拒绝点击。检查耗时必须计入下一次实际点击延迟测量，旧 callback 时延不能直接引用为新路径性能。
- Web 验收模式不自动弹首次窗口；明确从菜单进入。OS Automation 与 Chrome JavaScript 开关分开；授权不启用生产能力。恢复本地操作不以浏览器权限为条件，后续只读观察在权限可用后继续。
- 不删除或降级 v3 数据/UNKNOWN/补偿。正式分支仅快进提交；正在运行的本地验收无需中断，由集成负责人审查合流共享 App 差异。

## 保留 NOT_RUN / 未准入

真实 TCC 拒绝/恢复、文件夹选择与书签重启、Finder 首次启动、实际键盘/VoiceOver/多屏/减少动态效果、真实 HDR/EXIF 命中、实际空间压力、权限查询增加的真实点击时延均 **NOT_RUN**。受控 POSIX 拒绝不是 TCC 验收，软件窗口测试不是物理 GUI 验收。

真实 Web 开始、冷首击、业务 ABA、原正文/附件/选区、MID、物理 GUI、自包含和系统截图两操作闭环仍在本地 Codex 原任务中。普通模式 `UnavailableAdapter`；生产上传、开始吞噬和安全重试注册表保持关闭；Mac 客户端未启用；无发布、无 main 合并、无自动发消息。
