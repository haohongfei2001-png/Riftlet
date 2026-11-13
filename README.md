# Riftlet 1.0.1

[官方网站 · Official website](https://riftlet.com/)

Riftlet 把 Mac 上刚截的图放在桌面边缘。在 Google Chrome 打开要使用的 ChatGPT 对话，点一下缩略图，图片就会出现在草稿里。原有文字和附件会保留，消息由你发送。

[下载 Riftlet 1.0.1](https://github.com/haohongfei2001-png/Riftlet/releases/download/v1.0.1/Riftlet-1.0.1.dmg) · [版本说明](https://github.com/haohongfei2001-png/Riftlet/releases/tag/v1.0.1) · [English quick start](docs/consumer/QUICK-START.en.md)

支持 macOS 13 及以上的 Apple 芯片和 Intel Mac。首次打开时，跟随引导确认截图文件夹、连接 Chrome，再选择截图显示的位置。一键附加需要 macOS 自动化权限，以及 Chrome 菜单「显示 → 开发者 → 允许 Apple 事件中的 JavaScript」。只用本地截图和历史时可稍后设置 Chrome。

- **截图与找回。** 可在截图托盘、风铃和微缝之间切换。闲置的缩略图默认两分钟后归档，你可以从「截图历史」找回，或在设置调整归档时间。[第一次截图与附加](docs/consumer/QUICK-START.zh-CN.md)
- **安装与更新。** 同一份安装包适用于两种芯片。现有 1.0.0 用户需退出旧版、备份截图库并覆盖安装 1.0.1 一次；此后可在 App 内检查和安装新版。[安装与权限](docs/consumer/INSTALL-AND-PERMISSIONS.md) · [更新与恢复](docs/consumer/RECOVERY-AND-FAQ.md)
- **浏览器与隐私。** 一键附加支持 Chrome 中可编辑的 ChatGPT 网页。上传进度在草稿中查看；截图原件和本地历史保留。[支持范围](docs/consumer/SUPPORT-MATRIX.md) · [隐私政策](docs/consumer/PRIVACY.md)
- **联系。** 在「设置 → 权限与帮助」点「反馈与建议…」可私下反馈。隐私请求可发送至 [privacy@riftlet.com](mailto:privacy@riftlet.com)。

## 开发

使用带 XCTest 的 Xcode 运行测试。以下命令会构建本地开发版本：

```sh
swift test --parallel
bash scripts/build-macos.sh
build/Riftlet.app/Contents/MacOS/Riftlet --self-check
```

[正式发行流程](docs/release/AFTER_DEVELOPER_APPROVAL.md) · [源码审查与合并](docs/MAINLINE_GOVERNANCE.md) · [离线备份与恢复](docs/STORAGE_RECOVERY.md)
