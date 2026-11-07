# Riftlet

macOS 正常截图，图片停在桌面边缘；点一下微图，附加到当前 Chrome 的 ChatGPT 草稿。页面开始接收图片后微图收起，可以继续附加下一张。Riftlet 不发送聊天消息。

当前个人安装基线为 **Personal Beta 3 · 0.3.0（3）· ARM64**，来自已合并 PR #45 的 main `2e779f646ac4874344fac94f79103e8ddf9b02c8`。该版本已完成安全升级和历史双样式验收。后续文档、发行工具或 CI 工件不自动替代这个已验证安装包。

**尚未公开发行，也未达到陌生用户自行下载安装的准入条件。** 本轮当前版本 ChatGPT 真实附加验证受浏览器工具访问限制，不能由旧版本成功记录或合成测试替代；本机没有可用 Developer ID Application 身份，公开发行签名、公证和干净设备验收仍待完成。

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

- [本轮产品化进展与证据](engineering/productization-20261107/STATUS.md)
- [个人包与正式发行包的区别、当前构建命令](docs/release/PERSONAL_BETA_PACKAGING.md)
- [手动更新与完整回退](docs/release/MANUAL_UPDATE_AND_RECOVERY.md)
- [离线备份与恢复工具](docs/STORAGE_RECOVERY.md)
- [三层 Beta 准入](engineering/productization-20261107/RELEASE-READINESS.md)
- [封闭 Beta 方案](engineering/productization-20261107/consumer/CLOSED-BETA-PLAN.md)：本轮未邀请外部人员、未公开下载、未添加遥测。

开发要求 macOS 13+；完整 XCTest 需要含 XCTest 的 Xcode 环境。以下开发构建使用 ad-hoc 签名，不是已公证的公开安装包：

```sh
swift test --parallel
bash scripts/build-macos.sh
build/Riftlet.app/Contents/MacOS/Riftlet --self-check
```

正式产品源码来自 main，并遵守[独立源码审查与 mainline 准入](docs/MAINLINE_GOVERNANCE.md)。正式 Logo 与品牌色保持不变；桌面主体的重大视觉设计仍由正式设计方案决定。

[本轮之前的 README 原文](docs/history/README-before-productization-20261107.md)以及带日期的工程记录保留历史事实，其中旧安装身份、旧构建命令和当时权限状态不代表当前状态。官网视觉成果继续保留，本轮不发布下载。请勿向公开仓库提交真实截图、私人聊天、诊断原始数据、凭据或浏览器 profile。
