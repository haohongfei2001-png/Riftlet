# 系统截图自包含：公开 API 核查

核查日期：2026-10-27。性质：官方文档与既有证据复核；**本轮没有启动截图、操作 GUI 或验证新实现，运行验收状态为 NOT_RUN。**

结论：未找到可让仍显示在屏幕上的任意 Riftlet AppKit 窗口，对系统 Screenshot.app 及所有既有截图入口可靠自我排除的公开平台保证。不能将自有捕获流的过滤能力当作系统截图保证；本次没有发现值得据此启动新排除方案实测的公开接口。

## 平台依据与边界

| 路径 | 官方文档与判断 |
| --- | --- |
| `NSWindow.SharingType.none` | Apple 当前文档称其为 macOS 不再使用的遗留常量，并明确不应用来隐藏或排除捕获内容。本机 SDK 头文件仍有较旧的禁止跨进程读取描述，这不构成当前系统截图的可靠契约。[Apple 文档](https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum/none) |
| `SCContentFilter` | 过滤的是使用该 filter 的 `SCStream` 输出；支持排除窗口或应用。由此不能推导 Riftlet 能改写另一个捕获方 Screenshot.app 的规则。[Apple 文档](https://developer.apple.com/documentation/screencapturekit/sccontentfilter) |
| 自有 ScreenCaptureKit 捕获 | Apple 示例可在自己创建的捕获流中按 bundle ID 排除自身。这是自有捕获方案，不满足“不替换用户系统截图入口”前提下的通用自排除保证。[Apple 示例](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos) |
| 主动隐藏窗口 | `orderOut(_:)` 从屏幕窗口列表移除窗口而不释放对象，提供公开隐藏机制；文档还说明可能有默认动画。它不提供系统截图即将取像的先行通知或跨进程捕获同步屏障，不能据此宣称快捷键监听后临时隐藏必然来得及。[Apple 文档](https://developer.apple.com/documentation/appkit/nswindow/orderout(_:)) |

上述“未找到保证”是本次所查公开接口的范围结论，不是对所有未来 macOS 版本作不可实现证明。`.none` 文档提到 FairPlay Streaming，但这不是任意 Riftlet AppKit 界面的公开窗口排除接口；本次不提出 DRM 包装方案。也未把 iOS 开发者论坛关于截图保护的答复套用为 macOS 结论。

## 既有失败与 PR #4 契约

- 第三轮 [README](../2026-10-27-real-mac-round3/README.md) 已记 **FAIL**：只有实际 App、没有 helper 的系统区域截图中出现原五张 Riftlet 微图。[资源记录](../2026-10-27-real-mac-round3/capture-resources.json) 将来源限定为一次系统 CLI 区域截图，源 SHA 为 `159b3ef3e6c87ea468ba334dff64ad8db640d80c`。这是旧版本的范围性运行证据，不是本轮 Screenshot.app 交互、物理快捷键或全入口矩阵的新测试；资源测量 PASS 也不覆盖自排除。
- 本次通过 `git show 90a04883160032fc6354fb4f3d3f7d56fede2947:<path>` 阅读该提交中的 `docs/RELEASE_UX_REQUIREMENTS_2026-10-27.md`（R04）及 `docs/PRO_FEASIBILITY_REVIEW_FINDINGS_2026-10-27.md`（第 4 节）。前者保留系统截图习惯，禁止无依据的全入口保证、严重竞态拦截、偷偷修改原截图；后者提出持久主动隐藏作为低风险退路，不把研究结论标成实测 PASS。

后续最小方向仍是由产品负责人实现并验收持久 `userHidden`：全部微图和装饰一起隐藏，收录与旧操作观察继续，新图、动画回调、重排、唤醒和重启不得自动解除；只有明确用户意图恢复。需要无干扰画面时先隐藏有人工成本，不等价于原两步体验。自动暂隐仅可另立有界实验。后续实测须按来源隔离，并覆盖系统入口、动画完成时序和重新显示条件；本报告不证明这些实现已经存在或通过。
