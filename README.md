# Riftlet

macOS 正常截图，图片停在桌面边缘；点一下微图，附加到当前 Chrome 的 ChatGPT 聊天。聊天开始接收图片时微图收起，可以继续附加下一张。Riftlet 不发送聊天消息。

当前已验证安装版为个人 Beta 1，尚未公开发行。该安装版对应已交付基线 `b61fc46cf931bdbd14deec1b47d077e92db61e16`，身份 `personal-beta.1+004741f`。后续 main 工程进展、开发分支、设计候选或 CI 产物不自动成为已验证安装版。

## Beta 2 候选审核

**Beta 2 · 0.2.0（2）** 已实现原生六页设置、菜单栏控制中心和三步引导，[PR #43](https://github.com/haohongfei2001-png/Riftlet/pull/43) 为 Draft。精确候选 `f0e5b99` 已完成 13/13 scoped 原生检查与同包新进程 6/6 自动重启检查，33 张窗口图与跨进程数据摘要已核对。33 张原图已获非作者 scoped 目视通过，精确候选 CUA 已验证草稿 Escape/Return；修正后的正式 CI 和最终源码/工件仍待收口；旧 FAIL 与未运行平台项保留。Beta 1 安装不变，当前不声明 `BETA2_REVIEW_READY` 或 `PRODUCT_READY`；重大 UI 合并与普通数据升级仍等待最终外观决定。

- [候选范围、审核入口与升级/回退说明](docs/BETA2_CANDIDATE.md)
- [原生验收矩阵与真实未运行项](engineering/beta2-product-20261106/NATIVE-ACCEPTANCE-MATRIX.md)
- [隔离原生 driver 与同包重启验证](docs/SETTINGS_REVIEW_DRIVER.md)
- [当前工程状态](engineering/beta2-product-20261106/STATUS.md)

## 使用与支持

- [使用、安装及权限](docs/USER_GUIDE.md)
- [隐私、截图历史及卸载](docs/PRIVACY_AND_DATA.md)
- [问题排查与兼容范围](docs/SUPPORT.md)
- [备份与恢复](docs/STORAGE_RECOVERY.md)
- [发行构建、版本与手动更新](docs/RELEASE_ENGINEERING.md)

收录单帧 PNG、JPEG、HEIC/HEIF、TIFF。原系统截图保留；PNG/JPEG 原样附加，其他支持格式通常生成等分辨率 PNG；派生 PNG 超出预算时会单次尝试原文件，接收仍取决于页面兼容性。空队列不显示裂缝。暂停收录、隐藏微图和关闭内置截图各自独立。清空可见队列不删除截图文件、历史或聊天附件。

个人 Beta 已取得真实 ChatGPT 五张连续附加及最终版冷启动两张成功证据。动态菜单备用分支有受控浏览器验证，尚无当前个人 Beta 的真实页面触发证据。冷启动 MAIN 交接可能将 Chrome 窗口前置。具体范围及外部验收缺口见 [支持说明](docs/SUPPORT.md)。

## 开发

正式产品源码只来自 main。构建要求 macOS 13+；完整 XCTest 需要含 XCTest 的 Xcode 开发环境。开发构建使用 ad-hoc 签名，不能作为已公证公开安装包。

```sh
swift test --parallel
bash scripts/build-macos.sh
build/Riftlet.app/Contents/MacOS/Riftlet --self-check
```

[自动工程推进索引](engineering/autonomous-readiness-20261106/ROADMAP.md)记录基础工程状态、证据和接管入口；[mainline 治理](docs/MAINLINE_GOVERNANCE.md)规定独立源码审查及准入。设置与控制中心 V2 设计已有本轮原生候选实现，尚未替换当前安装 App。

[保留的早期 README](docs/history/README-20261028.md)及 `docs/`、`engineering/evidence/` 中带日期的工程记录描述当时事实；其中旧候选、上传关闭和 8 MiB 限制不能用于说明当前普通入口。

官网目录是独立受审视觉成果，本轮只准备发行接入规范，不发布下载。请勿向公开仓库提交真实截图、私人聊天、诊断原始数据、凭据或浏览器 profile。
