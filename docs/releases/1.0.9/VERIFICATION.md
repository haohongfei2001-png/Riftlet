# Riftlet 1.0.9（build 64）验收记录

正式通用安装包包含 Apple 芯片和 Intel 两种架构，大小为 **13,858,541 字节**，SHA-256 为 `d176cada3b20d71b8048d6eed485913c2a73f6e0f860ce284ea556c402e37bc4`。签名包的产品提交为 `af35a472c1668e62deae968a125cc2c7ca9331dc`。[下载 DMG](https://github.com/haohongfei2001-png/Riftlet/releases/download/v1.0.9/Riftlet-1.0.9.dmg) · [源码与正式检查](https://github.com/haohongfei2001-png/Riftlet/pull/130)

## 安装与首次使用

- 独立复核从最终 DMG 只读挂载并安装 App，核对了应用内容、通用二进制、Developer ID、App 和 DMG 各自的 Apple 公证、装订和 Gatekeeper。安装窗口的 App 与「应用程序」图标坐标、原生背景引用和双分辨率背景均已检查。
- 首用重启测试在两个独立进程间重开同一份临时 SQLite 和偏好。连续选两张截图，分别让第一张或第二张得到接收收据，再立即退出。两种顺序都能在重开后完成引导一次。无关操作的收据不能完成引导。该项使用合成接收收据。
- 同一正式包在原生窗口完成 16 项设置检查和 6 项新进程重启检查。重新核对 42 张窗口截取画面和重启前后的数据库、偏好、截图资产。900 点窗口的正文占可用的 725 点，1040 点窗口的正文达到 768 点并在侧栏右侧居中。
- 在独立的 GitHub 托管 macOS 15 新账户上，AppKit 启动时读到「减少透明度」已开启。验收器在该临时账户关闭此选项并通过新进程读回，然后执行透明度滑块操作及其余设置检查。临时构建通过全部 16 项设置用例与 6 项重启检查。另在本机验证了开启「减少透明度」时滑块保持可见、呈禁用状态并显示原因，关闭后恢复可调。[新账户检查和回执](https://github.com/haohongfei2001-png/Riftlet/actions/runs/45364194858/job/138341571523)
- 实体设置检查使用一块 1470 × 956 点的 Retina 内置屏幕。实体第二显示器的热插拔、不同 Space 之间移动及完整 VoiceOver 朗读本轮未实测。

## 正式源码与检查

GitHub 对正式 PR 的测试合并树为 `a813fceaa152a7c04876822c82beae042143ba4f`。非作者核对了源码、准入记录和六项实际作业。产品合入 main 的提交为 `125ab172bd163de966d199ef81f90a6d6e9c66dc`，其文件树与测试合并树一致。[正式合并](https://github.com/haohongfei2001-png/Riftlet/pull/130)

ARM64 和 Intel 各完成 1,445 项 Swift 检查。另有 24 项反馈服务测试通过。ARM64 第一次运行时，发行工具测试中的临时可写磁盘映像卸载失败，日志未记录系统错误码。同一提交只重跑 ARM64 作业一次，原用例及全部 128 项发行工具测试通过。[双架构检查及两次 ARM64 运行](https://github.com/haohongfei2001-png/Riftlet/actions/runs/45364194640) · [反馈服务检查](https://github.com/haohongfei2001-png/Riftlet/actions/runs/45364194525)

主线 push 的五项检查随后全部通过，Apple 芯片、Intel 分别再次完成 1,445 项 Swift 检查，反馈服务通过 24 项。第一次排队的 Apple 芯片作业未获托管机器，执行步数为零。独立复核按重新分配机器后的实际执行统计。[主线双架构检查](https://github.com/haohongfei2001-png/Riftlet/actions/runs/45371785866) · [主线反馈检查](https://github.com/haohongfei2001-png/Riftlet/actions/runs/45371786066)

## 浏览器及网页范围

普通 Google Chrome、Microsoft Edge 中可编辑的 ChatGPT 草稿是本版一键附加的公开范围。受控环境中，两款浏览器各完成 41 项项目回归，涵盖切换标签或草稿、刷新、重建编辑器、替换上传入口及拒绝错误目标。Safari、Brave、Firefox、Claude、Gemini 和 DeepSeek 尚未具备本版经过实站验收的发布适配。[支持范围](../../consumer/SUPPORT-MATRIX.md)

以下结果来自该签名包在两款普通浏览器已登录的 ChatGPT Temporary Chat。验收器向正式 App 投递鼠标事件，间隔按 AppKit 实际收到的两次 mouseDown 计算。每组使用两张不同的系统截图。

| 项目 | Google Chrome | Microsoft Edge |
| --- | --- | --- |
| 第一组双图 | 1,158.589 ms | 836.010 ms |
| 第二组双图 | 1,042.806 ms | 899.837 ms |
| 第三组双图 | 1,138.899 ms | 822.982 ms |
| 首张已有附件及三组双图 | 7 张图，各 1 次 input、1 次 change、1 个持久接收记录 | 7 张图，各 1 次 input、1 次 change、1 个持久接收记录 |
| 非空正文、正向选区与旧卡 | 原文逐字符一致，选区 12→40，新图接收一次 | 原文逐字符一致，选区 12→40，新图接收一次 |
| 发送按钮点击、表单提交 | 0、0 | 0、0 |

逐图复核覆盖原 PNG、草稿实际预览、原编辑器和已有卡。Edge 此前另有一份独立草稿，第二张图只观测到一次 input/change，后续仍只能核对首张预览，页面也没有给出可归属的明确错误。原操作保留为 UNKNOWN，原图可以找回，未经选择没有再次输入。表中的 Edge 选区通过记录来自另一份空临时聊天和两张全新的截图。五份草稿共使用 20 张不同的系统截图，记录 20 次 input、20 次 change 和 19 个持久接收记录，零自动发送和零提交。[同包实站总表与逐图记录](evidence/signed-browser-summary.json)

## 公开交付

[GitHub Release](https://github.com/haohongfei2001-png/Riftlet/releases/tag/v1.0.9) · [官网](https://riftlet.com/) · [公开更新源](https://riftlet.com/updates/stable.xml)
