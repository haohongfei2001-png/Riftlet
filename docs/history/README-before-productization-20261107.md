# Riftlet

macOS 正常截图，图片停在桌面边缘；点一下微图，附加到当前 Chrome 的 ChatGPT 聊天。聊天开始接收图片时微图收起，可以继续附加下一张。Riftlet 不发送聊天消息。

当前已验证安装版为个人 Beta 1，尚未公开发行。该安装版对应已交付基线 `b61fc46cf931bdbd14deec1b47d077e92db61e16`，身份 `personal-beta.1+004741f`。后续 main 工程进展、开发分支、设计候选或 CI 产物不自动成为已验证安装版。

## Beta 2 候选审核

**Beta 2 · 0.2.0（2）** 的六页原生设置、菜单栏控制中心和三步引导已完成有限精修，继续在 [PR #43](https://github.com/haohongfei2001-png/Riftlet/pull/43) 进行候选审核。实际构建源码 `a5aefd3` 的普通外观与真实系统高对比度环境各完成 14/14 隔离原生检查、39 张原始窗口图及同包新进程 6/6 重启检查。普通 39 张、提高对比度环境中的 24 张重点图已由非作者目视；实际键盘草稿关闭、Tab 顺序与首击保存有独立范围的 CUA 操作记录。

本轮修复了已接受的暂停/恢复命令与后台检查竞争造成的误报保存失败，保留全部旧 FAIL。真实系统 IME 组字、持续 VoiceOver 导航和实体菜单栏点击仍为 NOT_RUN。正式 G/H、五项 CI 和最终工件身份在 PR 的精确交付记录与私有包清单中绑定，不由原型或截图数量代替。Beta 1 安装不变；本轮不合并、不生产替换，也不宣布 `PRODUCT_READY`。最终外观决定仍由用户完成。

- [本轮精修结果与证据](engineering/beta2-polish-20261106/README.md)
- [本轮原生验收及保留失败](engineering/beta2-polish-20261106/native-acceptance.md)
- [候选范围、审核入口与升级/回退说明](docs/BETA2_CANDIDATE.md)
- [隔离原生 driver 与同包重启验证](docs/SETTINGS_REVIEW_DRIVER.md)
- [首次候选的历史记录](engineering/beta2-product-20261106/STATUS.md)

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
