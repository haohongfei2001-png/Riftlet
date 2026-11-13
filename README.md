# Riftlet

macOS 正常截图，图片停在桌面边缘；点一下微图，附加到当前 Chrome 的 ChatGPT 草稿。页面开始接收图片后微图收起，可以继续附加下一张。Riftlet 不发送聊天消息。

[下载 Mac Public Beta 0.3.5 (20)](https://github.com/haohongfei2001-png/Riftlet/releases/download/v0.3.5-beta.1/Riftlet-0.3.5-20-universal.dmg) · [版本说明](https://github.com/haohongfei2001-png/Riftlet/releases/tag/v0.3.5-beta.1)

支持 macOS 13 及以上的 Apple 芯片和 Intel Mac。当前采用手动更新，首次在非管理员账户中使用尚未完整验收。

一键附加需要 macOS 允许 Riftlet 控制 Chrome，并在 Chrome 的「显示 → 开发者」中勾选「允许 Apple 事件中的 JavaScript」。只用 Riftlet 收录和查看本地截图时可跳过。两张截图连续进入同一草稿的真实验收在 build 18 上通过；build 20 沿用相同的截图队列、附加与接收逻辑。

## 使用与支持

- [消费者入口与当前限制](docs/consumer/README.md)
- [中文快速开始](docs/consumer/QUICK-START.zh-CN.md) · [English quick start](docs/consumer/QUICK-START.en.md)
- [安装与分步权限说明](docs/consumer/INSTALL-AND-PERMISSIONS.md)
- [隐私、本地副本和卸载](docs/consumer/PRIVACY.md)
- [失败恢复、历史和存储 FAQ](docs/consumer/RECOVERY-AND-FAQ.md)
- [支持范围](docs/consumer/SUPPORT-MATRIX.md) · [反馈模板](docs/consumer/FEEDBACK-TEMPLATE.md)

截图原件与 Riftlet 本地副本均保留。`current` 列表是默认历史样式，`imageGrid` 图像网格可随时切换；共用搜索、筛选、分页、选中记录、预览和恢复动作。暂停收录、隐藏裂缝和关闭内置截图分别独立。收起队列、归档和卸载 App 都不自动删除本地截图数据。

`START` 证明页面已开始接收本张附件，**不证明网络上传最终完成**。最终状态以 ChatGPT 中实际附件为准；结果待核实的记录不会自动重传，可以在历史中找回原图。

## 发行与验证

- [2026-11-07 产品化进展与证据（历史）](engineering/productization-20261107/STATUS.md)
- [个人包与正式发行包的区别、当前构建命令](docs/release/PERSONAL_BETA_PACKAGING.md)
- [手动更新与完整回退](docs/release/MANUAL_UPDATE_AND_RECOVERY.md)
- [离线备份与恢复工具](docs/STORAGE_RECOVERY.md)
- [2026-11-07 三层 Beta 准入记录（历史）](engineering/productization-20261107/RELEASE-READINESS.md)
- [历史私测准备清单](engineering/productization-20261107/consumer/CLOSED-BETA-PLAN.md)（历史）

开发要求 macOS 13+；完整 XCTest 需要含 XCTest 的 Xcode 环境。以下开发构建使用 ad-hoc 签名，不是已公证的公开安装包：

```sh
swift test --parallel
bash scripts/build-macos.sh
build/Riftlet.app/Contents/MacOS/Riftlet --self-check
```

正式产品源码来自 main，并遵守[独立源码审查与 mainline 准入](docs/MAINLINE_GOVERNANCE.md)。正式 Logo 与品牌色保持不变；桌面主体的重大视觉设计仍由正式设计方案决定。

[本轮之前的 README 原文](docs/history/README-before-productization-20261107.md)以及带日期的工程记录保留历史事实，其中旧安装身份、旧构建命令和当时权限状态不代表当前状态。公开下载入口位于 [riftlet.com](https://riftlet.com/)。请勿向公开仓库提交真实截图、私人聊天、诊断原始数据、凭据或浏览器 profile。
