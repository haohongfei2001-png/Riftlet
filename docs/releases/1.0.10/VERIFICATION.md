# Riftlet 1.0.10（build 65）安装包与截图历史验收

正式通用 DMG 为 13,939,797 字节，SHA-256 为 `036a41733a57810824a830b0090e7360de22cdba3819704484bb01053da7033d`。产品提交为 `3f7d87ee242463cfc90bf5d600c8ee1d262de69d`。[下载安装包](https://github.com/haohongfei2001-png/Riftlet/releases/download/v1.0.10/Riftlet-1.0.10.dmg) · [产品源码及检查](https://github.com/haohongfei2001-png/Riftlet/pull/132)

SQLite 测试夹具修订提交为 `155abce80308ff9e0c33f10992a353bfc84cd599`。相对签名源码，它修正了两份 SQLite 旧库测试夹具，并包含此前的源码审查记录。后续提交 `dbc8d6ffe5bf9fa4bd5abdf2e6ecc7b8cfe24097` 将独立反馈作业改为 macOS 15 Intel 运行，并将该作业的超时提高至 30 分钟。App 源码、资源、依赖锁定文件及打包工具与正式包一致。

正式 PR 的五项检查通过，涵盖原生源码准入、Apple 芯片与 Intel 两个构建、反馈源码准入和反馈服务检查。合并至 main 的提交为 `8e001db19c9a943384bbc39e3f949c0165858249`，文件树与测试合并树一致。[正式合并](https://github.com/haohongfei2001-png/Riftlet/pull/132) · [双架构检查](https://github.com/haohongfei2001-png/Riftlet/actions/runs/45432703140) · [反馈检查](https://github.com/haohongfei2001-png/Riftlet/actions/runs/45432702844)

## 安装包

从只读挂载的 DMG 将 Riftlet 安装至空的测试目录后，核对了 App 的完整签名文件清单、Apple 芯片和 Intel 二进制、Developer ID 团队 `ZB9D4T66QB`、App 与 DMG 的公证票据以及 Gatekeeper。安装的 App 通过四项包内自检，覆盖私有导入、操作持久化、首次使用和模拟网页附加。

## 截图历史

在同一签名 App 的离线模拟模式中收录三张独立截图，通过原生辅助功能操作托盘。首次点选的一张截图在模拟草稿中附加成功后进入历史，其余两张仍在活动托盘。打开历史后再次点选同一张，模拟附加失败，原图仍在历史。两次主动选择分别建立操作，额外文件输入为零。

独立源码复核在 Apple 芯片 Mac 的 AppKit 窗口验证三种外观中的上下滚动、历史截图点选和重复点击保护。另用 23 张测试截图验证最近历史显示上限为 20 张，翻出最近列表的原文件保留在本地。用 1.0.9 创建测试截图库，再由新版打开，确认原图字节和历史操作保留，旧版回到活动托盘的失败截图移入历史。

以上网页传输结果来自受控模拟。1.0.9 在真实 Chrome、Edge 草稿中取得的验收数据保存在该版报告中。[1.0.9 实站记录](../1.0.9/VERIFICATION.md)
