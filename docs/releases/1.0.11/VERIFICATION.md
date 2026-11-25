# Riftlet 1.0.11（66）验收记录

2026-11-25，候选状态为 **PARTIAL**。用户仍可从官网和 Sparkle 稳定源取得 1.0.10（65）。1.0.11 的仓库找回修复已合并，实站无目标恢复还有可见失败。[产品 PR #134](https://github.com/haohongfei2001-png/Riftlet/pull/134) · [当前正式发行](https://github.com/haohongfei2001-png/Riftlet/releases/latest)

## 本地仓库找回

在 1.0.10 的隔离 SQLite 库中，点过且没有附加目标的第 1 张截图被 20 张更新截图挤出最近列表。原 PNG 字节仍在，完整仓库能找到该图，重新启动后按钮和底层恢复调用仍拒绝它。当时 21 张截图均没有附加操作。

使用同一批旧数据打开修复版，真实 AppKit 仓库按钮向回调交付了一次正确的截图 UUID。恢复只改变本地可见性，文件输入和新操作均为零。重新主动点选才产生新操作和一次输入。点击尚在处理中、已有历史操作但活动指针为空、缺失或已清理的图片均被拒绝。5 份旧工程档案逐字节保留。[独立源码复核及用例](https://github.com/haohongfei2001-png/Riftlet/pull/134) · [工程入口核销](https://github.com/haohongfei2001-png/Riftlet/issues/91)

## 真实 ChatGPT Temporary Chat

测试使用正式签名 App、独立截图库、普通 Chrome 和 Edge 已登录的专用草稿。图片是 macOS 对专用测试窗口的真实截图。通过软件生成的 AppKit 鼠标事件点选经核验的 Riftlet 行。原窗口、标签、文档、编辑器、文件输入和附件卡分别取证。

| 场景 | Chrome | Edge |
|---|---|---|
| 单张截图 | 一组通过，另一组在写入文件前失败 | 通过 |
| 连续两张，保留正文和旧附件 | 通过 | NOT_RUN |
| 最近历史中主动重新附加 | 通过 | NOT_RUN |
| 无目标点击，再回到草稿从历史点选 | 复现输入前失败 | 复现输入前失败。另一次出现新卡，已记录一次 input/change，逐卡像素及 START 未获证实 |
| 发送、提交和重复输入 | 完整取证的单图及双图／重选场景均为零 | 完整取证的单图场景均为零 |

Chrome 双图及重选在同一个草稿内取得四组匹配结果，包含先置入的附件。每次有效输入均有一次用户点选、一个操作和 invocation、一份 PNG 对应的网页原卡像素及一个最终持久化 START。第二张的 START 晚于网页确认。关闭后的数据库复核确认四份 START，原正文和原卡保留。

两款浏览器的无目标恢复失败均发生在第二次主动点选。原草稿先显示四个禁用文件字段，随后显示四个启用字段。附件入口从折叠变为展开，产品未取得可归属的选择器，因 `pickerNotInvoked` 结束。两组网页输入、发送及表单提交均为零。Edge 的一次记录可确认准备凭据早于字段启用，实际点选晚于启用。该次观察没有记录字段的 DOM 对象身份，尚不能判断启用时是否发生替换。Edge 双图与已成功截图的历史重选未取得可核验的实际点选。部分尝试遇到前台切换，另一次在用户正在使用桌面时止于创建测试窗口之前。两个浏览器都完成了专用窗口清理。最新回执包含逐组分类。[实站结果摘要](https://github.com/haohongfei2001-png/Riftlet/pull/134#issuecomment-7153415408)

## 安装和发行

产品源码为 `6c0af660a8738c673b85155c3169441c524511d7`，主线合并为 `28d1df45945b425c1961c8a0c0cf9aea340c17bd`。PR 和 main 的五项正式检查均通过。初次 PR Intel 作业在取得 Sparkle 依赖时中断，单独重跑后通过。[主线原生双架构检查](https://github.com/haohongfei2001-png/Riftlet/actions/runs/45550029047) · [主线反馈检查](https://github.com/haohongfei2001-png/Riftlet/actions/runs/45550029051)

通用 DMG 为 13,944,941 字节，SHA-256 为 `08fe6b2c70ef97fcb9882c22dcba0e847564afb83c7794f227b456b136eae0db`。App 和 DMG 均通过 Developer ID 验签、Apple 公证和 staple。独立安装至私有测试目录后，Gatekeeper 及四项包内自检通过。

65→66 公开应用内升级为 **NOT_RUN**。在独立 Intel Mac 上，正式 65 的可见控件已打开 Sparkle 当前版本弹窗。另已建立含原图、非默认设置及有回执的旧 UNKNOWN 操作的隔离库，供实际升级比较。该旧操作由 65 源码的 QueueStore API 生成。[65 更新预检运行](https://github.com/haohongfei2001-png/Riftlet/actions/runs/45546677981)
